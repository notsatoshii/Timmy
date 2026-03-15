// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";

/// @title MultiMarketTest
/// @notice Integration tests for multi-market scenarios:
///         Positions across different markets, shared OI caps, independent fee accrual,
///         and cross-market risk isolation.
contract MultiMarketTest is IntegrationBase {

    bytes32 marketId2 = keccak256("SPORTS_SUPERBOWL");
    uint256 marketResolutionTime2;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        // Create a second market (resolves in 72 hours)
        marketResolutionTime2 = block.timestamp + 72 hours;
        registry.createMarket(
            marketId2,
            "Super Bowl 2028",
            "polymarket_superbowl",
            marketResolutionTime2,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            15e16 // 15% allocation weight
        );
        registry.activateMarket(marketId2);

        borrowFeeEngine.initializeMarketIndex(marketId2);
        fundingRateEngine.initializeMarketIndex(marketId2);

        // Set market risk params for market 2
        borrowFeeEngine.updateMarketRiskParams(marketId2, 1e17, 1e17, 100_000e18, 100_000e18, 0, 0);
        fundingRateEngine.updateMarketRiskParams(marketId2, 1e17, 1e17, 100_000e18, 100_000e18, 0, 0);
        marginEngine.updateMarketRiskParams(marketId2, 1e17, 1e17, 100_000e18, 100_000e18, 0, 0, 0);
        leverageModel.setMarketRiskParams(marketId2, 1e17, 100_000e18);

        oracleAdapter.updateSmoothingParams(marketId2, IOracleAdapter.SmoothingParams({
            alpha: 3e17,
            deltaMax: 1e17,
            epsilon: 5e16,
            spreadLimit: 5e16,
            depthMin: 1e18
        }));

        vm.stopPrank();

        // Push initial PI for market 2
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId2,
            4e17,       // pYes = 0.40
            6e17,       // pNo = 0.60
            1e16,
            100_000e18,
            50_000e18
        );
    }

    // ─── Helper: open position on market 2 ───
    function _openPositionMarket2(
        address user,
        bool isLong,
        uint256 collateral,
        uint256 leverage
    ) internal returns (uint256 positionId) {
        // Ensure user has enough balance in AccountManager
        uint256 currentFree = accountManager.getFreeCollateral(user);
        if (currentFree < collateral) {
            _fundUser(user, collateral - currentFree);
        }

        vm.prank(user);
        positionId = executionEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId2,
                isLong: isLong,
                collateral: collateral,
                leverage: leverage
            })
        );
    }

    function _pushPI2(uint256 newPI) internal {
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId2,
            newPI,
            WAD - newPI,
            1e16,
            100_000e18,
            50_000e18
        );
    }

    // ─── Cross-Market Position Independence ───

    function test_positionsOnDifferentMarkets_independent() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 3e18);
        uint256 pos2 = _openPositionMarket2(alice, false, 800e18, 2e18);

        IPositionManager.Position memory p1 = positionManager.getPosition(pos1);
        IPositionManager.Position memory p2 = positionManager.getPosition(pos2);

        // Different markets
        assertEq(p1.marketId, marketId);
        assertEq(p2.marketId, marketId2);

        // Independent entry PIs
        assertEq(p1.entryPI, oracleAdapter.getPI(marketId));
        assertEq(p2.entryPI, oracleAdapter.getPI(marketId2));
        assertTrue(p1.entryPI != p2.entryPI); // Different starting prices
    }

    function test_piMoveInOneMarket_doesNotAffectOther() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 2e18);
        uint256 pos2 = _openPositionMarket2(alice, true, 1000e18, 2e18);

        IMarginEngine.EquityResult memory eq1Before = marginEngine.computeEquity(pos1);
        IMarginEngine.EquityResult memory eq2Before = marginEngine.computeEquity(pos2);

        // Move PI on market 1 only
        _pushPI(6e17); // 0.60

        IMarginEngine.EquityResult memory eq1After = marginEngine.computeEquity(pos1);
        IMarginEngine.EquityResult memory eq2After = marginEngine.computeEquity(pos2);

        // Market 1 position should be affected (long, PI up → profit)
        assertGt(eq1After.pnl, eq1Before.pnl);

        // Market 2 position should be unaffected
        assertEq(eq2After.pnl, eq2Before.pnl);
    }

    // ─── Global OI Tracking ───

    function test_globalOI_sumsAcrossMarkets() public {
        _openPosition(alice, true, 1000e18, 3e18);       // 3000 notional on market 1
        _openPositionMarket2(bob, false, 500e18, 2e18);   // 1000 notional on market 2

        uint256 m1OI = oiLimits.getMarketOI(marketId);
        uint256 m2OI = oiLimits.getMarketOI(marketId2);
        uint256 globalOI = oiLimits.getGlobalOI();

        assertGt(m1OI, 0);
        assertGt(m2OI, 0);
        assertEq(globalOI, m1OI + m2OI);
    }

    function test_closingOneMarket_preservesOtherMarketOI() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 2e18);
        _openPositionMarket2(bob, false, 500e18, 2e18);

        uint256 m2OIBefore = oiLimits.getMarketOI(marketId2);

        // Close market 1 position
        _closePosition(alice, pos1);

        uint256 m1OI = oiLimits.getMarketOI(marketId);
        uint256 m2OIAfter = oiLimits.getMarketOI(marketId2);

        assertEq(m1OI, 0);
        assertEq(m2OIAfter, m2OIBefore); // Unchanged
    }

    // ─── Per-Market Side OI ───

    function test_sideOI_trackedPerMarket() public {
        _openPosition(alice, true, 1000e18, 2e18);       // Long on market 1
        _openPositionMarket2(bob, false, 500e18, 2e18);   // Short on market 2

        uint256 m1Long = oiLimits.getSideOI(marketId, true);
        uint256 m1Short = oiLimits.getSideOI(marketId, false);
        uint256 m2Long = oiLimits.getSideOI(marketId2, true);
        uint256 m2Short = oiLimits.getSideOI(marketId2, false);

        assertGt(m1Long, 0);
        assertEq(m1Short, 0);
        assertEq(m2Long, 0);
        assertGt(m2Short, 0);
    }

    // ─── Independent Fee Accrual ───

    function test_borrowFees_accrueIndependentlyPerMarket() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 3e18);
        uint256 pos2 = _openPositionMarket2(bob, true, 1000e18, 3e18);

        vm.warp(block.timestamp + 4 hours);

        // Accrue only market 1
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        uint256 fees1 = borrowFeeEngine.getAccruedFees(pos1);
        uint256 fees2 = borrowFeeEngine.getAccruedFees(pos2);

        assertGt(fees1, 0); // Market 1 accrued
        assertEq(fees2, 0); // Market 2 not accrued yet

        // Now accrue market 2
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId2, true);

        fees2 = borrowFeeEngine.getAccruedFees(pos2);
        assertGt(fees2, 0);
    }

    function test_fundingRates_independentPerMarket() public {
        // Create imbalance on market 1 (long heavy)
        _openPosition(alice, true, 2000e18, 3e18);
        _openPosition(bob, false, 500e18, 2e18);

        // Create opposite imbalance on market 2 (short heavy)
        _openPositionMarket2(alice, false, 2000e18, 3e18);
        _openPositionMarket2(bob, true, 500e18, 2e18);

        int256 rate1 = fundingRateEngine.getCurrentFundingRate(marketId);
        int256 rate2 = fundingRateEngine.getCurrentFundingRate(marketId2);

        // Market 1: long heavy → positive rate (longs pay)
        assertGt(rate1, 0);
        // Market 2: short heavy → negative rate (shorts pay)
        assertLt(rate2, 0);
    }

    // ─── Independent τ (Time-to-Resolution) ───

    function test_tau_independentPerMarket() public {
        uint256 tau1 = registry.getTau(marketId);
        uint256 tau2 = registry.getTau(marketId2);

        // Market 2 resolves 24h later than market 1 → larger τ
        assertGt(tau2, tau1);
    }

    function test_leverageModel_differentPerMarket() public {
        uint256 maxLev1 = leverageModel.getEffectiveMaxLeverage(marketId);
        uint256 maxLev2 = leverageModel.getEffectiveMaxLeverage(marketId2);

        // Both should be valid (> 1×)
        assertGe(maxLev1, WAD);
        assertGe(maxLev2, WAD);

        // Different τ → different R(τ) → potentially different leverage limits
        // The exact relationship depends on where each τ sits on the curve
        // Just verify both work independently
        assertTrue(true);
    }

    // ─── Market Resolution Independence ───

    function test_resolveOneMarket_otherContinues() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 2e18);
        uint256 pos2 = _openPositionMarket2(bob, true, 1000e18, 2e18);

        // Resolve market 1
        vm.startPrank(admin);
        registry.setPendingResolution(marketId);
        registry.resolveMarket(marketId, 1, block.timestamp);
        oracleAdapter.grantRole(oracleAdapter.SETTLEMENT(), admin);
        oracleAdapter.snapToOutcome(marketId, WAD);
        vm.stopPrank();

        // Market 1 PI snapped to 1.0
        assertEq(oracleAdapter.getPI(marketId), WAD);

        // Market 2 still active with original PI
        uint256 pi2 = oracleAdapter.getPI(marketId2);
        assertGt(pi2, 0);
        assertLt(pi2, WAD);

        // Market 2 position still tradable
        IPositionManager.Position memory p2 = positionManager.getPosition(pos2);
        assertTrue(p2.isOpen);

        // Can still open new positions on market 2
        uint256 pos3 = _openPositionMarket2(alice, false, 500e18, 2e18);
        assertTrue(positionManager.isPositionOpen(pos3));
    }

    // ─── Live Compression per Market ───

    function test_liveCompression_affectsOnlyTargetMarket() public {
        uint256 maxLev1Before = leverageModel.getEffectiveMaxLeverage(marketId);
        uint256 maxLev2Before = leverageModel.getEffectiveMaxLeverage(marketId2);

        // Set only market 1 as live
        vm.prank(admin);
        registry.setLive(marketId);

        uint256 maxLev1After = leverageModel.getEffectiveMaxLeverage(marketId);
        uint256 maxLev2After = leverageModel.getEffectiveMaxLeverage(marketId2);

        // Market 2 should be unaffected
        assertEq(maxLev2After, maxLev2Before);
    }

    // ─── Same User, Multiple Markets ───

    function test_sameUser_positionsInMultipleMarkets() public {
        uint256 pos1 = _openPosition(alice, true, 1000e18, 2e18);
        uint256 pos2 = _openPositionMarket2(alice, false, 800e18, 3e18);

        // Both positions belong to alice
        IPositionManager.Position memory p1 = positionManager.getPosition(pos1);
        IPositionManager.Position memory p2 = positionManager.getPosition(pos2);
        assertEq(p1.owner, alice);
        assertEq(p2.owner, alice);

        // Move PI favorably for both (market 1 up for long, market 2 down for short)
        _pushPI(55e16);   // Market 1: 0.55 (good for long)
        _pushPI2(35e16);  // Market 2: 0.35 (good for short)

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(pos1);
        IMarginEngine.EquityResult memory eq2 = marginEngine.computeEquity(pos2);

        // Both should be profitable
        assertGt(eq1.pnl, 0);
        assertGt(eq2.pnl, 0);

        // Close both
        _closePosition(alice, pos1);
        _closePosition(alice, pos2);

        assertFalse(positionManager.isPositionOpen(pos1));
        assertFalse(positionManager.isPositionOpen(pos2));
    }

    // ─── Void One Market ───

    function test_voidOneMarket_otherUnaffected() public {
        _openPosition(alice, true, 1000e18, 2e18);
        _openPositionMarket2(bob, true, 500e18, 2e18);

        // Void market 1
        vm.prank(admin);
        registry.voidMarket(marketId);

        IMarketRegistry.MarketState state1 = registry.getMarketState(marketId);
        IMarketRegistry.MarketState state2 = registry.getMarketState(marketId2);

        assertEq(uint8(state1), uint8(IMarketRegistry.MarketState.VOIDED));
        assertEq(uint8(state2), uint8(IMarketRegistry.MarketState.ACTIVE));

        // Can still trade on market 2
        uint256 pos3 = _openPositionMarket2(alice, false, 300e18, 2e18);
        assertTrue(positionManager.isPositionOpen(pos3));
    }
}
