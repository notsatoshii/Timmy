// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOracleAdapter} from "../contracts/interfaces/IOracleAdapter.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title GrantOracleRole
 * @notice Grant ORACLE role to deployer for price setting
 */
contract GrantOracleRole is Script {

    address constant ORACLE_ADAPTER = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Granting ORACLE Role ===");
        console2.log("Deployer address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        IAccessControl oracle = IAccessControl(ORACLE_ADAPTER);

        // Grant ORACLE role to deployer
        oracle.grantRole(ORACLE_ROLE, deployer);

        console2.log("==> ORACLE role granted to deployer");

        vm.stopBroadcast();
    }
}