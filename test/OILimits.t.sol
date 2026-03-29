// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { OILimits } from "../contracts/OILimits.sol";
import { IOILimits } from "../contracts/interfaces/IOILimits.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarketRegistry {
    struct MockMarket {
        uint256 tau;
        bool live;
        uint256 allocationWeight;
    }

    mapping(bytes32 => MockMarket) public markets;

    function setMarket(bytes32 id, uint256 tau, bool live_, uint256 weight) external {
        markets[id] = MockMarket(tau, live_, weight);
    }

    function getTau(bytes32 id) external view returns (uint256) {
        return markets[id].tau;
    }

    function isLive(bytes32 id) external view returns (bool) {
        return markets[id].live;
    }

    function getAllocationWeight(bytes32 id) external view returns (uint256) {
        return markets[id].allocationWeight;
    }
}

contract MockLeverVault {
    uint256 private _totalAssets;

    function setTotalAssets(uint256 val) external {
        _totalAssets = val;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }
}

contract MockPositionManager_OI {
    mapping(bytes32 => uint256[]) private _marketPositions;

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return _marketPositions[marketId];
    }

    function addPosition(bytes32 marketId, uint256 positionId) external {
        _marketPositions[marketId].push(positionId);
    }

    function clearPositions(bytes32 marketId) external {
        delete _marketPositions[marketId];
    }
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

