// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IMockUSDT {
    function faucet() external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
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

contract MassiveTVLBoost is Script {

    function run() external {
        // Load environment
        address USDT_ADDRESS = vm.envAddress("USDT_ADDRESS");
        address LEVER_VAULT = vm.envAddress("LEVER_VAULT");
        address INSURANCE_FUND = vm.envAddress("INSURANCE_FUND");
        address FEE_ROUTER = vm.envAddress("FEE_ROUTER");

        IMockUSDT usdt = IMockUSDT(USDT_ADDRESS);
        ILeverVault vault = ILeverVault(LEVER_VAULT);
        IInsuranceFund insurance = IInsuranceFund(INSURANCE_FUND);
        IFeeRouter feeRouter = IFeeRouter(FEE_ROUTER);

        // Use test wallet which has more funds
        string memory testKeyString = vm.envString("TEST_WALLET_KEY");
        uint256 testKey = vm.parseUint(string(abi.encodePacked("0x", testKeyString)));
        vm.startBroadcast(testKey);

        address testWallet = vm.addr(testKey);
        console.log("Test Wallet Address:", testWallet);

        console.log("=== BEFORE MASSIVE BOOST ===");
        console.log("Current TVL (wei):", vault.totalAssets());
        console.log("Current TVL (USDT):", vault.totalAssets() / 1e6, "M USDT");
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Test Wallet USDT Balance:", usdt.balanceOf(testWallet));

        // The real issue: Insurance has ~5M USDT, but TVL is only ~68 USDT
        // We need TVL of at least 25M USDT to get IFR below 20%
        // Target: Deposit remaining test wallet balance to vault

        uint256 testWalletBalance = usdt.balanceOf(testWallet);
        console.log("Depositing ALL remaining USDT:", testWalletBalance);

        if (testWalletBalance > 0) {
            // Approve and deposit everything to vault
            require(usdt.approve(LEVER_VAULT, testWalletBalance), "Approval failed");
            uint256 shares = vault.deposit(testWalletBalance, testWallet);
            console.log("Received shares:", shares);
        }

        // Use deployer to get more via faucet
        vm.stopBroadcast();

        // Switch to deployer for faucet
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        address deployer = vm.addr(deployerKey);
        console.log("\nSwitching to deployer for faucet calls...");
        console.log("Deployer Address:", deployer);

        // Try multiple faucet calls (up to 5 times, may hit cooldown)
        for (uint i = 0; i < 5; i++) {
            console.log("Faucet attempt", i + 1);
            try usdt.faucet() {
                console.log("Faucet successful, got 10K USDT");

                // Deposit immediately
                uint256 balance = usdt.balanceOf(deployer);
                if (balance > 0) {
                    require(usdt.approve(LEVER_VAULT, balance), "Approval failed");
                    uint256 shares = vault.deposit(balance, deployer);
                    console.log("Deposited", balance, "USDT, received shares:", shares);
                }
            } catch Error(string memory reason) {
                console.log("Faucet failed:", reason);
                break;
            } catch {
                console.log("Faucet failed with unknown error");
                break;
            }
        }

        console.log("\n=== AFTER MASSIVE BOOST ===");
        console.log("New TVL (wei):", vault.totalAssets());
        console.log("New TVL (USDT):", vault.totalAssets() / 1e6, "M USDT");
        console.log("New Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());

        // Check final result
        uint8 newTier = feeRouter.getCurrentTier();
        bool stillFullyFunded = insurance.isFullyFunded();

        if (newTier == 1 && !stillFullyFunded) {
            console.log("\n[SUCCESS] Insurance fund flow restored!");
            console.log("- Tier switched to 1 (50/30/20 split)");
            console.log("- Insurance will now receive 20% of fees");
        } else {
            console.log("\n[STATUS] Current state:");
            console.log("- Tier:", newTier);
            console.log("- Fully Funded:", stillFullyFunded);

            uint256 currentTVL = vault.totalAssets();
            console.log("- Current TVL: ~", currentTVL / 1e6, "USDT");
            console.log("- Need TVL > 25M USDT to get IFR below 20%");
        }

        vm.stopBroadcast();
    }
}