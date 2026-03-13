// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {
    RewardsDistributor,
    RewardsDistributor__ZeroAddress,
    RewardsDistributor__ZeroAmount,
    RewardsDistributor__InsufficientBalance
} from "../contracts/RewardsDistributor.sol";
import { IRewardsDistributor } from "../contracts/interfaces/IRewardsDistributor.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { ILeverVault } from "../contracts/interfaces/ILeverVault.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mock USDT
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

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract RewardsDistributorTest is Test {
    using FixedPointMath for uint256;

    RewardsDistributor public distributor;
    LeverVault public vault;
    MockUSDT public usdt;

    address public admin = address(0xA);
    address public feeRouter = address(0xFE);
    address public fundingEngine = address(0xFD);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant WAD = 1e18;

    function setUp() public {
        usdt = new MockUSDT();

        // Deploy distributor first (vault needs distributor address)
        // But distributor needs vault address — circular dependency.
        // Use nonce prediction to resolve.
        uint64 nonce = vm.getNonce(address(this));
        // distributor is deployed at nonce, vault at nonce+1
        address predictedVault = vm.computeCreateAddress(address(this), nonce + 1);

        distributor = new RewardsDistributor(admin, address(usdt), predictedVault);
        vault = new LeverVault(admin, address(usdt), address(distributor));

        // Verify prediction
        assertEq(address(vault), predictedVault, "vault address prediction mismatch");

        // Grant roles
        vm.startPrank(admin);
        distributor.grantRole(distributor.FEE_ROUTER_ROLE(), feeRouter);
        distributor.grantRole(distributor.FUNDING_RATE_ENGINE_ROLE(), fundingEngine);
        distributor.grantRole(distributor.LEVER_VAULT_ROLE(), address(vault));
        vm.stopPrank();

        // Fund users and approve vault
        usdt.mint(alice, 1_000_000 * WAD);
        usdt.mint(bob, 1_000_000 * WAD);

        vm.prank(alice);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(vault), type(uint256).max);
    }

    // ──────────────────────────────────────────────
    // Helper: deposit USDT to vault as LP
    // ──────────────────────────────────────────────

    function _depositAsLP(address user, uint256 amount) internal {
        vm.prank(user);
        vault.deposit(amount, user);
    }

    /// @dev Simulate fee routing: mint USDT to distributor then call depositRewards
    function _depositRewards(uint256 amount) internal {
        usdt.mint(address(distributor), amount);
        vm.prank(feeRouter);
        distributor.depositRewards(amount);
    }

    /// @dev Simulate unmatched funding: mint USDT to distributor then call receiveUnmatchedFunding
    function _depositFunding(bytes32 marketId, uint256 amount) internal {
        usdt.mint(address(distributor), amount);
        vm.prank(fundingEngine);
        distributor.receiveUnmatchedFunding(marketId, amount);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(distributor.usdt()), address(usdt));
        assertEq(address(distributor.leverVault()), address(vault));
    }

    function test_constructor_revertsZeroAdmin() public {
        vm.expectRevert(RewardsDistributor__ZeroAddress.selector);
        new RewardsDistributor(address(0), address(usdt), address(vault));
    }

    function test_constructor_revertsZeroUsdt() public {
        vm.expectRevert(RewardsDistributor__ZeroAddress.selector);
        new RewardsDistributor(admin, address(0), address(vault));
    }

    function test_constructor_revertsZeroVault() public {
        vm.expectRevert(RewardsDistributor__ZeroAddress.selector);
        new RewardsDistributor(admin, address(usdt), address(0));
    }

    // ──────────────────────────────────────────────
    // depositRewards
    // ──────────────────────────────────────────────

    function test_depositRewards_increasesIndex() public {
        _depositAsLP(alice, 1000 * WAD);

        _depositRewards(100 * WAD);

        // indexDelta = 100e18 * 1e18 / 1000e18 = 1e17 (0.1 per share)
        assertEq(distributor.rewardPerShareCumulative(), 1e17);
    }

    function test_depositRewards_accumulatesIndex() public {
        _depositAsLP(alice, 1000 * WAD);

        _depositRewards(100 * WAD);
        _depositRewards(200 * WAD);

        // 0.1 + 0.2 = 0.3
        assertEq(distributor.rewardPerShareCumulative(), 3e17);
    }

    function test_depositRewards_tracksTotals() public {
        _depositAsLP(alice, 1000 * WAD);

        _depositRewards(100 * WAD);
        _depositRewards(200 * WAD);

        assertEq(distributor.totalDistributed(), 300 * WAD);
        assertEq(distributor.totalFeeRewards(), 300 * WAD);
        assertEq(distributor.totalUnmatchedFunding(), 0);
    }

    function test_depositRewards_noSharesDoesNotIncreaseIndex() public {
        // No LPs deposited yet
        _depositRewards(100 * WAD);

        assertEq(distributor.rewardPerShareCumulative(), 0);
        assertEq(distributor.totalDistributed(), 100 * WAD);
    }

    function test_depositRewards_revertsZeroAmount() public {
        vm.prank(feeRouter);
        vm.expectRevert(RewardsDistributor__ZeroAmount.selector);
        distributor.depositRewards(0);
    }

    function test_depositRewards_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.depositRewards(100 * WAD);
    }

    function test_depositRewards_emitsEvent() public {
        _depositAsLP(alice, 1000 * WAD);
        usdt.mint(address(distributor), 100 * WAD);

        vm.expectEmit(false, false, false, true);
        emit IRewardsDistributor.RewardsDeposited(100 * WAD, 1e17, block.timestamp);

        vm.prank(feeRouter);
        distributor.depositRewards(100 * WAD);
    }

    // ──────────────────────────────────────────────
    // receiveUnmatchedFunding
    // ──────────────────────────────────────────────

    function test_receiveUnmatchedFunding_increasesIndex() public {
        _depositAsLP(alice, 2000 * WAD);

        bytes32 marketId = keccak256("ELECTION_2024");
        _depositFunding(marketId, 200 * WAD);

        // indexDelta = 200e18 * 1e18 / 2000e18 = 1e17
        assertEq(distributor.rewardPerShareCumulative(), 1e17);
    }

    function test_receiveUnmatchedFunding_tracksFundingTotals() public {
        _depositAsLP(alice, 1000 * WAD);

        bytes32 marketId = keccak256("ELECTION_2024");
        _depositFunding(marketId, 50 * WAD);

        assertEq(distributor.totalUnmatchedFunding(), 50 * WAD);
        assertEq(distributor.totalDistributed(), 50 * WAD);
        assertEq(distributor.totalFeeRewards(), 0);
    }

    function test_receiveUnmatchedFunding_revertsZeroAmount() public {
        vm.prank(fundingEngine);
        vm.expectRevert(RewardsDistributor__ZeroAmount.selector);
        distributor.receiveUnmatchedFunding(bytes32(0), 0);
    }

    function test_receiveUnmatchedFunding_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.receiveUnmatchedFunding(bytes32(0), 100 * WAD);
    }

    function test_receiveUnmatchedFunding_emitsEvent() public {
        _depositAsLP(alice, 1000 * WAD);
        bytes32 marketId = keccak256("ELECTION_2024");
        usdt.mint(address(distributor), 50 * WAD);

        vm.expectEmit(true, false, false, true);
        emit IRewardsDistributor.UnmatchedFundingReceived(marketId, 50 * WAD, block.timestamp);

        vm.prank(fundingEngine);
        distributor.receiveUnmatchedFunding(marketId, 50 * WAD);
    }

    // ──────────────────────────────────────────────
    // Mixed fee + funding rewards
    // ──────────────────────────────────────────────

    function test_mixedRewards_indexAccumulatesBoth() public {
        _depositAsLP(alice, 1000 * WAD);

        _depositRewards(100 * WAD);          // +0.1 per share
        _depositFunding(bytes32(0), 50 * WAD); // +0.05 per share

        assertEq(distributor.rewardPerShareCumulative(), 15e16); // 0.15
        assertEq(distributor.totalDistributed(), 150 * WAD);
        assertEq(distributor.totalFeeRewards(), 100 * WAD);
        assertEq(distributor.totalUnmatchedFunding(), 50 * WAD);
    }

    // ──────────────────────────────────────────────
    // pendingRewards (view)
    // ──────────────────────────────────────────────

    function test_pendingRewards_singleLP() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        uint256 pending = distributor.pendingRewards(alice);
        // 1000 shares * 0.1 index = 100
        assertEq(pending, 100 * WAD);
    }

    function test_pendingRewards_twoLPs() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositAsLP(bob, 1000 * WAD);

        _depositRewards(100 * WAD);

        // index = 100 / 2000 = 0.05
        assertEq(distributor.pendingRewards(alice), 50 * WAD);
        assertEq(distributor.pendingRewards(bob), 50 * WAD);
    }

    function test_pendingRewards_laterDepositorEarnsLess() public {
        _depositAsLP(alice, 1000 * WAD);

        _depositRewards(100 * WAD); // index → 0.1

        _depositAsLP(bob, 1000 * WAD); // bob's snapshot = 0.1

        _depositRewards(200 * WAD); // index → 0.1 + 200/2000 = 0.2

        // Alice: 1000 * (0.2 - 0) = 200
        // Bob: 1000 * (0.2 - 0.1) = 100
        assertEq(distributor.pendingRewards(alice), 200 * WAD);
        assertEq(distributor.pendingRewards(bob), 100 * WAD);
    }

    function test_pendingRewards_zeroForNewDepositor() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        _depositAsLP(bob, 500 * WAD);

        // Bob just deposited, snapshot = current index → 0 pending
        assertEq(distributor.pendingRewards(bob), 0);
    }

    function test_pendingRewards_zeroWithNoRewards() public {
        _depositAsLP(alice, 1000 * WAD);
        assertEq(distributor.pendingRewards(alice), 0);
    }

    // ──────────────────────────────────────────────
    // claim (direct call reverts)
    // ──────────────────────────────────────────────

    function test_claim_reverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRewardsDistributor.RewardsDistributor__NothingToClaim.selector, address(0)));
        distributor.claim();
    }

    // ──────────────────────────────────────────────
    // releaseRewards
    // ──────────────────────────────────────────────

    function test_releaseRewards_transfersUSDT() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        uint256 balBefore = usdt.balanceOf(alice);

        vm.prank(address(vault));
        distributor.releaseRewards(alice, 100 * WAD);

        assertEq(usdt.balanceOf(alice) - balBefore, 100 * WAD);
    }

    function test_releaseRewards_revertsUnauthorized() public {
        usdt.mint(address(distributor), 100 * WAD);

        vm.prank(alice);
        vm.expectRevert();
        distributor.releaseRewards(alice, 100 * WAD);
    }

    function test_releaseRewards_revertsZeroAddress() public {
        usdt.mint(address(distributor), 100 * WAD);

        vm.prank(address(vault));
        vm.expectRevert(RewardsDistributor__ZeroAddress.selector);
        distributor.releaseRewards(address(0), 100 * WAD);
    }

    function test_releaseRewards_revertsZeroAmount() public {
        vm.prank(address(vault));
        vm.expectRevert(RewardsDistributor__ZeroAmount.selector);
        distributor.releaseRewards(alice, 0);
    }

    function test_releaseRewards_revertsInsufficientBalance() public {
        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(RewardsDistributor__InsufficientBalance.selector, 100 * WAD, 0)
        );
        distributor.releaseRewards(alice, 100 * WAD);
    }

    function test_releaseRewards_emitsEvents() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        vm.expectEmit(true, false, false, true);
        emit IRewardsDistributor.RewardsClaimed(alice, 50 * WAD, block.timestamp);

        vm.prank(address(vault));
        distributor.releaseRewards(alice, 50 * WAD);
    }

    // ──────────────────────────────────────────────
    // Full claim flow through vault
    // ──────────────────────────────────────────────

    function test_vaultClaim_transfersYieldToUser() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        uint256 balBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        uint256 claimed = vault.claim();

        assertEq(claimed, 100 * WAD);
        assertEq(usdt.balanceOf(alice) - balBefore, 100 * WAD);
    }

    function test_vaultClaim_resetsSnapshots() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        vm.prank(alice);
        vault.claim();

        // After claim, pending should be 0
        assertEq(distributor.pendingRewards(alice), 0);
        assertEq(vault.pendingYield(alice), 0);

        // Tranche snapshot should be updated to current index
        ILeverVault.Tranche[] memory tranches = vault.getTranches(alice);
        assertEq(tranches[0].rewardSnapshot, distributor.rewardPerShareCumulative());
    }

    function test_vaultClaim_revertsZeroYield() public {
        _depositAsLP(alice, 1000 * WAD);

        vm.prank(alice);
        vm.expectRevert(LeverVault.LeverVault__ZeroAmount.selector);
        vault.claim();
    }

    function test_vaultClaim_multipleTranches() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD); // index → 0.1

        _depositAsLP(alice, 500 * WAD); // second tranche at snapshot 0.1
        _depositRewards(150 * WAD); // index → 0.1 + 150/1500 = 0.2

        // Tranche 0: 1000 * (0.2 - 0) = 200
        // Tranche 1: 500 * (0.2 - 0.1) = 50
        // Total = 250

        uint256 balBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.claim();

        assertEq(claimed, 250 * WAD);
        assertEq(usdt.balanceOf(alice) - balBefore, 250 * WAD);
    }

    function test_vaultClaim_twoUsersClaimSequentially() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositAsLP(bob, 1000 * WAD);

        _depositRewards(200 * WAD); // index → 200/2000 = 0.1

        vm.prank(alice);
        uint256 aliceClaimed = vault.claim();
        assertEq(aliceClaimed, 100 * WAD);

        vm.prank(bob);
        uint256 bobClaimed = vault.claim();
        assertEq(bobClaimed, 100 * WAD);
    }

    function test_vaultClaim_claimTwiceSecondTimeReverts() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        vm.prank(alice);
        vault.claim();

        // No new rewards → nothing to claim
        vm.prank(alice);
        vm.expectRevert(LeverVault.LeverVault__ZeroAmount.selector);
        vault.claim();
    }

    function test_vaultClaim_claimAfterMoreRewards() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        vm.prank(alice);
        vault.claim(); // claims 100

        _depositRewards(50 * WAD); // index goes up by 50/1000 = 0.05

        vm.prank(alice);
        uint256 claimed = vault.claim();
        assertEq(claimed, 50 * WAD);
    }

    // ──────────────────────────────────────────────
    // Full compound flow through vault
    // ──────────────────────────────────────────────

    function test_vaultCompound_mintsNewShares() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 newShares = vault.compound();

        assertGt(newShares, 0);
        assertEq(vault.balanceOf(alice), sharesBefore + newShares);
    }

    function test_vaultCompound_zeroYieldReturnsZero() public {
        _depositAsLP(alice, 1000 * WAD);

        vm.prank(alice);
        uint256 newShares = vault.compound();

        assertEq(newShares, 0);
    }

    // ──────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────

    function test_pause_blocksDepositRewards() public {
        vm.prank(admin);
        distributor.pause();

        usdt.mint(address(distributor), 100 * WAD);
        vm.prank(feeRouter);
        vm.expectRevert();
        distributor.depositRewards(100 * WAD);
    }

    function test_pause_blocksReceiveUnmatchedFunding() public {
        vm.prank(admin);
        distributor.pause();

        vm.prank(fundingEngine);
        vm.expectRevert();
        distributor.receiveUnmatchedFunding(bytes32(0), 100 * WAD);
    }

    function test_pause_blocksReleaseRewards() public {
        usdt.mint(address(distributor), 100 * WAD);

        vm.prank(admin);
        distributor.pause();

        vm.prank(address(vault));
        vm.expectRevert();
        distributor.releaseRewards(alice, 100 * WAD);
    }

    function test_pause_unpauseRestores() public {
        _depositAsLP(alice, 1000 * WAD);

        vm.prank(admin);
        distributor.pause();

        vm.prank(admin);
        distributor.unpause();

        _depositRewards(100 * WAD);
        assertEq(distributor.rewardPerShareCumulative(), 1e17);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.pause();
    }

    // ──────────────────────────────────────────────
    // Edge cases
    // ──────────────────────────────────────────────

    function test_largeRewardSmallSupply() public {
        _depositAsLP(alice, 1 * WAD); // 1 share
        _depositRewards(1_000_000 * WAD);

        // index = 1_000_000e18 * 1e18 / 1e18 = 1_000_000e18
        assertEq(distributor.rewardPerShareCumulative(), 1_000_000 * WAD);
        assertEq(distributor.pendingRewards(alice), 1_000_000 * WAD);
    }

    function test_smallRewardLargeSupply() public {
        _depositAsLP(alice, 1_000_000 * WAD);
        _depositRewards(1); // 1 wei

        // index = 1 * 1e18 / 1_000_000e18 = 0 (truncated)
        // This is expected — dust reward with huge supply rounds to zero per share
        assertEq(distributor.rewardPerShareCumulative(), 0);
    }

    function test_multipleDepositorsDifferentTimes() public {
        // Alice deposits early
        _depositAsLP(alice, 1000 * WAD);

        // Rewards come in
        _depositRewards(100 * WAD); // index: +0.1

        // Bob deposits later
        _depositAsLP(bob, 1000 * WAD); // snapshot at 0.1

        // More rewards
        _depositRewards(200 * WAD); // index: +200/2000 = +0.1 → total 0.2

        // Alice: 1000 * (0.2 - 0) = 200
        // Bob: 1000 * (0.2 - 0.1) = 100
        assertEq(distributor.pendingRewards(alice), 200 * WAD);
        assertEq(distributor.pendingRewards(bob), 100 * WAD);

        // Total claimed should equal total rewards
        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        vault.claim();

        uint256 bobBefore = usdt.balanceOf(bob);
        vm.prank(bob);
        vault.claim();

        assertEq(usdt.balanceOf(alice) - aliceBefore, 200 * WAD);
        assertEq(usdt.balanceOf(bob) - bobBefore, 100 * WAD);
    }

    function test_pendingRewards_matchesVaultPendingYield() public {
        _depositAsLP(alice, 1000 * WAD);
        _depositRewards(100 * WAD);

        assertEq(distributor.pendingRewards(alice), vault.pendingYield(alice));
    }

    function test_viewFunctions_initialValues() public view {
        assertEq(distributor.rewardPerShareCumulative(), 0);
        assertEq(distributor.totalDistributed(), 0);
        assertEq(distributor.totalUnmatchedFunding(), 0);
        assertEq(distributor.totalFeeRewards(), 0);
    }
}
