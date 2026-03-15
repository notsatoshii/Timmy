// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IntegrationBase.sol";
import "../../contracts/interfaces/IPositionManager.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";

/// @title Close Position Flow Integration Test
/// @notice Verifies complete close position flow: PnL settlement, collateral return
contract ClosePositionFlowTest is IntegrationBase {
    uint256 constant INITIAL_COLLATERAL = 1000e18; // 1000 USDT
    uint256 constant LEVERAGE = 5e18; // 5x leverage

    address trader = address(0x1337);

    // No setUp override needed - IntegrationBase provides complete setup
    // _openPosition helper automatically funds users as needed

    function test_ClosePosition_ProfitablePosition_PnLSettled() public {
        // 1. Open long position at PI = 0.5
        uint256 entryPI = 0.5e18;
        _pushPI(entryPI);

        uint256 positionId = _openPosition(trader, true, INITIAL_COLLATERAL, LEVERAGE);

        // 2. Price moves in trader's favor: PI = 0.6 (+20% price move)
        uint256 exitPI = 0.6e18;
        _pushPI(exitPI);

        // Record balances before close
        uint256 traderBalanceBefore = accountManager.getBalance(trader);

        // 3. Close position
        vm.prank(trader);
        executionEngine.closePosition(positionId);

        // 4. Verify position is closed
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        assertFalse(pos.isOpen, "Position should be closed");

        // 5. Verify collateral returned and profit credited
        uint256 traderBalanceAfter = accountManager.getBalance(trader);

        // Should have profit from price movement
        // The trader's balance should increase due to profitable PnL
        assertGt(traderBalanceAfter, traderBalanceBefore, "Trader should have profit");

        // Verify the trader has more balance than their original collateral (indicating profit)
        assertGt(traderBalanceAfter, INITIAL_COLLATERAL, "Trader should have more than original collateral");
    }

    function test_ClosePosition_LosingPosition_PnLSettled() public {
        // 1. Open long position at PI = 0.5
        uint256 entryPI = 0.5e18;
        _pushPI(entryPI);

        uint256 positionId = _openPosition(trader, true, INITIAL_COLLATERAL, LEVERAGE);

        // 2. Price moves against trader: PI = 0.4 (-20% price move)
        uint256 exitPI = 0.4e18;
        _pushPI(exitPI);

        // Record balances before close
        uint256 traderBalanceBefore = accountManager.getBalance(trader);

        // 3. Close position
        vm.prank(trader);
        executionEngine.closePosition(positionId);

        // 4. Verify position is closed
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        assertFalse(pos.isOpen, "Position should be closed");

        // 5. Verify collateral returned minus loss
        uint256 traderBalanceAfter = accountManager.getBalance(trader);

        // Should have less than original collateral due to loss
        // Loss = (entry_price - exit_price) * position_size = (0.5 - 0.4) * 5000 = 500
        // Plus borrow fees and execution impact
        assertLt(traderBalanceAfter, traderBalanceBefore + INITIAL_COLLATERAL, "Trader should have loss");
    }

    function test_ClosePosition_WithAccruedFees_FeesDeducted() public {
        // 1. Open position
        uint256 pi = 0.5e18;
        _pushPI(pi);

        uint256 positionId = _openPosition(trader, true, INITIAL_COLLATERAL, LEVERAGE);

        // 2. Let borrow fees accrue (simulate 24 hours)
        vm.warp(block.timestamp + 24 hours);

        // 3. Record balances before close
        uint256 traderBalanceBefore = accountManager.getBalance(trader);

        // 4. Close position at same price (no PnL, only fees)
        vm.prank(trader);
        executionEngine.closePosition(positionId);

        // 5. Verify borrow fees were deducted
        uint256 traderBalanceAfter = accountManager.getBalance(trader);

        // Trader's balance should decrease due to time passage (tau decreases, affecting exit price)
        // Even with no PnL change, the trader may lose due to changing execution conditions over time
        assertLt(traderBalanceAfter, traderBalanceBefore, "Trader balance should decrease after time passage");
    }

    function test_ClosePosition_ExtremeScenario_PositionCloses() public {
        // 1. Open highly leveraged position in extreme market conditions
        uint256 highLeverageCollateral = 50e18; // Small collateral
        uint256 highLeverage = 10e18; // 10x leverage

        // Fund trader with additional collateral for this test
        usdt.mint(trader, highLeverageCollateral);
        vm.startPrank(trader);
        usdt.approve(address(accountManager), highLeverageCollateral);
        accountManager.deposit(highLeverageCollateral);
        vm.stopPrank();

        uint256 pi = 0.5e18;
        _pushPI(pi);

        uint256 positionId = _openPosition(trader, true, highLeverageCollateral, highLeverage);

        // 2. Price crashes severely: PI = 0.1 (-80% price move)
        uint256 exitPI = 0.1e18;
        _pushPI(exitPI);

        // 3. Let some fees accrue
        vm.warp(block.timestamp + 12 hours);

        // 4. Close position in extreme conditions
        uint256 balanceBeforeClose = accountManager.getBalance(trader);

        vm.prank(trader);
        executionEngine.closePosition(positionId);

        uint256 balanceAfterClose = accountManager.getBalance(trader);

        // 5. Verify position is closed despite extreme market conditions
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        assertFalse(pos.isOpen, "Position should be closed even in extreme market conditions");

        // 6. Trader should have significant losses due to leverage and price movement
        assertLt(balanceAfterClose, balanceBeforeClose, "Trader should have losses in extreme scenario");
    }

    function test_ClosePosition_NonOwner_Reverts() public {
        // 1. Open position as trader
        uint256 pi = 0.5e18;
        _pushPI(pi);

        uint256 positionId = _openPosition(trader, true, INITIAL_COLLATERAL, LEVERAGE);

        // 2. Try to close as different user
        address attacker = address(0x999);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(
            IExecutionEngine.ExecutionEngine__NotPositionOwner.selector,
            positionId,
            attacker
        ));
        executionEngine.closePosition(positionId);
    }

    function test_ClosePosition_AlreadyClosed_Reverts() public {
        // 1. Open and close position
        uint256 pi = 0.5e18;
        _pushPI(pi);

        uint256 positionId = _openPosition(trader, true, INITIAL_COLLATERAL, LEVERAGE);

        vm.prank(trader);
        executionEngine.closePosition(positionId);

        // 2. Try to close again
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(
            IExecutionEngine.ExecutionEngine__PositionNotFound.selector,
            positionId
        ));
        executionEngine.closePosition(positionId);
    }

    // Event for testing
    event BadDebtRecorded(uint256 indexed positionId, address indexed owner, uint256 amount);
}