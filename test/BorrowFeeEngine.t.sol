// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { IBorrowFeeEngine } from "../contracts/interfaces/IBorrowFeeEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarketRegistryBorrow {
    struct MockMarket {
        uint256 tau;
        bool live;
        bytes32[] activeMarkets;
    }

    mapping(bytes32 => MockMarket) private _markets;
    bytes32[] private _activeMarketIds;

    function setMarket(bytes32 marketId, uint256 tau, bool live) external {
        _markets[marketId].tau = tau;
        _markets[marketId].live = live;
    }

    function addActiveMarket(bytes32 marketId) external {
        _activeMarketIds.push(marketId);
    }

    function getTau(bytes32 marketId) external view returns (uint256) {
        return _markets[marketId].tau;
    }

    function isLive(bytes32 marketId) external view returns (bool) {
        return _markets[marketId].live;
    }

    function getActiveMarkets() external view returns (bytes32[] memory) {
        return _activeMarketIds;
    }
}

contract MockOILimitsBorrow {
    mapping(bytes32 => int256) private _imbalanceRatio;

    function setImbalanceRatio(bytes32 marketId, int256 ratio) external {
        _imbalanceRatio[marketId] = ratio;
    }

    function getImbalanceRatio(bytes32 marketId) external view returns (int256) {
        return _imbalanceRatio[marketId];
    }
}

