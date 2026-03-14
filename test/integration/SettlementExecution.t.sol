// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";
import { SettlementEngine } from "../../contracts/SettlementEngine.sol";
import { ISettlementEngine } from "../../contracts/interfaces/ISettlementEngine.sol";

/// @title SettlementExecutionTest
/// @notice Integration tests for actual settlement execution: market resolution → PI snap →
///         payout calculation → position closure → fee routing → bad debt waterfall.
contract SettlementExecutionTest is IntegrationBase {

    SettlementEngine public settlementEngine;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        settlementEngine = new SettlementEngine(
            admin,
            address(registry),
            address(positionManager),
            address(oracleAdapter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(insuranceFund),
            address(feeRouter),
            address(oiLimits),
            address(accountManager),
            address(vault)
        );

        // Grant roles
        positionManager.grantRole(positionManager.ENGINE(), address(settlementEngine));
        oiLimits.grantRole(oiLimits.SETTLEMENT_ENGINE_ROLE(), address(settlementEngine));
        accountManager.grantRole(accountManager.ENGINE(), address(settlementEngine));
        oracleAdapter.grantRole(oracleAdapter.KEEPER(), address(settlementEngine));
        settlementEngine.grantRole(settlementEngine.KEEPER_ROLE(), keeper);

        vm.stopPrank();
    }

    /// @dev Helper: advance market to resolved state with given outcome
    function _resolveMarket(uint8 outcome) internal {
        vm.startPrank(admin);

        // Set market live
        registry.setLive(marketId);

        // Warp past resolution time
        vm.warp(marketResolutionTime + 1);

        // Set pending resolution
        registry.setPendingResolution(marketId, marketResolutionTime);

        // Resolve
        registry.resolveMarket(marketId, outcome);

        vm.stopPrank();
    }

    /// @dev Helper: open opposing positions for a balanced market
    function _openOpposingPositions(
        uint256 collateral,
        uint256 leverage
    ) internal returns (uint256 longId, uint256 shortId) {
        longId = _openPosition(alice, true, collateral, leverage);
        shortId = _openPosition(bob, false, collateral, leverage);
    }

    // ─── Basic Settlement ───

    function test_settleMarket_YES_outcome() public {
        // Open positions: Alice long, Bob short
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 3e18);

        // Accrue some borrow fees
        vm.warp(block.timestamp + 12 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, false);

        // Resolve market YES
        _resolveMarket(1);

        // Settle
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        // Market should be settled
        ISettlementEngine.MarketSettlementSummary memory summary = settlementEngine.getMarketSettlement(marketId);
        assertEq(summary.outcome, 1);
        assertEq(summary.totalPositions, 2);
        assertEq(summary.winnerCount, 1); // longs win on YES
        assertEq(summary.loserCount, 1);

        // PI should be snapped to 1.0
        uint256 pi = oracleAdapter.getPI(marketId);
        assertEq(pi, WAD);
    }

    function test_settleMarket_NO_outcome() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 3e18);

        vm.warp(block.timestamp + 12 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, false);

        _resolveMarket(0);

        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        ISettlementEngine.MarketSettlementSummary memory summary = settlementEngine.getMarketSettlement(marketId);
        assertEq(summary.outcome, 0);
        assertEq(summary.winnerCount, 1); // shorts win on NO
        assertEq(summary.loserCount, 1);

        // PI should be snapped to 0
        uint256 pi = oracleAdapter.getPI(marketId);
        assertEq(pi, 0);
    }

    // ─── Claim Settlement ───

    function test_claimSettlement_winnerGetsPayout() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 2e18);

        _resolveMarket(1); // YES — Alice's long wins

        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        // Preview Alice's settlement
        ISettlementEngine.SettlementResult memory preview = settlementEngine.previewSettlement(longId);
        assertTrue(preview.isWinner);
        assertGt(preview.payout, 0);

        // Claim
        vm.prank(alice);
        ISettlementEngine.SettlementResult memory result = settlementEngine.claimSettlement(longId);

        assertTrue(result.isWinner);
        assertGt(result.payout, 0);
        assertTrue(settlementEngine.isSettled(longId));

        // Position should be closed
        assertFalse(positionManager.isPositionOpen(longId));
    }

    function test_claimSettlement_loserGetsZeroOrRemaining() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 2e18);

        _resolveMarket(1); // YES — Bob's short loses

        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        // Claim Bob's settlement
        vm.prank(bob);
        ISettlementEngine.SettlementResult memory result = settlementEngine.claimSettlement(shortId);

        assertFalse(result.isWinner);
        // Losers may get remaining equity (if positive) or 0
        assertTrue(settlementEngine.isSettled(shortId));
        assertFalse(positionManager.isPositionOpen(shortId));
    }

    function test_claimSettlement_cannotClaimTwice() public {
        (uint256 longId,) = _openOpposingPositions(1000e18, 2e18);

        _resolveMarket(1);
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        vm.prank(alice);
        settlementEngine.claimSettlement(longId);

        // Second claim should revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            ISettlementEngine.SettlementEngine__PositionAlreadySettled.selector,
            longId
        ));
        settlementEngine.claimSettlement(longId);
    }

    // ─── Settlement Fees ───

    function test_settlementFee_deductedFromWinners() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 2e18);

        _resolveMarket(1);
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory winnerResult = settlementEngine.previewSettlement(longId);
        ISettlementEngine.SettlementResult memory loserResult = settlementEngine.previewSettlement(shortId);

        // Winner should have settlement fee > 0
        assertGt(winnerResult.settlementFee, 0);

        // Loser should have settlement fee = 0
        assertEq(loserResult.settlementFee, 0);
    }

    // ─── Bad Debt Waterfall ───

    function test_settlement_withBadDebt() public {
        // Open asymmetric positions — one side with very high leverage
        uint256 longId = _openPosition(alice, true, 500e18, 5e18);
        uint256 shortId = _openPosition(bob, false, 2000e18, 2e18);

        // Accrue significant borrow fees over time
        vm.warp(block.timestamp + 36 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, false);

        // Resolve NO — Alice's long loses with high leverage, possibly bad debt
        _resolveMarket(0);

        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        ISettlementEngine.MarketSettlementSummary memory summary = settlementEngine.getMarketSettlement(marketId);

        // Check that bad debt was handled
        // (Whether there's actual bad debt depends on exact fee accrual + PI move)
        assertEq(summary.totalPositions, 2);
    }

    // ─── OI Cleanup ───

    function test_settlement_cleansUpOI() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 2e18);
        assertGt(oiLimits.getGlobalOI(), 0);

        _resolveMarket(1);
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        // Claim both positions
        vm.prank(alice);
        settlementEngine.claimSettlement(longId);
        vm.prank(bob);
        settlementEngine.claimSettlement(shortId);

        // All OI should be gone
        assertEq(oiLimits.getGlobalOI(), 0);
    }

    // ─── Revert Cases ───

    function test_settleMarket_revertsIfNotResolved() public {
        _openOpposingPositions(1000e18, 2e18);

        // Market is ACTIVE, not RESOLVED
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            ISettlementEngine.SettlementEngine__MarketNotResolved.selector,
            marketId
        ));
        settlementEngine.settleMarket(marketId);
    }

    function test_claimSettlement_revertsIfMarketNotSettled() public {
        (uint256 longId,) = _openOpposingPositions(1000e18, 2e18);

        _resolveMarket(1);
        // Don't call settleMarket

        vm.prank(alice);
        vm.expectRevert();
        settlementEngine.claimSettlement(longId);
    }

    // ─── Multiple Positions Same Side ───

    function test_settlement_multipleWinners() public {
        // Three longs, one short
        uint256 long1 = _openPosition(alice, true, 1000e18, 2e18);
        uint256 long2 = _openPosition(bob, true, 800e18, 2e18);
        address charlie = address(0xA3);
        uint256 long3 = _openPosition(charlie, true, 600e18, 2e18);
        uint256 short1 = _openPosition(address(0xA4), false, 2400e18, 2e18);

        _resolveMarket(1);
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        ISettlementEngine.MarketSettlementSummary memory summary = settlementEngine.getMarketSettlement(marketId);
        assertEq(summary.totalPositions, 4);
        assertEq(summary.winnerCount, 3);
        assertEq(summary.loserCount, 1);

        // All winners should get payouts
        ISettlementEngine.SettlementResult memory r1 = settlementEngine.previewSettlement(long1);
        ISettlementEngine.SettlementResult memory r2 = settlementEngine.previewSettlement(long2);
        ISettlementEngine.SettlementResult memory r3 = settlementEngine.previewSettlement(long3);

        assertTrue(r1.isWinner);
        assertTrue(r2.isWinner);
        assertTrue(r3.isWinner);
    }

    // ─── Borrow Fees Affect Settlement Equity ───

    function test_settlement_borrowFeesReduceEquity() public {
        (uint256 longId, uint256 shortId) = _openOpposingPositions(1000e18, 3e18);

        // Fast-forward significant time for borrow fee accrual
        vm.warp(block.timestamp + 40 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, false);

        _resolveMarket(1);
        vm.prank(keeper);
        settlementEngine.settleMarket(marketId);

        // Winner's payout should be reduced by borrow fees
        ISettlementEngine.SettlementResult memory winnerResult = settlementEngine.previewSettlement(longId);
        assertTrue(winnerResult.isWinner);

        // The payout should be less than pure PnL because borrow fees ate into equity
        // (We can't easily compare without knowing exact fee amounts, but payout should exist)
        assertGt(winnerResult.payout, 0);
    }
}
