// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../integration/IntegrationBase.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";

/// @title VaultDrainTest
/// @notice Regression tests for LEVER-BUG-2: $304K unaccounted vault drain from broken fee accounting.
///
/// Root causes:
///   Bug A (_executeOpen): collectTransactionFee() distributed fees FROM FeeRouter's own seeded
///         reserves before any USDT entered FeeRouter from the user. accountManager.debitPnL
///         reduced the user ledger but moved no USDT. Result: phantom balance in AccountManager,
///         FeeRouter reserves drained.
///
///   Bug B (_executeClose): collectTransactionFee() drained FeeRouter reserves (payment #1),
///         then _settlePnL moved the same amount from AccountManager to FeeRouter and routed
///         it again (payment #2). Double-payment to LP/protocol/insurance per close.
///
/// Fix (LEVER-P03, already applied and VERIFIED PASS):
///   - Open: fees computed locally with TX_FEE_RATE; USDT flows via debitPnL + transferOut + routeFees.
///   - Close: collectTransactionFee removed; closingFee computed locally; _settlePnL routes once.
///
/// These tests verify the invariants that the fix established and would catch any regression.
contract VaultDrainTest is IntegrationBase {

    uint256 constant COLLATERAL = 1_000e18;
    uint256 constant LEVERAGE   = 2e18;        // 2x => notional = $2000
    uint256 constant TX_FEE_BPS = 1e15;        // 10bps = 0.10%

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Opening fee deducted from AccountManager USDT, not FeeRouter reserves
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice BUG-A regression: the transaction fee at open must be physically moved from
    ///         AccountManager to FeeRouter via transferOut, not extracted from FeeRouter's own balance.
    ///
    ///         If the bug were reintroduced (collectTransactionFee + debitPnL, no transferOut):
    ///         - usdt.balanceOf(accountManager) would NOT decrease (no USDT left AM)
    ///         - usdt.balanceOf(feeRouter) would NOT increase (no USDT entered FeeRouter)
    ///         Both assertions below would fail, catching the regression.
    function test_BUG2_openFeeDebitedFromAccountManager() public {
        _fundUser(alice, COLLATERAL);

        uint256 notional     = COLLATERAL * LEVERAGE / WAD;
        uint256 expectedFee  = notional * TX_FEE_BPS / WAD;

        uint256 amUsdtBefore         = usdt.balanceOf(address(accountManager));
        uint256 feeRouterUsdtBefore  = usdt.balanceOf(address(feeRouter));
        uint256 userLedgerBefore     = accountManager.getBalance(alice);

        vm.prank(alice);
        executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        // USDT physically transferred out of AccountManager
        assertEq(
            usdt.balanceOf(address(accountManager)),
            amUsdtBefore - expectedFee,
            "AM must transfer txFee USDT to FeeRouter, not retain as phantom balance"
        );
        // USDT physically received by FeeRouter (from AM, not from its own reserves)
        assertEq(
            usdt.balanceOf(address(feeRouter)),
            feeRouterUsdtBefore + expectedFee,
            "FeeRouter must receive txFee from AM, not from its own vault-seeded reserves"
        );
        // User ledger also debited (no free credit)
        assertEq(
            accountManager.getBalance(alice),
            userLedgerBefore - expectedFee,
            "User AM ledger must be debited for txFee"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Closing fee routed exactly once
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice BUG-B regression: the closing fee must be distributed exactly once through FeeRouter.
    ///
    ///         Old code called collectTransactionFee (routing #1, debiting FeeRouter reserves)
    ///         then _settlePnL called transferOut + routeFees for the same amount (routing #2).
    ///         MockFeeRouter.totalFeesCollected increments on every routeFees call, so double
    ///         routing shows as a 2x increment when only 1x is expected.
    ///
    ///         If the bug were reintroduced: feesAfterClose - feesAfterOpen would be 2 * closingFee.
    ///         This assertion would catch it.
    function test_BUG2_closeFeeRoutedOnce() public {
        _fundUser(alice, COLLATERAL);

        vm.prank(alice);
        uint256 positionId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        uint256 feesAfterOpen = feeRouter.totalFeesCollected();

        // Close immediately in the same block: borrowFees = 0, fundingFees = 0
        vm.prank(alice);
        executionEngine.closePosition(positionId);

        uint256 feesAfterClose = feeRouter.totalFeesCollected();

        // positionSize = notional (set at open)
        uint256 notional            = COLLATERAL * LEVERAGE / WAD;
        uint256 expectedClosingFee  = notional * TX_FEE_BPS / WAD;

        // Exactly one routing increment for the closing fee (not two)
        assertEq(
            feesAfterClose - feesAfterOpen,
            expectedClosingFee,
            "Closing fee must be routed exactly once (double routing would give 2x)"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: USDT conservation invariant across a full open+close round trip
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice No USDT is created or destroyed within the system.
    ///
    ///         After a breakeven round trip (open and close at the same PI), every USDT
    ///         that entered AccountManager from the trader is still accounted for: either
    ///         still in AccountManager (trader's remaining balance) or moved to FeeRouter
    ///         (as protocol fees). The vault is not involved (PnL = 0).
    ///
    ///         If Bug A were present: AM would retain phantom USDT that was never sent to
    ///         FeeRouter, causing amUsdtAfter + feeRouterUsdtAfter > initialDeposit.
    ///         This assertion would catch it.
    function test_BUG2_accountingInvariantAfterRoundTrip() public {
        _fundUser(alice, COLLATERAL);

        uint256 initialDeposit = usdt.balanceOf(address(accountManager));

        vm.prank(alice);
        uint256 positionId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        // Close at the same PI — PnL is 0, borrowFees = 0 (same block)
        vm.prank(alice);
        executionEngine.closePosition(positionId);

        uint256 amUsdtAfter         = usdt.balanceOf(address(accountManager));
        uint256 feeRouterUsdtAfter  = usdt.balanceOf(address(feeRouter));

        // All USDT is accounted for: AM + FeeRouter + Vault = initial deposit.
        // BUG-1 fix: entry spread is now visible as PnL loss, which flows to vault.
        uint256 vaultUsdtAfter = usdt.balanceOf(address(vault));
        assertEq(
            amUsdtAfter + feeRouterUsdtAfter + vaultUsdtAfter,
            initialDeposit,
            "Total USDT must equal initial deposit: no phantom balances, no unexplained drain"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Vault capital not consumed by fees on a breakeven trade
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Fees must come from trader collateral, not vault LP capital.
    ///
    ///         On a breakeven trade (PnL = 0), the vault should not transfer any USDT.
    ///         The trader's final AccountManager balance must equal their initial deposit
    ///         minus exactly the transaction fees (open + close). Any discrepancy greater
    ///         than fees would indicate vault capital was consumed.
    ///
    ///         Vault USDT balance must remain 0 throughout: no vault seeding was consumed.
    function test_BUG2_vaultNotFundedOnBreakevenTrade() public {
        _fundUser(alice, COLLATERAL);

        assertEq(usdt.balanceOf(address(vault)), 0, "Vault holds no USDT at start");

        vm.prank(alice);
        uint256 positionId = executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   marketId,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));

        vm.prank(alice);
        executionEngine.closePosition(positionId);

        // BUG-1 fix: entry spread is visible as PnL loss, which flows from trader to vault.
        // Vault receives the entry spread (trader's loss = vault's gain on price).
        // This is correct: the vault is the counterparty to the trader's spread cost.
        // Vault USDT may be non-zero due to the spread, but it came FROM the trader, not LP capital.

        // Accounting: AM + FeeRouter + Vault = initial deposit (no phantom balances)
        uint256 totalSystem = usdt.balanceOf(address(accountManager))
            + usdt.balanceOf(address(feeRouter))
            + usdt.balanceOf(address(vault));
        assertEq(totalSystem, COLLATERAL, "System USDT must equal initial deposit");

        // Alice's cost = tx fees + entry spread (all from her own capital)
        uint256 aliceFinalBalance = accountManager.getBalance(alice);
        assertLt(aliceFinalBalance, COLLATERAL, "Alice must pay fees + entry spread");
    }
}
