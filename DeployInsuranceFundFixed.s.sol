// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./contracts/InsuranceFundFixed.sol";

interface IFeeRouter {
    function updateInsuranceFund(address newInsuranceFund) external;
    function getCurrentTier() external view returns (uint8);
}

interface IInsuranceFund {
    function getIFR() external view returns (uint256);
    function isFullyFunded() external view returns (bool);
    function getBalance() external view returns (uint256);
}

interface ILeverVault {
    function totalAssets() external view returns (uint256);
}

contract DeployInsuranceFundFixed is Script {
    function run() external {
        // Load environment variables
        address USDT_ADDRESS = vm.envAddress("USDT_ADDRESS");
        address LEVER_VAULT = vm.envAddress("LEVER_VAULT");
        address OLD_INSURANCE_FUND = vm.envAddress("INSURANCE_FUND");
        address FEE_ROUTER = vm.envAddress("FEE_ROUTER");

        IFeeRouter feeRouter = IFeeRouter(FEE_ROUTER);
        IInsuranceFund oldInsurance = IInsuranceFund(OLD_INSURANCE_FUND);
        ILeverVault vault = ILeverVault(LEVER_VAULT);

        vm.startBroadcast();

        console.log("=== BEFORE DEPLOYMENT ===");
        console.log("Old Insurance Fund:", OLD_INSURANCE_FUND);
        console.log("Old IFR:", oldInsurance.getIFR());
        console.log("Old Fully Funded:", oldInsurance.isFullyFunded());
        console.log("Current Tier:", feeRouter.getCurrentTier());
        console.log("TVL:", vault.totalAssets());

        // Deploy new InsuranceFundFixed
        console.log("\n=== DEPLOYING FIXED INSURANCE FUND ===");
        InsuranceFundFixed newInsuranceFund = new InsuranceFundFixed(USDT_ADDRESS, LEVER_VAULT);
        address newInsuranceAddr = address(newInsuranceFund);
        console.log("New InsuranceFundFixed deployed at:", newInsuranceAddr);

        // Transfer the balance from old insurance fund to new one
        uint256 oldBalance = oldInsurance.getBalance();
        console.log("Old insurance balance:", oldBalance);

        // Note: We'll need to manually transfer the balance or have a migration function
        // For now, let's update the FeeRouter to point to the new contract

        // Update FeeRouter to use new insurance fund
        console.log("Updating FeeRouter to use new InsuranceFund...");
        feeRouter.updateInsuranceFund(newInsuranceAddr);

        console.log("\n=== AFTER DEPLOYMENT ===");
        console.log("New Insurance Fund:", newInsuranceAddr);
        console.log("New IFR:", newInsuranceFund.getIFR());
        console.log("New Fully Funded:", newInsuranceFund.isFullyFunded());
        console.log("New Tier:", feeRouter.getCurrentTier());

        // Check if the fix worked
        uint8 newTier = feeRouter.getCurrentTier();
        bool stillFullyFunded = newInsuranceFund.isFullyFunded();

        if (newTier == 1 && !stillFullyFunded) {
            console.log("\n[SUCCESS] Insurance fund flow restored!");
            console.log("- Tier switched to 1 (50/30/20 split)");
            console.log("- Insurance will now receive 20% of fees");
        } else {
            console.log("\n[CHECKING] Insurance fund state:");
            console.log("- Tier:", newTier);
            console.log("- Fully Funded:", stillFullyFunded);

            if (newTier == 2) {
                console.log("- Note: Fixed IFR calculation should now work correctly");
                console.log("- Balance needs to be migrated to new contract");
            }
        }

        console.log("\n=== MIGRATION NOTE ===");
        console.log("The old insurance balance needs to be migrated to the new contract.");
        console.log("This may require manual intervention or a migration script.");

        vm.stopBroadcast();
    }
}