// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

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

contract MintAndFixInsuranceFund is Script {

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
        console.log("Insurance Balance:", insurance.getBalance());
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Deployer USDT Balance:", usdt.balanceOf(msg.sender));

        // Calculate required deposit (using 6 decimals for USDT)
        // Target: IFR = 19% (below 20% threshold)
        // Current insurance balance: ~5,011,000 USDT (in 18 decimals)
        // Required TVL: 5,011,000 / 0.19 ≈ 26,400,000 USDT
        uint256 currentTVL = vault.totalAssets();
        uint256 insuranceBalance = insurance.getBalance();

        // Convert insurance balance from 18 decimals to 6 decimals for calculation
        // Insurance balance is in WAD (18 decimals), but USDT uses 6 decimals
        uint256 insuranceBalanceUSDT = insuranceBalance / 1e12;

        uint256 targetTVL_USDT = (insuranceBalanceUSDT * 100) / 19; // 19% target for safety margin
        uint256 currentTVL_USDT = currentTVL; // Already in USDT 6 decimals
        uint256 requiredDeposit = targetTVL_USDT - currentTVL_USDT;

        console.log("Insurance Balance (USDT 6 decimals):", insuranceBalanceUSDT);
        console.log("Target TVL for 19% IFR (USDT):", targetTVL_USDT);
        console.log("Required deposit (USDT):", requiredDeposit);

        // Mint the required USDT to deployer
        console.log("Minting", requiredDeposit, "USDT to deployer...");
        usdt.mint(msg.sender, requiredDeposit);

        // Check balance after mint
        uint256 deployerBalance = usdt.balanceOf(msg.sender);
        console.log("Deployer USDT Balance after mint:", deployerBalance);

        // Approve and deposit to vault
        console.log("Approving USDT...");
        require(usdt.approve(LEVER_VAULT, requiredDeposit), "Approval failed");

        console.log("Depositing to vault...");
        uint256 shares = vault.deposit(requiredDeposit, msg.sender);
        console.log("Received shares:", shares);

        console.log("\n=== AFTER FIX ===");
        console.log("New TVL:", vault.totalAssets());
        console.log("Insurance Balance:", insurance.getBalance());
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
            console.log("\n[FAILED] Insurance fund still not receiving fees");
            console.log("- Tier:", newTier);
            console.log("- Fully Funded:", stillFullyFunded);
        }

        vm.stopBroadcast();
    }
}