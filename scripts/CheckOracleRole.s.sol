// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract CheckOracleRole is Script {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE");

    function run() external {
        // Load deployment config
        string memory deploymentFile = vm.readFile("deployment.json");
        address oracleAdapter = vm.parseJsonAddress(deploymentFile, ".oracleAdapter");

        console.log("OracleAdapter:", oracleAdapter);
        console.log("Deployer address:", vm.addr(vm.envUint("PRIVATE_KEY")));

        // Check if deployer has ORACLE role
        AccessControl oracle = AccessControl(oracleAdapter);
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        bool hasRole = oracle.hasRole(ORACLE_ROLE, deployer);
        console.log("Deployer has ORACLE role:", hasRole);

        if (!hasRole) {
            console.log("Granting ORACLE role to deployer...");
            vm.startBroadcast();
            oracle.grantRole(ORACLE_ROLE, deployer);
            vm.stopBroadcast();
            console.log("ORACLE role granted!");
        } else {
            console.log("ORACLE role already assigned.");
        }
    }
}