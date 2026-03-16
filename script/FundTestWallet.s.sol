// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/periphery/MockUSDT.sol";
import "../contracts/LeverVault.sol";
import "../contracts/core/AccountManager.sol";

/**
 * @title FundTestWallet
 * @notice Fully fund the test wallet for demo mode:
 *         - 5M USDT to LeverVault for LP shares
 *         - 2M USDT to AccountManager for trading collateral
 */
contract FundTestWallet is Script {
    // Contract addresses (using deployer as sender, test wallet as beneficiary)
    address private constant TEST_WALLET = 0xB072263740D7c60f1Aa0BF46e737F83544C7b785;

    // Target amounts in USDT (6 decimals)
    uint256 private constant VAULT_DEPOSIT = 5_000_000 * 1e6;  // 5M USDT
    uint256 private constant TRADING_DEPOSIT = 2_000_000 * 1e6; // 2M USDT

    function run() external {
        // Get contract addresses from environment
        address usdtAddr = vm.envAddress("USDT_ADDRESS");
        address vaultAddr = vm.envAddress("LEVER_VAULT");
        address accountManagerAddr = vm.envAddress("ACCOUNT_MANAGER");

        MockUSDT usdt = MockUSDT(usdtAddr);
        LeverVault vault = LeverVault(vaultAddr);
        AccountManager accountManager = AccountManager(accountManagerAddr);

        // Use deployer key (has USDT minting privileges)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Funding Test Wallet ===");
        console.log("Test Wallet:", TEST_WALLET);
        console.log("Current USDT balance:", usdt.balanceOf(TEST_WALLET));

        vm.startBroadcast(deployerKey);

        // Step 1: Mint USDT to deployer first, then transfer to test wallet
        uint256 totalNeeded = VAULT_DEPOSIT + TRADING_DEPOSIT;
        console.log("Minting", totalNeeded, "USDT to deployer...");
        usdt.mint(vm.addr(deployerKey), totalNeeded);

        console.log("Transferring", totalNeeded, "USDT to test wallet...");
        usdt.transfer(TEST_WALLET, totalNeeded);

        vm.stopBroadcast();

        // Step 2: Use test wallet to make deposits
        string memory testKeyString = vm.envString("TEST_WALLET_KEY");
        uint256 testKey = vm.parseUint(string(abi.encodePacked("0x", testKeyString)));
        vm.startBroadcast(testKey);

        // Approve vault for LP deposit
        console.log("Approving vault for", VAULT_DEPOSIT, "USDT...");
        usdt.approve(vaultAddr, VAULT_DEPOSIT);

        // Deposit to vault (receives lvUSDT shares)
        console.log("Depositing", VAULT_DEPOSIT, "USDT to LeverVault...");
        uint256 sharesBefore = vault.balanceOf(TEST_WALLET);
        vault.deposit(VAULT_DEPOSIT, TEST_WALLET);
        uint256 sharesAfter = vault.balanceOf(TEST_WALLET);
        console.log("LP shares minted:", sharesAfter - sharesBefore);

        // Approve AccountManager for trading deposit
        console.log("Approving AccountManager for", TRADING_DEPOSIT, "USDT...");
        usdt.approve(accountManagerAddr, TRADING_DEPOSIT);

        // Deposit trading collateral
        console.log("Depositing", TRADING_DEPOSIT, "USDT to AccountManager...");
        accountManager.deposit(TRADING_DEPOSIT);

        vm.stopBroadcast();

        // Verification
        console.log("\n=== Verification ===");
        console.log("Test wallet USDT balance:", usdt.balanceOf(TEST_WALLET));
        console.log("Test wallet LP shares:", vault.balanceOf(TEST_WALLET));
        console.log("Test wallet trading balance:", accountManager.getBalance(TEST_WALLET));

        console.log("\nTest wallet funding COMPLETE!");
    }
}