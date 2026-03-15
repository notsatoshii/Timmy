// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";

/// @title PositionLifecycleTest
/// @notice Integration tests for the full position lifecycle:
///         Open position → modify collateral → PI moves → close position.
///         Uses real contracts: ExecutionEngine, PositionManager, OILimits,
///         MarginEngine, BorrowFeeEngine, FundingRateEngine, OracleAdapter, MarketRegistry.
contract PositionLifecycleTest is IntegrationBase {

    // ─── Open Position ───

    function test_openLongPosition() public {
        uint256 collateral = 1000e18;
        uint256 leverage = 5e18;

        uint256 posId = _openPosition(alice, true, collateral, leverage);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.owner, alice);
        assertTrue(pos.isLong);
        assertTrue(pos.isOpen);
        assertEq(pos.marketId, marketId);
        assertEq(pos.leverage, leverage);

        // Notional = collateral * leverage (before fee deduction on collateral)
        uint256 expectedNotional = (collateral * leverage) / WAD;
        assertEq(pos.positionSize, expectedNotional);

        // Collateral reduced by TX fee (10bps of notional)
        uint256 txFee = (expectedNotional * 1e15) / WAD;
        assertEq(pos.collateral, collateral - txFee);
    }

    function test_openShortPosition() public {
        uint256 posId = _openPosition(bob, false, 500e18, 3e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.owner, bob);
        assertFalse(pos.isLong);
        assertTrue(pos.isOpen);
    }

    function test_openMultiplePositions_sameMarket() public {
        uint256 posA = _openPosition(alice, true, 1000e18, 2e18);
        uint256 posB = _openPosition(bob, false, 800e18, 3e18);
        uint256 posC = _openPosition(alice, true, 500e18, 2e18);

        assertTrue(posA != posB && posB != posC);

        // OI should be updated
        uint256 globalOI = oiLimits.getGlobalOI();
        assertGt(globalOI, 0);

        uint256 marketOI = oiLimits.getMarketOI(marketId);
        assertGt(marketOI, 0);

        // Long side OI should be > short side OI (alice opened two longs)
        uint256 longOI = oiLimits.getSideOI(marketId, true);
        uint256 shortOI = oiLimits.getSideOI(marketId, false);
        assertGt(longOI, shortOI);
    }

    // ─── Close Position ───

    function test_closePosition_breakeven() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 2e18);

        // Close at same PI — PnL should be ~0 (only impact difference)
        _closePosition(alice, posId);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_closePosition_withProfit() public {
        // Open long at PI=0.50
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        // PI rises to 0.60
        _pushPI(6e17);

        _closePosition(alice, posId);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_closePosition_withLoss() public {
        // Open long at PI=0.50
        uint256 posId = _openPosition(alice, true, 1000e18, 2e18);

        // PI drops to 0.45
        _pushPI(45e16);

        _closePosition(alice, posId);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_closePosition_reducesOI() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 2e18);

        uint256 oiBefore = oiLimits.getGlobalOI();
        assertGt(oiBefore, 0);

        _closePosition(alice, posId);

        uint256 oiAfter = oiLimits.getGlobalOI();
        assertEq(oiAfter, 0);
    }

    // ─── Add / Remove Collateral ───

    function test_addCollateral() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IPositionManager.Position memory posBefore = positionManager.getPosition(posId);
        uint256 addAmount = 200e18;

        // Fund alice with additional collateral
        _fundUser(alice, addAmount);

        vm.prank(alice);
        executionEngine.addCollateral(posId, addAmount);

        IPositionManager.Position memory posAfter = positionManager.getPosition(posId);
        assertEq(posAfter.collateral, posBefore.collateral + addAmount);
    }

    function test_removeCollateral() public {
        // Open with generous collateral (low leverage)
        uint256 posId = _openPosition(alice, true, 2000e18, 1e18);

        IPositionManager.Position memory posBefore = positionManager.getPosition(posId);
        uint256 removeAmount = 100e18;

        vm.prank(alice);
        executionEngine.removeCollateral(posId, removeAmount);

        IPositionManager.Position memory posAfter = positionManager.getPosition(posId);
        assertEq(posAfter.collateral, posBefore.collateral - removeAmount);
    }

    // ─── Access Control ───

    function test_cannotCloseOtherUsersPosition() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 2e18);

        vm.expectRevert();
        vm.prank(bob);
        executionEngine.closePosition(posId);
    }

    function test_cannotOpenOnInactiveMarket() public {
        bytes32 fakeMarket = keccak256("FAKE_MARKET");

        vm.expectRevert();
        vm.prank(alice);
        executionEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: fakeMarket,
                isLong: true,
                collateral: 1000e18,
                leverage: 2e18
            })
        );
    }

    function test_cannotOpenWithZeroCollateral() public {
        vm.expectRevert();
        vm.prank(alice);
        executionEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 0,
                leverage: 2e18
            })
        );
    }

    // ─── Cross-Contract State Consistency ───

    function test_positionManagerState_matchesExecution() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);

        // Entry PI should match oracle PI at time of open (with smoothing)
        uint256 currentPI = oracleAdapter.getPI(marketId);
        assertEq(pos.entryPI, currentPI);

        // Entry price should differ from PI by impact amount
        assertGe(pos.entryPrice, pos.entryPI); // long: entry_price >= PI
    }

    function test_marginEngine_computesEquity_afterOpen() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);

        // Right after open, PnL should be slightly negative (entry impact)
        // Borrow fees should be ~0 (just opened)
        // Equity should be close to collateral
        assertGt(uint256(eq.equity), 0);
        assertEq(eq.accruedBorrowFees, 0);
        assertEq(eq.accruedFunding, 0);
    }

    function test_borrowFeeIndex_snapshotted() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);

        // Borrow index should be snapshotted at open
        uint256 currentIndex = borrowFeeEngine.getBorrowIndex(marketId, true);
        assertEq(pos.borrowIndex, currentIndex);
    }

    function test_fundingIndex_snapshotted() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);

        int256 currentIndex = fundingRateEngine.getFundingIndex(marketId);
        assertEq(pos.fundingIndex, currentIndex);
    }

    // ─── Full Lifecycle ───

    function test_fullLifecycle_openModifyClose() public {
        // 1. Open long at PI=0.50
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);
        assertTrue(positionManager.isPositionOpen(posId));

        // 2. Add collateral
        _fundUser(alice, 200e18);
        vm.prank(alice);
        executionEngine.addCollateral(posId, 200e18);

        // 3. PI moves favorably
        _pushPI(55e16); // 0.55

        // 4. Check equity increased
        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);
        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        // Long + PI up → positive PnL
        assertGt(eq.pnl, 0);
        assertGt(uint256(eq.equity), pos.collateral);

        // 5. Close with profit
        _closePosition(alice, posId);
        assertFalse(positionManager.isPositionOpen(posId));

        // 6. OI should be zero
        assertEq(oiLimits.getGlobalOI(), 0);
    }

    function test_fullLifecycle_openPIDropsClose() public {
        // 1. Open short at PI=0.50
        uint256 posId = _openPosition(alice, false, 500e18, 2e18);

        // 2. PI rises (bad for short)
        _pushPI(55e16);

        // 3. Check equity decreased
        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);
        assertLt(eq.pnl, 0); // Short + PI up → negative PnL

        // 4. Close with loss
        _closePosition(alice, posId);
        assertFalse(positionManager.isPositionOpen(posId));
    }

    function test_multipleUsers_independentPositions() public {
        // Alice opens long
        uint256 posAlice = _openPosition(alice, true, 1000e18, 2e18);
        // Bob opens short
        uint256 posBob = _openPosition(bob, false, 800e18, 2e18);

        // PI moves up — good for alice, bad for bob
        _pushPI(55e16);

        IMarginEngine.EquityResult memory eqAlice = marginEngine.computeEquity(posAlice);
        IMarginEngine.EquityResult memory eqBob = marginEngine.computeEquity(posBob);

        assertGt(eqAlice.pnl, 0); // Long profits from PI up
        assertLt(eqBob.pnl, 0);   // Short loses from PI up

        // Both can close independently
        _closePosition(alice, posAlice);
        _closePosition(bob, posBob);

        assertEq(oiLimits.getGlobalOI(), 0);
    }
}
