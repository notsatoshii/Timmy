// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOracleAdapter} from "../contracts/interfaces/IOracleAdapter.sol";

/**
 * @title RegisterOracleSource
 * @notice Register deployer as an oracle source
 */
contract RegisterOracleSource is Script {

    address constant ORACLE_ADAPTER = 0x13e01E7E58196cff03068FDf0bB29382ec60b676;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Registering Oracle Source ===");
        console2.log("Source address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        IOracleAdapter oracle = IOracleAdapter(ORACLE_ADAPTER);

        // Register deployer as oracle source with high weight (90%)
        oracle.registerSource(deployer, 0.9e18);

        console2.log("==> Deployer registered as oracle source with 90% weight");

        vm.stopBroadcast();
    }
}