// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";

/// @title FeeFlowTest
/// @notice Integration tests for fee accrual and routing:
///         Transaction fees on open, borrow fee accrual, funding rate payments.
///         Tests the interaction between ExecutionEngine, BorrowFeeEngine,
///         FundingRateEngine, MarginEngine, and FeeRouter.
contract FeeFlowTest is IntegrationBase {

    // ─── Transaction Fees ───

    function test_txFee_deductedOnOpen() public {
        uint256 collateral = 1000e18;
        uint256 leverage = 3e18;

        uint256 posId = _openPosition(alice, true, collateral, leverage);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);

        // TX fee = 10bps of notional = 0.001 * (1000 * 3) = 3.0
        uint256 notional = (collateral * leverage) / WAD;
        uint256 expectedFee = (notional * 1e15) / WAD; // 10bps
        uint256 expectedCollateral = collateral - expectedFee;

        assertEq(pos.collateral, expectedCollateral);
        assertEq(pos.positionSize, notional); // Notional unaffected by fee
    }

    function test_txFee_scaledByNotional() public {
        // Larger position → larger fee
        uint256 posSmall = _openPosition(alice, true, 100e18, 2e18);
        uint256 posLarge = _openPosition(bob, true, 1000e18, 2e18);

        IPositionManager.Position memory small = positionManager.getPosition(posSmall);
        IPositionManager.Position memory large = positionManager.getPosition(posLarge);

        // Fee deducted from collateral: larger position has proportionally larger fee
        uint256 feeSmall = 100e18 - small.collateral;
        uint256 feeLarge = 1000e18 - large.collateral;

        // feeLarge should be ~10x feeSmall
        assertApproxEqRel(feeLarge, feeSmall * 10, 1e16); // Within 1%
    }

    function test_mockFeeRouter_tracksCollectedFees() public {
        _openPosition(alice, true, 1000e18, 5e18);
        _openPosition(bob, false, 500e18, 3e18);

        uint256 totalFees = feeRouter.totalFeesCollected();
        assertGt(totalFees, 0);
    }

    // ─── Borrow Fees ───

    function test_borrowRate_existsForActiveMarket() public {
        uint256 rate = borrowFeeEngine.getCurrentBorrowRate(marketId, true);
        // Rate should be > 0 for an active market with τ > 0
        assertGt(rate, 0);
    }

    function test_borrowFees_accrueForLeveragedPosition() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        // Initially zero
        uint256 fees0 = borrowFeeEngine.getAccruedFees(posId);
        assertEq(fees0, 0);

        // Warp + accrue index
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        uint256 fees1 = borrowFeeEngine.getAccruedFees(posId);
        assertGt(fees1, 0);
    }

    function test_borrowFees_increaseWithTime() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        uint256 fees1hr = borrowFeeEngine.getAccruedFees(posId);

        vm.warp(block.timestamp + 3 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        uint256 fees4hr = borrowFeeEngine.getAccruedFees(posId);

        assertGt(fees4hr, fees1hr);
    }

    function test_borrowFees_reflectedInEquity() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IMarginEngine.EquityResult memory eq0 = marginEngine.computeEquity(posId);

        vm.warp(block.timestamp + 6 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posId);

        // Borrow fees should reduce equity
        assertGt(eq1.accruedBorrowFees, eq0.accruedBorrowFees);
        assertLt(eq1.equity, eq0.equity);
    }

    function test_borrowIndex_growsMonotonically() public {
        uint256 idx0 = borrowFeeEngine.getBorrowIndex(marketId, true);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        uint256 idx1 = borrowFeeEngine.getBorrowIndex(marketId, true);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        uint256 idx2 = borrowFeeEngine.getBorrowIndex(marketId, true);

        assertGe(idx1, idx0);
        assertGe(idx2, idx1);
    }

    // ─── Funding Rate ───

    function test_fundingRate_zeroWithNoOI() public {
        // No open positions → funding rate should be 0
        int256 rate = fundingRateEngine.getCurrentFundingRate(marketId);
        assertEq(rate, 0);
    }

    function test_fundingRate_existsWithImbalancedOI() public {
        // Create OI imbalance: more longs than shorts
        _openPosition(alice, true, 1000e18, 3e18);
        _openPosition(bob, true, 500e18, 2e18);

        int256 rate = fundingRateEngine.getCurrentFundingRate(marketId);
        // With only longs and no shorts, funding rate should be positive (longs pay)
        assertGt(rate, 0);
    }

    function test_fundingRate_directionDependsOnImbalance() public {
        // Heavy longs
        _openPosition(alice, true, 2000e18, 3e18);
        _openPosition(bob, false, 500e18, 2e18);

        int256 rateLongHeavy = fundingRateEngine.getCurrentFundingRate(marketId);

        // Funding rate positive when longs are heavy side
        assertGt(rateLongHeavy, 0);
    }

    function test_fundingIndex_updatesWithAccrual() public {
        _openPosition(alice, true, 1000e18, 3e18);
        _openPosition(bob, false, 500e18, 2e18);

        int256 idx0 = fundingRateEngine.getFundingIndex(marketId);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        fundingRateEngine.accrueFunding(marketId);

        int256 idx1 = fundingRateEngine.getFundingIndex(marketId);

        // Index should have changed (direction depends on imbalance)
        assertTrue(idx1 != idx0);
    }

    function test_funding_reflectedInEquity() public {
        // Create imbalance: alice long (heavy), bob short (light)
        uint256 posAlice = _openPosition(alice, true, 2000e18, 3e18);
        uint256 posBob = _openPosition(bob, false, 500e18, 2e18);

        // Accrue funding
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        fundingRateEngine.accrueFunding(marketId);

        IMarginEngine.EquityResult memory eqAlice = marginEngine.computeEquity(posAlice);
        IMarginEngine.EquityResult memory eqBob = marginEngine.computeEquity(posBob);

        // Heavy side (longs) pays → alice's funding should be negative (paid)
        // Light side (shorts) receives → bob's funding should be positive (received)
        assertLt(eqAlice.accruedFunding, 0); // Alice pays
        assertGt(eqBob.accruedFunding, 0);    // Bob receives
    }

    function test_matchedUnmatched_oiSplit() public {
        _openPosition(alice, true, 1000e18, 3e18);   // 3000 notional
        _openPosition(bob, false, 500e18, 2e18);     // 1000 notional

        (uint256 matched, uint256 unmatched) = fundingRateEngine.getOISplit(marketId);

        // Matched = min(longOI, shortOI), Unmatched = |longOI - shortOI|
        assertGt(matched, 0);
        assertGt(unmatched, 0);
        assertGt(unmatched, matched); // More longs than shorts → large unmatched
    }

    // ─── Combined Fee Impact ───

    function test_combinedFees_erodeEquity() public {
        // Open with imbalance to ensure both borrow + funding affect equity
        uint256 posAlice = _openPosition(alice, true, 1000e18, 5e18);
        _openPosition(bob, false, 200e18, 2e18); // Small short for imbalance

        IMarginEngine.EquityResult memory eq0 = marginEngine.computeEquity(posAlice);

        // Warp and accrue both fee types
        vm.warp(block.timestamp + 8 hours);
        vm.startPrank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        fundingRateEngine.accrueFunding(marketId);
        vm.stopPrank();

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posAlice);

        // Both borrow fees and funding payments (heavy side pays) erode equity
        assertGt(eq1.accruedBorrowFees, 0);
        assertLt(eq1.accruedFunding, 0); // Heavy side pays funding
        assertLt(eq1.equity, eq0.equity); // Combined erosion
    }
}
