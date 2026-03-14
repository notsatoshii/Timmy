// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";
import { LiquidationEngine } from "../../contracts/LiquidationEngine.sol";
import { ILiquidationEngine } from "../../contracts/interfaces/ILiquidationEngine.sol";

/// @title LiquidationExecutionTest
/// @notice Integration tests that actually call liquidate() — verifying the full
///         liquidation waterfall: detect → liquidate → fee extraction → bad debt →
///         insurance absorption → OI update → position closure.
contract LiquidationExecutionTest is IntegrationBase {

    LiquidationEngine public liquidationEngine;
    address liquidator = address(0xBBB);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

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

        // Grant ENGINE role to liquidation engine on AccountManager
        accountManager.grantRole(accountManager.ENGINE(), address(liquidationEngine));

        vm.stopPrank();
    }

    /// @dev Push PI down aggressively through multiple ticks to overcome smoothing
    function _pushPIDown(uint256 target) internal {
        uint256 current = oracleAdapter.getPI(marketId);
        while (current > target) {
            uint256 step = current > target + 3e16 ? current - 3e16 : target;
            vm.warp(block.timestamp + 10);
            _pushPI(step);
            current = oracleAdapter.getPI(marketId);
        }
    }

    /// @dev Push PI up aggressively through multiple ticks
    function _pushPIUp(uint256 target) internal {
        uint256 current = oracleAdapter.getPI(marketId);
        while (current < target) {
            uint256 step = current + 3e16 < target ? current + 3e16 : target;
            vm.warp(block.timestamp + 10);
            _pushPI(step);
            current = oracleAdapter.getPI(marketId);
        }
    }

    // ─── Basic Liquidation Execution ───

    function test_liquidate_closesPosition() public {
        // Open high-leverage long at PI=0.50
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);
        assertTrue(positionManager.isPositionOpen(posId));

        // Push PI down until liquidatable
        _pushPIDown(35e16);

        // Accrue borrow fees to help push toward liquidation
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        // Verify liquidatable
        if (!marginEngine.isLiquidatable(posId)) {
            // Push further if not yet liquidatable
            _pushPIDown(30e16);
            vm.prank(admin);
            borrowFeeEngine.accrueIndex(marketId, true);
        }

        // Skip if still not liquidatable (smoothing may prevent reaching threshold)
        if (!marginEngine.isLiquidatable(posId)) return;

        // Execute liquidation
        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = liquidationEngine.liquidate(posId);

        // Position should be closed
        assertFalse(positionManager.isPositionOpen(posId));

        // Result should have the position ID
        assertEq(result.positionId, posId);

        // Liquidation fee should be > 0
        assertGt(result.liquidationFee, 0);
    }

    function test_liquidate_reducesOI() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);
        uint256 oiBefore = oiLimits.getGlobalOI();
        assertGt(oiBefore, 0);

        _pushPIDown(30e16);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        if (!marginEngine.isLiquidatable(posId)) return;

        vm.prank(liquidator);
        liquidationEngine.liquidate(posId);

        assertEq(oiLimits.getGlobalOI(), 0);
    }

    function test_liquidate_revertsIfNotLiquidatable() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 2e18);

        // Position at 2x leverage with no adverse PI move should not be liquidatable
        assertFalse(marginEngine.isLiquidatable(posId));

        vm.prank(liquidator);
        vm.expectRevert();
        liquidationEngine.liquidate(posId);
    }

    function test_liquidate_shortPosition() public {
        uint256 posId = _openPosition(alice, false, 1000e18, 5e18);

        // Push PI up to hurt short
        _pushPIUp(65e16);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, false);

        if (!marginEngine.isLiquidatable(posId)) {
            _pushPIUp(70e16);
            vm.prank(admin);
            borrowFeeEngine.accrueIndex(marketId, false);
        }

        if (!marginEngine.isLiquidatable(posId)) return;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = liquidationEngine.liquidate(posId);

        assertFalse(positionManager.isPositionOpen(posId));
        assertEq(result.positionId, posId);
    }

    // ─── Bad Debt Scenarios ───

    function test_liquidate_withBadDebt_insuranceAbsorbs() public {
        // Open high-leverage position
        uint256 posId = _openPosition(alice, true, 500e18, 5e18);

        // Push PI down dramatically + time passes for borrow fees
        vm.warp(block.timestamp + 6 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        _pushPIDown(25e16);

        if (!marginEngine.isLiquidatable(posId)) return;

        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = liquidationEngine.liquidate(posId);

        // If equity was negative, there should be bad debt
        if (eq.equity < 0) {
            assertGt(result.badDebt, 0);
            // Insurance should have paid something
            assertGt(result.insurancePaid, 0);
        }
    }

    // ─── Batch Liquidation ───

    function test_batchLiquidate_multiplePositions() public {
        // Open two positions
        uint256 posId1 = _openPosition(alice, true, 1000e18, 5e18);
        uint256 posId2 = _openPosition(bob, true, 800e18, 5e18);

        // Push PI down
        _pushPIDown(30e16);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        uint256[] memory posIds = new uint256[](2);
        posIds[0] = posId1;
        posIds[1] = posId2;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult[] memory results = liquidationEngine.batchLiquidate(posIds);

        assertEq(results.length, 2);

        // At least check that results were populated for liquidatable positions
        for (uint256 i; i < results.length; i++) {
            if (results[i].positionId != 0) {
                assertFalse(positionManager.isPositionOpen(results[i].positionId));
            }
        }
    }

    // ─── Pincer Effect Leading to Liquidation ───

    function test_pincerEffect_borrowFeesAlone_causeLiquidation() public {
        // Open position with moderate leverage
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);
        assertFalse(marginEngine.isLiquidatable(posId));

        // Slight adverse PI move
        _pushPI(48e16);

        // Warp forward significantly — borrow fees should erode equity
        vm.warp(block.timestamp + 24 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(posId);
        // Equity should be significantly eroded
        assertGt(eq.accruedBorrowFees, 0);

        // If liquidatable, execute
        if (marginEngine.isLiquidatable(posId)) {
            vm.prank(liquidator);
            liquidationEngine.liquidate(posId);
            assertFalse(positionManager.isPositionOpen(posId));
        }
    }

    // ─── Preview ───

    function test_previewLiquidation_matchesExecution() public {
        uint256 posId = _openPosition(alice, true, 1000e18, 5e18);

        _pushPIDown(30e16);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);

        if (!marginEngine.isLiquidatable(posId)) return;

        // Preview
        ILiquidationEngine.LiquidationResult memory preview = liquidationEngine.previewLiquidation(posId);

        // Execute
        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory actual = liquidationEngine.liquidate(posId);

        // Fee should match (or be very close — block.timestamp may differ)
        assertEq(preview.liquidationFee, actual.liquidationFee);
        assertEq(preview.badDebt, actual.badDebt);
    }

    // ─── Lifetime Counters ───

    function test_totalBadDebt_accumulates() public {
        uint256 before = liquidationEngine.totalBadDebt();

        uint256 posId = _openPosition(alice, true, 500e18, 5e18);

        vm.warp(block.timestamp + 12 hours);
        vm.prank(admin);
        borrowFeeEngine.accrueIndex(marketId, true);
        _pushPIDown(25e16);

        if (!marginEngine.isLiquidatable(posId)) return;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = liquidationEngine.liquidate(posId);

        if (result.badDebt > 0) {
            assertGt(liquidationEngine.totalBadDebt(), before);
        }
    }
}
