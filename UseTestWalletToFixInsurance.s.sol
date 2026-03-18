// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ILeverVault {
    function totalAssets() external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

interface IInsuranceFund {
    function getIFR() external view returns (uint256);
    function isFullyFunded() external view returns (bool);
    function getBalance() external view returns (uint256);
}

interface IFeeRouter {
    function getCurrentTier() external view returns (uint8);
}

contract UseTestWalletToFixInsurance is Script {

    function run() external {
        // Load environment
        address USDT_ADDRESS = vm.envAddress("USDT_ADDRESS");
        address LEVER_VAULT = vm.envAddress("LEVER_VAULT");
        address INSURANCE_FUND = vm.envAddress("INSURANCE_FUND");
        address FEE_ROUTER = vm.envAddress("FEE_ROUTER");

        IERC20 usdt = IERC20(USDT_ADDRESS);
        ILeverVault vault = ILeverVault(LEVER_VAULT);
        IInsuranceFund insurance = IInsuranceFund(INSURANCE_FUND);
        IFeeRouter feeRouter = IFeeRouter(FEE_ROUTER);

        // Use test wallet private key
        string memory testKeyString = vm.envString("TEST_WALLET_KEY");
        uint256 testKey = vm.parseUint(string(abi.encodePacked("0x", testKeyString)));

        vm.startBroadcast(testKey);

        address testWallet = vm.addr(testKey);
        console.log("Test Wallet Address:", testWallet);

        console.log("=== BEFORE FIX ===");
        console.log("Current TVL:", vault.totalAssets());
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Test Wallet USDT Balance:", usdt.balanceOf(testWallet));

        // Use most of the test wallet's USDT for vault deposit
        // Keep 500K USDT for the test wallet to maintain its functionality
        uint256 testWalletBalance = usdt.balanceOf(testWallet);
        uint256 keepAmount = 500_000e6; // Keep 500K USDT
        uint256 depositAmount;

        if (testWalletBalance > keepAmount) {
            depositAmount = testWalletBalance - keepAmount;
        } else {
            // If test wallet has less than 500K, use 80% of what it has
            depositAmount = (testWalletBalance * 80) / 100;
        }

        console.log("Depositing", depositAmount, "USDT to vault...");
        console.log("Keeping", testWalletBalance - depositAmount, "USDT in test wallet");

        // Approve and deposit to vault
        require(usdt.approve(LEVER_VAULT, depositAmount), "Approval failed");
        uint256 shares = vault.deposit(depositAmount, testWallet);
        console.log("Received shares:", shares);

        console.log("\n=== AFTER FIX ===");
        console.log("New TVL:", vault.totalAssets());
        console.log("New Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Test Wallet remaining USDT:", usdt.balanceOf(testWallet));

        // Verify fix
        uint8 newTier = feeRouter.getCurrentTier();
        bool stillFullyFunded = insurance.isFullyFunded();

        if (newTier == 1 && !stillFullyFunded) {
            console.log("\n[SUCCESS] Insurance fund flow restored!");
            console.log("- Tier switched to 1 (50/30/20 split)");
            console.log("- Insurance will now receive 20% of fees");
        } else {
            console.log("\n[PROGRESS] Made significant progress");
            console.log("- Tier:", newTier);
            console.log("- Fully Funded:", stillFullyFunded);
            if (newTier == 2) {
                console.log("- Still need more TVL to get IFR below 20%");
            }
        }

        vm.stopBroadcast();
    }
}