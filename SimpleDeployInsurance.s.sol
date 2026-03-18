// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/InsuranceFundFixed.sol";

/// @notice Simple deployment without role granting
contract SimpleDeployInsurance is Script {
    function run() external {
        // Load addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address leverVault = vm.envAddress("LEVER_VAULT");
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== SIMPLE INSURANCE FUND DEPLOY ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("LeverVault:", leverVault);

        vm.startBroadcast();

        // Deploy InsuranceFundFixed
        InsuranceFundFixed insuranceFund = new InsuranceFundFixed(
            deployer,       // admin
            usdt,          // USDT token
            leverVault     // LeverVault for TVL
        );

        console2.log("InsuranceFund deployed at:", address(insuranceFund));

        vm.stopBroadcast();
    }
}