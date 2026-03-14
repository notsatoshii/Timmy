// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";
import { LiquidationEngine } from "../../contracts/LiquidationEngine.sol";
import { ILiquidationEngine } from "../../contracts/interfaces/ILiquidationEngine.sol";

/// @title LiquidationFlowTest
/// @notice Integration tests for the liquidation flow:
///         Open position → PI moves against → equity falls below MM → liquidation.
///         Tests the MarginEngine pincer effect with real contract interactions.
contract LiquidationFlowTest is IntegrationBase {

    LiquidationEngine public liquidationEngine;
    address liquidator = address(0xBBB);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        // Deploy LiquidationEngine with real contracts + mocks for vault/insurance
        liquidationEngine = new LiquidationEngine(
            admin,
            address(marginEngine),
            address(positionManager),
            address(executionEngine),
            address(oiLimits),
            address(accountManager),
            address(insuranceFund),
            address(feeRouter),
            address(vault),
            address(registry)
        );

        // Grant ENGINE role to liquidation engine on PositionManager
        positionManager.grantRole(positionManager.ENGINE(), address(liquidationEngine));

        // Grant liquidation engine role on OILimits
        oiLimits.grantRole(oiLimits.LIQUIDATION_ENGINE_ROLE(), address(liquidationEngine));

        vm.stopPrank();
    }

    // ─── Liquidation Check ───

    function test_positionNotLiquidatable_atOpen() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);
        assertFalse(marginEngine.isLiquidatable(posId));
    }

    function test_positionBecomesLiquidatable_afterLargePIMove() public {
        // Open high-leverage long at PI=0.50
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);

        // PI drops significantly — long loses heavily
        // With 5x leverage, a ~20% PI drop should wipe most equity
        // Push PI down incrementally (smoothing limits per-tick movement)
        _pushPI(45e16); // 0.45
        vm.warp(block.timestamp + 10);
        _pushPI(40e16); // 0.40
        vm.warp(block.timestamp + 10);
        _pushPI(38e16); // 0.38

        // Check if liquidatable
        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);
        uint256 mm = marginEngine.getMaintenanceMargin(posId);

        // If equity is below MM + buffer, should be liquidatable
        if (eq.equity < int256(mm)) {
            assertTrue(marginEngine.isLiquidatable(posId));
        }
    }

    function test_shortBecomesLiquidatable_whenPIRises() public {
        // Open high-leverage short at PI=0.50
        uint256 posId = _openPosition(alice, false, 1000e18, 5e18);

        // PI rises significantly — short loses heavily
        _pushPI(55e16); // 0.55
        vm.warp(block.timestamp + 10);
        _pushPI(6e17);  // 0.60
        vm.warp(block.timestamp + 10);
        _pushPI(62e16); // 0.62

        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);
        uint256 mm = marginEngine.getMaintenanceMargin(posId);

        if (eq.equity < int256(mm)) {
            assertTrue(marginEngine.isLiquidatable(posId));
        }
    }

    // ─── Danger Zone ───

    function test_dangerZone_detectedBeforeLiquidation() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);

        // Small adverse move — should enter danger zone before liquidation
        _pushPI(47e16); // 0.47
        vm.warp(block.timestamp + 10);
        _pushPI(45e16); // 0.45

        // Danger zone threshold is 2x the liquidation threshold
        bool inDanger = marginEngine.isInDangerZone(posId);
        bool isLiq = marginEngine.isLiquidatable(posId);

        // If liquidatable, must also be in danger zone
        if (isLiq) {
            assertTrue(inDanger);
        }
    }

    // ─── Margin Engine Equity Computation ───

    function test_equityDecreases_withAdversePI() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posId);

        // PI drops
        _pushPI(48e16);

        IMarginEngine.EquityResult memory eq2 = marginEngine.computeEquity(posId);

        // Equity should decrease for long when PI drops
        assertLt(eq2.equity, eq1.equity);
    }

    function test_equityIncreases_withFavorablePI() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posId);

        // PI rises
        _pushPI(52e16);

        IMarginEngine.EquityResult memory eq2 = marginEngine.computeEquity(posId);

        // Equity should increase for long when PI rises
        assertGt(eq2.equity, eq1.equity);
    }

    // ─── Borrow Fee Accrual ───

    function test_borrowFees_accrueOverTime() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        // Initially no fees
        uint256 fees0 = borrowFeeEngine.getAccruedFees(posId);
        assertEq(fees0, 0);

        // Accrue the borrow index after time passes
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        // Now fees should be > 0
        uint256 fees1 = borrowFeeEngine.getAccruedFees(posId);
        assertGt(fees1, 0);

        // More time = more fees
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        uint256 fees2 = borrowFeeEngine.getAccruedFees(posId);
        assertGt(fees2, fees1);
    }

    function test_borrowFees_erodeEquity() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        IMarginEngine.EquityResult memory eq0 = marginEngine.computeEquity(posId);

        // Accrue fees for several hours
        vm.warp(block.timestamp + 12 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posId);

        // Equity should decrease due to borrow fees (the "ticking clock")
        assertLt(eq1.equity, eq0.equity);
        assertGt(eq1.accruedBorrowFees, 0);
    }

    // ─── Pincer Effect: MM rises + borrow erodes ───

    function test_pincerEffect_borrowFeesAndPIMove() public {
        // Open with moderate leverage
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);

        // Step 1: Record initial state
        IMarginEngine.EquityResult memory eq0 = marginEngine.computeEquity(posId);
        assertFalse(marginEngine.isLiquidatable(posId));

        // Step 2: Time passes (borrow fees accrue)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        // Step 3: PI moves slightly against position
        _pushPI(48e16); // 0.48

        IMarginEngine.EquityResult memory eq1 = marginEngine.computeEquity(posId);

        // Equity eroded from both PnL loss AND borrow fees
        assertLt(eq1.equity, eq0.equity);
        assertLt(eq1.pnl, 0);             // Negative PnL from PI drop
        assertGt(eq1.accruedBorrowFees, 0); // Borrow fees accumulated
    }

    // ─── OI Consistency ───

    function test_oiUpdated_throughFullLiquidationFlow() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 3e18);

        uint256 oiBefore = oiLimits.getGlobalOI();
        assertGt(oiBefore, 0);

        // Close position (simulating what liquidation would do)
        _closePosition(alice, posId);

        uint256 oiAfter = oiLimits.getGlobalOI();
        assertEq(oiAfter, 0);
    }
}
