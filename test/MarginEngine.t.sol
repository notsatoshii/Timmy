// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { IMarginEngine } from "../contracts/interfaces/IMarginEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockPositionManager {
    mapping(uint256 => IPositionManager.Position) private _positions;
    uint256 private _nextId = 1;

    function createMockPosition(
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 entryPI,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        uint256 borrowIndex,
        int256 fundingIndex
    ) external returns (uint256 posId) {
        posId = _nextId++;
        _positions[posId] = IPositionManager.Position({
            id: posId,
            owner: owner,
            marketId: marketId,
            isLong: isLong,
            entryPI: entryPI,
            entryPrice: entryPI, // simplified
            positionSize: positionSize,
            collateral: collateral,
            leverage: leverage,
            borrowIndex: borrowIndex,
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

    function isPositionOpen(uint256 posId) external view returns (bool) {
        return _positions[posId].isOpen;
    }
}

contract MockOracleAdapter {
    mapping(bytes32 => uint256) private _pi;

    function setPI(bytes32 marketId, uint256 pi) external {
        _pi[marketId] = pi;
    }

    function getPI(bytes32 marketId) external view returns (uint256) {
        return _pi[marketId];
    }

    function getVolatility(bytes32 marketId) external pure returns (uint256) {
        return 0;
    }
}

contract MockMarketRegistry {
    struct MockMarket {
        uint256 tau;
        bool live;
    }

    mapping(bytes32 => MockMarket) public markets;

    function setMarket(bytes32 id, uint256 tau, bool live_) external {
        markets[id] = MockMarket(tau, live_);
    }

    function getTau(bytes32 id) external view returns (uint256) {
        return markets[id].tau;
    }

    function isLive(bytes32 id) external view returns (bool) {
        return markets[id].live;
    }
}

contract MockBorrowFeeEngine {
    mapping(uint256 => uint256) private _fees;

    function setAccruedFees(uint256 positionId, uint256 fees) external {
        _fees[positionId] = fees;
    }

    function getAccruedFees(uint256 positionId) external view returns (uint256) {
        return _fees[positionId];
    }
}

contract MockFundingRateEngine {
    mapping(uint256 => int256) private _funding;

    function setAccruedFunding(uint256 positionId, int256 funding) external {
        _funding[positionId] = funding;
    }

    function getAccruedFunding(uint256 positionId) external view returns (int256) {
        return _funding[positionId];
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract MarginEngineTest is Test {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    MarginEngine public engine;
    MockPositionManager public posMgr;
    MockOracleAdapter public oracle;
    MockMarketRegistry public registry;
    MockBorrowFeeEngine public borrowEngine;
    MockFundingRateEngine public fundingEngine;

    address public admin = address(0xAD);
    address public user = address(0xBEEF);
    bytes32 public marketId = keccak256("BTC-ELECTION");

    function setUp() public {
        posMgr = new MockPositionManager();
        oracle = new MockOracleAdapter();
        registry = new MockMarketRegistry();
        borrowEngine = new MockBorrowFeeEngine();
        fundingEngine = new MockFundingRateEngine();

        engine = new MarginEngine(
            admin,
            address(posMgr),
            address(oracle),
            address(registry),
            address(borrowEngine),
            address(fundingEngine)
        );

        // Default market: 48 hours to resolution, not live
        // R_adjusted ≈ 0.9817 (high, far from resolution) with M_market = 1.0
        registry.setMarket(marketId, 48e18, false);

        // Set default risk params (M_market = 1.0: no vol/depth/concentration adjustment)
        vm.prank(admin);
        engine.updateMarketRiskParams(
            marketId,
            0,     // sigmaCurrent = 0
            0,     // sigmaBaseline = 0
            WAD,   // externalDepth = 1.0
            WAD,   // depthThreshold = 1.0
            0,     // marketOI = 0
            WAD,   // globalOI = 1.0 (avoid div by zero in concentration)
            0      // marketUtilization = 0
        );

        // Default PI = 0.50
        oracle.setPI(marketId, 5e17);
    }

    // ──────────────────────────────────────────────
    // Constructor Tests
    // ──────────────────────────────────────────────

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(address(0), address(posMgr), address(oracle), address(registry), address(borrowEngine), address(fundingEngine));

        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(admin, address(0), address(oracle), address(registry), address(borrowEngine), address(fundingEngine));

        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(admin, address(posMgr), address(0), address(registry), address(borrowEngine), address(fundingEngine));

        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(admin, address(posMgr), address(oracle), address(0), address(borrowEngine), address(fundingEngine));

        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(admin, address(posMgr), address(oracle), address(registry), address(0), address(fundingEngine));

        vm.expectRevert(MarginEngine.MarginEngine__ZeroAddress.selector);
        new MarginEngine(admin, address(posMgr), address(oracle), address(registry), address(borrowEngine), address(0));
    }

    // ──────────────────────────────────────────────
    // computeEquity Tests
    // ──────────────────────────────────────────────

    function test_computeEquity_noPnlNoFeesNoFunding() public {
        // Position: long, entry PI = 0.50, current PI = 0.50, collateral = 100
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17,    // entryPI = 0.50
            1000e18, // positionSize = 1000
            100e18,  // collateral = 100
            10e18,   // leverage = 10×
            WAD,     // borrowIndex
            0        // fundingIndex
        );

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        assertEq(eq.pnl, 0, "PnL should be zero when PI unchanged");
        assertEq(eq.accruedBorrowFees, 0, "No borrow fees");
        assertEq(eq.accruedFunding, 0, "No funding");
        assertEq(eq.equity, 100e18, "Equity = collateral");
        // MR = 100/1000 = 0.10
        assertEq(eq.marginRatio, 1e17, "MR = 10%");
    }

    function test_computeEquity_longPositivePnL() public {
        // Long entry at 0.50, current PI = 0.60 → positive PnL
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17,    // entryPI = 0.50
            1000e18,
            100e18,
            10e18,
            WAD, 0
        );

        oracle.setPI(marketId, 6e17); // PI moves to 0.60

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = +1 × (0.60 - 0.50) × 1000 = +100
        assertEq(eq.pnl, 100e18, "Long PnL positive when PI rises");
        // Equity = 100 + 100 = 200
        assertEq(eq.equity, 200e18, "Equity includes positive PnL");
    }

    function test_computeEquity_longNegativePnL() public {
        // Long entry at 0.50, current PI = 0.40 → negative PnL
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17,
            1000e18,
            100e18,
            10e18,
            WAD, 0
        );

        oracle.setPI(marketId, 4e17); // PI drops to 0.40

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = +1 × (0.40 - 0.50) × 1000 = -100
        assertEq(eq.pnl, -100e18, "Long PnL negative when PI drops");
        // Equity = 100 - 100 = 0
        assertEq(eq.equity, 0, "Equity = 0");
        assertEq(eq.marginRatio, 0, "MR = 0 when equity is zero");
    }

    function test_computeEquity_shortPositivePnL() public {
        // Short entry at 0.50, current PI = 0.40 → positive PnL for short
        uint256 posId = posMgr.createMockPosition(
            user, marketId, false, // short
            5e17,
            1000e18,
            100e18,
            10e18,
            WAD, 0
        );

        oracle.setPI(marketId, 4e17);

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = -1 × (0.40 - 0.50) × 1000 = +100
        assertEq(eq.pnl, 100e18, "Short PnL positive when PI drops");
        assertEq(eq.equity, 200e18);
    }

    function test_computeEquity_withBorrowFees() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        borrowEngine.setAccruedFees(posId, 20e18); // 20 USDT borrow fees

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // Equity = 100 + 0 - 20 + 0 = 80
        assertEq(eq.accruedBorrowFees, 20e18);
        assertEq(eq.equity, 80e18, "Borrow fees reduce equity");
    }

    function test_computeEquity_withPositiveFunding() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        fundingEngine.setAccruedFunding(posId, 15e18); // received 15 USDT

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // Equity = 100 + 0 - 0 + 15 = 115
        assertEq(eq.accruedFunding, 15e18);
        assertEq(eq.equity, 115e18, "Positive funding increases equity");
    }

    function test_computeEquity_withNegativeFunding() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        fundingEngine.setAccruedFunding(posId, -25e18); // paid 25 USDT

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // Equity = 100 + 0 - 0 + (-25) = 75
        assertEq(eq.accruedFunding, -25e18);
        assertEq(eq.equity, 75e18, "Negative funding decreases equity");
    }

    function test_computeEquity_fullPincerEffect() public {
        // Pincer: PnL drops, borrow fees accrue, funding paid
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        oracle.setPI(marketId, 45e16); // PI drops to 0.45 → PnL = -50
        borrowEngine.setAccruedFees(posId, 10e18); // 10 USDT borrow
        fundingEngine.setAccruedFunding(posId, -5e18); // paid 5 USDT funding

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // Equity = 100 + (-50) - 10 + (-5) = 35
        assertEq(eq.pnl, -50e18);
        assertEq(eq.equity, 35e18, "Pincer: PnL + borrow + funding all erode equity");
    }

    function test_computeEquity_negativeEquity() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        oracle.setPI(marketId, 38e16); // PI = 0.38, PnL = -120
        borrowEngine.setAccruedFees(posId, 5e18);

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // Equity = 100 - 120 - 5 = -25
        assertEq(eq.equity, -25e18, "Equity can go negative");
        assertEq(eq.marginRatio, 0, "MR = 0 when equity < 0");
    }

    function test_computeEquity_revertsForClosedPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );
        posMgr.closePosition(posId);

        vm.expectRevert(abi.encodeWithSelector(
            IMarginEngine.MarginEngine__PositionNotFound.selector, posId
        ));
        engine.computeEquity(posId);
    }

    // ──────────────────────────────────────────────
    // Margin Requirements Tests
    // ──────────────────────────────────────────────

    function test_computeMarginRequirements_farFromResolution() public {
        // τ = 48h, not live → R_adjusted ≈ 0.9817 (high)
        // MM_Multiplier ≈ 3.0 - 0.9817 × 2.0 ≈ 1.0365
        // MM = 0.025 × 1000 × 1.0365 ≈ 25.91

        IMarginEngine.MarginRequirements memory reqs = engine.computeMarginRequirements(
            marketId, 1000e18, 10e18
        );

        // mmMultiplier should be close to 1.0 (far from resolution)
        assertGt(reqs.mmMultiplier, WAD, "MM mult > 1.0");
        assertLt(reqs.mmMultiplier, 15e17, "MM mult < 1.5 far from resolution");

        // MM should be slightly above base (2.5%)
        assertGt(reqs.maintenanceMargin, 25e18, "MM > 25 (base 2.5%)");
        assertLt(reqs.maintenanceMargin, 40e18, "MM < 40 far from resolution");

        // IM = 1000 × 0.05 × ~1.04 ≈ 52 (rate-based)
        assertGt(reqs.initialMargin, 50e18, "IM > 50");
        assertLt(reqs.initialMargin, 60e18, "IM < 60");
    }

    function test_computeMarginRequirements_nearResolution() public {
        // τ = 1h, not live → R_adjusted ≈ 0.0800
        // MM_Multiplier ≈ 3.0 - 0.08 × 2.0 ≈ 2.84
        registry.setMarket(marketId, 1e18, false);

        IMarginEngine.MarginRequirements memory reqs = engine.computeMarginRequirements(
            marketId, 1000e18, 10e18
        );

        // MM multiplier should be close to 3.0 (near resolution)
        assertGt(reqs.mmMultiplier, 25e17, "MM mult > 2.5 near resolution");
        assertLt(reqs.mmMultiplier, 3e18 + 1, "MM mult <= 3.0");

        // MM = 0.025 × 1000 × ~2.84 ≈ 71
        assertGt(reqs.maintenanceMargin, 60e18, "MM > 60 near resolution");
    }

    function test_computeMarginRequirements_atResolution() public {
        // τ = 0 → R = 0 → MM_Multiplier = 3.0, IM_Multiplier = 3.0
        registry.setMarket(marketId, 0, false);

        IMarginEngine.MarginRequirements memory reqs = engine.computeMarginRequirements(
            marketId, 1000e18, 10e18
        );

        // MM_Multiplier = 3.0 - 0 × 2.0 = 3.0
        assertEq(reqs.mmMultiplier, 3e18, "MM mult = 3.0 at resolution");
        // MM = 0.025 × 1000 × 3.0 = 75
        assertEq(reqs.maintenanceMargin, 75e18, "MM = 75 at resolution");
    }

    function test_getMaintenanceMargin() public {
        registry.setMarket(marketId, 0, false); // R = 0 → MM_mult = 3.0

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        uint256 mm = engine.getMaintenanceMargin(posId);
        // MM = 0.025 × 1000 × 3.0 = 75
        assertEq(mm, 75e18);
    }

    function test_getMaintenanceMargin_revertsForClosed() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );
        posMgr.closePosition(posId);

        vm.expectRevert(abi.encodeWithSelector(
            IMarginEngine.MarginEngine__PositionNotFound.selector, posId
        ));
        engine.getMaintenanceMargin(posId);
    }

    function test_getInitialMargin_withVolAdjustment() public {
        // Set high current volatility
        vm.prank(admin);
        engine.updateMarketRiskParams(
            marketId,
            5e17,  // sigmaCurrent = 0.50
            1e17,  // sigmaBaseline = 0.10
            WAD, WAD, 0, WAD, 0
        );

        // vol_adj = 0.5 × (0.50 - 0.10) = 0.5 × 0.40 = 0.20
        // IM = 1000 × 0.05 × IM_mult × 1.20 ≈ 62
        uint256 im = engine.getInitialMargin(marketId, 1000e18, 10e18);
        uint256 imBase = engine.getInitialMargin(marketId, 1000e18, 10e18);

        // With vol adjustment, IM should be higher than base
        // Base IM ≈ 52, adjusted ≈ 62
        assertGt(im, 55e18, "IM increased by volatility");
        assertLt(im, 100e18, "IM reasonable range");
    }

    function test_getInitialMargin_withUtilAdjustment() public {
        // Set high market utilization
        vm.prank(admin);
        engine.updateMarketRiskParams(
            marketId,
            0, 0, WAD, WAD, 0, WAD,
            8e17 // marketUtilization = 80%
        );

        // util_adj = 1.0 × (0.80 - 0.50) = 0.30
        // IM = 1000 × 0.05 × IM_mult × 1.30 ≈ 68
        uint256 im = engine.getInitialMargin(marketId, 1000e18, 10e18);

        assertGt(im, 60e18, "IM increased by utilization");
        assertLt(im, 80e18, "IM reasonable range");
    }

    // ──────────────────────────────────────────────
    // Liquidation Tests
    // ──────────────────────────────────────────────

    function test_isLiquidatable_healthyPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        assertFalse(engine.isLiquidatable(posId), "Healthy position not liquidatable");
    }

    function test_isLiquidatable_belowThreshold() public {
        // At resolution: MM_mult = 3.0 → MM = 75, buffer = 5
        // Threshold = 80. Need equity < 80.
        registry.setMarket(marketId, 0, false);

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Drop PI so equity falls below threshold
        // PnL = (0.47 - 0.50) × 1000 = -30
        // Equity = 100 - 30 = 70 < 80 → liquidatable
        oracle.setPI(marketId, 47e16);

        assertTrue(engine.isLiquidatable(posId), "Should be liquidatable");
    }

    function test_isLiquidatable_exactlyAtThreshold() public {
        // At resolution: threshold = MM + buffer = 75 + 5 = 80
        registry.setMarket(marketId, 0, false);

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Equity = 100 - 20 = 80 = threshold → NOT liquidatable (equity < threshold is the check)
        oracle.setPI(marketId, 48e16); // PnL = -20, equity = 80

        assertFalse(engine.isLiquidatable(posId), "At threshold = not liquidatable");
    }

    function test_isLiquidatable_closedPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );
        posMgr.closePosition(posId);

        assertFalse(engine.isLiquidatable(posId), "Closed position not liquidatable");
    }

    function test_isLiquidatable_borrowFeesErodeEquity() public {
        registry.setMarket(marketId, 0, false);

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Borrow fees of 25 → equity = 100 - 25 = 75 < 80 → liquidatable
        borrowEngine.setAccruedFees(posId, 25e18);

        assertTrue(engine.isLiquidatable(posId), "Borrow fees push below threshold");
    }

    // ──────────────────────────────────────────────
    // Danger Zone Tests
    // ──────────────────────────────────────────────

    function test_isInDangerZone_healthyPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Far from resolution: threshold ≈ 30, danger ≈ 60. Equity = 100 > 60
        assertFalse(engine.isInDangerZone(posId), "Healthy position not in danger zone");
    }

    function test_isInDangerZone_nearThreshold() public {
        // At resolution: threshold = 80, danger = 160
        registry.setMarket(marketId, 0, false);

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Equity = 100 < 160 → in danger zone
        assertTrue(engine.isInDangerZone(posId), "Should be in danger zone");
    }

    // ──────────────────────────────────────────────
    // Margin Check Validation Tests
    // ──────────────────────────────────────────────

    function test_validateMarginChecks_validPosition() public {
        (bool valid, uint8 failedCheck) = engine.validateMarginChecks(
            marketId, user, true,
            100e18, // collateral
            10e18   // leverage = 10x
        );

        assertTrue(valid);
        assertEq(failedCheck, 0);
    }

    function test_validateMarginChecks_zeroCollateral() public {
        (bool valid, uint8 failedCheck) = engine.validateMarginChecks(
            marketId, user, true, 0, 10e18
        );

        assertFalse(valid);
        assertEq(failedCheck, 1, "Failed check 1: zero collateral");
    }

    function test_validateMarginChecks_zeroLeverage() public {
        (bool valid, uint8 failedCheck) = engine.validateMarginChecks(
            marketId, user, true, 100e18, 0
        );

        assertFalse(valid);
        assertEq(failedCheck, 2, "Failed check 2: leverage below 1x");
    }

    function test_validateMarginChecks_insufficientCollateralForIM() public {
        // At resolution: IM_mult = 3.0
        // IM = (notional / leverage) × 3.0 = (50 / 10) × 3.0 = 15
        // Collateral = 4 < 15 → fail check 4
        registry.setMarket(marketId, 0, false);

        (bool valid, uint8 failedCheck) = engine.validateMarginChecks(
            marketId, user, true,
            4e18,  // collateral = 4
            10e18  // leverage = 10× → notional = 40
        );

        assertFalse(valid);
        assertEq(failedCheck, 4, "Failed check 4: insufficient collateral for IM");
    }

    // ──────────────────────────────────────────────
    // Collateral Removal Tests
    // ──────────────────────────────────────────────

    function test_canRemoveCollateral_small() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 200e18, 5e18, WAD, 0
        );

        // Remove 10 USDT from 200 → plenty of margin left
        assertTrue(engine.canRemoveCollateral(posId, 10e18));
    }

    function test_canRemoveCollateral_tooMuch() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Try to remove 60 → new equity = 40
        // Required MR = MM/notional + 0.02
        // With τ=48h: MM ≈ 26, requiredMR ≈ 0.026 + 0.02 = 0.046
        // postMR = 40/1000 = 0.04 < 0.046 → should fail
        assertFalse(engine.canRemoveCollateral(posId, 60e18));
    }

    function test_canRemoveCollateral_allCollateral() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // Remove all collateral
        assertFalse(engine.canRemoveCollateral(posId, 100e18));
    }

    function test_canRemoveCollateral_moreThanCollateral() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        assertFalse(engine.canRemoveCollateral(posId, 101e18));
    }

    function test_canRemoveCollateral_closedPosition() public {
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true, 5e17, 1000e18, 100e18, 10e18, WAD, 0
        );
        posMgr.closePosition(posId);

        assertFalse(engine.canRemoveCollateral(posId, 10e18));
    }

    // ──────────────────────────────────────────────
    // Access Control Tests
    // ──────────────────────────────────────────────

    function test_updateMarketRiskParams_onlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        engine.updateMarketRiskParams(marketId, 0, 0, 0, 0, 0, 0, 0);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        engine.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        engine.pause();

        vm.prank(user);
        vm.expectRevert();
        engine.unpause();
    }

    // ──────────────────────────────────────────────
    // Edge Cases
    // ──────────────────────────────────────────────

    function test_computeEquity_maxPnL_longAtPI1() public {
        // Long entry at 0.50, PI settles to 1.0 → max PnL
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        oracle.setPI(marketId, WAD); // PI = 1.0

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = (1.0 - 0.50) × 1000 = 500
        assertEq(eq.pnl, 500e18);
        // Equity = 100 + 500 = 600
        assertEq(eq.equity, 600e18);
    }

    function test_computeEquity_maxLoss_longAtPI0() public {
        // Long entry at 0.50, PI settles to 0 → max loss
        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        oracle.setPI(marketId, 0); // PI = 0

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = (0 - 0.50) × 1000 = -500
        assertEq(eq.pnl, -500e18);
        // Equity = 100 - 500 = -400
        assertEq(eq.equity, -400e18);
    }

    function test_computeEquity_shortProfitsFromPI0() public {
        // Short entry at 0.50, PI goes to 0 → max profit for short
        uint256 posId = posMgr.createMockPosition(
            user, marketId, false, // short
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        oracle.setPI(marketId, 0);

        IMarginEngine.EquityResult memory eq = engine.computeEquity(posId);

        // PnL = -1 × (0 - 0.50) × 1000 = +500
        assertEq(eq.pnl, 500e18);
        assertEq(eq.equity, 600e18);
    }

    function test_marginRequirements_liveMarketIncreasesRisk() public {
        // Live market: τ_effective = τ × 0.30, so R is much lower → MM higher
        registry.setMarket(marketId, 48e18, true); // live

        IMarginEngine.MarginRequirements memory liveReqs = engine.computeMarginRequirements(
            marketId, 1000e18, 10e18
        );

        registry.setMarket(marketId, 48e18, false); // not live

        IMarginEngine.MarginRequirements memory normalReqs = engine.computeMarginRequirements(
            marketId, 1000e18, 10e18
        );

        // Live → lower R → higher MM multiplier → higher MM
        assertGt(liveReqs.maintenanceMargin, normalReqs.maintenanceMargin,
            "Live market has higher MM");
    }

    function test_isLiquidatable_fundingReceivedSavesPosition() public {
        registry.setMarket(marketId, 0, false); // threshold = 80

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // PnL = -30, equity before funding = 70 < 80 → would be liquidatable
        oracle.setPI(marketId, 47e16);

        assertTrue(engine.isLiquidatable(posId), "Liquidatable without funding");

        // Receive funding of 15 → equity = 85 > 80 → saved
        fundingEngine.setAccruedFunding(posId, 15e18);

        assertFalse(engine.isLiquidatable(posId), "Funding received saves position");
    }

    function test_isLiquidatable_fundingPaidPushesBelow() public {
        registry.setMarket(marketId, 0, false); // threshold = 80

        uint256 posId = posMgr.createMockPosition(
            user, marketId, true,
            5e17, 1000e18, 100e18, 10e18, WAD, 0
        );

        // PnL = -15, equity before funding = 85 > 80 → not liquidatable
        oracle.setPI(marketId, 485e15);

        assertFalse(engine.isLiquidatable(posId), "Not liquidatable before funding");

        // Pay funding of 10 → equity = 75 < 80 → liquidatable
        fundingEngine.setAccruedFunding(posId, -10e18);

        assertTrue(engine.isLiquidatable(posId), "Funding paid pushes below threshold");
    }
}
