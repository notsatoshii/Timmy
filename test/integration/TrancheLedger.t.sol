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

/// @dev Simple ERC20 for tests
contract TrancheTestToken is ERC20 {
    constructor() ERC20("Test USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title TrancheLedgerTest
/// @notice Integration tests for the tranche ledger system:
///         Multiple deposits create separate tranches, transfers use proportional split,
///         consolidation fires when exceeding MAX_TRANCHES, yield tracking per tranche.
contract TrancheLedgerTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xA2);

    TrancheTestToken public usdt;
    LeverVault public vault;
    RewardsDistributor public distributor;

    function setUp() public {
        vm.startPrank(admin);

        usdt = new TrancheTestToken();

        // Predict vault address so distributor can reference it at construction
        uint64 nonce = vm.getNonce(admin);
        address predictedVault = vm.computeCreateAddress(admin, nonce + 1);

        distributor = new RewardsDistributor(admin, address(usdt), predictedVault);
        vault = new LeverVault(admin, address(usdt), address(distributor));
        require(address(vault) == predictedVault, "vault address mismatch");

        distributor.grantRole(distributor.LEVER_VAULT_ROLE(), address(vault));

        vm.stopPrank();

        // Fund users
        usdt.mint(alice, 1_000_000e18);
        usdt.mint(bob, 1_000_000e18);

        vm.prank(alice);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(vault), type(uint256).max);
    }

    // ─── Single Deposit Creates One Tranche ───

    function test_singleDeposit_createsSingleTranche() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 1);
        assertEq(tranches[0].shares, vault.balanceOf(alice));
    }

    // ─── Multiple Deposits Create Multiple Tranches ───

    function test_multipleDeposits_createSeparateTranches() public {
        vm.startPrank(alice);
        vault.deposit(5_000e18, alice);
        vault.deposit(3_000e18, alice);
        vault.deposit(2_000e18, alice);
        vm.stopPrank();

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 3);

        // Total tranche shares should equal balance
        uint256 totalTrancheShares;
        for (uint256 i; i < tranches.length; ++i) {
            totalTrancheShares += tranches[i].shares;
        }
        assertEq(totalTrancheShares, vault.balanceOf(alice));
    }

    // ─── Tranche Consolidation at Max (10) ───

    function test_consolidation_firesAt11thTranche() public {
        vm.startPrank(alice);

        // Make 10 deposits → 10 tranches
        for (uint256 i; i < 10; ++i) {
            vault.deposit(1_000e18, alice);
        }

        ILeverVault.Tranche[] memory tranchesBefore = vault.getTranches(alice);
        assertEq(tranchesBefore.length, 10);

        // 11th deposit → should trigger consolidation
        vault.deposit(1_000e18, alice);

        ILeverVault.Tranche[] memory tranchesAfter = vault.getTranches(alice);
        assertEq(tranchesAfter.length, 10); // Back to 10 after consolidation

        vm.stopPrank();

        // Total shares should still be correct
        uint256 totalTrancheShares;
        for (uint256 i; i < tranchesAfter.length; ++i) {
            totalTrancheShares += tranchesAfter[i].shares;
        }
        assertEq(totalTrancheShares, vault.balanceOf(alice));
    }

    // ─── Transfer: Proportional Split ───

    function test_transfer_proportionalSplit() public {
        // Alice makes two deposits at different times
        vm.prank(alice);
        vault.deposit(6_000e18, alice);
        vm.prank(alice);
        vault.deposit(4_000e18, alice);

        uint256 aliceBalance = vault.balanceOf(alice);
        uint256 halfBalance = aliceBalance / 2;

        // Transfer half to bob
        vm.prank(alice);
        vault.transfer(bob, halfBalance);

        // Alice should have 2 tranches with ~half their original shares
        ILeverVault.Tranche[] memory aliceTranches = vault.getTranches(alice);
        assertGt(aliceTranches.length, 0);

        // Bob should have received tranches from alice (proportional from each)
        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);
        assertGt(bobTranches.length, 0);

        // Verify total shares consistency
        uint256 aliceTrancheShares;
        for (uint256 i; i < aliceTranches.length; ++i) {
            aliceTrancheShares += aliceTranches[i].shares;
        }
        uint256 bobTrancheShares;
        for (uint256 i; i < bobTranches.length; ++i) {
            bobTrancheShares += bobTranches[i].shares;
        }

        assertEq(aliceTrancheShares, vault.balanceOf(alice));
        assertEq(bobTrancheShares, vault.balanceOf(bob));
    }

    function test_transfer_preservesRewardSnapshots() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        ILeverVault.Tranche[] memory aliceTranchesBefore = vault.getTranches(alice);
        uint128 originalSnapshot = aliceTranchesBefore[0].rewardSnapshot;

        // Transfer half to bob
        uint256 half = vault.balanceOf(alice) / 2;
        vm.prank(alice);
        vault.transfer(bob, half);

        // Bob's tranche should carry the same reward snapshot as alice's original
        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);
        assertEq(bobTranches[0].rewardSnapshot, originalSnapshot);
    }

    // ─── Transfer: Receiver Consolidation ───

    function test_transfer_triggersReceiverConsolidation() public {
        // Bob already has 9 tranches
        vm.startPrank(bob);
        for (uint256 i; i < 9; ++i) {
            vault.deposit(500e18, bob);
        }
        vm.stopPrank();

        ILeverVault.Tranche[] memory bobBefore = vault.getTranches(bob);
        assertEq(bobBefore.length, 9);

        // Alice deposits and creates 3 tranches
        vm.startPrank(alice);
        vault.deposit(3_000e18, alice);
        vault.deposit(3_000e18, alice);
        vault.deposit(3_000e18, alice);
        vm.stopPrank();

        // Transfer from alice to bob — should add tranches to bob and consolidate
        uint256 aliceHalf = vault.balanceOf(alice) / 2;
        vm.prank(alice);
        vault.transfer(bob, aliceHalf);

        ILeverVault.Tranche[] memory bobAfter = vault.getTranches(bob);
        assertLe(bobAfter.length, 10); // Should never exceed max

        // Shares still consistent
        uint256 totalBobShares;
        for (uint256 i; i < bobAfter.length; ++i) {
            totalBobShares += bobAfter[i].shares;
        }
        assertEq(totalBobShares, vault.balanceOf(bob));
    }

    // ─── Full Transfer ───

    function test_fullTransfer_movesAllTranches() public {
        vm.startPrank(alice);
        vault.deposit(5_000e18, alice);
        vault.deposit(5_000e18, alice);
        vm.stopPrank();

        uint256 aliceBalance = vault.balanceOf(alice);

        vm.prank(alice);
        vault.transfer(bob, aliceBalance);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), aliceBalance);

        // Alice should have no tranches (or empty ones cleaned up)
        ILeverVault.Tranche[] memory aliceTranches = vault.getTranches(alice);
        uint256 aliceTrancheShares;
        for (uint256 i; i < aliceTranches.length; ++i) {
            aliceTrancheShares += aliceTranches[i].shares;
        }
        assertEq(aliceTrancheShares, 0);

        // Bob should have all the shares across tranches
        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);
        uint256 bobTrancheShares;
        for (uint256 i; i < bobTranches.length; ++i) {
            bobTrancheShares += bobTranches[i].shares;
        }
        assertEq(bobTrancheShares, aliceBalance);
    }

    // ─── Consolidation: Weighted Average Snapshot ───

    function test_consolidation_mergesOldest_weightedAverage() public {
        // We need to create deposits at different reward index levels
        // to verify the weighted average snapshot on consolidation

        // Fund distributor so it can increase reward index
        usdt.mint(address(distributor), 1_000_000e18);
        bytes32 feeRouterRole = distributor.FEE_ROUTER_ROLE();
        vm.prank(admin);
        distributor.grantRole(feeRouterRole, admin);

        vm.startPrank(alice);

        // First deposit
        vault.deposit(1_000e18, alice);
        vm.stopPrank();

        // Increase reward index
        vm.prank(admin);
        distributor.depositRewards(100e18);

        // More deposits to fill up tranches
        vm.startPrank(alice);
        for (uint256 i; i < 9; ++i) {
            vault.deposit(1_000e18, alice);
        }

        ILeverVault.Tranche[] memory tranchesBefore = vault.getTranches(alice);
        assertEq(tranchesBefore.length, 10);

        // Record first two tranches for verification
        uint128 shares0 = tranchesBefore[0].shares;
        uint128 snap0 = tranchesBefore[0].rewardSnapshot;
        uint128 shares1 = tranchesBefore[1].shares;
        uint128 snap1 = tranchesBefore[1].rewardSnapshot;

        // 11th deposit triggers consolidation of oldest two
        vault.deposit(1_000e18, alice);
        vm.stopPrank();

        ILeverVault.Tranche[] memory tranchesAfter = vault.getTranches(alice);
        assertEq(tranchesAfter.length, 10);

        // First tranche should be the merged result
        uint128 mergedShares = tranchesAfter[0].shares;
        assertEq(mergedShares, shares0 + shares1);

        // Merged snapshot should be weighted average
        uint128 expectedSnapshot = uint128(
            (uint256(shares0) * uint256(snap0) + uint256(shares1) * uint256(snap1))
                / uint256(mergedShares)
        );
        assertEq(tranchesAfter[0].rewardSnapshot, expectedSnapshot);
    }

    // ─── Withdrawal Removes Tranches Proportionally ───

    function test_withdrawal_removesTranchesProportionally() public {
        vm.startPrank(alice);
        vault.deposit(6_000e18, alice);
        vault.deposit(4_000e18, alice);
        vm.stopPrank();

        uint256 totalShares = vault.balanceOf(alice);
        uint256 halfShares = totalShares / 2;

        // Request and execute withdrawal for half
        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(halfShares);
        vm.warp(block.timestamp + 48 hours + 1);
        vm.prank(alice);
        vault.executeWithdrawal(receiptId);

        // Remaining tranches should sum to remaining shares
        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        uint256 remainingTrancheShares;
        for (uint256 i; i < tranches.length; ++i) {
            remainingTrancheShares += tranches[i].shares;
        }
        assertEq(remainingTrancheShares, vault.balanceOf(alice));
    }
}
