// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/InsuranceFundFixed.sol";

/// @notice Simple script to deploy InsuranceFundFixed contract
contract DeployInsuranceFundFixedSimple is Script {
    function run() external {
        // Load addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address leverVault = vm.envAddress("LEVER_VAULT");
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== DEPLOYING INSURANCE FUND FIXED ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("LeverVault:", leverVault);

        vm.startBroadcast();

        // Deploy new InsuranceFundFixed
        InsuranceFundFixed newInsuranceFund = new InsuranceFundFixed(
            deployer,       // admin
            usdt,          // USDT token
            leverVault     // LeverVault for TVL
        );

        console2.log("InsuranceFundFixed deployed at:", address(newInsuranceFund));

        // Test the initial state
        uint256 balance = newInsuranceFund.getBalance();
        uint256 ifr = newInsuranceFund.getIFR();
        bool isFullyFunded = newInsuranceFund.isFullyFunded();

        console2.log("Initial balance:", balance);
        console2.log("Initial IFR:", ifr);
        console2.log("Is fully funded:", isFullyFunded);

        vm.stopBroadcast();

        console2.log("");
        console2.log("SUCCESS: InsuranceFundFixed deployed and initialized");
        console2.log("Next: Update deploy-env.sh with this address");
        console2.log("Address:", address(newInsuranceFund));
    }
}