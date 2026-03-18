// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IMockUSDT {
    function mint(address to, uint256 amount) external;
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

contract SimpleFixInsuranceFund is Script {

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

        // Simple approach: deposit 30M USDT to ensure we get below 20% IFR
        // 30M should be more than enough since insurance has ~5M
        // This gives us IFR = 5M / 30M = ~16.7%, which is below 20%
        uint256 depositAmount = 30_000_000e6; // 30M USDT (6 decimals)

        console.log("Depositing fixed amount:", depositAmount, "USDT (30M)");

        // Mint the USDT to deployer
        console.log("Minting", depositAmount, "USDT to deployer...");
        usdt.mint(msg.sender, depositAmount);

        // Check balance after mint
        uint256 deployerBalance = usdt.balanceOf(msg.sender);
        console.log("Deployer USDT Balance after mint:", deployerBalance);

        // Approve and deposit to vault
        console.log("Approving USDT...");
        require(usdt.approve(LEVER_VAULT, depositAmount), "Approval failed");

        console.log("Depositing to vault...");
        uint256 shares = vault.deposit(depositAmount, msg.sender);
        console.log("Received shares:", shares);

        console.log("\n=== AFTER FIX ===");
        console.log("New TVL:", vault.totalAssets());
        console.log("New Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());

        // Verify fix
        uint8 newTier = feeRouter.getCurrentTier();
        bool stillFullyFunded = insurance.isFullyFunded();

        if (newTier == 1 && !stillFullyFunded) {
            console.log("\n[SUCCESS] Insurance fund flow restored!");
            console.log("- Tier switched to 1 (50/30/20 split)");
            console.log("- Insurance will now receive 20% of fees");
        } else {
            console.log("\n[NEEDS MORE LIQUIDITY] Insurance fund still not receiving fees");
            console.log("- Tier:", newTier);
            console.log("- Fully Funded:", stillFullyFunded);
            console.log("- Try depositing more liquidity to lower IFR further");
        }

        vm.stopBroadcast();
    }
}