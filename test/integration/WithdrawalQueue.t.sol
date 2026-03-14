// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { LeverVault } from "../../contracts/LeverVault.sol";
import { RewardsDistributor } from "../../contracts/RewardsDistributor.sol";
import { ILeverVault } from "../../contracts/interfaces/ILeverVault.sol";
import { IRewardsDistributor } from "../../contracts/interfaces/IRewardsDistributor.sol";
import { FixedPointMath } from "../../contracts/libraries/FixedPointMath.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple ERC20 for vault tests
contract VaultTestToken is ERC20 {
    constructor() ERC20("Test USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title WithdrawalQueueTest
/// @notice Integration tests for the LeverVault withdrawal queue:
///         Request → 48h wait → execute at current NAV. FIFO ordering.
///         Cancellable with 24h re-request cooldown. Edge cases around timing,
///         multiple requests, and cancel→re-request flow.
contract WithdrawalQueueTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xA2);
    address charlie = address(0xA3);

    VaultTestToken public usdt;
    LeverVault public vault;
    RewardsDistributor public distributor;

    function setUp() public {
        vm.startPrank(admin);

        usdt = new VaultTestToken();

        // Deploy distributor first with admin as placeholder vault
        distributor = new RewardsDistributor(admin, address(usdt), admin);

        // Deploy vault with real distributor
        vault = new LeverVault(admin, address(usdt), address(distributor));

        // Grant roles
        distributor.grantRole(distributor.LEVER_VAULT_ROLE(), address(vault));

        vm.stopPrank();

        // Fund users with USDT
        usdt.mint(alice, 100_000e18);
        usdt.mint(bob, 100_000e18);
        usdt.mint(charlie, 100_000e18);

        // Approve vault
        vm.prank(alice);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        usdt.approve(address(vault), type(uint256).max);
    }

    // ─── Deposit + Request ───

    function test_deposit_mintsShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e18, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_requestWithdrawal_locksShares() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(sharesBefore);

        // Shares still belong to alice (not burned yet)
        assertEq(vault.balanceOf(alice), sharesBefore);

        // Receipt created
        ILeverVault.WithdrawalReceipt memory receipt = vault.getReceipt(receiptId);
        assertEq(receipt.owner, alice);
        assertEq(receipt.shares, sharesBefore);
        assertFalse(receipt.executed);
        assertFalse(receipt.cancelled);
    }

    function test_requestWithdrawal_cannotTransferQueuedShares() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdrawal(shares);

        // Trying to transfer should revert (shares locked in queue)
        vm.expectRevert();
        vm.prank(alice);
        vault.transfer(bob, shares);
    }

    function test_requestWithdrawal_partialLock() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 halfShares = shares / 2;

        vm.prank(alice);
        vault.requestWithdrawal(halfShares);

        // Can still transfer the non-queued half
        vm.prank(alice);
        vault.transfer(bob, shares - halfShares);

        assertEq(vault.balanceOf(bob), shares - halfShares);
    }

    // ─── Cooldown Enforcement ───

    function test_executeWithdrawal_reverts_beforeCooldown() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        // Try to execute immediately — should revert
        vm.expectRevert();
        vm.prank(alice);
        vault.executeWithdrawal(receiptId);
    }

    function test_executeWithdrawal_succeeds_afterCooldown() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        // Warp past 48h cooldown
        vm.warp(block.timestamp + 48 hours + 1);

        vm.prank(alice);
        uint256 assets = vault.executeWithdrawal(receiptId);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), 0); // Shares burned

        ILeverVault.WithdrawalReceipt memory receipt = vault.getReceipt(receiptId);
        assertTrue(receipt.executed);
    }

    function test_executeWithdrawal_atCurrentNAV() public {
        // Alice and Bob both deposit
        vm.prank(alice);
        vault.deposit(10_000e18, alice);
        vm.prank(bob);
        vault.deposit(10_000e18, bob);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice requests withdrawal
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(aliceShares);

        // Warp past cooldown
        vm.warp(block.timestamp + 48 hours + 1);

        // Execute — should get assets at current NAV
        vm.prank(alice);
        uint256 assets = vault.executeWithdrawal(receiptId);

        // Alice deposited 10k, NAV hasn't changed, should get ~10k back
        assertApproxEqRel(assets, 10_000e18, 1e16); // Within 1%
    }

    // ─── Cancel + Cooldown ───

    function test_cancelWithdrawal_unlocksShares() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        // Cancel
        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        ILeverVault.WithdrawalReceipt memory receipt = vault.getReceipt(receiptId);
        assertTrue(receipt.cancelled);

        // Shares should be transferable again
        vm.prank(alice);
        vault.transfer(bob, shares);
        assertEq(vault.balanceOf(bob), shares);
    }

    function test_cancelCooldown_preventsImmediateReRequest() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);

        // Request then cancel
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);
        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        // Immediately try to re-request — should revert (24h cooldown)
        vm.expectRevert();
        vm.prank(alice);
        vault.requestWithdrawal(shares);
    }

    function test_cancelCooldown_allowsReRequestAfter24h() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);
        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        // Warp past 24h cooldown
        vm.warp(block.timestamp + 24 hours + 1);

        // Should succeed
        vm.prank(alice);
        uint256 newReceiptId = vault.requestWithdrawal(shares);
        assertGt(newReceiptId, receiptId);
    }

    // ─── Multiple Requests ───

    function test_multipleRequests_sameUser() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 half = shares / 2;

        vm.startPrank(alice);
        uint256 receipt1 = vault.requestWithdrawal(half);
        uint256 receipt2 = vault.requestWithdrawal(shares - half);
        vm.stopPrank();

        assertTrue(receipt1 != receipt2);

        // Total queued should match full balance
        assertEq(vault.totalQueuedShares(), shares);
    }

    function test_multipleUsers_withdrawalQueue() public {
        // Three users deposit
        vm.prank(alice);
        vault.deposit(10_000e18, alice);
        vm.prank(bob);
        vault.deposit(5_000e18, bob);
        vm.prank(charlie);
        vault.deposit(3_000e18, charlie);

        // Store balances before pranking (avoid prank consumed by balanceOf)
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);
        uint256 charlieShares = vault.balanceOf(charlie);

        // All request withdrawals
        vm.prank(alice);
        uint256 r1 = vault.requestWithdrawal(aliceShares);
        vm.prank(bob);
        uint256 r2 = vault.requestWithdrawal(bobShares);
        vm.prank(charlie);
        uint256 r3 = vault.requestWithdrawal(charlieShares);

        // Warp past cooldown
        vm.warp(block.timestamp + 48 hours + 1);

        // All can execute (FIFO but all ready)
        vm.prank(alice);
        uint256 a1 = vault.executeWithdrawal(r1);
        vm.prank(bob);
        uint256 a2 = vault.executeWithdrawal(r2);
        vm.prank(charlie);
        uint256 a3 = vault.executeWithdrawal(r3);

        assertApproxEqRel(a1, 10_000e18, 1e16);
        assertApproxEqRel(a2, 5_000e18, 1e16);
        assertApproxEqRel(a3, 3_000e18, 1e16);
    }

    // ─── Cannot Execute Others' Withdrawals ───

    function test_cannotExecuteOthersWithdrawal() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        vm.warp(block.timestamp + 48 hours + 1);

        vm.expectRevert();
        vm.prank(bob);
        vault.executeWithdrawal(receiptId);
    }

    function test_cannotCancelOthersWithdrawal() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        vm.expectRevert();
        vm.prank(bob);
        vault.cancelWithdrawal(receiptId);
    }

    // ─── Double Execution / Cancellation ───

    function test_cannotExecuteTwice() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        vm.warp(block.timestamp + 48 hours + 1);

        vm.prank(alice);
        vault.executeWithdrawal(receiptId);

        // Second execution should revert
        vm.expectRevert();
        vm.prank(alice);
        vault.executeWithdrawal(receiptId);
    }

    function test_cannotCancelExecutedWithdrawal() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        vm.warp(block.timestamp + 48 hours + 1);

        vm.prank(alice);
        vault.executeWithdrawal(receiptId);

        vm.expectRevert();
        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);
    }

    function test_cannotExecuteCancelledWithdrawal() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(shares);

        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        vm.warp(block.timestamp + 48 hours + 1);

        vm.expectRevert();
        vm.prank(alice);
        vault.executeWithdrawal(receiptId);
    }

    // ─── Zero / Edge Cases ───

    function test_cannotRequestZeroShares() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.requestWithdrawal(0);
    }

    function test_cannotRequestMoreSharesThanFree() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        uint256 shares = vault.balanceOf(alice);

        // Queue half
        vm.prank(alice);
        vault.requestWithdrawal(shares / 2);

        // Try to queue more than remaining free shares
        vm.expectRevert();
        vm.prank(alice);
        vault.requestWithdrawal(shares); // Can't queue full amount — half already queued
    }

    // ─── NAV Changes Between Request and Execution ───

    function test_navDecrease_reducesWithdrawalPayout() public {
        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(10_000e18, alice);
        vm.prank(bob);
        vault.deposit(10_000e18, bob);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice requests withdrawal
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(aliceShares);

        // Simulate NAV decrease (socialize loss into vault)
        vm.startPrank(admin);
        vault.grantRole(vault.LIQUIDATION_ENGINE_ROLE(), admin);
        vault.socializeLoss(2_000e18); // $2k loss
        vm.stopPrank();

        // Warp past cooldown
        vm.warp(block.timestamp + 48 hours + 1);

        // Execute — should get less than deposited
        vm.prank(alice);
        uint256 assets = vault.executeWithdrawal(receiptId);

        // NAV decreased by $2k split across $20k → each share worth ~10% less
        // Alice should get roughly $9k instead of $10k
        assertLt(assets, 10_000e18);
        assertGt(assets, 8_000e18); // But not completely wiped
    }
}
