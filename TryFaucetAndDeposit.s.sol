// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IMockUSDT {
    function faucet() external;
    function balanceOf(address account) external view returns (uint256);
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

contract TryFaucetAndDeposit is Script {

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

        vm.startBroadcast();

        console.log("=== BEFORE FIX ===");
        console.log("Current TVL:", vault.totalAssets());
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Deployer USDT Balance:", usdt.balanceOf(msg.sender));

        // Try to use faucet to get some USDT
        console.log("Trying faucet...");
        try usdt.faucet() {
            console.log("Faucet successful!");
        } catch Error(string memory reason) {
            console.log("Faucet failed:", reason);
        } catch {
            console.log("Faucet failed with unknown error");
        }

        uint256 deployerBalance = usdt.balanceOf(msg.sender);
        console.log("Deployer USDT Balance after faucet:", deployerBalance);

        if (deployerBalance > 0) {
            // Deposit whatever we have
            console.log("Depositing", deployerBalance, "USDT to vault...");

            // Approve and deposit to vault
            require(usdt.approve(LEVER_VAULT, deployerBalance), "Approval failed");
            uint256 shares = vault.deposit(deployerBalance, msg.sender);
            console.log("Received shares:", shares);

            console.log("\n=== AFTER DEPOSIT ===");
            console.log("New TVL:", vault.totalAssets());
            console.log("New Tier:", feeRouter.getCurrentTier());
            console.log("Is Fully Funded:", insurance.isFullyFunded());

            // Check if we made progress
            uint8 newTier = feeRouter.getCurrentTier();
            bool stillFullyFunded = insurance.isFullyFunded();

            if (newTier == 1 && !stillFullyFunded) {
                console.log("\n[SUCCESS] Insurance fund flow restored!");
                console.log("- Tier switched to 1 (50/30/20 split)");
                console.log("- Insurance will now receive 20% of fees");
            } else {
                console.log("\n[PARTIAL] Made progress, but need more liquidity");
                console.log("- Tier:", newTier, "(need tier 1)");
                console.log("- Fully Funded:", stillFullyFunded, "(need false)");
                console.log("- Need to deposit more USDT to lower IFR further");
            }
        } else {
            console.log("No USDT available - cannot proceed with deposit");
        }

        vm.stopBroadcast();
    }
}