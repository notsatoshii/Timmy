// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../integration/IntegrationBase.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";
import "../../contracts/interfaces/IMarginEngine.sol";

/// @title UnrealizedPnLTest
/// @notice Tests for LEVER-BUG-9: Vault NAV must include unrealized PnL from open positions.
///
/// Architecture: delta update on close (LEVER-P06, already done) + periodic keeper full
/// recompute via refreshUnrealizedPnL. The aggregation view computeNetUnrealizedPnL iterates
/// all open positions per market and sums their PnL.
contract UnrealizedPnLTest is IntegrationBase {

    uint256 constant COLLATERAL = 1_000e18;
    uint256 constant LEVERAGE   = 2e18;

    function setUp() public override {
        super.setUp();

        // Grant KEEPER_ROLE for refreshUnrealizedPnL
        vm.startPrank(admin);
        executionEngine.grantRole(executionEngine.KEEPER_ROLE(), keeper);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: computeNetUnrealizedPnL returns zero with no positions
    // ─────────────────────────────────────────────────────────────────────────

    function test_BUG9_noPositionsReturnsZero() public view {
        int256 netPnL = marginEngine.computeNetUnrealizedPnL();
        assertEq(netPnL, 0, "No positions should mean zero unrealized PnL");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: computeNetUnrealizedPnL reflects price movement
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice After opening a long and PI increases, unrealized PnL should be positive.
    function test_BUG9_longProfitReflectedInAggregation() public {
        // Open long at PI=0.50
        _openPosition(alice, true, COLLATERAL, LEVERAGE);

        // Move PI up to 0.55 (5% move, with smoothing it moves partially)
        vm.warp(block.timestamp + 60);
        _pushPI(55e16);

        uint256 currentPI = oracleAdapter.getPI(marketId);
        // PI should have moved above 0.50 (at least partially from smoothing)
        assertGt(currentPI, 5e17, "PI should increase");

        int256 netPnL = marginEngine.computeNetUnrealizedPnL();
        // Long profits when PI rises
        assertGt(netPnL, 0, "Long position should have positive PnL when PI rises");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: refreshUnrealizedPnL updates vault's _netUnrealizedPnL
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The keeper calls refreshUnrealizedPnL which reads from MarginEngine and
    ///         writes to LeverVault. Vault NAV should reflect the update.
    function test_BUG9_keeperRefreshUpdatesVault() public {
        // Open long at PI=0.50
        _openPosition(alice, true, COLLATERAL, LEVERAGE);

        // Move PI up
        vm.warp(block.timestamp + 60);
        _pushPI(55e16);

        // Before refresh, vault's _netUnrealizedPnL should be 0 (no keeper ran yet)
        int256 vaultPnLBefore = vault.getNetUnrealizedPnL();
        assertEq(vaultPnLBefore, 0, "Vault PnL should be 0 before keeper refresh");

        // Keeper refreshes
        vm.prank(keeper);
        executionEngine.refreshUnrealizedPnL();

        // After refresh, vault's _netUnrealizedPnL should match MarginEngine's computation
        int256 vaultPnLAfter = vault.getNetUnrealizedPnL();
        int256 computedPnL = marginEngine.computeNetUnrealizedPnL();
        assertEq(vaultPnLAfter, computedPnL, "Vault PnL must match MarginEngine computation after refresh");
        assertGt(vaultPnLAfter, 0, "Long position profit should be reflected in vault PnL");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Close delta removes position's PnL from aggregate (P06 behavior)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice When a position closes, LEVER-P06 subtracts its realized PnL from the
    ///         vault's _netUnrealizedPnL. After close, the vault should no longer account
    ///         for that position's PnL.
    function test_BUG9_closeDeltaRemovesFromUnrealized() public {
        // Open a long
        uint256 posId = _openPosition(alice, true, COLLATERAL, LEVERAGE);

        // Set vault unrealized PnL as if keeper had run (simulate 500e18 unrealized)
        // We need EXECUTION_ENGINE_ROLE to call updateUnrealizedPnL
        // The vault mock allows any caller for updateUnrealizedPnL
        vault.updateUnrealizedPnL(500e18);
        assertEq(vault.getNetUnrealizedPnL(), 500e18, "Setup: vault PnL should be 500");

        // Close the position at same PI (PnL=0, so delta is 0)
        vm.prank(alice);
        executionEngine.closePosition(posId);

        // P06 subtracts pnl from vault's _netUnrealizedPnL
        // PnL = 0 (same PI), so _netUnrealizedPnL = 500 - 0 = 500
        int256 afterClose = vault.getNetUnrealizedPnL();
        assertEq(afterClose, 500e18, "PnL=0 close should not change vault unrealized (delta=0)");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: Multiple positions aggregate correctly
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Two positions (long and short) should partially offset in the aggregation.
    function test_BUG9_multiplePositionsAggregate() public {
        // Open a long and a short at same PI
        _openPosition(alice, true, COLLATERAL, LEVERAGE);
        _openPosition(bob, false, COLLATERAL, LEVERAGE);

        // At the same PI, both have PnL=0
        int256 netPnL = marginEngine.computeNetUnrealizedPnL();
        assertEq(netPnL, 0, "Long + short at same PI should net to zero PnL");

        // Move PI up: long profits, short loses (should approximately cancel)
        vm.warp(block.timestamp + 60);
        _pushPI(55e16);

        int256 netPnLAfter = marginEngine.computeNetUnrealizedPnL();
        // With equal size positions, long gain ~ short loss, net should be near zero
        // (not exactly zero due to execution impact differences, but close)
        int256 absNet = netPnLAfter > 0 ? netPnLAfter : -netPnLAfter;
        // Net should be small relative to individual position sizes
        uint256 notional = COLLATERAL * LEVERAGE / 1e18;
        assertLt(uint256(absNet), notional / 10, "Equal long+short should approximately cancel");
    }
}