contract MockPositionManagerBorrow {
    mapping(uint256 => IPositionManager.Position) private _positions;
    uint256 private _nextId = 1;

    function createMockPosition(
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        uint256 borrowIndex
    ) external returns (uint256 posId) {
        posId = _nextId++;
        _positions[posId] = IPositionManager.Position({
            id: posId,
            owner: owner,
            marketId: marketId,
            isLong: isLong,
            entryPI: 5e17,
            entryPrice: 5e17,
            positionSize: positionSize,
            collateral: collateral,
            leverage: leverage,
            borrowIndex: borrowIndex,
            fundingIndex: int256(0),
            openTimestamp: block.timestamp,
            isOpen: true
        });
    }

    function closePosition(uint256 posId) external {
        _positions[posId].isOpen = false;
    }

    function getPosition(uint256 posId) external view returns (IPositionManager.Position memory) {
        return _positions[posId];
    }
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

contract BorrowFeeEngineTest is Test {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    BorrowFeeEngine public engine;
    MockMarketRegistryBorrow public registry;
    MockOILimitsBorrow public oiLimits;
    MockPositionManagerBorrow public posMgr;

    address public admin = address(this);
    address public user1 = address(0x1);

    bytes32 public constant MARKET_A = keccak256("MARKET_A");

    function setUp() public {
        registry = new MockMarketRegistryBorrow();
        oiLimits = new MockOILimitsBorrow();
        posMgr = new MockPositionManagerBorrow();

        engine = new BorrowFeeEngine(
            admin,
            address(registry),
            address(oiLimits),
            address(posMgr)
        );

        // Initialize market: 48 hours to resolution, not live, balanced OI
        registry.setMarket(MARKET_A, 48e18, false);
        registry.addActiveMarket(MARKET_A);
        oiLimits.setImbalanceRatio(MARKET_A, 0);

        // Initialize the borrow index
        engine.initializeMarketIndex(MARKET_A);

        // Set default risk params (no stress: M_market = 1.0)
        engine.updateMarketRiskParams(
            MARKET_A,
            0,    // sigmaCurrent
            0,    // sigmaBaseline
            WAD,  // externalDepth
            WAD,  // depthThreshold
            0,    // marketOI
            0     // globalOI
        );
    }

    // ──────────────────────────────────────────────
    // Constructor Tests
    // ──────────────────────────────────────────────

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(BorrowFeeEngine.BorrowFeeEngine__ZeroAddress.selector);
        new BorrowFeeEngine(address(0), address(registry), address(oiLimits), address(posMgr));
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert(BorrowFeeEngine.BorrowFeeEngine__ZeroAddress.selector);
        new BorrowFeeEngine(admin, address(0), address(oiLimits), address(posMgr));
    }

    function test_constructor_revertsOnZeroOILimits() public {
        vm.expectRevert(BorrowFeeEngine.BorrowFeeEngine__ZeroAddress.selector);
        new BorrowFeeEngine(admin, address(registry), address(0), address(posMgr));
    }

    function test_constructor_revertsOnZeroPosMgr() public {
        vm.expectRevert(BorrowFeeEngine.BorrowFeeEngine__ZeroAddress.selector);
        new BorrowFeeEngine(admin, address(registry), address(oiLimits), address(0));
    }

    // ──────────────────────────────────────────────
    // Index Initialization
    // ──────────────────────────────────────────────

    function test_initializeMarketIndex_setsToWAD() public {
        bytes32 newMarket = keccak256("NEW");
        engine.initializeMarketIndex(newMarket);

        assertEq(engine.getBorrowIndex(newMarket, true), WAD, "Long index should be WAD");
        assertEq(engine.getBorrowIndex(newMarket, false), WAD, "Short index should be WAD");
    }

    function test_initializeMarketIndex_doesNotReinitialize() public {
        // Accrue some fees first
        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 indexAfterAccrual = engine.getBorrowIndex(MARKET_A, true);
        assertGt(indexAfterAccrual, WAD, "Index should have grown");

        // Try re-initializing — should be no-op
        engine.initializeMarketIndex(MARKET_A);
        assertEq(engine.getBorrowIndex(MARKET_A, true), indexAfterAccrual, "Should not reinitialize");
    }

    // ──────────────────────────────────────────────
    // M_ttR Tests
    // ──────────────────────────────────────────────

    function test_getMttR_farFromResolution() public view {
        // τ = 48h, M_market = 1.0
        // R_borrow = 1 - e^(-2 * 48/168) = 1 - e^(-0.571...) ≈ 0.4353
        // M_ttR = 1 + 24 × (1 - 0.4353) = 1 + 24 × 0.5647 ≈ 14.55
        uint256 mttR = engine.getMttR(MARKET_A);
        assertGt(mttR, 14e18, "M_ttR should be > 14");
        assertLt(mttR, 15e18, "M_ttR should be < 15");
    }

    function test_getMttR_nearResolution() public {
        // τ = 1h: R_borrow = 1 - e^(-2/168) ≈ 0.01183
        // M_ttR = 1 + 24 × (1 - 0.01183) ≈ 24.72
        registry.setMarket(MARKET_A, 1e18, false);
        uint256 mttR = engine.getMttR(MARKET_A);
        assertGt(mttR, 24e18, "M_ttR should be > 24");
        assertLt(mttR, 25e18, "M_ttR should be < 25");
    }

    function test_getMttR_atResolution() public {
        // τ = 0: R_borrow = 0, M_ttR = 1 + 24 × 1 = 25
        registry.setMarket(MARKET_A, 0, false);
        uint256 mttR = engine.getMttR(MARKET_A);
        assertEq(mttR, 25e18, "M_ttR at tau=0 should be 25");
    }

    // ──────────────────────────────────────────────
    // Imbalance Surcharge Tests
    // ──────────────────────────────────────────────

    function test_surcharge_balancedMarket() public view {
        assertEq(engine.getImbalanceSurcharge(MARKET_A, true), 0, "No surcharge on balanced long");
        assertEq(engine.getImbalanceSurcharge(MARKET_A, false), 0, "No surcharge on balanced short");
    }

    function test_surcharge_longHeavy() public {
        // imbalanceRatio = +0.4 (longs are heavy)
        oiLimits.setImbalanceRatio(MARKET_A, 4e17);

        uint256 longSurcharge = engine.getImbalanceSurcharge(MARKET_A, true);
        uint256 shortSurcharge = engine.getImbalanceSurcharge(MARKET_A, false);

        assertGt(longSurcharge, 0, "Long side should have surcharge");
        assertEq(shortSurcharge, 0, "Short side (light) should have no surcharge");
        // surcharge = 0.4 × 1.0 = 0.4
        assertApproxEqRel(longSurcharge, 4e17, 1e15, "Surcharge should be ~0.4");
    }

    function test_surcharge_shortHeavy() public {
        // imbalanceRatio = -0.3 (shorts are heavy)
        oiLimits.setImbalanceRatio(MARKET_A, -3e17);

        uint256 longSurcharge = engine.getImbalanceSurcharge(MARKET_A, true);
        uint256 shortSurcharge = engine.getImbalanceSurcharge(MARKET_A, false);

        assertEq(longSurcharge, 0, "Long side (light) should have no surcharge");
        assertGt(shortSurcharge, 0, "Short side should have surcharge");
        assertApproxEqRel(shortSurcharge, 3e17, 1e15, "Surcharge should be ~0.3");
    }

    // ──────────────────────────────────────────────
    // Borrow Rate Tests
    // ──────────────────────────────────────────────

    function test_getCurrentBorrowRate_balanced() public view {
        // rate = BASE (0.02%) × M_ttR × (1 + 0)
        uint256 rate = engine.getCurrentBorrowRate(MARKET_A, true);
        uint256 mttR = engine.getMttR(MARKET_A);
        uint256 expected = uint256(2e14).wadMul(mttR);
        assertApproxEqRel(rate, expected, 1e15, "Rate should be base x M_ttR");
    }

    function test_getCurrentBorrowRate_withSurcharge() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17); // +0.5 imbalance

        uint256 rateLong = engine.getCurrentBorrowRate(MARKET_A, true);
        uint256 rateShort = engine.getCurrentBorrowRate(MARKET_A, false);

        assertGt(rateLong, rateShort, "Heavy side should pay more");
        // Long rate = base × M_ttR × (1 + 0.5) = 1.5× short rate
        assertApproxEqRel(rateLong, rateShort * 3 / 2, 1e15, "Long should be 1.5x short");
    }

    function test_getAnnualizedRate() public view {
        uint256 hourly = engine.getCurrentBorrowRate(MARKET_A, true);
        uint256 annual = engine.getAnnualizedRate(MARKET_A, true);
        assertEq(annual, hourly * 8760, "Annualized = hourly x 8760");
    }

    // ──────────────────────────────────────────────
    // Index Accrual Tests
    // ──────────────────────────────────────────────

    function test_accrueIndex_increasesOverTime() public {
        uint256 indexBefore = engine.getBorrowIndex(MARKET_A, true);
        assertEq(indexBefore, WAD, "Should start at WAD");

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 indexAfter = engine.getBorrowIndex(MARKET_A, true);
        assertGt(indexAfter, indexBefore, "Index should increase after time passes");
    }

    function test_accrueIndex_noOpSameBlock() public {
        uint256 indexBefore = engine.getBorrowIndex(MARKET_A, true);

        // Same block — no time passed
        engine.accrueIndex(MARKET_A, true);

        uint256 indexAfter = engine.getBorrowIndex(MARKET_A, true);
        assertEq(indexAfter, indexBefore, "Index should not change in same block");
    }

    function test_accrueIndex_correctAmount() public {
        uint256 rate = engine.getCurrentBorrowRate(MARKET_A, true);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 indexDelta = engine.getBorrowIndex(MARKET_A, true) - WAD;
        // Expected: rate (per hour) / 3600 × 3600 = rate
        assertApproxEqRel(indexDelta, rate, 1e15, "1 hour accrual should equal hourly rate");
    }

    function test_accrueIndex_sidesIndependent() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17); // longs heavy

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);
        engine.accrueIndex(MARKET_A, false);

        uint256 longIdx = engine.getBorrowIndex(MARKET_A, true);
        uint256 shortIdx = engine.getBorrowIndex(MARKET_A, false);

        assertGt(longIdx, shortIdx, "Heavy side (long) should accrue faster");
    }

    // ──────────────────────────────────────────────
    // Accrued Fee Tests
    // ──────────────────────────────────────────────

    function test_getAccruedFees_basic() public {
        // Create a leveraged position at current index (WAD)
        uint256 posId = posMgr.createMockPosition(
            user1,
            MARKET_A,
            true,          // isLong
            1000e18,       // positionSize (notional)
            100e18,        // collateral
            10e18,         // leverage (10×)
            WAD            // borrowIndex snapshot = current
        );

        // Advance 1 hour and accrue
        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 fees = engine.getAccruedFees(posId);
        assertGt(fees, 0, "Should have accrued fees");

        // fees = positionSize × indexDelta
        uint256 indexDelta = engine.getBorrowIndex(MARKET_A, true) - WAD;
        uint256 expected = uint256(1000e18).wadMul(indexDelta);
        assertApproxEqRel(fees, expected, 1e15, "Fees should match index delta x size");
    }

    function test_getAccruedFees_1xExempt() public {
        // 1× position should be exempt
        uint256 posId = posMgr.createMockPosition(
            user1,
            MARKET_A,
            true,
            1000e18,
            1000e18,  // collateral = notional (1×)
            WAD,      // leverage = 1×
            WAD
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 fees = engine.getAccruedFees(posId);
        assertEq(fees, 0, "1x positions should be exempt");
    }

    function test_getAccruedFees_closedPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, WAD
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        posMgr.closePosition(posId);
        uint256 fees = engine.getAccruedFees(posId);
        assertEq(fees, 0, "Closed position should return 0 fees");
    }

    function test_getAccruedFees_twoPositionsDifferentTimes() public {
        // Position 1 opens now
        uint256 pos1 = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, WAD
        );

        // Advance 1 hour and accrue
        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        // Position 2 opens after 1 hour of accrual
        uint256 currentIndex = engine.getBorrowIndex(MARKET_A, true);
        uint256 pos2 = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, currentIndex
        );

        // Advance another hour
        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 fees1 = engine.getAccruedFees(pos1);
        uint256 fees2 = engine.getAccruedFees(pos2);

        assertGt(fees1, fees2, "Position 1 should have more fees (open longer)");
        assertGt(fees2, 0, "Position 2 should also have fees");
    }

    // ──────────────────────────────────────────────
    // accrueAll Tests
    // ──────────────────────────────────────────────

    function test_accrueAll() public {
        bytes32 marketB = keccak256("MARKET_B");
        registry.setMarket(marketB, 72e18, false);
        registry.addActiveMarket(marketB);
        engine.initializeMarketIndex(marketB);
        engine.updateMarketRiskParams(marketB, 0, 0, WAD, WAD, 0, 0);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueAll();

        assertGt(engine.getBorrowIndex(MARKET_A, true), WAD, "Market A long should accrue");
        assertGt(engine.getBorrowIndex(MARKET_A, false), WAD, "Market A short should accrue");
        assertGt(engine.getBorrowIndex(marketB, true), WAD, "Market B long should accrue");
        assertGt(engine.getBorrowIndex(marketB, false), WAD, "Market B short should accrue");
    }

    // ──────────────────────────────────────────────
    // computeIndexAt (Settlement Freeze) Tests
    // ──────────────────────────────────────────────

    function test_computeIndexAt_futureTimestamp() public view {
        // Should project the index forward
        uint256 futureTs = block.timestamp + 1 hours;
        uint256 projectedLong = engine.computeIndexAt(MARKET_A, true, futureTs);
        uint256 projectedShort = engine.computeIndexAt(MARKET_A, false, futureTs);

        assertGt(projectedLong, WAD, "Projected long index should be > WAD");
        assertGt(projectedShort, WAD, "Projected short index should be > WAD");
    }

    function test_computeIndexAt_pastTimestamp() public {
        // Advance and accrue first
        vm.warp(block.timestamp + 2 hours);
        engine.accrueIndex(MARKET_A, true);

        uint256 currentIndex = engine.getBorrowIndex(MARKET_A, true);

        // Ask for index at a past time — should return stored index
        uint256 pastTs = block.timestamp - 1 hours;
        uint256 pastIndex = engine.computeIndexAt(MARKET_A, true, pastTs);

        assertEq(pastIndex, currentIndex, "Past timestamp should return stored index");
    }

    function test_computeIndexAt_matchesActualAccrual() public {
        // Project what index would be at T+1h
        uint256 targetTs = block.timestamp + 1 hours;
        uint256 projected = engine.computeIndexAt(MARKET_A, true, targetTs);

        // Actually accrue to that time
        vm.warp(targetTs);
        engine.accrueIndex(MARKET_A, true);
        uint256 actual = engine.getBorrowIndex(MARKET_A, true);

        assertApproxEqRel(projected, actual, 1e15, "Projected should match actual accrual");
    }

    function test_computeIndexAt_settlementFreeze() public {
        // Scenario: market resolved externally at T+30min, but we accrue until T+2h
        uint256 startTs = block.timestamp;
        uint256 externalResolution = startTs + 30 minutes;

        // Accrue past the resolution time
        vm.warp(startTs + 2 hours);
        engine.accrueIndex(MARKET_A, true);

        // computeIndexAt at resolution time should be less than current
        uint256 frozenIndex = engine.computeIndexAt(MARKET_A, true, externalResolution);
        uint256 currentIndex = engine.getBorrowIndex(MARKET_A, true);

        // The frozen index is capped at lastAccrual (current), so it returns current
        // But what we really want to test is projecting from BEFORE the accrual.
        // Let's do a proper scenario:

        // Reset: new engine
        BorrowFeeEngine engine2 = new BorrowFeeEngine(
            admin, address(registry), address(oiLimits), address(posMgr)
        );
        vm.warp(startTs);
        engine2.initializeMarketIndex(MARKET_A);
        engine2.updateMarketRiskParams(MARKET_A, 0, 0, WAD, WAD, 0, 0);

        // Project from T=0 to T+30min
        uint256 frozenIdx = engine2.computeIndexAt(MARKET_A, true, externalResolution);

        // Now accrue to T+2h
        vm.warp(startTs + 2 hours);
        engine2.accrueIndex(MARKET_A, true);
        uint256 fullIdx = engine2.getBorrowIndex(MARKET_A, true);

        assertGt(fullIdx, frozenIdx, "Full accrual should exceed frozen-at-resolution index");
    }

    // ──────────────────────────────────────────────
    // Live Compression Tests
    // ──────────────────────────────────────────────

    function test_rate_increasesWhenLive() public {
        // Not live: τ_eff = τ
        uint256 rateNotLive = engine.getCurrentBorrowRate(MARKET_A, true);

        // Live: τ_eff = τ × 0.30 → closer to resolution → higher M_ttR → higher rate
        registry.setMarket(MARKET_A, 48e18, true);
        uint256 rateLive = engine.getCurrentBorrowRate(MARKET_A, true);

        assertGt(rateLive, rateNotLive, "Rate should be higher when live (compressed tau)");
    }

    // ──────────────────────────────────────────────
    // Pause Tests
    // ──────────────────────────────────────────────

    function test_accrueIndex_revertsWhenPaused() public {
        engine.pause();
        vm.expectRevert();
        engine.accrueIndex(MARKET_A, true);
    }

    function test_accrueIndex_worksAfterUnpause() public {
        engine.pause();
        engine.unpause();

        vm.warp(block.timestamp + 1 hours);
        engine.accrueIndex(MARKET_A, true);

        assertGt(engine.getBorrowIndex(MARKET_A, true), WAD);
    }

    // ──────────────────────────────────────────────
    // Edge Case: Fees Monotonically Increase
    // ──────────────────────────────────────────────

    function test_fuzz_feesNeverDecrease(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1, 365 days);

        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, WAD
        );

        // First accrual
        vm.warp(block.timestamp + timeDelta / 2);
        engine.accrueIndex(MARKET_A, true);
        uint256 fees1 = engine.getAccruedFees(posId);

        // Second accrual
        vm.warp(block.timestamp + timeDelta / 2);
        engine.accrueIndex(MARKET_A, true);
        uint256 fees2 = engine.getAccruedFees(posId);

        assertGe(fees2, fees1, "Fees should never decrease over time");
    }

    // ──────────────────────────────────────────────
    // M_ttR Verification Against WP Table
    // ──────────────────────────────────────────────

    function test_mttR_atResolutionIs25() public {
        registry.setMarket(MARKET_A, 0, false);
        assertEq(engine.getMttR(MARKET_A), 25e18, "M_ttR at tau=0 must be exactly 25x");
    }

    function test_mttR_veryFarFromResolution() public {
        // τ = 720h (30 days): R_borrow should be large, M_ttR close to 1
        registry.setMarket(MARKET_A, 720e18, false);
        uint256 mttR = engine.getMttR(MARKET_A);
        assertLt(mttR, 2e18, "M_ttR far from resolution should be close to 1");
    }
}
