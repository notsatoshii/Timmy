// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import {
    FundingRateEngine,
    FundingRateEngine__ZeroAddress,
    FundingRateEngine__NoUnmatchedFunding
} from "../contracts/FundingRateEngine.sol";
import { IFundingRateEngine } from "../contracts/interfaces/IFundingRateEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarketRegistryFunding {
    struct MockMarket {
        uint256 tau;
        bool live;
    }

    mapping(bytes32 => MockMarket) private _markets;

    function setMarket(bytes32 marketId, uint256 tau, bool live) external {
        _markets[marketId].tau = tau;
        _markets[marketId].live = live;
    }

    function getTau(bytes32 marketId) external view returns (uint256) {
        return _markets[marketId].tau;
    }

    function isLive(bytes32 marketId) external view returns (bool) {
        return _markets[marketId].live;
    }
}

contract MockOILimitsFunding {
    mapping(bytes32 => int256) private _imbalanceRatio;
    mapping(bytes32 => uint256) private _longOI;
    mapping(bytes32 => uint256) private _shortOI;

    function setImbalanceRatio(bytes32 marketId, int256 ratio) external {
        _imbalanceRatio[marketId] = ratio;
    }

    function setOI(bytes32 marketId, uint256 longOI, uint256 shortOI) external {
        _longOI[marketId] = longOI;
        _shortOI[marketId] = shortOI;
    }

    function getImbalanceRatio(bytes32 marketId) external view returns (int256) {
        return _imbalanceRatio[marketId];
    }

    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256) {
        return isLong ? _longOI[marketId] : _shortOI[marketId];
    }
}

