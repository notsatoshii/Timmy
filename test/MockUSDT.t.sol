// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { MockUSDT } from "../contracts/periphery/MockUSDT.sol";

contract MockUSDTTest is Test {
    MockUSDT usdt;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp
        usdt = new MockUSDT();
    }

    function test_decimals() public view {
        assertEq(usdt.decimals(), 6);
    }

    function test_nameAndSymbol() public view {
        assertEq(usdt.name(), "Mock USDT");
        assertEq(usdt.symbol(), "USDT");
    }

    function test_faucet_mintsCorrectAmount() public {
        vm.prank(alice);
        usdt.faucet();
        assertEq(usdt.balanceOf(alice), 10_000e6);
    }

    function test_faucet_cooldown() public {
        vm.startPrank(alice);
        usdt.faucet();

        // Second call within cooldown should revert
        vm.expectRevert(abi.encodeWithSelector(
            MockUSDT.MockUSDT__FaucetCooldown.selector,
            block.timestamp + 1 hours
        ));
        usdt.faucet();
        vm.stopPrank();
    }

    function test_faucet_afterCooldown() public {
        vm.startPrank(alice);
        usdt.faucet();

        // Warp past cooldown
        vm.warp(block.timestamp + 1 hours);
        usdt.faucet();

        assertEq(usdt.balanceOf(alice), 20_000e6);
        vm.stopPrank();
    }

    function test_faucetTo() public {
        usdt.faucetTo(bob);
        assertEq(usdt.balanceOf(bob), 10_000e6);
    }

    function test_faucetTo_cooldownPerRecipient() public {
        usdt.faucetTo(alice);

        // Same recipient within cooldown
        vm.expectRevert(abi.encodeWithSelector(
            MockUSDT.MockUSDT__FaucetCooldown.selector,
            block.timestamp + 1 hours
        ));
        usdt.faucetTo(alice);

        // Different recipient should work
        usdt.faucetTo(bob);
        assertEq(usdt.balanceOf(bob), 10_000e6);
    }

    function test_ownerMint() public {
        usdt.mint(alice, 1_000_000e6);
        assertEq(usdt.balanceOf(alice), 1_000_000e6);
    }

    function test_ownerMint_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        usdt.mint(alice, 1_000_000e6);
    }

    function test_transfer() public {
        usdt.mint(alice, 1000e6);

        vm.prank(alice);
        usdt.transfer(bob, 400e6);

        assertEq(usdt.balanceOf(alice), 600e6);
        assertEq(usdt.balanceOf(bob), 400e6);
    }

    function test_approveAndTransferFrom() public {
        usdt.mint(alice, 1000e6);

        vm.prank(alice);
        usdt.approve(bob, 500e6);

        vm.prank(bob);
        usdt.transferFrom(alice, bob, 300e6);

        assertEq(usdt.balanceOf(alice), 700e6);
        assertEq(usdt.balanceOf(bob), 300e6);
        assertEq(usdt.allowance(alice, bob), 200e6);
    }
}
