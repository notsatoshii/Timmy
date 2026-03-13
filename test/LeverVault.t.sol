// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { ILeverVault } from "../contracts/interfaces/ILeverVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockUSDT {
    string public name = "Mock USDT";
    string public symbol = "USDT";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockRewardsDistributor {
    uint256 private _rewardIndex;
    uint256 private _claimAmount;

    function setRewardIndex(uint256 idx) external {
        _rewardIndex = idx;
    }

    function setClaimAmount(uint256 amount) external {
        _claimAmount = amount;
    }

    function rewardPerShareCumulative() external view returns (uint256) {
        return _rewardIndex;
    }

    function claim() external returns (uint256) {
        return _claimAmount;
    }

    function depositRewards(uint256) external {}
    function receiveUnmatchedFunding(bytes32, uint256) external {}
    function pendingRewards(address) external view returns (uint256) { return 0; }
    function totalDistributed() external view returns (uint256) { return 0; }
    function totalUnmatchedFunding() external view returns (uint256) { return 0; }
    function totalFeeRewards() external view returns (uint256) { return 0; }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract LeverVaultTest is Test {
    LeverVault public vault;
    MockUSDT public usdt;
    MockRewardsDistributor public rewards;

    address public admin = address(0xA);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public execEngine = address(0xE);
    address public liqEngine = address(0xF);

    uint256 constant WAD = 1e18;
    uint256 constant WITHDRAWAL_COOLDOWN = 172_800;
    uint256 constant CANCEL_COOLDOWN = 86_400;

    function setUp() public {
        usdt = new MockUSDT();
        rewards = new MockRewardsDistributor();
        vault = new LeverVault(admin, address(usdt), address(rewards));

        // Grant roles
        vm.startPrank(admin);
        vault.grantRole(vault.EXECUTION_ENGINE_ROLE(), execEngine);
        vault.grantRole(vault.LIQUIDATION_ENGINE_ROLE(), liqEngine);
        vm.stopPrank();

        // Fund users
        usdt.mint(alice, 1_000_000 * WAD);
        usdt.mint(bob, 1_000_000 * WAD);
        usdt.mint(charlie, 1_000_000 * WAD);

        // Approve vault
        vm.prank(alice);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        usdt.approve(address(vault), type(uint256).max);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(vault.name(), "Lever Vault USDT");
        assertEq(vault.symbol(), "lvUSDT");
    }

    function test_constructor_setsAsset() public view {
        assertEq(vault.asset(), address(usdt));
    }

    function test_constructor_revertsZeroAdmin() public {
        vm.expectRevert(LeverVault.LeverVault__ZeroAddress.selector);
        new LeverVault(address(0), address(usdt), address(rewards));
    }

    function test_constructor_revertsZeroUsdt() public {
        vm.expectRevert(LeverVault.LeverVault__ZeroAddress.selector);
        new LeverVault(admin, address(0), address(rewards));
    }

    function test_constructor_revertsZeroRewards() public {
        vm.expectRevert(LeverVault.LeverVault__ZeroAddress.selector);
        new LeverVault(admin, address(usdt), address(0));
    }

    // ──────────────────────────────────────────────
    // Deposit
    // ──────────────────────────────────────────────

    function test_deposit_mintsShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000 * WAD, alice);

        assertEq(shares, 1000 * WAD);
        assertEq(vault.balanceOf(alice), 1000 * WAD);
        assertEq(usdt.balanceOf(address(vault)), 1000 * WAD);
    }

    function test_deposit_createsTranche() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 1);
        assertEq(tranches[0].shares, 1000 * WAD);
        assertEq(tranches[0].rewardSnapshot, 0);
    }

    function test_deposit_multipleCreatesMultipleTranches() public {
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        rewards.setRewardIndex(1e17); // 0.1 WAD
        vm.prank(alice);
        vault.deposit(500 * WAD, alice);

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 2);
        assertEq(tranches[0].shares, 1000 * WAD);
        assertEq(tranches[1].shares, 500 * WAD);
        assertEq(tranches[1].rewardSnapshot, 1e17);
    }

    function test_deposit_secondDepositorGetsProportionalShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(1000 * WAD, bob);

        assertEq(bobShares, 1000 * WAD);
        assertEq(vault.totalSupply(), 2000 * WAD);
    }

    // ──────────────────────────────────────────────
    // NAV / totalAssets
    // ──────────────────────────────────────────────

    function test_totalAssets_matchesBalance() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        assertEq(vault.totalAssets(), 1000 * WAD);
    }

    function test_totalAssets_decreasesWithPositivePnL() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        // Traders are profitable → vault owes them → NAV decreases
        vm.prank(execEngine);
        vault.updateUnrealizedPnL(int256(200 * WAD));

        assertEq(vault.totalAssets(), 800 * WAD);
    }

    function test_totalAssets_increasesWithNegativePnL() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        // Traders are losing → vault gains → NAV increases
        vm.prank(execEngine);
        vault.updateUnrealizedPnL(-int256(200 * WAD));

        assertEq(vault.totalAssets(), 1200 * WAD);
    }

    function test_totalAssets_floorsAtZero() public {
        vm.prank(alice);
        vault.deposit(100 * WAD, alice);

        vm.prank(execEngine);
        vault.updateUnrealizedPnL(int256(200 * WAD));

        assertEq(vault.totalAssets(), 0);
    }

    function test_getNAV_matchesTotalAssets() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        assertEq(vault.getNAV(), vault.totalAssets());
    }

    // ──────────────────────────────────────────────
    // socializeLoss
    // ──────────────────────────────────────────────

    function test_socializeLoss_reducesNAV() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(liqEngine);
        vault.socializeLoss(100 * WAD);

        assertEq(vault.totalAssets(), 900 * WAD);
    }

    function test_socializeLoss_revertsZeroAmount() public {
        vm.prank(liqEngine);
        vm.expectRevert(LeverVault.LeverVault__ZeroAmount.selector);
        vault.socializeLoss(0);
    }

    function test_socializeLoss_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.socializeLoss(100 * WAD);
    }

    function test_socializeLoss_cumulative() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(liqEngine);
        vault.socializeLoss(100 * WAD);
        vm.prank(liqEngine);
        vault.socializeLoss(50 * WAD);

        assertEq(vault.totalAssets(), 850 * WAD);
    }

    // ──────────────────────────────────────────────
    // updateUnrealizedPnL access control
    // ──────────────────────────────────────────────

    function test_updateUnrealizedPnL_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.updateUnrealizedPnL(100);
    }

    // ──────────────────────────────────────────────
    // Direct withdraw/redeem disabled
    // ──────────────────────────────────────────────

    function test_maxWithdraw_returnsZero() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_maxRedeem_returnsZero() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        assertEq(vault.maxRedeem(alice), 0);
    }

    // ──────────────────────────────────────────────
    // Withdrawal Queue — Request
    // ──────────────────────────────────────────────

    function test_requestWithdrawal_createsReceipt() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        assertEq(receiptId, 1);
        ILeverVault.WithdrawalReceipt memory r = vault.getReceipt(receiptId);
        assertEq(r.owner, alice);
        assertEq(r.shares, 500 * WAD);
        assertFalse(r.executed);
        assertFalse(r.cancelled);
    }

    function test_requestWithdrawal_locksShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.requestWithdrawal(600 * WAD);

        assertEq(vault.totalQueuedShares(), 600 * WAD);
    }

    function test_requestWithdrawal_revertsZeroShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vm.expectRevert(ILeverVault.LeverVault__ZeroShares.selector);
        vault.requestWithdrawal(0);
    }

    function test_requestWithdrawal_revertsExceedsFreeShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.requestWithdrawal(800 * WAD);

        // Try to queue more than remaining free shares (200 WAD)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILeverVault.LeverVault__SharesInQueue.selector, 300 * WAD));
        vault.requestWithdrawal(300 * WAD);
    }

    function test_requestWithdrawal_multipleReceipts() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 id1 = vault.requestWithdrawal(300 * WAD);
        vm.prank(alice);
        uint256 id2 = vault.requestWithdrawal(200 * WAD);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(vault.totalQueuedShares(), 500 * WAD);
    }

    // ──────────────────────────────────────────────
    // Withdrawal Queue — Execute
    // ──────────────────────────────────────────────

    function test_executeWithdrawal_afterCooldown() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        // Advance past 48h cooldown
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        uint256 balBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.executeWithdrawal(receiptId);

        assertEq(assets, 500 * WAD);
        assertEq(usdt.balanceOf(alice) - balBefore, 500 * WAD);
        assertEq(vault.balanceOf(alice), 500 * WAD);
        assertEq(vault.totalQueuedShares(), 0);

        ILeverVault.WithdrawalReceipt memory r = vault.getReceipt(receiptId);
        assertTrue(r.executed);
    }

    function test_executeWithdrawal_revertsBeforeCooldown() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILeverVault.LeverVault__WithdrawalNotReady.selector,
                receiptId,
                block.timestamp + WITHDRAWAL_COOLDOWN
            )
        );
        vault.executeWithdrawal(receiptId);
    }

    function test_executeWithdrawal_revertsNotOwner() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ILeverVault.LeverVault__NotReceiptOwner.selector, receiptId, bob)
        );
        vault.executeWithdrawal(receiptId);
    }

    function test_executeWithdrawal_navComputedAtExecution() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        // NAV drops during cooldown (traders profit)
        vm.prank(execEngine);
        vault.updateUnrealizedPnL(int256(200 * WAD));

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        vm.prank(alice);
        uint256 assets = vault.executeWithdrawal(receiptId);

        // NAV = 1000 - 200 = 800, shares = 500/1000 → 400
        assertEq(assets, 400 * WAD);
    }

    function test_executeWithdrawal_revertsInvalidReceipt() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILeverVault.LeverVault__NoWithdrawalRequest.selector, 999));
        vault.executeWithdrawal(999);
    }

    function test_executeWithdrawal_removesTranches() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(1000 * WAD);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        vm.prank(alice);
        vault.executeWithdrawal(receiptId);

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 0);
    }

    // ──────────────────────────────────────────────
    // Withdrawal Queue — Cancel
    // ──────────────────────────────────────────────

    function test_cancelWithdrawal_unlockShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        assertEq(vault.totalQueuedShares(), 0);
        ILeverVault.WithdrawalReceipt memory r = vault.getReceipt(receiptId);
        assertTrue(r.cancelled);
    }

    function test_cancelWithdrawal_triggersCooldown() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        assertTrue(vault.isInCooldown(alice));

        // Can't request again during cooldown
        vm.prank(alice);
        vm.expectRevert();
        vault.requestWithdrawal(200 * WAD);
    }

    function test_cancelWithdrawal_cooldownExpires() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        // Advance past 24h cancel cooldown
        vm.warp(block.timestamp + CANCEL_COOLDOWN + 1);

        assertFalse(vault.isInCooldown(alice));

        // Can request again
        vm.prank(alice);
        vault.requestWithdrawal(200 * WAD);
    }

    function test_cancelWithdrawal_revertsNotOwner() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ILeverVault.LeverVault__NotReceiptOwner.selector, receiptId, bob)
        );
        vault.cancelWithdrawal(receiptId);
    }

    // ──────────────────────────────────────────────
    // Transfer — Proportional Tranche Split
    // ──────────────────────────────────────────────

    function test_transfer_splitsTrancheProportionally() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        // Transfer 50% to bob
        vm.prank(alice);
        vault.transfer(bob, 500 * WAD);

        assertEq(vault.balanceOf(alice), 500 * WAD);
        assertEq(vault.balanceOf(bob), 500 * WAD);

        ILeverVault.Tranche[] memory aliceTranches = vault.getTranches(alice);
        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);

        assertEq(aliceTranches.length, 1);
        assertEq(bobTranches.length, 1);
        assertEq(aliceTranches[0].shares, 500 * WAD);
        assertEq(bobTranches[0].shares, 500 * WAD);
    }

    function test_transfer_multipleTranchesProportional() public {
        // Alice deposits twice at different reward indexes
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(600 * WAD, alice);

        rewards.setRewardIndex(1e17);
        vm.prank(alice);
        vault.deposit(400 * WAD, alice);

        // Transfer 50% (500 WAD) to bob
        vm.prank(alice);
        vault.transfer(bob, 500 * WAD);

        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);
        // Bob should get proportional shares from each tranche
        // fraction = 500/1000 = 0.5
        // From tranche 0: 600 * 0.5 = 300
        // From tranche 1: 400 * 0.5 = 200
        uint256 totalBobTranche = 0;
        for (uint256 i; i < bobTranches.length; i++) {
            totalBobTranche += bobTranches[i].shares;
        }
        assertEq(totalBobTranche, 500 * WAD);
    }

    function test_transfer_fullAmount_movesAllTranches() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.transfer(bob, 1000 * WAD);

        ILeverVault.Tranche[] memory aliceTranches = vault.getTranches(alice);
        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);

        assertEq(aliceTranches.length, 0);
        assertGt(bobTranches.length, 0);
        assertEq(vault.balanceOf(bob), 1000 * WAD);
    }

    function test_transfer_blockedByQueuedShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.requestWithdrawal(800 * WAD);

        // Can only transfer 200 free shares
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILeverVault.LeverVault__SharesInQueue.selector, 300 * WAD));
        vault.transfer(bob, 300 * WAD);
    }

    function test_transfer_allowedUpToFreeShares() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.requestWithdrawal(800 * WAD);

        // Transfer remaining free 200 shares
        vm.prank(alice);
        vault.transfer(bob, 200 * WAD);

        assertEq(vault.balanceOf(bob), 200 * WAD);
    }

    // ──────────────────────────────────────────────
    // Tranche Consolidation
    // ──────────────────────────────────────────────

    function test_consolidation_mergesOldestWhenExceeds10() public {
        // Make 11 deposits to trigger consolidation
        for (uint256 i = 0; i < 11; i++) {
            rewards.setRewardIndex(i * 1e17);
            vm.prank(alice);
            vault.deposit(100 * WAD, alice);
        }

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 10);
        assertEq(vault.balanceOf(alice), 1100 * WAD);
    }

    function test_consolidation_mergedSnapshotIsWeightedAvg() public {
        // Deposit with snapshot 0
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(100 * WAD, alice);

        // Deposit with snapshot 1e18
        rewards.setRewardIndex(1e18);
        vm.prank(alice);
        vault.deposit(300 * WAD, alice);

        // Fill up to 10 + 1 to trigger consolidation
        for (uint256 i = 2; i <= 10; i++) {
            rewards.setRewardIndex(i * 1e18);
            vm.prank(alice);
            vault.deposit(50 * WAD, alice);
        }

        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches.length, 10);

        // First tranche should be merged: (100*0 + 300*1e18) / 400 = 0.75e18
        assertEq(tranches[0].shares, 400 * WAD);
        assertEq(tranches[0].rewardSnapshot, 75e16); // 0.75e18
    }

    // ──────────────────────────────────────────────
    // Pending Yield
    // ──────────────────────────────────────────────

    function test_pendingYield_calculatesCorrectly() public {
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        // Reward index increases by 0.1 WAD
        rewards.setRewardIndex(1e17);

        uint256 yield_ = vault.pendingYield(alice);
        // yield = 1000e18 * 0.1e18 / 1e18 = 100e18
        assertEq(yield_, 100 * WAD);
    }

    function test_pendingYield_multiTranches() public {
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        rewards.setRewardIndex(5e16); // 0.05
        vm.prank(alice);
        vault.deposit(500 * WAD, alice);

        rewards.setRewardIndex(1e17); // 0.1
        uint256 yield_ = vault.pendingYield(alice);

        // Tranche 0: 1000 * (0.1 - 0) = 100
        // Tranche 1: 500 * (0.1 - 0.05) = 25
        // Total: 125
        assertEq(yield_, 125 * WAD);
    }

    // ──────────────────────────────────────────────
    // Total Value
    // ──────────────────────────────────────────────

    function test_totalValue_includesNavAndYield() public {
        rewards.setRewardIndex(0);
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        rewards.setRewardIndex(1e17); // 0.1

        uint256 value = vault.totalValue(alice);
        // NAV portion: 1000 * 1000/1000 = 1000
        // Yield: 1000 * 0.1 = 100
        assertEq(value, 1100 * WAD);
    }

    // ──────────────────────────────────────────────
    // Max Tranches
    // ──────────────────────────────────────────────

    function test_maxTranches_returns10() public view {
        assertEq(vault.maxTranches(), 10);
    }

    // ──────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────

    function test_pause_blocksDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1000 * WAD, alice);
    }

    function test_pause_blocksRequestWithdrawal() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.requestWithdrawal(500 * WAD);
    }

    function test_pause_unpauseRestoresFunction() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);
        assertEq(vault.balanceOf(alice), 1000 * WAD);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    // ──────────────────────────────────────────────
    // User Receipts
    // ──────────────────────────────────────────────

    function test_getUserReceipts_returnsAll() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.requestWithdrawal(200 * WAD);
        vm.prank(alice);
        vault.requestWithdrawal(300 * WAD);

        ILeverVault.WithdrawalReceipt[] memory receipts = vault.getUserReceipts(alice);
        assertEq(receipts.length, 2);
        assertEq(receipts[0].shares, 200 * WAD);
        assertEq(receipts[1].shares, 300 * WAD);
    }

    // ──────────────────────────────────────────────
    // Execute already-executed or cancelled receipt
    // ──────────────────────────────────────────────

    function test_executeWithdrawal_revertsAlreadyExecuted() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        vm.prank(alice);
        vault.executeWithdrawal(receiptId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILeverVault.LeverVault__NoWithdrawalRequest.selector, receiptId));
        vault.executeWithdrawal(receiptId);
    }

    function test_cancelWithdrawal_revertsCancelledReceipt() public {
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        uint256 receiptId = vault.requestWithdrawal(500 * WAD);

        vm.prank(alice);
        vault.cancelWithdrawal(receiptId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILeverVault.LeverVault__NoWithdrawalRequest.selector, receiptId));
        vault.cancelWithdrawal(receiptId);
    }

    // ──────────────────────────────────────────────
    // Transfer preserves yield identity
    // ──────────────────────────────────────────────

    function test_transfer_preservesRewardSnapshot() public {
        rewards.setRewardIndex(5e17); // 0.5
        vm.prank(alice);
        vault.deposit(1000 * WAD, alice);

        vm.prank(alice);
        vault.transfer(bob, 500 * WAD);

        ILeverVault.Tranche[] memory bobTranches = vault.getTranches(bob);
        assertEq(bobTranches[0].rewardSnapshot, 5e17);
    }
}
