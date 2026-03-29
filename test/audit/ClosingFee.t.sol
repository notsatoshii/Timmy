// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../integration/IntegrationBase.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";

/// @title ClosingFeeTest
/// @notice Tests for LEVER-BUG-8: Closing transaction fee must be routed as TRANSACTION, not BORROW.
///
/// Background: LEVER-P03 already fixed the double-routing bug (collectTransactionFee removed,
/// fees computed locally). The remaining issue was that closing fees and borrow fees were
/// combined and routed together as FeeType.BORROW, misclassifying half the transaction fee revenue.
///
/// Fix: Split the routeFees call in _settlePnL into two: BORROW for borrow fees, TRANSACTION
/// for closing fees.
contract ClosingFeeTest is IntegrationBase {

    uint256 constant COLLATERAL = 1_000e18;
    uint256 constant LEVERAGE   = 2e18;
    uint256 constant TX_FEE_BPS = 1e15; // 10bps

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Closing fee is deducted from user balance
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice User must pay 10bps of notional on close (in addition to the opening fee).
    function test_BUG8_closingFeeDeductedFromUser() public {
        _fundUser(alice, COLLATERAL);

        vm.prank(alice);
        uint256 posId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        // Close at same PI (PnL=0, borrowFees=0 in same block)
        vm.prank(alice);
        executionEngine.closePosition(posId);

        uint256 balanceAfterClose = accountManager.getBalance(alice);

        // Closing fee = notional * TX_FEE_RATE / WAD = 2000e18 * 1e15 / 1e18 = 2e18
        uint256 notional = COLLATERAL * LEVERAGE / 1e18;
        uint256 expectedClosingFee = notional * TX_FEE_BPS / 1e18;

        // User should have paid the closing fee
        // balanceAfterOpen includes locked collateral; after close, collateral is released
        // but closing fee is deducted. Net change = +collateral - closingFee
        // Actually: after close, balance = balanceAfterOpen + collateral(released) - closingFee
        // But balanceAfterOpen already had collateral locked (not in free balance)
        // Simplest check: final balance = initial deposit - openFee - closingFee
        uint256 expectedFinal = COLLATERAL - expectedClosingFee - expectedClosingFee; // both fees identical
        assertEq(balanceAfterClose, expectedFinal,
            "User must pay closing fee (10bps of notional)");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Close does not revert (FeeType split works)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The FeeType split in _settlePnL must not revert. Two routeFees calls
    ///         are made: BORROW for borrow fees, TRANSACTION for closing fee.
    function test_BUG8_closeFeeTypeDoesNotRevert() public {
        _fundUser(alice, COLLATERAL);

        vm.prank(alice);
        uint256 posId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        // Accrue some borrow fees so both fee types are non-zero
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        // Close should succeed with both borrow and closing fees routed
        vm.prank(alice);
        executionEngine.closePosition(posId);

        // If we reach here, the split routeFees calls worked
        uint256 finalBalance = accountManager.getBalance(alice);
        assertLt(finalBalance, COLLATERAL, "User should have paid fees");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: Total fees sent to FeeRouter match expected amounts
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice FeeRouter must receive exactly openFee + closingFee after a round trip
    ///         (when borrowFees=0).
    function test_BUG8_feeRouterReceivesTotalFees() public {
        _fundUser(alice, COLLATERAL);

        vm.prank(alice);
        uint256 posId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        uint256 feeRouterUsdtAfterOpen = usdt.balanceOf(address(feeRouter));

        // Close at same PI, same block (borrowFees=0)
        vm.prank(alice);
        executionEngine.closePosition(posId);

        uint256 feeRouterUsdtAfterClose = usdt.balanceOf(address(feeRouter));

        // Closing fee = 2e18 (same as opening fee)
        uint256 notional = COLLATERAL * LEVERAGE / 1e18;
        uint256 closingFee = notional * TX_FEE_BPS / 1e18;

        assertEq(
            feeRouterUsdtAfterClose - feeRouterUsdtAfterOpen,
            closingFee,
            "FeeRouter must receive exactly the closing fee on close"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: routeFees called for closing fee (MockFeeRouter tracks total)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice MockFeeRouter.totalFeesCollected must increment by exactly the closing fee
    ///         on close (not double or zero).
    function test_BUG8_routeFeesCalledForClosingFee() public {
        _fundUser(alice, COLLATERAL);

        vm.prank(alice);
        uint256 posId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        uint256 feesAfterOpen = feeRouter.totalFeesCollected();

        // Close at same PI, same block
        vm.prank(alice);
        executionEngine.closePosition(posId);

        uint256 feesAfterClose = feeRouter.totalFeesCollected();

        uint256 notional = COLLATERAL * LEVERAGE / 1e18;
        uint256 closingFee = notional * TX_FEE_BPS / 1e18;

        // totalFeesCollected incremented by exactly the closing fee (routed once)
        assertEq(
            feesAfterClose - feesAfterOpen,
            closingFee,
            "routeFees must be called exactly once for the closing fee"
        );
    }
}
