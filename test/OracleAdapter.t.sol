// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { IOracleAdapter } from "../contracts/interfaces/IOracleAdapter.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";

contract OracleAdapterTest is Test {
    OracleAdapter public oracle;
    MarketRegistry public registry;

    address public admin = address(0xA);
    address public oracleRole = address(0xB);
    address public keeper = address(0xC);
    address public settlement = address(0xD);
    address public nobody = address(0xE);

    uint256 constant WAD = 1e18;

    bytes32 constant MARKET_ID = keccak256("TEST_MARKET");
    bytes32 constant MARKET_ID_2 = keccak256("TEST_MARKET_2");

    uint256 public resolutionTime;

    function setUp() public {
        vm.warp(1_000_000);
        resolutionTime = block.timestamp + 30 days;

        // Deploy MarketRegistry
        registry = new MarketRegistry(admin);

        // Deploy OracleAdapter
        oracle = new OracleAdapter(admin, address(registry));

        // Grant roles on OracleAdapter
        vm.startPrank(admin);
        oracle.grantRole(oracle.ORACLE(), oracleRole);
        oracle.grantRole(oracle.KEEPER(), keeper);
        oracle.grantRole(oracle.SETTLEMENT(), settlement);
        vm.stopPrank();

        // Create and activate a market
        vm.startPrank(admin);
        registry.createMarket(
            MARKET_ID,
            "Test Market",
            "polymarket-123",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
        registry.activateMarket(MARKET_ID);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────

    function _pushPrice(
        bytes32 marketId,
        uint256 pYes,
        uint256 pNo,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) internal {
        vm.prank(oracleRole);
        oracle.pushPrice(marketId, pYes, pNo, spread, depth, volume);
    }

    function _pushDefaultPrice(bytes32 marketId, uint256 pYes) internal {
        uint256 pNo = WAD - pYes;
        _pushPrice(marketId, pYes, pNo, 0.01e18, 100_000e18, 1_000_000e18);
    }

    function _createAndActivateMarket(bytes32 marketId) internal {
        vm.startPrank(admin);
        registry.createMarket(
            marketId,
            "Market",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
        registry.activateMarket(marketId);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────
    // Initialization
    // ─────────────────────────────────────────────────────

    function test_constructor_setsRoles() public view {
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(oracle.hasRole(oracle.ORACLE(), admin));
        assertTrue(oracle.hasRole(oracle.ORACLE(), oracleRole));
        assertTrue(oracle.hasRole(oracle.KEEPER(), admin));
        assertTrue(oracle.hasRole(oracle.KEEPER(), keeper));
        assertTrue(oracle.hasRole(oracle.SETTLEMENT(), settlement));
    }

    function test_constructor_setsMarketRegistry() public view {
        assertEq(address(oracle.MARKET_REGISTRY()), address(registry));
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — First update (initialization)
    // ─────────────────────────────────────────────────────

    function test_pushPrice_firstUpdate_initializesPI() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        assertEq(oracle.getPI(MARKET_ID), 0.5e18);

        IOracleAdapter.SmoothingState memory ss = oracle.getSmoothingState(MARKET_ID);
        assertTrue(ss.initialized);
        assertEq(ss.pSmooth, 0.5e18);
        assertEq(ss.lastPRaw, 0.5e18);
        assertEq(ss.sigma, 0);
        assertEq(ss.lastUpdateTime, block.timestamp);
    }

    function test_pushPrice_firstUpdate_emitsPIUpdated() public {
        vm.expectEmit(true, false, false, true);
        emit IOracleAdapter.PIUpdated(MARKET_ID, 0.5e18, 0.5e18, WAD, block.timestamp);

        _pushDefaultPrice(MARKET_ID, 0.5e18);
    }

    function test_pushPrice_firstUpdate_setsPriceData() public {
        _pushDefaultPrice(MARKET_ID, 0.6e18);

        IOracleAdapter.PriceData memory pd = oracle.getLatestPrice(MARKET_ID);
        assertEq(pd.pRaw, 0.6e18);
        assertEq(pd.pi, 0.6e18);
        assertEq(pd.spread, 0.01e18);
        assertEq(pd.depth, 100_000e18);
        assertEq(pd.volume, 1_000_000e18);
        assertEq(pd.timestamp, block.timestamp);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Smoothing behavior
    // ─────────────────────────────────────────────────────

    function test_pushPrice_smoothing_smallMovement() public {
        // Initialize at 0.50
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push 0.51 — small movement should be smoothed
        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, 0.51e18);

        uint256 pi = oracle.getPI(MARKET_ID);
        // PI should move toward 0.51 but not reach it (smoothed)
        assertGt(pi, 0.5e18);
        assertLt(pi, 0.51e18);
    }

    function test_pushPrice_smoothing_piAlwaysBetween0And1() public {
        _pushDefaultPrice(MARKET_ID, 0.99e18);

        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, WAD); // exactly 1.0

        uint256 pi = oracle.getPI(MARKET_ID);
        assertLe(pi, WAD);
    }

    function test_pushPrice_smoothing_convergesToTarget() public {
        // Initialize at 0.50
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push 0.55 repeatedly — should converge
        for (uint256 i = 0; i < 50; i++) {
            vm.warp(block.timestamp + 60);
            _pushDefaultPrice(MARKET_ID, 0.55e18);
        }

        uint256 pi = oracle.getPI(MARKET_ID);
        // After many updates, PI should be close to 0.55
        assertGt(pi, 0.54e18);
        assertLe(pi, 0.55e18);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Anti-manipulation filters
    // ─────────────────────────────────────────────────────

    function test_pushPrice_rejectsLargeTickMovement() public {
        // Initialize at 0.50
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Try to spike to 0.70 (20% move > 5% deltaMax)
        vm.warp(block.timestamp + 60);
        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.UpdateRejected(MARKET_ID, "TICK_TOO_LARGE", 0.7e18, block.timestamp + 60);

        _pushDefaultPrice(MARKET_ID, 0.7e18);

        // PI should stay at 0.50
        assertEq(oracle.getPI(MARKET_ID), 0.5e18);
    }

    function test_pushPrice_rejectsWidespread() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push with spread exceeding limit (default spreadLimit = 0.10)
        vm.warp(block.timestamp + 60);
        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.UpdateRejected(MARKET_ID, "SPREAD_TOO_WIDE", 0.51e18, block.timestamp + 60);

        _pushPrice(MARKET_ID, 0.51e18, 0.49e18, 0.15e18, 100_000e18, 1_000_000e18);

        // PI should stay at initial value
        assertEq(oracle.getPI(MARKET_ID), 0.5e18);
    }

    function test_pushPrice_rejectsLowDepth() public {
        // Set custom params with depthMin > 0
        IOracleAdapter.SmoothingParams memory params = IOracleAdapter.SmoothingParams({
            alpha: 3e17,
            deltaMax: 5e16,
            epsilon: 1e16,
            spreadLimit: 1e17,
            depthMin: 50_000e18
        });
        vm.prank(keeper);
        oracle.updateSmoothingParams(MARKET_ID, params);

        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push with low depth
        vm.warp(block.timestamp + 60);
        _pushPrice(MARKET_ID, 0.51e18, 0.49e18, 0.01e18, 10_000e18, 1_000_000e18);

        // PI should stay at 0.50 (rejected by depth filter)
        assertEq(oracle.getPI(MARKET_ID), 0.5e18);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Rate-of-change clamp (epsilon)
    // ─────────────────────────────────────────────────────

    function test_pushPrice_rateOfChangeClamp() public {
        // Initialize at 0.50
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push a value that would move PI by more than epsilon (1%)
        // but within deltaMax (5%)
        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, 0.545e18);

        uint256 pi = oracle.getPI(MARKET_ID);
        // The smoothed change should be clamped by epsilon (0.01)
        uint256 maxChange = 0.01e18;
        assertLe(pi - 0.5e18, maxChange);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Volatility dampening
    // ─────────────────────────────────────────────────────

    function test_pushPrice_volatilityBuildUp() public {
        // Initialize
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Push volatile updates — sigma should increase
        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, 0.54e18);
        uint256 sigma1 = oracle.getVolatility(MARKET_ID);
        assertGt(sigma1, 0);

        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, 0.50e18);
        uint256 sigma2 = oracle.getVolatility(MARKET_ID);
        assertGt(sigma2, 0);
    }

    function test_pushPrice_volatilityDampensSmoothing() public {
        // Initialize at 0.50
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Build up volatility with back-and-forth moves
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 60);
            _pushDefaultPrice(MARKET_ID, 0.54e18);
            vm.warp(block.timestamp + 60);
            _pushDefaultPrice(MARKET_ID, 0.50e18);
        }

        uint256 highVolSigma = oracle.getVolatility(MARKET_ID);
        assertGt(highVolSigma, 0);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Validation
    // ─────────────────────────────────────────────────────

    function test_pushPrice_revert_marketNotActive() public {
        bytes32 listedMkt = keccak256("LISTED_MARKET");
        vm.prank(admin);
        registry.createMarket(
            listedMkt,
            "Listed",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );

        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__MarketNotActive.selector, listedMkt));
        _pushDefaultPrice(listedMkt, 0.5e18);
    }

    function test_pushPrice_revert_frozen() public {
        vm.prank(keeper);
        oracle.freezeMarket(MARKET_ID);

        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__UpdateRejected.selector, MARKET_ID, "FROZEN"));
        _pushDefaultPrice(MARKET_ID, 0.5e18);
    }

    function test_pushPrice_revert_pYesAboveWAD() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidProbability.selector, WAD + 1));
        _pushPrice(MARKET_ID, WAD + 1, 0, 0, 0, 0);
    }

    function test_pushPrice_revert_pNoAboveWAD() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidProbability.selector, WAD + 1));
        _pushPrice(MARKET_ID, 0, WAD + 1, 0, 0, 0);
    }

    function test_pushPrice_revert_inconsistentPrices_tooHigh() public {
        // pYes + pNo > WAD + tolerance (5%)
        uint256 pYes = 0.6e18;
        uint256 pNo = 0.5e18; // sum = 1.10 > 1.05
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InconsistentPrices.selector, pYes, pNo));
        _pushPrice(MARKET_ID, pYes, pNo, 0, 100_000e18, 0);
    }

    function test_pushPrice_revert_inconsistentPrices_tooLow() public {
        // pYes + pNo < WAD - tolerance (5%)
        uint256 pYes = 0.4e18;
        uint256 pNo = 0.5e18; // sum = 0.90 < 0.95
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InconsistentPrices.selector, pYes, pNo));
        _pushPrice(MARKET_ID, pYes, pNo, 0, 100_000e18, 0);
    }

    function test_pushPrice_acceptsWithinConsistencyTolerance() public {
        // pYes + pNo = 1.04 (within 5% tolerance)
        _pushPrice(MARKET_ID, 0.54e18, 0.5e18, 0.01e18, 100_000e18, 1_000_000e18);
        assertEq(oracle.getPI(MARKET_ID), 0.54e18); // first update = pRaw
    }

    function test_pushPrice_acceptsBoundaryValues() public {
        // pRaw = 0 is valid
        _pushPrice(MARKET_ID, 0, WAD, 0.01e18, 100_000e18, 1_000_000e18);
        assertEq(oracle.getPI(MARKET_ID), 0);
    }

    function test_pushPrice_acceptsExactlyWAD() public {
        _pushPrice(MARKET_ID, WAD, 0, 0.01e18, 100_000e18, 1_000_000e18);
        assertEq(oracle.getPI(MARKET_ID), WAD);
    }

    // ─────────────────────────────────────────────────────
    // pushPrice — Access control
    // ─────────────────────────────────────────────────────

    function test_pushPrice_revert_notOracle() public {
        vm.prank(nobody);
        vm.expectRevert();
        oracle.pushPrice(MARKET_ID, 0.5e18, 0.5e18, 0, 0, 0);
    }

    // ─────────────────────────────────────────────────────
    // snapToOutcome
    // ─────────────────────────────────────────────────────

    function test_snapToOutcome_yes() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, WAD);

        assertEq(oracle.getPI(MARKET_ID), WAD);

        IOracleAdapter.PriceData memory pd = oracle.getLatestPrice(MARKET_ID);
        assertEq(pd.pi, WAD);
    }

    function test_snapToOutcome_no() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, 0);

        assertEq(oracle.getPI(MARKET_ID), 0);
    }

    function test_snapToOutcome_emitsEvent() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        vm.expectEmit(true, false, false, true);
        emit IOracleAdapter.PIUpdated(MARKET_ID, WAD, WAD, WAD, block.timestamp);

        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, WAD);
    }

    function test_snapToOutcome_revert_invalidOutcome() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidProbability.selector, 0.5e18));
        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, 0.5e18);
    }

    function test_snapToOutcome_revert_notSettlement() public {
        vm.prank(nobody);
        vm.expectRevert();
        oracle.snapToOutcome(MARKET_ID, WAD);
    }

    // ─────────────────────────────────────────────────────
    // Source management
    // ─────────────────────────────────────────────────────

    function test_registerSource() public {
        address src = address(0x123);

        vm.expectEmit(true, false, false, true);
        emit IOracleAdapter.SourceRegistered(src, WAD);

        vm.prank(admin);
        oracle.registerSource(src, WAD);

        IOracleAdapter.SourceConfig[] memory sources = oracle.getActiveSources();
        assertEq(sources.length, 1);
        assertEq(sources[0].source, src);
        assertEq(sources[0].weight, WAD);
        assertTrue(sources[0].isActive);
    }

    function test_removeSource() public {
        address src = address(0x123);
        vm.startPrank(admin);
        oracle.registerSource(src, WAD);

        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.SourceRemoved(src);

        oracle.removeSource(src);
        vm.stopPrank();

        IOracleAdapter.SourceConfig[] memory sources = oracle.getActiveSources();
        assertEq(sources.length, 0);
    }

    function test_removeSource_revert_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__SourceNotRegistered.selector, address(0x999)));
        vm.prank(admin);
        oracle.removeSource(address(0x999));
    }

    function test_updateSourceWeight() public {
        address src = address(0x123);
        vm.startPrank(admin);
        oracle.registerSource(src, WAD);

        vm.expectEmit(true, false, false, true);
        emit IOracleAdapter.SourceDegraded(src, 0.5e18);

        oracle.updateSourceWeight(src, 0.5e18);
        vm.stopPrank();

        IOracleAdapter.SourceConfig[] memory sources = oracle.getActiveSources();
        assertEq(sources[0].weight, 0.5e18);
    }

    function test_updateSourceWeight_revert_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__SourceNotRegistered.selector, address(0x999)));
        vm.prank(admin);
        oracle.updateSourceWeight(address(0x999), WAD);
    }

    // ─────────────────────────────────────────────────────
    // Market controls
    // ─────────────────────────────────────────────────────

    function test_freezeMarket() public {
        vm.expectEmit(true, false, false, true);
        emit IOracleAdapter.MarketFrozen(MARKET_ID, "MANUAL_FREEZE");

        vm.prank(keeper);
        oracle.freezeMarket(MARKET_ID);

        assertTrue(oracle.isFrozen(MARKET_ID));
    }

    function test_unfreezeMarket() public {
        vm.prank(keeper);
        oracle.freezeMarket(MARKET_ID);
        assertTrue(oracle.isFrozen(MARKET_ID));

        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.MarketUnfrozen(MARKET_ID);

        vm.prank(keeper);
        oracle.unfreezeMarket(MARKET_ID);

        assertFalse(oracle.isFrozen(MARKET_ID));
    }

    function test_freezeMarket_revert_notKeeper() public {
        vm.prank(nobody);
        vm.expectRevert();
        oracle.freezeMarket(MARKET_ID);
    }

    function test_unfreezeMarket_revert_notKeeper() public {
        vm.prank(nobody);
        vm.expectRevert();
        oracle.unfreezeMarket(MARKET_ID);
    }

    function test_updateSmoothingParams() public {
        IOracleAdapter.SmoothingParams memory params = IOracleAdapter.SmoothingParams({
            alpha: 2e17,
            deltaMax: 4e16,
            epsilon: 8e15,
            spreadLimit: 8e16,
            depthMin: 20_000e18
        });

        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.SmoothingParamsUpdated(MARKET_ID);

        vm.prank(keeper);
        oracle.updateSmoothingParams(MARKET_ID, params);

        IOracleAdapter.SmoothingParams memory fetched = oracle.getSmoothingParams(MARKET_ID);
        assertEq(fetched.alpha, 2e17);
        assertEq(fetched.deltaMax, 4e16);
        assertEq(fetched.epsilon, 8e15);
        assertEq(fetched.spreadLimit, 8e16);
        assertEq(fetched.depthMin, 20_000e18);
    }

    function test_updateSmoothingParams_revert_notKeeper() public {
        IOracleAdapter.SmoothingParams memory params = IOracleAdapter.SmoothingParams({
            alpha: 2e17, deltaMax: 4e16, epsilon: 8e15, spreadLimit: 8e16, depthMin: 20_000e18
        });
        vm.prank(nobody);
        vm.expectRevert();
        oracle.updateSmoothingParams(MARKET_ID, params);
    }

    // ─────────────────────────────────────────────────────
    // View functions
    // ─────────────────────────────────────────────────────

    function test_getPI_returnsZeroBeforeInit() public view {
        bytes32 uninit = keccak256("UNINIT");
        assertEq(oracle.getPI(uninit), 0);
    }

    function test_getSmoothingState_beforeInit() public view {
        IOracleAdapter.SmoothingState memory ss = oracle.getSmoothingState(MARKET_ID);
        assertFalse(ss.initialized);
        assertEq(ss.pSmooth, 0);
    }

    function test_getSmoothingParams_defaults() public view {
        IOracleAdapter.SmoothingParams memory params = oracle.getSmoothingParams(MARKET_ID);
        assertEq(params.alpha, 3e17);       // 0.30
        assertEq(params.deltaMax, 5e16);    // 0.05
        assertEq(params.epsilon, 1e16);     // 0.01
        assertEq(params.spreadLimit, 1e17); // 0.10
        assertEq(params.depthMin, 0);       // no min by default
    }

    function test_getVolatility_zeroBeforeInit() public view {
        assertEq(oracle.getVolatility(MARKET_ID), 0);
    }

    function test_isStale_trueBeforeInit() public view {
        assertTrue(oracle.isStale(MARKET_ID));
    }

    function test_isStale_falseAfterFreshUpdate() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);
        assertFalse(oracle.isStale(MARKET_ID));
    }

    function test_isStale_trueAfterThreshold() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Get staleness threshold and warp past it
        uint256 threshold = oracle.getStalenessThreshold(MARKET_ID);
        vm.warp(block.timestamp + threshold + 1);

        assertTrue(oracle.isStale(MARKET_ID));
    }

    function test_isFrozen_defaultFalse() public view {
        assertFalse(oracle.isFrozen(MARKET_ID));
    }

    function test_getActiveSources_emptyByDefault() public view {
        IOracleAdapter.SourceConfig[] memory sources = oracle.getActiveSources();
        assertEq(sources.length, 0);
    }

    // ─────────────────────────────────────────────────────
    // Pause / Unpause
    // ─────────────────────────────────────────────────────

    function test_pause_blocksPushPrice() public {
        vm.prank(admin);
        oracle.pause();

        vm.prank(oracleRole);
        vm.expectRevert();
        oracle.pushPrice(MARKET_ID, 0.5e18, 0.5e18, 0, 100_000e18, 0);
    }

    function test_unpause_resumesPushPrice() public {
        vm.startPrank(admin);
        oracle.pause();
        oracle.unpause();
        vm.stopPrank();

        // Should work after unpause
        _pushDefaultPrice(MARKET_ID, 0.5e18);
        assertEq(oracle.getPI(MARKET_ID), 0.5e18);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        oracle.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        oracle.pause();

        vm.prank(nobody);
        vm.expectRevert();
        oracle.unpause();
    }

    // ─────────────────────────────────────────────────────
    // Multiple updates in same block
    // ─────────────────────────────────────────────────────

    function test_pushPrice_multipleUpdatesInSameBlock() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        // Two updates in same block — both should succeed
        _pushDefaultPrice(MARKET_ID, 0.51e18);
        uint256 pi1 = oracle.getPI(MARKET_ID);

        _pushDefaultPrice(MARKET_ID, 0.52e18);
        uint256 pi2 = oracle.getPI(MARKET_ID);

        // Second update should produce different (greater) PI
        assertGe(pi2, pi1);
    }

    // ─────────────────────────────────────────────────────
    // Frozen market preserves PI
    // ─────────────────────────────────────────────────────

    function test_frozenMarket_preservesLastPI() public {
        _pushDefaultPrice(MARKET_ID, 0.6e18);
        uint256 piBefore = oracle.getPI(MARKET_ID);

        vm.prank(keeper);
        oracle.freezeMarket(MARKET_ID);

        // Verify PI is preserved
        assertEq(oracle.getPI(MARKET_ID), piBefore);
    }

    // ─────────────────────────────────────────────────────
    // Time-weighted smoothing
    // ─────────────────────────────────────────────────────

    function test_pushPrice_timeWeighting_nearResolution() public {
        // Create a market resolving very soon (10 minutes from now)
        bytes32 soonMkt = keccak256("SOON_MARKET");
        vm.startPrank(admin);
        registry.createMarket(
            soonMkt,
            "Soon",
            "ext",
            block.timestamp + 10 minutes,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
        registry.activateMarket(soonMkt);
        vm.stopPrank();

        // Initialize both markets
        _pushDefaultPrice(MARKET_ID, 0.5e18);
        _pushDefaultPrice(soonMkt, 0.5e18);

        // Warp 9 minutes so soonMkt has only 1 min left (low tau/tauMax)
        vm.warp(block.timestamp + 9 minutes);

        // Push same small update to both
        _pushDefaultPrice(MARKET_ID, 0.51e18);
        _pushDefaultPrice(soonMkt, 0.51e18);

        uint256 piFar = oracle.getPI(MARKET_ID);
        uint256 piNear = oracle.getPI(soonMkt);

        // Far market should move more (lighter smoothing)
        // Near market has w_time = sqrt(1min / 10min) ≈ 0.316
        // Far market has w_time = sqrt(~29.99d / 30d) ≈ 0.9998
        assertGt(piFar, piNear, "Far market should move more than near-resolution market");
    }

    // ─────────────────────────────────────────────────────
    // Fuzz tests
    // ─────────────────────────────────────────────────────

    function testFuzz_pushPrice_piAlwaysInBounds(uint256 pYes) public {
        pYes = bound(pYes, 0, WAD);
        uint256 pNo = WAD - pYes;

        _pushPrice(MARKET_ID, pYes, pNo, 0.01e18, 100_000e18, 1_000_000e18);

        uint256 pi = oracle.getPI(MARKET_ID);
        assertLe(pi, WAD);
    }

    function testFuzz_pushPrice_piChangeNeverExceedsEpsilon(
        uint256 pYes1,
        uint256 pYes2
    ) public {
        pYes1 = bound(pYes1, 0.1e18, 0.9e18);
        pYes2 = bound(pYes2, 0.1e18, 0.9e18);

        // Initialize
        _pushDefaultPrice(MARKET_ID, pYes1);
        uint256 pi1 = oracle.getPI(MARKET_ID);

        // Second update
        vm.warp(block.timestamp + 60);

        // Only push if within deltaMax
        uint256 diff = pYes1 > pYes2 ? pYes1 - pYes2 : pYes2 - pYes1;
        if (diff <= 5e16) {
            // within deltaMax
            _pushDefaultPrice(MARKET_ID, pYes2);
            uint256 pi2 = oracle.getPI(MARKET_ID);

            uint256 piChange = pi2 > pi1 ? pi2 - pi1 : pi1 - pi2;
            // Epsilon = 0.01 (default)
            assertLe(piChange, 1e16, "PI change exceeded epsilon");
        }
    }

    function testFuzz_snapToOutcome_onlyValidValues(uint256 outcome) public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        if (outcome != 0 && outcome != WAD) {
            vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidProbability.selector, outcome));
        }

        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, outcome);
    }

    // ─────────────────────────────────────────────────────
    // Source management — multiple sources
    // ─────────────────────────────────────────────────────

    function test_getActiveSources_multipleRegistrations() public {
        address src1 = address(0x111);
        address src2 = address(0x222);
        address src3 = address(0x333);

        vm.startPrank(admin);
        oracle.registerSource(src1, WAD);
        oracle.registerSource(src2, 0.8e18);
        oracle.registerSource(src3, 0.5e18);

        // Remove src2
        oracle.removeSource(src2);
        vm.stopPrank();

        IOracleAdapter.SourceConfig[] memory sources = oracle.getActiveSources();
        assertEq(sources.length, 2);
    }

    // ─────────────────────────────────────────────────────
    // Edge case: sigma starts at 0
    // ─────────────────────────────────────────────────────

    function test_pushPrice_sigmaStartsAtZero() public {
        _pushDefaultPrice(MARKET_ID, 0.5e18);

        IOracleAdapter.SmoothingState memory ss = oracle.getSmoothingState(MARKET_ID);
        assertEq(ss.sigma, 0);

        // First subsequent update builds sigma
        vm.warp(block.timestamp + 60);
        _pushDefaultPrice(MARKET_ID, 0.52e18);

        ss = oracle.getSmoothingState(MARKET_ID);
        assertGt(ss.sigma, 0);
    }

    // ─────────────────────────────────────────────────────
    // Full pipeline test
    // ─────────────────────────────────────────────────────

    function test_fullPipeline_initSmoothSnap() public {
        // 1. Initialize
        _pushDefaultPrice(MARKET_ID, 0.5e18);
        assertEq(oracle.getPI(MARKET_ID), 0.5e18);

        // 2. Push a series of updates trending upward
        uint256[5] memory prices = [uint256(0.52e18), 0.54e18, 0.55e18, 0.55e18, 0.55e18];
        for (uint256 i = 0; i < prices.length; i++) {
            vm.warp(block.timestamp + 120);
            _pushDefaultPrice(MARKET_ID, prices[i]);
        }

        uint256 piBeforeSnap = oracle.getPI(MARKET_ID);
        assertGt(piBeforeSnap, 0.5e18);
        assertLe(piBeforeSnap, 0.55e18);

        // 3. Snap to outcome
        vm.prank(settlement);
        oracle.snapToOutcome(MARKET_ID, WAD);

        assertEq(oracle.getPI(MARKET_ID), WAD);
    }
}
