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

contract FixInsuranceFundFlow is Script {

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

        vm.startBroadcast();

        console.log("=== BEFORE FIX ===");
        console.log("Current TVL:", vault.totalAssets());
        console.log("Insurance Balance:", insurance.getBalance());
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("Is Fully Funded:", insurance.isFullyFunded());
        console.log("Deployer USDT Balance:", usdt.balanceOf(msg.sender));

        // Calculate required deposit
        // Target: IFR = 19% (below 20% threshold)
        // Current insurance balance: ~5,011,000 USDT
        // Required TVL: 5,011,000 / 0.19 ≈ 26,400,000 USDT
        uint256 currentTVL = vault.totalAssets();
        uint256 insuranceBalance = insurance.getBalance();
        uint256 targetTVL = (insuranceBalance * 100) / 19; // 19% target for safety margin
        uint256 requiredDeposit = targetTVL - currentTVL;

        console.log("Target TVL for 19% IFR:", targetTVL);
        console.log("Required deposit:", requiredDeposit);

        // Check if we have enough USDT
        uint256 deployerBalance = usdt.balanceOf(msg.sender);
        if (deployerBalance < requiredDeposit) {
            console.log("ERROR: Insufficient USDT balance");
            console.log("Need:", requiredDeposit);
            console.log("Have:", deployerBalance);
            revert("Insufficient USDT");
        }

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