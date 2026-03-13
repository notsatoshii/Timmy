// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { IAccountManager } from "../contracts/interfaces/IAccountManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC20 for testing
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "mUSDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AccountManagerTest is Test {
    AccountManager public accountManager;
    MockUSDT public usdt;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public stranger = makeAddr("stranger");

    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE");

    uint256 constant WAD = 1e18;

    function setUp() public {
        usdt = new MockUSDT();
        accountManager = new AccountManager(admin, address(usdt));

        // Grant ENGINE role to the engine address
        vm.prank(admin);
        accountManager.grantRole(ENGINE_ROLE, engine);

        // Mint tokens to alice and bob and approve
        usdt.mint(alice, 1_000_000 * WAD);
        usdt.mint(bob, 1_000_000 * WAD);

        vm.prank(alice);
        usdt.approve(address(accountManager), type(uint256).max);

        vm.prank(bob);
        usdt.approve(address(accountManager), type(uint256).max);
    }

    // ═══════════════════════════════════════════════
    // Deposit
    // ═══════════════════════════════════════════════

    function test_deposit_happyPath() public {
        uint256 amount = 1000 * WAD;

        vm.expectEmit(true, false, false, true);
        emit IAccountManager.CollateralDeposited(alice, amount);

        vm.prank(alice);
        accountManager.deposit(amount);

        assertEq(accountManager.getBalance(alice), amount);
        assertEq(accountManager.getFreeCollateral(alice), amount);
        assertEq(accountManager.getLockedCollateral(alice), 0);
        assertEq(usdt.balanceOf(address(accountManager)), amount);
    }

    function test_deposit_multipleDeposits() public {
        vm.prank(alice);
        accountManager.deposit(100 * WAD);

        vm.prank(alice);
        accountManager.deposit(200 * WAD);

        assertEq(accountManager.getBalance(alice), 300 * WAD);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IAccountManager.AccountManager__ZeroAmount.selector);
        accountManager.deposit(0);
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(admin);
        accountManager.pause();

        vm.prank(alice);
        vm.expectRevert();
        accountManager.deposit(100 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Withdraw
    // ═══════════════════════════════════════════════

    function test_withdraw_happyPath() public {
        uint256 depositAmt = 1000 * WAD;
        uint256 withdrawAmt = 400 * WAD;

        vm.prank(alice);
        accountManager.deposit(depositAmt);

        uint256 balBefore = usdt.balanceOf(alice);

        vm.expectEmit(true, false, false, true);
        emit IAccountManager.CollateralWithdrawn(alice, withdrawAmt);

        vm.prank(alice);
        accountManager.withdraw(withdrawAmt);

        assertEq(accountManager.getBalance(alice), depositAmt - withdrawAmt);
        assertEq(usdt.balanceOf(alice), balBefore + withdrawAmt);
    }

    function test_withdraw_fullFreeCollateral() public {
        vm.prank(alice);
        accountManager.deposit(500 * WAD);

        vm.prank(alice);
        accountManager.withdraw(500 * WAD);

        assertEq(accountManager.getBalance(alice), 0);
    }

    function test_withdraw_revertsOnZeroAmount() public {
        vm.prank(alice);
        accountManager.deposit(100 * WAD);

        vm.prank(alice);
        vm.expectRevert(IAccountManager.AccountManager__ZeroAmount.selector);
        accountManager.withdraw(0);
    }

    function test_withdraw_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        accountManager.deposit(100 * WAD);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__InsufficientBalance.selector,
                alice,
                200 * WAD,
                100 * WAD
            )
        );
        accountManager.withdraw(200 * WAD);
    }

    function test_withdraw_revertsWhenCollateralLocked() public {
        uint256 depositAmt = 1000 * WAD;
        uint256 lockAmt = 800 * WAD;

        vm.prank(alice);
        accountManager.deposit(depositAmt);

        vm.prank(engine);
        accountManager.lockCollateral(alice, lockAmt);

        // Free = 1000 - 800 = 200. Trying to withdraw 300 should fail.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__InsufficientBalance.selector,
                alice,
                300 * WAD,
                200 * WAD
            )
        );
        accountManager.withdraw(300 * WAD);
    }

    function test_withdraw_revertsWhenPaused() public {
        vm.prank(alice);
        accountManager.deposit(100 * WAD);

        vm.prank(admin);
        accountManager.pause();

        vm.prank(alice);
        vm.expectRevert();
        accountManager.withdraw(50 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Lock Collateral
    // ═══════════════════════════════════════════════

    function test_lockCollateral_happyPath() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 600 * WAD);

        assertEq(accountManager.getLockedCollateral(alice), 600 * WAD);
        assertEq(accountManager.getFreeCollateral(alice), 400 * WAD);
        // Total balance unchanged
        assertEq(accountManager.getBalance(alice), 1000 * WAD);
    }

    function test_lockCollateral_multipleLocks() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 300 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 200 * WAD);

        assertEq(accountManager.getLockedCollateral(alice), 500 * WAD);
        assertEq(accountManager.getFreeCollateral(alice), 500 * WAD);
    }

    function test_lockCollateral_revertsOnInsufficientFree() public {
        vm.prank(alice);
        accountManager.deposit(500 * WAD);

        vm.prank(engine);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__InsufficientBalance.selector,
                alice,
                600 * WAD,
                500 * WAD
            )
        );
        accountManager.lockCollateral(alice, 600 * WAD);
    }

    function test_lockCollateral_revertsWithoutEngineRole() public {
        vm.prank(alice);
        accountManager.deposit(500 * WAD);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.lockCollateral(alice, 100 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Release Collateral
    // ═══════════════════════════════════════════════

    function test_releaseCollateral_happyPath() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 600 * WAD);

        vm.prank(engine);
        accountManager.releaseCollateral(alice, 400 * WAD);

        assertEq(accountManager.getLockedCollateral(alice), 200 * WAD);
        assertEq(accountManager.getFreeCollateral(alice), 800 * WAD);
    }

    function test_releaseCollateral_fullRelease() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 1000 * WAD);

        vm.prank(engine);
        accountManager.releaseCollateral(alice, 1000 * WAD);

        assertEq(accountManager.getLockedCollateral(alice), 0);
        assertEq(accountManager.getFreeCollateral(alice), 1000 * WAD);
    }

    function test_releaseCollateral_revertsOnUnderflow() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.lockCollateral(alice, 100 * WAD);

        // Trying to release more than locked triggers arithmetic underflow
        vm.prank(engine);
        vm.expectRevert();
        accountManager.releaseCollateral(alice, 200 * WAD);
    }

    function test_releaseCollateral_revertsWithoutEngineRole() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.releaseCollateral(alice, 100 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Credit PnL
    // ═══════════════════════════════════════════════

    function test_creditPnL_happyPath() public {
        // Credit PnL increases balance without requiring a deposit
        vm.prank(engine);
        accountManager.creditPnL(alice, 500 * WAD);

        assertEq(accountManager.getBalance(alice), 500 * WAD);
        assertEq(accountManager.getFreeCollateral(alice), 500 * WAD);
    }

    function test_creditPnL_addsToExistingBalance() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.creditPnL(alice, 250 * WAD);

        assertEq(accountManager.getBalance(alice), 1250 * WAD);
    }

    function test_creditPnL_revertsWithoutEngineRole() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.creditPnL(alice, 100 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Debit PnL
    // ═══════════════════════════════════════════════

    function test_debitPnL_happyPath() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(engine);
        accountManager.debitPnL(alice, 300 * WAD);

        assertEq(accountManager.getBalance(alice), 700 * WAD);
    }

    function test_debitPnL_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        accountManager.deposit(100 * WAD);

        vm.prank(engine);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__InsufficientBalance.selector,
                alice,
                200 * WAD,
                100 * WAD
            )
        );
        accountManager.debitPnL(alice, 200 * WAD);
    }

    function test_debitPnL_revertsWithoutEngineRole() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.debitPnL(alice, 100 * WAD);
    }

    function test_debitPnL_entireBalance() public {
        vm.prank(alice);
        accountManager.deposit(500 * WAD);

        vm.prank(engine);
        accountManager.debitPnL(alice, 500 * WAD);

        assertEq(accountManager.getBalance(alice), 0);
    }

    // ═══════════════════════════════════════════════
    // Assign Position
    // ═══════════════════════════════════════════════

    function test_assignPosition_happyPath() public {
        vm.expectEmit(true, true, false, true);
        emit IAccountManager.PositionAssigned(alice, 42);

        vm.prank(engine);
        accountManager.assignPosition(alice, 42);

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 1);
        assertEq(positions[0], 42);
    }

    function test_assignPosition_multiplePositions() public {
        vm.prank(engine);
        accountManager.assignPosition(alice, 1);
        vm.prank(engine);
        accountManager.assignPosition(alice, 2);
        vm.prank(engine);
        accountManager.assignPosition(alice, 3);

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 3);
        assertEq(positions[0], 1);
        assertEq(positions[1], 2);
        assertEq(positions[2], 3);
    }

    function test_assignPosition_revertsWithoutEngineRole() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.assignPosition(alice, 1);
    }

    // ═══════════════════════════════════════════════
    // Remove Position
    // ═══════════════════════════════════════════════

    function test_removePosition_happyPath() public {
        vm.prank(engine);
        accountManager.assignPosition(alice, 42);

        vm.expectEmit(true, true, false, true);
        emit IAccountManager.PositionRemoved(alice, 42);

        vm.prank(engine);
        accountManager.removePosition(alice, 42);

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 0);
    }

    function test_removePosition_middleElement() public {
        // Assign 3 positions: [1, 2, 3]
        vm.startPrank(engine);
        accountManager.assignPosition(alice, 1);
        accountManager.assignPosition(alice, 2);
        accountManager.assignPosition(alice, 3);

        // Remove middle (2) => last element (3) swaps in: [1, 3]
        accountManager.removePosition(alice, 2);
        vm.stopPrank();

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], 1);
        assertEq(positions[1], 3);
    }

    function test_removePosition_firstElement() public {
        vm.startPrank(engine);
        accountManager.assignPosition(alice, 10);
        accountManager.assignPosition(alice, 20);
        accountManager.assignPosition(alice, 30);

        // Remove first (10) => last (30) swaps in: [30, 20]
        accountManager.removePosition(alice, 10);
        vm.stopPrank();

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], 30);
        assertEq(positions[1], 20);
    }

    function test_removePosition_lastElement() public {
        vm.startPrank(engine);
        accountManager.assignPosition(alice, 10);
        accountManager.assignPosition(alice, 20);

        // Remove last (20) => just pop: [10]
        accountManager.removePosition(alice, 20);
        vm.stopPrank();

        uint256[] memory positions = accountManager.getUserPositions(alice);
        assertEq(positions.length, 1);
        assertEq(positions[0], 10);
    }

    function test_removePosition_revertsOnNotOwned() public {
        vm.prank(engine);
        accountManager.assignPosition(alice, 42);

        // Bob does not own position 42
        vm.prank(engine);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__PositionNotOwned.selector,
                bob,
                42
            )
        );
        accountManager.removePosition(bob, 42);
    }

    function test_removePosition_revertsOnNonexistent() public {
        // Position 999 never assigned
        vm.prank(engine);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountManager.AccountManager__PositionNotOwned.selector,
                alice,
                999
            )
        );
        accountManager.removePosition(alice, 999);
    }

    function test_removePosition_revertsWithoutEngineRole() public {
        vm.prank(engine);
        accountManager.assignPosition(alice, 1);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                ENGINE_ROLE
            )
        );
        accountManager.removePosition(alice, 1);
    }

    // ═══════════════════════════════════════════════
    // View Functions
    // ═══════════════════════════════════════════════

    function test_getBalance_defaultsToZero() public view {
        assertEq(accountManager.getBalance(stranger), 0);
    }

    function test_getFreeCollateral_defaultsToZero() public view {
        assertEq(accountManager.getFreeCollateral(stranger), 0);
    }

    function test_getLockedCollateral_defaultsToZero() public view {
        assertEq(accountManager.getLockedCollateral(stranger), 0);
    }

    function test_getUserPositions_defaultsToEmpty() public view {
        uint256[] memory positions = accountManager.getUserPositions(stranger);
        assertEq(positions.length, 0);
    }

    // ═══════════════════════════════════════════════
    // Pause / Unpause
    // ═══════════════════════════════════════════════

    function test_pause_onlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        accountManager.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        accountManager.pause();

        vm.prank(stranger);
        vm.expectRevert();
        accountManager.unpause();
    }

    function test_unpause_resumesOperations() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(admin);
        accountManager.pause();

        // Deposit fails when paused
        vm.prank(alice);
        vm.expectRevert();
        accountManager.deposit(100 * WAD);

        // Unpause
        vm.prank(admin);
        accountManager.unpause();

        // Deposit works again
        vm.prank(alice);
        accountManager.deposit(100 * WAD);
        assertEq(accountManager.getBalance(alice), 1100 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Engine role operations NOT blocked by pause
    // (lockCollateral, releaseCollateral, creditPnL,
    //  debitPnL, assignPosition, removePosition
    //  are NOT guarded by whenNotPaused)
    // ═══════════════════════════════════════════════

    function test_engineOps_workWhenPaused() public {
        // Deposit before pause
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.prank(admin);
        accountManager.pause();

        // Engine operations should still work (no whenNotPaused modifier)
        vm.startPrank(engine);
        accountManager.lockCollateral(alice, 100 * WAD);
        accountManager.releaseCollateral(alice, 50 * WAD);
        accountManager.creditPnL(alice, 200 * WAD);
        accountManager.debitPnL(alice, 50 * WAD);
        accountManager.assignPosition(alice, 1);
        accountManager.removePosition(alice, 1);
        vm.stopPrank();

        // Verify state is consistent
        assertEq(accountManager.getBalance(alice), 1150 * WAD); // 1000 + 200 - 50
        assertEq(accountManager.getLockedCollateral(alice), 50 * WAD); // 100 - 50
    }

    // ═══════════════════════════════════════════════
    // Integration: Full lifecycle
    // ═══════════════════════════════════════════════

    function test_fullLifecycle_profit() public {
        // 1. Alice deposits
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        // 2. Engine opens a position: lock collateral + assign position
        vm.startPrank(engine);
        accountManager.lockCollateral(alice, 500 * WAD);
        accountManager.assignPosition(alice, 1);
        vm.stopPrank();

        assertEq(accountManager.getFreeCollateral(alice), 500 * WAD);
        assertEq(accountManager.getLockedCollateral(alice), 500 * WAD);

        // 3. Engine closes position with profit: release + credit + remove
        //    In production, the engine would transfer profit tokens into the contract.
        //    Simulate by minting the profit amount to the contract so it can pay out.
        usdt.mint(address(accountManager), 200 * WAD);

        vm.startPrank(engine);
        accountManager.releaseCollateral(alice, 500 * WAD);
        accountManager.creditPnL(alice, 200 * WAD);
        accountManager.removePosition(alice, 1);
        vm.stopPrank();

        assertEq(accountManager.getBalance(alice), 1200 * WAD);
        assertEq(accountManager.getLockedCollateral(alice), 0);
        assertEq(accountManager.getUserPositions(alice).length, 0);

        // 4. Alice withdraws all
        vm.prank(alice);
        accountManager.withdraw(1200 * WAD);

        assertEq(accountManager.getBalance(alice), 0);
    }

    function test_fullLifecycle_loss() public {
        vm.prank(alice);
        accountManager.deposit(1000 * WAD);

        vm.startPrank(engine);
        accountManager.lockCollateral(alice, 500 * WAD);
        accountManager.assignPosition(alice, 7);

        // Close with loss: release collateral then debit
        accountManager.releaseCollateral(alice, 500 * WAD);
        accountManager.debitPnL(alice, 300 * WAD);
        accountManager.removePosition(alice, 7);
        vm.stopPrank();

        assertEq(accountManager.getBalance(alice), 700 * WAD);
    }

    // ═══════════════════════════════════════════════
    // Constructor
    // ═══════════════════════════════════════════════

    function test_constructor_setsCollateralToken() public view {
        assertEq(address(accountManager.collateralToken()), address(usdt));
    }

    function test_constructor_grantsAdminRole() public view {
        assertTrue(accountManager.hasRole(accountManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_engineRoleConstant() public view {
        assertEq(accountManager.ENGINE(), keccak256("ENGINE"));
    }
}
