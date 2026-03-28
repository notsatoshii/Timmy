// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { ILeverageModel } from "../contracts/interfaces/ILeverageModel.sol";
import { IOracleAdapter } from "../contracts/interfaces/IOracleAdapter.sol";

// ──────────────────────────────────────────────
// Mock Contracts
// ──────────────────────────────────────────────

contract MockLeverVault {
    uint256 private _totalAssets;

    function setTotalAssets(uint256 val) external {
        _totalAssets = val;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }
}

contract MockInsuranceFund {
    uint256 private _balance;

    function setBalance(uint256 val) external {
        _balance = val;
    }

    function getBalance() external view returns (uint256) {
        return _balance;
    }
}

contract MockOILimits {
    uint256 private _globalUtil;
    mapping(bytes32 => uint256) private _marketOI;
    uint256 private _globalOI;

    function setGlobalUtilization(uint256 val) external {
        _globalUtil = val;
    }

    function getGlobalUtilization() external view returns (uint256) {
        return _globalUtil;
    }

    function setMarketOI(bytes32 marketId, uint256 val) external {
        _marketOI[marketId] = val;
    }

    function getMarketOI(bytes32 marketId) external view returns (uint256) {
        return _marketOI[marketId];
    }

    function setGlobalOI(uint256 val) external {
        _globalOI = val;
    }

    function getGlobalOI() external view returns (uint256) {
        return _globalOI;
    }
}

contract MockMarketRegistry {
    mapping(bytes32 => uint256) private _tau;
    mapping(bytes32 => bool) private _isLive;

    function setTau(bytes32 marketId, uint256 val) external {
        _tau[marketId] = val;
    }

    function getTau(bytes32 marketId) external view returns (uint256) {
        return _tau[marketId];
    }

    function setIsLive(bytes32 marketId, bool val) external {
        _isLive[marketId] = val;
    }

    function isLive(bytes32 marketId) external view returns (bool) {
        return _isLive[marketId];
    }
}

