// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockUSDT} from "../contracts/periphery/MockUSDT.sol";
import {LeverVault} from "../contracts/LeverVault.sol";

/// @title SeedTVL — Seed LeverVault with 20M USDT TVL
/// @notice Uses MockUSDT owner mint + vault deposit for initial TVL seeding
contract SeedTVL is Script {
    // Target seeding amount
    uint256 private constant SEED_AMOUNT = 20_000_000e6; // 20M USDT (6 decimals)

    // Contract addresses from deployment.json
    MockUSDT private constant usdt = MockUSDT(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);
    LeverVault private constant vault = LeverVault(0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LEVER TVL Seeding ===");
        console.log("Deployer:", deployer);
        console.log("MockUSDT:", address(usdt));
        console.log("LeverVault:", address(vault));
        console.log("Target amount: %s USDT", SEED_AMOUNT / 1e6);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Check initial balances
        console.log("=== Initial State ===");
        uint256 initialBalance = usdt.balanceOf(deployer);
        uint256 initialTVL = vault.totalAssets();
        console.log("Deployer USDT balance:", initialBalance / 1e6);
        console.log("Vault TVL:", initialTVL / 1e6);
        console.log("");

        // 2. Mint USDT (owner-only function, no limits)
        console.log("=== Minting USDT ===");
        usdt.mint(deployer, SEED_AMOUNT);

        uint256 newBalance = usdt.balanceOf(deployer);
        console.log("Post-mint USDT balance:", newBalance / 1e6);
        console.log("Minted amount:", (newBalance - initialBalance) / 1e6);
        console.log("");

        // 3. Approve vault to spend USDT
        console.log("=== Approving Vault ===");
        usdt.approve(address(vault), SEED_AMOUNT);
        console.log("Approved vault to spend: %s USDT", SEED_AMOUNT / 1e6);
        console.log("");

        // 4. Deposit to vault
        console.log("=== Depositing to Vault ===");
        uint256 shares = vault.deposit(SEED_AMOUNT, deployer);

        uint256 finalTVL = vault.totalAssets();
        uint256 deployerShares = vault.balanceOf(deployer);

        console.log("Shares received:", shares);
        console.log("Deployer total shares:", deployerShares);
        console.log("Final vault TVL:", finalTVL / 1e6);
        console.log("TVL increase:", (finalTVL - initialTVL) / 1e6);
        console.log("");

        vm.stopBroadcast();

        // 5. Summary
        console.log("=== TVL Seeding Complete ===");
        console.log("Target TVL: %s USDT", SEED_AMOUNT / 1e6);
        console.log("Actual TVL: %s USDT", finalTVL / 1e6);
        console.log("Success: %s", finalTVL >= SEED_AMOUNT ? "YES" : "NO");

        if (finalTVL >= SEED_AMOUNT) {
            console.log("SUCCESS: 20M TVL target achieved!");
        } else {
            console.log("FAILURE: TVL target not met");
        }
    }
}