contract OILimitsTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    OILimits oiLimits;
    MockMarketRegistry registry;
    MockLeverVault vault;
    MockPositionManager_OI posMgr;

    address admin = address(0xAD);
    address engine = address(0xE1);
    address liquidator = address(0xE2);
    address settler = address(0xE3);
    address alice = address(0xA1);
    address bob = address(0xA2);

    bytes32 marketId = keccak256("ELECTION_2026");
    bytes32 marketId2 = keccak256("SUPERBOWL_2026");

    // Default setup: $10M TVL, market with 20% allocation, 48h to resolution, not live
    function setUp() public {
        registry = new MockMarketRegistry();
        vault = new MockLeverVault();
        posMgr = new MockPositionManager_OI();

        vm.prank(admin);
        oiLimits = new OILimits(address(registry), address(vault), address(posMgr), admin);

        // Grant roles
        vm.startPrank(admin);
        oiLimits.grantRole(oiLimits.EXECUTION_ENGINE_ROLE(), engine);
        oiLimits.grantRole(oiLimits.LIQUIDATION_ENGINE_ROLE(), liquidator);
        oiLimits.grantRole(oiLimits.SETTLEMENT_ENGINE_ROLE(), settler);
        vm.stopPrank();

        // Set TVL to $10M
        vault.setTotalAssets(10_000_000e18);

        // Set market: 48h to resolution, not live, 20% allocation
        registry.setMarket(marketId, 48e18, false, 2e17);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(oiLimits.marketRegistry()), address(registry));
        assertEq(address(oiLimits.vault()), address(vault));
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(oiLimits.hasRole(oiLimits.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(oiLimits.hasRole(oiLimits.ADMIN_ROLE(), admin));
    }

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(OILimits.OILimits__ZeroAddress.selector);
        new OILimits(address(0), address(vault), address(posMgr), admin);

        vm.expectRevert(OILimits.OILimits__ZeroAddress.selector);
        new OILimits(address(registry), address(0), address(posMgr), admin);

        vm.expectRevert(OILimits.OILimits__ZeroAddress.selector);
        new OILimits(address(registry), address(vault), address(0), admin);

        vm.expectRevert(OILimits.OILimits__ZeroAddress.selector);
        new OILimits(address(registry), address(vault), address(posMgr), address(0));
    }

    // ──────────────────────────────────────────────
    // Tier 1: Global OI Cap
    // ──────────────────────────────────────────────

    function test_globalOICap_is60PercentOfTVL() public view {
        // $10M × 0.60 = $6M
        uint256 cap = oiLimits.getGlobalOICap();
        assertEq(cap, 6_000_000e18);
    }

    function test_globalOICap_zeroTVL() public {
        vault.setTotalAssets(0);
        assertEq(oiLimits.getGlobalOICap(), 0);
    }

    function test_globalOICap_scalesWithTVL() public {
        vault.setTotalAssets(50_000_000e18);
        assertEq(oiLimits.getGlobalOICap(), 30_000_000e18);
    }

    // ──────────────────────────────────────────────
    // Tier 2: Per-Market OI Cap
    // ──────────────────────────────────────────────

    function test_marketOICap_baseCaseWithRCompression() public view {
        // Global cap = $6M, allocation = 20%, so base = $1.2M
        // 48h τ, not live → R ≈ high (far from resolution) → oiCapMult ≈ near 1.0
        uint256 cap = oiLimits.getMarketOICap(marketId);
        // R(48h) = 1 - e^(-2×48/24) = 1 - e^(-4) ≈ 0.9817
        // oiCapMult = 0.20 + 0.9817 × 0.80 ≈ 0.9853
        // marketCap ≈ $1.2M × 0.9853 ≈ $1,182,369
        assertGt(cap, 1_100_000e18);
        assertLt(cap, 1_200_001e18);
    }

    function test_marketOICap_nearResolution() public {
        // 1 hour to resolution → R is small → cap shrinks
        registry.setMarket(marketId, 1e18, false, 2e17);
        uint256 cap = oiLimits.getMarketOICap(marketId);
        // R(1h) = 1 - e^(-2/24) ≈ 0.0800 → oiCapMult ≈ 0.264
        // base = $1.2M → cap ≈ $316,800
        assertGt(cap, 250_000e18);
        assertLt(cap, 400_000e18);
    }

    function test_marketOICap_atResolution() public {
        // τ = 0 → R = 0 → oiCapMult = 0.20 (floor)
        registry.setMarket(marketId, 0, false, 2e17);
        uint256 cap = oiLimits.getMarketOICap(marketId);
        // base = $1.2M × 0.20 = $240,000
        assertEq(cap, 240_000e18);
    }

    function test_marketOICap_zeroWeight() public {
        registry.setMarket(marketId, 48e18, false, 0);
        assertEq(oiLimits.getMarketOICap(marketId), 0);
    }

    function test_marketOICap_liveCompression() public {
        // 48h but live → τ_effective = 48 × 0.30 = 14.4h
        registry.setMarket(marketId, 48e18, true, 2e17);
        uint256 capLive = oiLimits.getMarketOICap(marketId);

        registry.setMarket(marketId, 48e18, false, 2e17);
        uint256 capNotLive = oiLimits.getMarketOICap(marketId);

        // Live should compress → lower cap
        assertLt(capLive, capNotLive);
    }

    // ──────────────────────────────────────────────
    // Tier 3: Per-Side OI Cap
    // ──────────────────────────────────────────────

    function test_sideOICap_is70PercentOfMarket() public view {
        uint256 marketCap = oiLimits.getMarketOICap(marketId);
        uint256 sideCap = oiLimits.getSideOICap(marketId);
        // sideCap = marketCap × 0.70
        uint256 expected = marketCap * 7e17 / WAD;
        assertApproxEqAbs(sideCap, expected, 1);
    }

    // ──────────────────────────────────────────────
    // Tier 4: Per-User OI Cap
    // ──────────────────────────────────────────────

    function test_userOICap_is20PercentOfMarket() public view {
        uint256 marketCap = oiLimits.getMarketOICap(marketId);
        uint256 userCap = oiLimits.getUserOICap(marketId);
        uint256 expected = marketCap * 2e17 / WAD;
        assertApproxEqAbs(userCap, expected, 1);
    }

    // ──────────────────────────────────────────────
    // increaseOI — happy path
    // ──────────────────────────────────────────────

    function test_increaseOI_updatesAllCounters() public {
        uint256 notional = 100_000e18;

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, notional);

        assertEq(oiLimits.getGlobalOI(), notional);
        assertEq(oiLimits.getMarketOI(marketId), notional);
        assertEq(oiLimits.getSideOI(marketId, true), notional);
        assertEq(oiLimits.getSideOI(marketId, false), 0);
        assertEq(oiLimits.getUserOI(marketId, alice), notional);
    }

    function test_increaseOI_shortSide() public {
        uint256 notional = 50_000e18;

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, false, notional);

        assertEq(oiLimits.getSideOI(marketId, false), notional);
        assertEq(oiLimits.getSideOI(marketId, true), 0);
    }

    function test_increaseOI_multipleUsers() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 50_000e18);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, false, 30_000e18);

        assertEq(oiLimits.getGlobalOI(), 80_000e18);
        assertEq(oiLimits.getMarketOI(marketId), 80_000e18);
        assertEq(oiLimits.getSideOI(marketId, true), 50_000e18);
        assertEq(oiLimits.getSideOI(marketId, false), 30_000e18);
        assertEq(oiLimits.getUserOI(marketId, alice), 50_000e18);
        assertEq(oiLimits.getUserOI(marketId, bob), 30_000e18);
    }

    function test_increaseOI_emitsEvent() public {
        uint256 notional = 100_000e18;
        vm.expectEmit(true, false, false, true);
        emit IOILimits.OIIncreased(marketId, true, notional, notional);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, notional);
    }

    // ──────────────────────────────────────────────
    // increaseOI — cap breaches
    // ──────────────────────────────────────────────

    function test_increaseOI_revertsGlobalCap() public {
        // Global cap = $6M. Try to add $6.1M
        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, 6_100_000e18);
    }

    function test_increaseOI_revertsMarketCap() public {
        // Market cap ≈ $1.18M. Try to add $1.3M (under global but over market)
        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, 1_300_000e18);
    }

    function test_increaseOI_revertsSideCap() public {
        // Side cap ≈ $1.18M × 0.70 ≈ $828K. Need multiple users to breach side without hitting user cap.
        // User cap ≈ $1.18M × 0.20 ≈ $236K. Use 4 users on same side.
        uint256 userCap = oiLimits.getUserOICap(marketId);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, userCap);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, true, userCap);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, address(0xA3), true, userCap);

        // 4th user should breach side cap (3 × userCap < sideCap, but 4 × might exceed)
        // sideCap = marketCap × 0.70, userCap = marketCap × 0.20
        // 4 × 0.20 = 0.80 > 0.70 → should revert
        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, address(0xA4), true, userCap);
    }

    function test_increaseOI_revertsUserCap() public {
        uint256 userCap = oiLimits.getUserOICap(marketId);

        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, userCap + 1);
    }

    function test_increaseOI_revertsZeroNotional() public {
        vm.prank(engine);
        vm.expectRevert(OILimits.OILimits__ZeroNotional.selector);
        oiLimits.increaseOI(marketId, alice, true, 0);
    }

    // ──────────────────────────────────────────────
    // increaseOI — access control
    // ──────────────────────────────────────────────

    function test_increaseOI_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, 100e18);
    }

    function test_increaseOI_revertsLiquidatorRole() public {
        // Liquidator can decrease but NOT increase
        vm.prank(liquidator);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, 100e18);
    }

    // ──────────────────────────────────────────────
    // decreaseOI — happy path
    // ──────────────────────────────────────────────

    function test_decreaseOI_updatesAllCounters() public {
        uint256 notional = 100_000e18;
        uint256 closeAmount = 40_000e18;

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, notional);

        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, closeAmount);

        uint256 remaining = notional - closeAmount;
        assertEq(oiLimits.getGlobalOI(), remaining);
        assertEq(oiLimits.getMarketOI(marketId), remaining);
        assertEq(oiLimits.getSideOI(marketId, true), remaining);
        assertEq(oiLimits.getUserOI(marketId, alice), remaining);
    }

    function test_decreaseOI_emitsEvent() public {
        uint256 notional = 100_000e18;
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, notional);

        vm.expectEmit(true, false, false, true);
        emit IOILimits.OIDecreased(marketId, true, 30_000e18, 70_000e18);

        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, 30_000e18);
    }

    function test_decreaseOI_floorsAtZero() public {
        uint256 notional = 50_000e18;
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, notional);

        // Decrease by MORE than tracked — should floor at 0
        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, notional + 10_000e18);

        assertEq(oiLimits.getGlobalOI(), 0);
        assertEq(oiLimits.getMarketOI(marketId), 0);
        assertEq(oiLimits.getSideOI(marketId, true), 0);
        assertEq(oiLimits.getUserOI(marketId, alice), 0);
    }

    // ──────────────────────────────────────────────
    // decreaseOI — access control
    // ──────────────────────────────────────────────

    function test_decreaseOI_executionEngine() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, 50_000e18);
        assertEq(oiLimits.getGlobalOI(), 50_000e18);
    }

    function test_decreaseOI_liquidationEngine() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        vm.prank(liquidator);
        oiLimits.decreaseOI(marketId, alice, true, 100_000e18);
        assertEq(oiLimits.getGlobalOI(), 0);
    }

    function test_decreaseOI_settlementEngine() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        vm.prank(settler);
        oiLimits.decreaseOI(marketId, alice, true, 100_000e18);
        assertEq(oiLimits.getGlobalOI(), 0);
    }

    function test_decreaseOI_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oiLimits.decreaseOI(marketId, alice, true, 100e18);
    }

    function test_decreaseOI_revertsZeroNotional() public {
        vm.prank(engine);
        vm.expectRevert(OILimits.OILimits__ZeroNotional.selector);
        oiLimits.decreaseOI(marketId, alice, true, 0);
    }

    // ──────────────────────────────────────────────
    // getImbalanceRatio
    // ──────────────────────────────────────────────

    function test_imbalanceRatio_zeroOI() public view {
        assertEq(oiLimits.getImbalanceRatio(marketId), 0);
    }

    function test_imbalanceRatio_allLong() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        // (100 - 0) / 100 = +1.0
        assertEq(oiLimits.getImbalanceRatio(marketId), int256(WAD));
    }

    function test_imbalanceRatio_allShort() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, false, 100_000e18);

        // (0 - 100) / 100 = -1.0
        assertEq(oiLimits.getImbalanceRatio(marketId), -int256(WAD));
    }

    function test_imbalanceRatio_balanced() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, false, 100_000e18);

        assertEq(oiLimits.getImbalanceRatio(marketId), 0);
    }

    function test_imbalanceRatio_longHeavy() public {
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 70_000e18);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, false, 30_000e18);

        // (70 - 30) / 100 = 0.40
        int256 ratio = oiLimits.getImbalanceRatio(marketId);
        assertEq(ratio, int256(4e17));
    }

    // ──────────────────────────────────────────────
    // canIncreaseOI
    // ──────────────────────────────────────────────

    function test_canIncreaseOI_returnsTrue() public view {
        assertTrue(oiLimits.canIncreaseOI(marketId, alice, true, 100_000e18));
    }

    function test_canIncreaseOI_returnsFalseGlobalCap() public view {
        assertFalse(oiLimits.canIncreaseOI(marketId, alice, true, 6_100_000e18));
    }

    function test_canIncreaseOI_returnsFalseUserCap() public view {
        uint256 userCap = oiLimits.getUserOICap(marketId);
        assertFalse(oiLimits.canIncreaseOI(marketId, alice, true, userCap + 1));
    }

    // ──────────────────────────────────────────────
    // Utilization
    // ──────────────────────────────────────────────

    function test_globalUtilization_zero() public view {
        assertEq(oiLimits.getGlobalUtilization(), 0);
    }

    function test_globalUtilization_50percent() public {
        // Global cap = $6M. Add $3M OI → 50%
        // Set allocation to 100% and spread across users to stay under user cap
        registry.setMarket(marketId, 48e18, false, WAD);

        // User cap ≈ marketCap × 0.20. Use 3 users at $1M each.
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 1_000_000e18);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, true, 1_000_000e18);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, address(0xA3), true, 1_000_000e18);

        uint256 util = oiLimits.getGlobalUtilization();
        assertApproxEqAbs(util, 5e17, 1e15); // ~50%
    }

    function test_marketUtilization_zero() public view {
        assertEq(oiLimits.getMarketUtilization(marketId), 0);
    }

    function test_globalUtilization_zeroTVL() public {
        vault.setTotalAssets(0);
        assertEq(oiLimits.getGlobalUtilization(), 0);
    }

    // ──────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────

    function test_pause_blocksIncrease() public {
        vm.prank(admin);
        oiLimits.pause();

        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, alice, true, 100e18);
    }

    function test_pause_blocksDecrease() public {
        vm.prank(admin);
        oiLimits.pause();

        vm.prank(engine);
        vm.expectRevert();
        oiLimits.decreaseOI(marketId, alice, true, 100e18);
    }

    function test_unpause_allowsOperations() public {
        vm.prank(admin);
        oiLimits.pause();

        vm.prank(admin);
        oiLimits.unpause();

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);
        assertEq(oiLimits.getGlobalOI(), 100_000e18);
    }

    function test_pause_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oiLimits.pause();
    }

    // ──────────────────────────────────────────────
    // Edge cases
    // ──────────────────────────────────────────────

    function test_grandfathered_existingOIExceedsNewCap() public {
        // Set high capacity and open position
        registry.setMarket(marketId, 48e18, false, 5e17); // 50% allocation
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 200_000e18);

        // Reduce allocation weight → cap shrinks below existing OI
        registry.setMarket(marketId, 48e18, false, 1e16); // 1% allocation

        // Existing OI exceeds new cap — that's fine (grandfathered)
        uint256 marketCap = oiLimits.getMarketOICap(marketId);
        assertGt(oiLimits.getMarketOI(marketId), marketCap);

        // But new opens should fail
        vm.prank(engine);
        vm.expectRevert();
        oiLimits.increaseOI(marketId, bob, true, 1e18);
    }

    function test_multipleMarkets_independentTracking() public {
        registry.setMarket(marketId2, 72e18, false, 15e16); // 15% allocation

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        vm.prank(engine);
        oiLimits.increaseOI(marketId2, bob, false, 50_000e18);

        assertEq(oiLimits.getGlobalOI(), 150_000e18);
        assertEq(oiLimits.getMarketOI(marketId), 100_000e18);
        assertEq(oiLimits.getMarketOI(marketId2), 50_000e18);
    }

    // ──────────────────────────────────────────────
    // Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_increaseAndDecrease_roundTrip(uint256 amount) public {
        // Bound to something reasonable under caps
        amount = bound(amount, 1e18, 200_000e18);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, amount);

        assertEq(oiLimits.getGlobalOI(), amount);

        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, amount);

        assertEq(oiLimits.getGlobalOI(), 0);
        assertEq(oiLimits.getMarketOI(marketId), 0);
        assertEq(oiLimits.getSideOI(marketId, true), 0);
        assertEq(oiLimits.getUserOI(marketId, alice), 0);
    }

    function testFuzz_imbalanceRatio_bounded(uint256 longAmt, uint256 shortAmt) public {
        longAmt = bound(longAmt, 1e18, 100_000e18);
        shortAmt = bound(shortAmt, 1e18, 100_000e18);

        // Use large allocation to avoid cap issues
        registry.setMarket(marketId, 48e18, false, WAD);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, longAmt);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, bob, false, shortAmt);

        int256 ratio = oiLimits.getImbalanceRatio(marketId);
        assertGe(ratio, -int256(WAD));
        assertLe(ratio, int256(WAD));
    }

    function testFuzz_decreaseOI_neverUnderflows(uint256 increase, uint256 decrease) public {
        increase = bound(increase, 1e18, 200_000e18);
        decrease = bound(decrease, 1e18, type(uint128).max);

        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, increase);

        vm.prank(engine);
        oiLimits.decreaseOI(marketId, alice, true, decrease);

        // Should never revert, just floor at 0
        assertLe(oiLimits.getGlobalOI(), increase);
    }
}