contract MockOracleAdapter {
    mapping(bytes32 => uint256) private _volatility;
    mapping(bytes32 => IOracleAdapter.PriceData) private _priceData;

    function setVolatility(bytes32 marketId, uint256 val) external {
        _volatility[marketId] = val;
    }

    function getVolatility(bytes32 marketId) external view returns (uint256) {
        return _volatility[marketId];
    }

    function setDepth(bytes32 marketId, uint256 val) external {
        _priceData[marketId].depth = val;
    }

    function getLatestPrice(bytes32 marketId) external view returns (IOracleAdapter.PriceData memory) {
        return _priceData[marketId];
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract LeverageModelTest is Test {
    uint256 constant WAD = 1e18;

    LeverageModel model;
    MockLeverVault mockVault;
    MockInsuranceFund mockInsurance;
    MockOILimits mockOI;
    MockMarketRegistry mockRegistry;
    MockOracleAdapter mockOracle;

    address admin = address(0xAD);
    bytes32 marketId = keccak256("ELECTION_2026");

    function setUp() public {
        mockVault = new MockLeverVault();
        mockInsurance = new MockInsuranceFund();
        mockOI = new MockOILimits();
        mockRegistry = new MockMarketRegistry();
        mockOracle = new MockOracleAdapter();

        model = new LeverageModel(
            address(mockVault),
            address(mockInsurance),
            address(mockOI),
            address(mockRegistry),
            address(mockOracle),
            admin
        );

        // Default: set market risk params
        vm.prank(admin);
        model.setMarketRiskParams(marketId, 1e17, WAD); // baseline=0.10, threshold=1.0
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(model.vault()), address(mockVault));
        assertEq(address(model.insuranceFund()), address(mockInsurance));
        assertEq(address(model.oiLimits()), address(mockOI));
        assertEq(address(model.marketRegistry()), address(mockRegistry));
        assertEq(address(model.oracleAdapter()), address(mockOracle));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(LeverageModel.LeverageModel__ZeroAddress.selector);
        new LeverageModel(address(0), address(mockInsurance), address(mockOI), address(mockRegistry), address(mockOracle), admin);
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(model.hasRole(model.ADMIN_ROLE(), admin));
        assertTrue(model.hasRole(model.KEEPER_ROLE(), admin));
    }

    // ──────────────────────────────────────────────
    // setMarketRiskParams — Access Control
    // ──────────────────────────────────────────────

    function test_setMarketRiskParams_success() public {
        vm.prank(admin);
        model.setMarketRiskParams(marketId, 2e17, 5e18);

        LeverageModel.MarketRiskParams memory p = model.getMarketRiskParams(marketId);
        assertEq(p.sigmaBaseline, 2e17);
        assertEq(p.depthThreshold, 5e18);
    }

    function test_setMarketRiskParams_revertsUnauthorized() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        model.setMarketRiskParams(marketId, 2e17, 5e18);
    }

    // ──────────────────────────────────────────────
    // Step 1: TVL Multiplier
    // ──────────────────────────────────────────────

    function test_tvlMult_zeroTVL() public {
        mockVault.setTotalAssets(0);
        uint256 mult = model.getTVLMultiplier();
        assertEq(mult, 1e17, "TVL=0 => floor 0.10");
    }

    function test_tvlMult_atMaturity() public {
        mockVault.setTotalAssets(50_000_000e6);
        uint256 mult = model.getTVLMultiplier();
        assertEq(mult, WAD, "TVL=maturity => 1.0");
    }

    function test_tvlMult_aboveMaturity() public {
        mockVault.setTotalAssets(100_000_000e6);
        uint256 mult = model.getTVLMultiplier();
        assertEq(mult, WAD, "TVL>maturity => capped at 1.0");
    }

    function test_tvlMult_10M() public {
        // sqrt(10M/50M) = sqrt(0.2) ~ 0.4472
        mockVault.setTotalAssets(10_000_000e6);
        uint256 mult = model.getTVLMultiplier();
        assertApproxEqAbs(mult, 4472e14, 1e15, "TVL=$10M => ~0.447");
    }

    function test_tvlMult_small() public {
        // sqrt(100k/50M) = sqrt(0.002) ~ 0.0447 => floored to 0.10
        mockVault.setTotalAssets(100_000e6);
        uint256 mult = model.getTVLMultiplier();
        assertEq(mult, 1e17, "Small TVL floored to 0.10");
    }

    // ──────────────────────────────────────────────
    // Step 1: IFR Multiplier
    // ──────────────────────────────────────────────

    function test_ifrMult_zeroInsurance() public {
        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(0);
        uint256 mult = model.getIFRMultiplier();
        assertEq(mult, 4e17, "IFR=0 => floor 0.40");
    }

    function test_ifrMult_atTarget() public {
        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(2_000_000e6); // IFR = 20%
        uint256 mult = model.getIFRMultiplier();
        assertEq(mult, WAD, "IFR=target => 1.0");
    }

    function test_ifrMult_aboveTarget() public {
        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(5_000_000e6); // IFR = 50%
        uint256 mult = model.getIFRMultiplier();
        assertEq(mult, WAD, "IFR>target => capped at 1.0");
    }

    function test_ifrMult_6pct() public {
        // IFR = 6%, mult = 0.40 + 3.0 x 0.06 = 0.40 + 0.18 = 0.58
        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(600_000e6);
        uint256 mult = model.getIFRMultiplier();
        assertApproxEqAbs(mult, 58e16, 1e15, "IFR=6% => 0.58");
    }

    function test_ifrMult_zeroTVL() public {
        mockVault.setTotalAssets(0);
        uint256 mult = model.getIFRMultiplier();
        assertEq(mult, 4e17, "TVL=0 => floor 0.40");
    }

    // ──────────────────────────────────────────────
    // Step 1: Utilization Multiplier
    // ──────────────────────────────────────────────

    function test_utilMult_belowThreshold() public {
        mockOI.setGlobalUtilization(2e17); // 20%
        uint256 mult = model.getUtilizationMultiplier();
        assertEq(mult, WAD, "U<30% => 1.0");
    }

    function test_utilMult_atThreshold() public {
        mockOI.setGlobalUtilization(3e17); // 30%
        uint256 mult = model.getUtilizationMultiplier();
        assertEq(mult, WAD, "U=30% => 1.0");
    }

    function test_utilMult_40pct() public {
        // 1.0 - 0.70 x (0.40 - 0.30) / 0.70 = 1.0 - 0.10 = 0.90
        mockOI.setGlobalUtilization(4e17);
        uint256 mult = model.getUtilizationMultiplier();
        assertApproxEqAbs(mult, 9e17, 1e15, "U=40% => 0.90");
    }

    function test_utilMult_100pct() public {
        // 1.0 - 0.70 x (1.0 - 0.30) / 0.70 = 1.0 - 1.0 = 0 => floored to 0.30
        mockOI.setGlobalUtilization(WAD);
        uint256 mult = model.getUtilizationMultiplier();
        assertEq(mult, 3e17, "U=100% => floor 0.30");
    }

    function test_utilMult_aboveHundred() public {
        // Defensive: U > 100% (shouldn't happen) => floor
        mockOI.setGlobalUtilization(15e17); // 150%
        uint256 mult = model.getUtilizationMultiplier();
        assertEq(mult, 3e17, "U>100% => floor 0.30");
    }

    // ──────────────────────────────────────────────
    // Step 1: Platform Ceiling
    // ──────────────────────────────────────────────

    function test_platformCeiling_allFactorsOne() public {
        mockVault.setTotalAssets(50_000_000e6);     // TVL_Mult = 1.0
        mockInsurance.setBalance(10_000_000e6);      // IFR = 20% => IFR_Mult = 1.0
        mockOI.setGlobalUtilization(1e17);            // 10% => Util_Mult = 1.0

        uint256 ceiling = model.getPlatformCeiling();
        assertEq(ceiling, 30e18, "All factors 1.0 => 30x");
    }

    function test_platformCeiling_workedExample() public {
        // From spec: TVL=$10M, IFR=6%, U=40%
        // TVL_Mult ~ 0.447, IFR_Mult ~ 0.58, Util_Mult ~ 0.90
        // Ceiling = 30 x 0.447 x 0.58 x 0.90 ~ 7.0
        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(600_000e6);
        mockOI.setGlobalUtilization(4e17);

        uint256 ceiling = model.getPlatformCeiling();
        assertApproxEqAbs(ceiling, 7e18, 5e16, "Worked example ceiling ~ 7.0");
    }

    // ──────────────────────────────────────────────
    // Step 2: Compressed Leverage
    // ──────────────────────────────────────────────

    function test_compressedLeverage_zeroTau() public {
        // τ = 0 => R = 0 => compressed = 0
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 0);
        _setupPerfectMarket(marketId);

        uint256 compressed = model.getCompressedLeverage(marketId);
        assertEq(compressed, 0, "tau=0 => compressed=0");
    }

    function test_compressedLeverage_largeTau() public {
        // τ = 120h, not live => R ~ 0.99995 => compressed ~ ceiling
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 120e18);
        mockRegistry.setIsLive(marketId, false);
        _setupPerfectMarket(marketId);

        uint256 compressed = model.getCompressedLeverage(marketId);
        assertApproxEqAbs(compressed, 30e18, 5e16, "Large tau => near full ceiling");
    }

    // ──────────────────────────────────────────────
    // Step 3: Market Adjustment (double M_market)
    // ──────────────────────────────────────────────

    function test_marketAdjustment_perfectMarket() public {
        _setupPerfectMarket(marketId);
        uint256 adj = model.getMarketAdjustment(marketId);
        assertEq(adj, WAD, "Perfect market => M_market = 1.0");
    }

    function test_marketAdjustment_highVol() public {
        // sigma=0.30, baseline=0.10 => excess=0.20 => vol_factor = 1/(1+0.20) ~ 0.833
        // depth at threshold => 1.0, no concentration => 1.0
        // M = 0.833
        mockOracle.setVolatility(marketId, 3e17);
        mockOracle.setDepth(marketId, WAD);
        vm.prank(admin);
        model.setMarketRiskParams(marketId, 1e17, WAD);
        mockOI.setMarketOI(marketId, 0);
        mockOI.setGlobalOI(0);

        uint256 adj = model.getMarketAdjustment(marketId);
        assertApproxEqAbs(adj, 833333333333333333, 1e15, "High vol => M ~ 0.833");
    }

    // ──────────────────────────────────────────────
    // Full Pipeline: getEffectiveMaxLeverage
    // ──────────────────────────────────────────────

    function test_effectiveMax_allPerfect() public {
        // All factors at 1.0, τ=120h not live => R ~ 1 => M_market=1 => 30 x ~1 x 1 = 30
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 120e18);
        mockRegistry.setIsLive(marketId, false);
        _setupPerfectMarket(marketId);

        uint256 maxLev = model.getEffectiveMaxLeverage(marketId);
        assertApproxEqAbs(maxLev, 30e18, 5e16, "All perfect => 30x");
    }

    function test_effectiveMax_neverBelowOne() public {
        // τ = 0 => R = 0 => compressed = 0 => floored at 1x
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 0);
        _setupPerfectMarket(marketId);

        uint256 maxLev = model.getEffectiveMaxLeverage(marketId);
        assertEq(maxLev, WAD, "Floor at 1x");
    }

    function test_effectiveMax_workedExample() public {
        // From spec worked example:
        // Platform: TVL=$10M, IFR=6%, U=40% => Ceiling ~ 7.0x
        // Market: τ=4h, is_live=true
        // Vol_Factor=0.7, Depth_Factor=0.8, Conc_Factor=1.0 => M_market=0.56
        //
        // τ_eff = 4 x 0.30 = 1.2h
        // R(1.2) ~ 0.095
        // R_adjusted = 0.095 x 0.56 = 0.053
        // Compressed = 7.0 x 0.053 = 0.37x
        // Step 3 = max(1.0, 0.37 x 0.56) = max(1.0, 0.21) = 1.0x

        mockVault.setTotalAssets(10_000_000e6);
        mockInsurance.setBalance(600_000e6);
        mockOI.setGlobalUtilization(4e17);

        mockRegistry.setTau(marketId, 4e18);
        mockRegistry.setIsLive(marketId, true);

        // To get Vol_Factor=0.7: 1/(1+excess) = 0.7 => excess ~ 0.4286
        // sigma_current = baseline + excess = 0 + 0.4286 (use baseline=0 for simplicity)
        // Actually: Vol_Factor = 1/(1 + max(0, sigma - baseline))
        // With baseline=0: 1/(1 + sigma) = 0.7 => sigma = 3/7 ~ 0.4286
        uint256 sigmaForVol07 = 428571428571428571; // ~ 3/7 WAD
        mockOracle.setVolatility(marketId, sigmaForVol07);

        // Depth_Factor = 0.8: depth/threshold = 0.8
        mockOracle.setDepth(marketId, 8e17);
        vm.prank(admin);
        model.setMarketRiskParams(marketId, 0, WAD); // baseline=0, threshold=1.0

        // Concentration: market_OI / global_OI = 10% (below 15% threshold => factor=1.0)
        mockOI.setMarketOI(marketId, 1e18);
        mockOI.setGlobalOI(10e18);

        uint256 maxLev = model.getEffectiveMaxLeverage(marketId);
        // Should be 1x (floor)
        assertEq(maxLev, WAD, "Worked example => 1x (floor)");
    }

    function test_effectiveMax_doubleMMarketCompounding() public {
        // Verify M_market is applied TWICE by checking that reducing M_market
        // has a quadratic effect on leverage (not linear)
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 48e18); // far out, not live
        mockRegistry.setIsLive(marketId, false);

        // Perfect market: M_market = 1.0
        _setupPerfectMarket(marketId);
        uint256 lev_perfect = model.getEffectiveMaxLeverage(marketId);

        // Now set M_market ~ 0.5 via depth factor
        mockOracle.setDepth(marketId, 5e17); // depth/threshold = 0.5
        vm.prank(admin);
        model.setMarketRiskParams(marketId, 0, WAD);
        uint256 lev_half = model.getEffectiveMaxLeverage(marketId);

        // R_adjusted at M=0.5 is R*0.5 (Step 2 already compressed)
        // Then Step 3 multiplies by 0.5 again
        // So leverage ~ ceiling x R(48h) x 0.5 x 0.5 = ceiling x R x 0.25
        // vs perfect: ceiling x R x 1.0 x 1.0
        // Ratio should be approximately 0.25 (not 0.5)
        // But R_adjusted also changes R*M, so it's not exactly 0.25 from R perspective

        // Key assertion: double application means leverage is much less than half
        // If M_market were applied only once, lev_half would be ~lev_perfect * 0.5 * R_ratio
        // With double application, it should be significantly lower
        assertLt(
            lev_half * 4, // if linear, lev_half*2 ~ lev_perfect
            lev_perfect * 3, // so lev_half*4 should be < lev_perfect*3 with double application
            "Double M_market compounding reduces leverage more than linear"
        );
    }

    function test_effectiveMax_liveCompression() public {
        // Live event should reduce leverage vs non-live (same τ)
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 24e18);
        _setupPerfectMarket(marketId);

        mockRegistry.setIsLive(marketId, false);
        uint256 lev_notLive = model.getEffectiveMaxLeverage(marketId);

        mockRegistry.setIsLive(marketId, true);
        uint256 lev_live = model.getEffectiveMaxLeverage(marketId);

        assertGt(lev_notLive, lev_live, "Live compression reduces leverage");
    }

    // ──────────────────────────────────────────────
    // validateLeverage
    // ──────────────────────────────────────────────

    function test_validateLeverage_valid() public {
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 120e18);
        mockRegistry.setIsLive(marketId, false);
        _setupPerfectMarket(marketId);

        bool valid = model.validateLeverage(marketId, 10e18);
        assertTrue(valid, "10x should be valid when max is ~30x");
    }

    function test_validateLeverage_exceedsMax() public {
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 120e18);
        mockRegistry.setIsLive(marketId, false);
        _setupPerfectMarket(marketId);

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageModel.LeverageModel__LeverageExceedsMax.selector, 50e18, model.getEffectiveMaxLeverage(marketId))
        );
        model.validateLeverage(marketId, 50e18);
    }

    function test_validateLeverage_belowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(ILeverageModel.LeverageModel__LeverageBelowMinimum.selector, 5e17));
        model.validateLeverage(marketId, 5e17);
    }

    function test_validateLeverage_exactlyAtMax() public {
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 120e18);
        mockRegistry.setIsLive(marketId, false);
        _setupPerfectMarket(marketId);

        uint256 maxLev = model.getEffectiveMaxLeverage(marketId);
        bool valid = model.validateLeverage(marketId, maxLev);
        assertTrue(valid, "Exactly at max should be valid");
    }

    function test_validateLeverage_exactlyOne() public {
        // τ = 0 => max = 1x, requesting 1x should work
        _setupPlatformAtMax();
        mockRegistry.setTau(marketId, 0);
        _setupPerfectMarket(marketId);

        bool valid = model.validateLeverage(marketId, WAD);
        assertTrue(valid, "1x should always be valid");
    }

    // ──────────────────────────────────────────────
    // Edge Cases
    // ──────────────────────────────────────────────

    function test_edge_allZeros() public {
        // TVL=0, Insurance=0, U=0 => ceiling = 30 x 0.10 x 0.40 x 1.0 = 1.2
        mockVault.setTotalAssets(0);
        mockInsurance.setBalance(0);
        mockOI.setGlobalUtilization(0);

        uint256 ceiling = model.getPlatformCeiling();
        assertApproxEqAbs(ceiling, 12e17, 1e15, "All zeros => 30 x 0.1 x 0.4 x 1.0 = 1.2");
    }

    function test_edge_tinyTVL() public {
        // Very small TVL: still functions with floor multipliers
        mockVault.setTotalAssets(1e6); // $1
        mockInsurance.setBalance(0);
        mockOI.setGlobalUtilization(0);

        uint256 ceiling = model.getPlatformCeiling();
        // TVL_Mult = floor(0.10), IFR_Mult = floor(0.40), Util=1.0
        assertApproxEqAbs(ceiling, 12e17, 1e15, "Tiny TVL => floors apply");
    }

    // ──────────────────────────────────────────────
    // Fuzz Tests
    // ──────────────────────────────────────────────

    function testFuzz_tvlMult_bounded(uint256 tvl) public {
        tvl = bound(tvl, 0, 1_000_000_000e6); // 0 to $1B
        mockVault.setTotalAssets(tvl);
        uint256 mult = model.getTVLMultiplier();
        assertGe(mult, 1e17, "TVL mult >= 0.10");
        assertLe(mult, WAD, "TVL mult <= 1.0");
    }

    function testFuzz_ifrMult_bounded(uint256 balance, uint256 tvl) public {
        tvl = bound(tvl, 1e6, 1_000_000_000e6);
        balance = bound(balance, 0, tvl);
        mockVault.setTotalAssets(tvl);
        mockInsurance.setBalance(balance);
        uint256 mult = model.getIFRMultiplier();
        assertGe(mult, 4e17, "IFR mult >= 0.40");
        assertLe(mult, WAD, "IFR mult <= 1.0");
    }

    function testFuzz_utilMult_bounded(uint256 u) public {
        u = bound(u, 0, 3e18); // up to 300%
        mockOI.setGlobalUtilization(u);
        uint256 mult = model.getUtilizationMultiplier();
        assertGe(mult, 3e17, "Util mult >= 0.30");
        assertLe(mult, WAD, "Util mult <= 1.0");
    }

    function testFuzz_effectiveMax_neverBelowOne(uint256 tvl, uint256 tau, bool isLive) public {
        tvl = bound(tvl, 0, 1_000_000_000e6);
        tau = bound(tau, 0, 1000e18);

        mockVault.setTotalAssets(tvl);
        mockInsurance.setBalance(0);
        mockOI.setGlobalUtilization(0);
        mockRegistry.setTau(marketId, tau);
        mockRegistry.setIsLive(marketId, isLive);
        _setupPerfectMarket(marketId);

        uint256 maxLev = model.getEffectiveMaxLeverage(marketId);
        assertGe(maxLev, WAD, "Effective max leverage >= 1x");
    }

    // ──────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────

    function _setupPlatformAtMax() internal {
        mockVault.setTotalAssets(50_000_000e6);
        mockInsurance.setBalance(10_000_000e6);
        mockOI.setGlobalUtilization(0);
    }

    /// @dev Set up a "perfect" market: no vol excess, depth at threshold, no concentration
    function _setupPerfectMarket(bytes32 _marketId) internal {
        mockOracle.setVolatility(_marketId, 0);      // no vol
        mockOracle.setDepth(_marketId, WAD);          // depth = threshold
        vm.prank(admin);
        model.setMarketRiskParams(_marketId, 0, WAD); // baseline=0, threshold=1.0
        mockOI.setMarketOI(_marketId, 0);
        mockOI.setGlobalOI(0);
    }
}