contract MockPositionManagerFunding {
    mapping(uint256 => IPositionManager.Position) private _positions;
    uint256 private _nextId = 1;

    function createMockPosition(
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        int256 fundingIndex
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
            borrowIndex: 1e18,
            fundingIndex: fundingIndex,
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

contract MockAccountManager_FRE {
    function transferOut(address, uint256) external {}
}

contract MockRewardsDistributor_FRE {
    function depositRewards(uint256) external {}
    // FIX LEVER-P05: receiveUnmatchedFunding is the correct function (requires FUNDING_RATE_ENGINE_ROLE)
    function receiveUnmatchedFunding(bytes32, uint256) external {}
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

contract FundingRateEngineTest is Test {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    FundingRateEngine public engine;
    MockMarketRegistryFunding public registry;
    MockOILimitsFunding public oiLimits;
    MockPositionManagerFunding public posMgr;

    address public admin = address(this);
    address public user1 = address(0x1);
    MockAccountManager_FRE public mockAccountManager;
    MockRewardsDistributor_FRE public mockRewardsDistributor;

    bytes32 public constant MARKET_A = keccak256("MARKET_A");

    function setUp() public {
        registry = new MockMarketRegistryFunding();
        oiLimits = new MockOILimitsFunding();
        posMgr = new MockPositionManagerFunding();
        mockAccountManager = new MockAccountManager_FRE();
        mockRewardsDistributor = new MockRewardsDistributor_FRE();

        engine = new FundingRateEngine(
            admin,
            address(registry),
            address(oiLimits),
            address(posMgr),
            address(mockAccountManager),
            address(mockRewardsDistributor)
        );

        // 48h to resolution, not live, balanced OI
        registry.setMarket(MARKET_A, 48e18, false);
        oiLimits.setImbalanceRatio(MARKET_A, 0);
        oiLimits.setOI(MARKET_A, 500e18, 500e18);

        engine.initializeMarketIndex(MARKET_A);

        // Set default risk params (no stress: M_market = 1.0)
        engine.updateMarketRiskParams(MARKET_A, 0, 0, WAD, WAD, 0, 0);
    }

    // ──────────────────────────────────────────────
    // Constructor Tests
    // ──────────────────────────────────────────────

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(address(0), address(registry), address(oiLimits), address(posMgr), address(mockAccountManager), address(mockRewardsDistributor));
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(admin, address(0), address(oiLimits), address(posMgr), address(mockAccountManager), address(mockRewardsDistributor));
    }

    function test_constructor_revertsOnZeroOILimits() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(admin, address(registry), address(0), address(posMgr), address(mockAccountManager), address(mockRewardsDistributor));
    }

    function test_constructor_revertsOnZeroPosMgr() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(admin, address(registry), address(oiLimits), address(0), address(mockAccountManager), address(mockRewardsDistributor));
    }

    function test_constructor_revertsOnZeroAccountManager() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(admin, address(registry), address(oiLimits), address(posMgr), address(0), address(mockRewardsDistributor));
    }

    function test_constructor_revertsOnZeroRewardsDistributor() public {
        vm.expectRevert(FundingRateEngine__ZeroAddress.selector);
        new FundingRateEngine(admin, address(registry), address(oiLimits), address(posMgr), address(mockAccountManager), address(0));
    }

    // ──────────────────────────────────────────────
    // Index Initialization
    // ──────────────────────────────────────────────

    function test_initializeMarketIndex_setsToZero() public {
        bytes32 newMarket = keccak256("NEW");
        engine.initializeMarketIndex(newMarket);

        assertEq(engine.getFundingIndex(newMarket), 0, "Funding index should start at 0");
    }

    function test_initializeMarketIndex_doesNotReinitialize() public {
        // Create imbalance and accrue
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);
        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 indexAfterAccrual = engine.getFundingIndex(MARKET_A);
        assertGt(indexAfterAccrual, 0, "Index should have changed");

        // Try re-initializing - should be no-op
        engine.initializeMarketIndex(MARKET_A);
        assertEq(engine.getFundingIndex(MARKET_A), indexAfterAccrual, "Should not reinitialize");
    }

    // ──────────────────────────────────────────────
    // Funding Rate Calculation Tests
    // ──────────────────────────────────────────────

    function test_fundingRate_balanced() public view {
        // No imbalance → rate should be 0
        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        assertEq(rate, 0, "Balanced market should have zero funding rate");
    }

    function test_fundingRate_longHeavy() public {
        // imbalance = +0.5 (longs heavy)
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        assertGt(rate, 0, "Long-heavy market should have positive rate (longs pay)");
    }

    function test_fundingRate_shortHeavy() public {
        // imbalance = -0.5 (shorts heavy)
        oiLimits.setImbalanceRatio(MARKET_A, -5e17);

        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        assertLt(rate, 0, "Short-heavy market should have negative rate (shorts pay)");
    }

    function test_fundingRate_symmetry() public {
        oiLimits.setImbalanceRatio(MARKET_A, 3e17);
        int256 rateLong = engine.getCurrentFundingRate(MARKET_A);

        oiLimits.setImbalanceRatio(MARKET_A, -3e17);
        int256 rateShort = engine.getCurrentFundingRate(MARKET_A);

        assertEq(rateLong, -rateShort, "Rates should be symmetric");
    }

    function test_fundingRate_cappedAtMax() public {
        // At resolution (tau=0): multiplier = 1 + 3*(1-0) = 4
        // rate = 1e14 * 1.0 * 4.0 = 4e14 < 5e14 max
        registry.setMarket(MARKET_A, 0, false);
        oiLimits.setImbalanceRatio(MARKET_A, int256(WAD));

        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        assertEq(rate, 4e14, "Rate at full imbalance + max multiplier");
        assertTrue(rate <= int256(engine.MAX_FUNDING_RATE()), "Should not exceed cap");
    }

    function test_fundingRate_zeroImbalanceZeroRate() public view {
        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        assertEq(rate, 0, "Zero imbalance = zero rate");
    }

    // ──────────────────────────────────────────────
    // Funding Multiplier Tests
    // ──────────────────────────────────────────────

    function test_fundingMultiplier_farFromResolution() public view {
        // tau=48h: R close to 1, multiplier close to 1
        uint256 mult = engine.getFundingMultiplier(MARKET_A);
        assertGt(mult, WAD, "Multiplier should be >= 1");
        assertLt(mult, 11e17, "Multiplier should be close to 1 far from resolution");
    }

    function test_fundingMultiplier_atResolution() public {
        // tau=0: R=0, multiplier = 1 + 3*(1-0) = 4
        registry.setMarket(MARKET_A, 0, false);
        uint256 mult = engine.getFundingMultiplier(MARKET_A);
        assertEq(mult, 4e18, "Multiplier at resolution should be 4.0");
    }

    function test_fundingMultiplier_nearResolution() public {
        // tau=1h: R small, multiplier close to 4
        registry.setMarket(MARKET_A, 1e18, false);
        uint256 mult = engine.getFundingMultiplier(MARKET_A);
        assertGt(mult, 35e17, "Multiplier near resolution should be > 3.5");
        assertLt(mult, 4e18, "Multiplier near resolution should be < 4.0");
    }

    // ──────────────────────────────────────────────
    // Index Accrual Tests
    // ──────────────────────────────────────────────

    function test_accrueFunding_noOpWhenBalanced() public {
        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        assertEq(engine.getFundingIndex(MARKET_A), 0, "Balanced market index should stay at 0");
    }

    function test_accrueFunding_increasesWhenLongHeavy() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 idx = engine.getFundingIndex(MARKET_A);
        assertGt(idx, 0, "Index should increase when longs pay");
    }

    function test_accrueFunding_decreasesWhenShortHeavy() public {
        oiLimits.setImbalanceRatio(MARKET_A, -5e17);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 idx = engine.getFundingIndex(MARKET_A);
        assertLt(idx, 0, "Index should decrease when shorts pay");
    }

    function test_accrueFunding_noOpSameBlock() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);
        engine.accrueFunding(MARKET_A);

        int256 idx = engine.getFundingIndex(MARKET_A);
        assertEq(idx, 0, "No change in same block");
    }

    function test_accrueFunding_correctAmount() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        int256 rate = engine.getCurrentFundingRate(MARKET_A);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 idx = engine.getFundingIndex(MARKET_A);
        // 1 hour of accrual: indexDelta = rate * 3600 / 3600 = rate
        assertApproxEqAbs(idx, rate, 1, "1 hour accrual should equal the hourly rate");
    }

    function test_accrueFunding_multipleHours() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        int256 rate = engine.getCurrentFundingRate(MARKET_A);

        vm.warp(block.timestamp + 3 hours);
        engine.accrueFunding(MARKET_A);

        int256 idx = engine.getFundingIndex(MARKET_A);
        int256 expected = rate * 3;
        assertApproxEqAbs(idx, expected, 1, "3 hour accrual should be 3x hourly rate");
    }

    // ──────────────────────────────────────────────
    // Accrued Funding Per Position Tests
    // ──────────────────────────────────────────────

    function test_getAccruedFunding_longPaysFunding() public {
        // Long-heavy: longs pay (positive rate, index rises)
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        // Open long at index=0
        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 funding = engine.getAccruedFunding(posId);
        assertLt(funding, 0, "Long should pay funding when long-heavy (negative accrued)");
    }

    function test_getAccruedFunding_shortReceivesFunding() public {
        // Long-heavy: shorts receive (positive rate, index rises)
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        // Open short at index=0
        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, false, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 funding = engine.getAccruedFunding(posId);
        assertGt(funding, 0, "Short should receive funding when long-heavy (positive accrued)");
    }

    function test_getAccruedFunding_shortPaysFunding() public {
        // Short-heavy: shorts pay
        oiLimits.setImbalanceRatio(MARKET_A, -5e17);

        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, false, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 funding = engine.getAccruedFunding(posId);
        assertLt(funding, 0, "Short should pay funding when short-heavy");
    }

    function test_getAccruedFunding_longReceivesFunding() public {
        // Short-heavy: longs receive
        oiLimits.setImbalanceRatio(MARKET_A, -5e17);

        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 funding = engine.getAccruedFunding(posId);
        assertGt(funding, 0, "Long should receive funding when short-heavy");
    }

    function test_getAccruedFunding_correctAmount() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 funding = engine.getAccruedFunding(posId);
        int256 idx = engine.getFundingIndex(MARKET_A);

        // For long: accrued = -1 * 1000e18 * idx / WAD = -(1000 * idx / WAD)
        int256 expected = -int256(uint256(1000e18)) * idx / int256(WAD);
        assertEq(funding, expected, "Accrued funding should match formula");
    }

    function test_getAccruedFunding_closedPositionReturnsZero() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        uint256 posId = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        posMgr.closePosition(posId);
        int256 funding = engine.getAccruedFunding(posId);
        assertEq(funding, 0, "Closed position should return 0");
    }

    function test_getAccruedFunding_laterEntryLessFunding() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        // Position 1: opens at index=0
        uint256 pos1 = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, 0
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        // Position 2: opens at current index
        int256 currentIdx = engine.getFundingIndex(MARKET_A);
        uint256 pos2 = posMgr.createMockPosition(
            user1, MARKET_A, true, 1000e18, 100e18, 10e18, currentIdx
        );

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        int256 fund1 = engine.getAccruedFunding(pos1);
        int256 fund2 = engine.getAccruedFunding(pos2);

        // Both negative (long paying), but pos1 paid more (open longer)
        assertLt(fund1, fund2, "Earlier position should have paid more (more negative)");
        assertLt(fund2, 0, "Later position should also have paid");
    }

    // ──────────────────────────────────────────────
    // OI Split Tests
    // ──────────────────────────────────────────────

    function test_getOISplit_balanced() public view {
        (uint256 matched, uint256 unmatched) = engine.getOISplit(MARKET_A);
        assertEq(matched, 500e18, "Matched should be min(500, 500)");
        assertEq(unmatched, 0, "No unmatched when balanced");
    }

    function test_getOISplit_longHeavy() public {
        oiLimits.setOI(MARKET_A, 700e18, 300e18);
        (uint256 matched, uint256 unmatched) = engine.getOISplit(MARKET_A);
        assertEq(matched, 300e18, "Matched should be min(700, 300)");
        assertEq(unmatched, 400e18, "Unmatched should be 400");
    }

    function test_getOISplit_shortHeavy() public {
        oiLimits.setOI(MARKET_A, 200e18, 800e18);
        (uint256 matched, uint256 unmatched) = engine.getOISplit(MARKET_A);
        assertEq(matched, 200e18, "Matched should be min(200, 800)");
        assertEq(unmatched, 600e18, "Unmatched should be 600");
    }

    // ──────────────────────────────────────────────
    // Unmatched Funding Routing Tests
    // ──────────────────────────────────────────────

    function test_unmatchedFunding_accumulatesOnAccrual() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);
        oiLimits.setOI(MARKET_A, 750e18, 250e18);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        uint256 pending = engine.getPendingUnmatchedFunding(MARKET_A);
        assertGt(pending, 0, "Should have pending unmatched funding");
    }

    function test_unmatchedFunding_zeroWhenBalanced() public {
        oiLimits.setOI(MARKET_A, 500e18, 500e18);
        oiLimits.setImbalanceRatio(MARKET_A, 5e17); // rate is nonzero but unmatched OI is 0

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        uint256 pending = engine.getPendingUnmatchedFunding(MARKET_A);
        assertEq(pending, 0, "No unmatched funding when OI is balanced");
    }

    function test_routeUnmatchedFunding_clearsPending() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);
        oiLimits.setOI(MARKET_A, 750e18, 250e18);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        uint256 pendingBefore = engine.getPendingUnmatchedFunding(MARKET_A);
        assertGt(pendingBefore, 0);

        engine.routeUnmatchedFunding(MARKET_A);

        assertEq(engine.getPendingUnmatchedFunding(MARKET_A), 0, "Should be cleared after routing");
    }

    function test_routeUnmatchedFunding_revertsWhenNoPending() public {
        vm.expectRevert(abi.encodeWithSelector(
            FundingRateEngine__NoUnmatchedFunding.selector,
            MARKET_A
        ));
        engine.routeUnmatchedFunding(MARKET_A);
    }

    // ──────────────────────────────────────────────
    // computeIndexAt (Settlement Freeze) Tests
    // ──────────────────────────────────────────────

    function test_computeIndexAt_futureTimestamp() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        uint256 futureTs = block.timestamp + 1 hours;
        int256 projected = engine.computeIndexAt(MARKET_A, futureTs);

        assertGt(projected, 0, "Projected index should be positive for long-heavy");
    }

    function test_computeIndexAt_pastTimestamp() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        vm.warp(block.timestamp + 2 hours);
        engine.accrueFunding(MARKET_A);

        int256 currentIdx = engine.getFundingIndex(MARKET_A);
        int256 pastIdx = engine.computeIndexAt(MARKET_A, block.timestamp - 1 hours);

        assertEq(pastIdx, currentIdx, "Past timestamp should return stored index");
    }

    function test_computeIndexAt_matchesActualAccrual() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        uint256 targetTs = block.timestamp + 1 hours;
        int256 projected = engine.computeIndexAt(MARKET_A, targetTs);

        vm.warp(targetTs);
        engine.accrueFunding(MARKET_A);
        int256 actual = engine.getFundingIndex(MARKET_A);

        assertApproxEqAbs(projected, actual, 1, "Projected should match actual accrual");
    }

    // ──────────────────────────────────────────────
    // Live Compression Tests
    // ──────────────────────────────────────────────

    function test_multiplier_increasesWhenLive() public {
        uint256 multNotLive = engine.getFundingMultiplier(MARKET_A);

        // Live: tau_eff = tau*0.30 -> closer to resolution -> higher multiplier
        registry.setMarket(MARKET_A, 48e18, true);
        uint256 multLive = engine.getFundingMultiplier(MARKET_A);

        assertGt(multLive, multNotLive, "Multiplier should increase when live (compressed tau)");
    }

    // ──────────────────────────────────────────────
    // Pause Tests
    // ──────────────────────────────────────────────

    function test_accrueFunding_revertsWhenPaused() public {
        engine.pause();
        vm.expectRevert();
        engine.accrueFunding(MARKET_A);
    }

    function test_accrueFunding_worksAfterUnpause() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);

        engine.pause();
        engine.unpause();

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        assertGt(engine.getFundingIndex(MARKET_A), 0);
    }

    function test_routeUnmatchedFunding_revertsWhenPaused() public {
        oiLimits.setImbalanceRatio(MARKET_A, 5e17);
        oiLimits.setOI(MARKET_A, 750e18, 250e18);
        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(MARKET_A);

        engine.pause();
        vm.expectRevert();
        engine.routeUnmatchedFunding(MARKET_A);
    }

    // ──────────────────────────────────────────────
    // Access Control Tests
    // ──────────────────────────────────────────────

    function test_initializeMarketIndex_onlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        engine.initializeMarketIndex(keccak256("NEW2"));
    }

    function test_updateMarketRiskParams_onlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        engine.updateMarketRiskParams(MARKET_A, 0, 0, WAD, WAD, 0, 0);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        engine.pause();
    }

    // ──────────────────────────────────────────────
    // Fuzz: Funding Never Loses Directionality
    // ──────────────────────────────────────────────

    function test_fuzz_fundingDirectionConsistent(int256 imbalance) public {
        // Bound imbalance to valid range [-1, 1] WAD
        imbalance = bound(imbalance, -int256(WAD), int256(WAD));

        oiLimits.setImbalanceRatio(MARKET_A, imbalance);

        int256 rate = engine.getCurrentFundingRate(MARKET_A);

        if (imbalance > 0) {
            assertGe(rate, 0, "Positive imbalance should give non-negative rate");
        } else if (imbalance < 0) {
            assertLe(rate, 0, "Negative imbalance should give non-positive rate");
        } else {
            assertEq(rate, 0, "Zero imbalance should give zero rate");
        }
    }

    function test_fuzz_indexMonotonic(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1, 365 days);

        oiLimits.setImbalanceRatio(MARKET_A, 3e17); // long-heavy

        vm.warp(block.timestamp + timeDelta / 2);
        engine.accrueFunding(MARKET_A);
        int256 idx1 = engine.getFundingIndex(MARKET_A);

        vm.warp(block.timestamp + timeDelta / 2);
        engine.accrueFunding(MARKET_A);
        int256 idx2 = engine.getFundingIndex(MARKET_A);

        assertGe(idx2, idx1, "Index should monotonically increase for constant positive rate");
    }

    // ──────────────────────────────────────────────
    // Edge: Uninitialized Market
    // ──────────────────────────────────────────────

    function test_accrueFunding_uninitializedMarketNoOp() public {
        bytes32 uninit = keccak256("UNINIT");
        registry.setMarket(uninit, 48e18, false);

        vm.warp(block.timestamp + 1 hours);
        engine.accrueFunding(uninit); // Should not revert, just no-op

        assertEq(engine.getFundingIndex(uninit), 0);
    }
}
