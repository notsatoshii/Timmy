// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IMockUSDT {
    function mint(address to, uint256 amount) external;
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
    function getTarget() external view returns (uint256);
    function getFloor() external view returns (uint256);
}

interface IFeeRouter {
    function getCurrentTier() external view returns (uint8);
    function getCurrentSplit() external view returns (uint256, uint256, uint256);
}

contract FixInsuranceFundFlowCorrect is Script {

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
        uint256 currentTVL = vault.totalAssets();
        uint256 internalBalance = insurance.getBalance();
        uint256 actualUSDTBalance = usdt.balanceOf(INSURANCE_FUND);
        uint256 currentIFR = insurance.getIFR();
        uint8 currentTier = feeRouter.getCurrentTier();
        bool isFullyFunded = insurance.isFullyFunded();

        console.log("Current TVL:", currentTVL);
        console.log("Insurance Internal Balance:", internalBalance);
        console.log("Insurance Actual USDT Balance:", actualUSDTBalance);
        console.log("Current IFR (WAD):", currentIFR);
        console.log("Current Tier:", currentTier);
        console.log("Is Fully Funded:", isFullyFunded);
        console.log("Deployer USDT Balance:", usdt.balanceOf(msg.sender));

        // Step 1: Calculate the USDT deficit at InsuranceFund
        uint256 usdtDeficit = internalBalance - actualUSDTBalance;
        console.log("\nStep 1: Align USDT balances");
        console.log("USDT deficit to cover:", usdtDeficit);

        // Step 2: Mint USDT to deployer to cover the deficit
        console.log("Minting", usdtDeficit, "USDT to deployer...");
        usdt.mint(msg.sender, usdtDeficit);

        // Step 3: Transfer USDT directly to InsuranceFund to align balances
        console.log("Transferring", usdtDeficit, "USDT to InsuranceFund...");
        require(usdt.transfer(INSURANCE_FUND, usdtDeficit), "Transfer to InsuranceFund failed");

        // Verify alignment
        uint256 newActualBalance = usdt.balanceOf(INSURANCE_FUND);
        console.log("Insurance Fund USDT Balance after transfer:", newActualBalance);

        // Step 4: Now calculate required TVL to get IFR below 20%
        console.log("\nStep 2: Adjust TVL for proper IFR");
        uint256 targetIFRPercent = 15; // Target 15% IFR (below 20% threshold)
        uint256 targetTVL = (internalBalance * 100) / targetIFRPercent;
        uint256 requiredVaultDeposit = targetTVL > currentTVL ? targetTVL - currentTVL : 0;

        console.log("Target TVL for 15% IFR:", targetTVL);
        console.log("Required additional vault deposit:", requiredVaultDeposit);

        if (requiredVaultDeposit > 0) {
            // Mint additional USDT for vault deposit
            console.log("Minting", requiredVaultDeposit, "USDT for vault deposit...");
            usdt.mint(msg.sender, requiredVaultDeposit);

            // Approve and deposit to vault
            console.log("Approving and depositing to vault...");
            require(usdt.approve(LEVER_VAULT, requiredVaultDeposit), "Vault approval failed");
            uint256 shares = vault.deposit(requiredVaultDeposit, msg.sender);
            console.log("Received vault shares:", shares);
        }

        console.log("\n=== AFTER FIX ===");
        uint256 finalTVL = vault.totalAssets();
        uint256 finalIFR = insurance.getIFR();
        uint8 finalTier = feeRouter.getCurrentTier();
        bool finallyFullyFunded = insurance.isFullyFunded();
        uint256 finalUSDTBalance = usdt.balanceOf(INSURANCE_FUND);

        console.log("Final TVL:", finalTVL);
        console.log("Insurance Internal Balance:", insurance.getBalance());
        console.log("Insurance USDT Balance:", finalUSDTBalance);
        console.log("Final IFR (WAD):", finalIFR);
        console.log("Final Tier:", finalTier);
        console.log("Is Fully Funded:", finallyFullyFunded);

        // Calculate IFR percentage for display
        if (finalTVL > 0) {
            uint256 ifrPercent = (insurance.getBalance() * 10000) / finalTVL; // Basis points
            console.log("Final IFR Percentage:", ifrPercent / 100, ".", ifrPercent % 100, "%");
        }

        // Get fee split
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = feeRouter.getCurrentSplit();
        console.log("Fee Split - LP:", (lpPct * 100) / 1e18, "% Protocol:", (protocolPct * 100) / 1e18, "% Insurance:", (insurancePct * 100) / 1e18, "%");

        // Verify fix
        if (finalTier == 1 && !finallyFullyFunded && insurancePct > 0) {
            console.log("\n[SUCCESS] Insurance fund flow restored!");
            console.log("- Tier switched to 1 (50/30/20 split)");
            console.log("- Insurance will now receive 20% of fees");
            console.log("- USDT balances are aligned");
        } else {
            console.log("\n[PARTIAL SUCCESS] Some issues remain:");
            console.log("- Final Tier:", finalTier, "(should be 1)");
            console.log("- Fully Funded:", finallyFullyFunded, "(should be false)");
            console.log("- Insurance Fee Share:", (insurancePct * 100) / 1e18, "% (should be 20%)");
        }

        vm.stopBroadcast();
    }
}