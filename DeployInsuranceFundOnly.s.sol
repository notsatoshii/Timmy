// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/InsuranceFundFixed.sol";

/// @notice Simple deployment of fixed InsuranceFund contract
contract DeployInsuranceFundOnly is Script {
    function run() external {
        // Load addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address leverVault = vm.envAddress("LEVER_VAULT");
        address feeRouter = vm.envAddress("FEE_ROUTER");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== DEPLOYING FIXED INSURANCE FUND ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("LeverVault:", leverVault);
        console2.log("FeeRouter:", feeRouter);
        console2.log("");

        vm.startBroadcast();

        // Deploy new InsuranceFundFixed
        console2.log("Deploying InsuranceFundFixed...");
        InsuranceFundFixed newInsuranceFund = new InsuranceFundFixed(
            deployer,       // admin
            usdt,          // USDT token
            leverVault     // LeverVault for TVL
        );

        console2.log("InsuranceFundFixed deployed at:", address(newInsuranceFund));

        // Grant necessary roles to FeeRouter
        console2.log("Granting FEE_ROUTER_ROLE to:", feeRouter);
        newInsuranceFund.grantRole(newInsuranceFund.FEE_ROUTER_ROLE(), feeRouter);

        // Verify deployment
        uint256 balance = newInsuranceFund.getBalance();
        uint256 ifr = newInsuranceFund.getIFR();
        bool isFullyFunded = newInsuranceFund.isFullyFunded();

        console2.log("");
        console2.log("=== VERIFICATION ===");
        console2.log("Balance (USDT):", balance / 1e6, "USDT");
        console2.log("IFR (raw):", ifr);
        console2.log("IFR percentage:", (ifr * 100) / 1e18, "%");
        console2.log("Is fully funded:", isFullyFunded);

        if (balance == 10_000e6) {
            console2.log("SUCCESS: Bootstrap amount is correct (10,000 USDT)");
        } else {
            console2.log("ERROR: Unexpected bootstrap amount");
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== UPDATE REQUIRED ===");
        console2.log("Update deploy-env.sh with:");
        console2.log("export INSURANCE_FUND=", address(newInsuranceFund));
    }
}