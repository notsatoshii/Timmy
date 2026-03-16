// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LeverageModel} from "../contracts/LeverageModel.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title SetMarketRiskParams
 * @notice Set risk parameters for all demo markets
 */
contract SetMarketRiskParams is Script {

    address constant LEVERAGE_MODEL = 0x891b44d5fb7BBA7e68f27367f1E7b4FC74A1c850;

    // Market names from demo_markets.json
    string[] public marketNames = [
        "Largest IPO by Market Cap 2026: SpaceX?",
        "US-Iran Ceasefire by April 30, 2026?",
        "Nothing Ever Happens: 2026",
        "2026 FIFA World Cup Winner: Spain?",
        "Fed Rate End of 2026: Below 4%?",
        "SpaceX IPO via Ackman SPAR?",
        "AAPL Above $250 in April 2026?",
        "OpenSea Token Launch by 2026?",
        "Fed April 2026: Rate Cut?",
        "Argentina USD Rate Above 1500 ARS End of 2026?"
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Setting Market Risk Parameters ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        LeverageModel leverageModel = LeverageModel(LEVERAGE_MODEL);
        IAccessControl accessControl = IAccessControl(LEVERAGE_MODEL);

        // Grant KEEPER role to deployer
        bytes32 KEEPER_ROLE = keccak256("KEEPER");
        console2.log("Granting KEEPER role to deployer...");
        accessControl.grantRole(KEEPER_ROLE, deployer);

        for (uint256 i = 0; i < marketNames.length; i++) {
            bytes32 marketId = sha256(bytes(marketNames[i]));

            // Set reasonable default risk parameters
            uint256 sigmaBaseline = 0.25e18;  // 25% baseline volatility
            uint256 depthThreshold = 500e18;  // 500 USDT depth threshold

            console2.log("Setting risk params for market:", i);
            console2.log("  Market ID:", vm.toString(marketId));
            console2.log("  Sigma baseline:", sigmaBaseline / 1e16, "basis points");
            console2.log("  Depth threshold:", depthThreshold / 1e18, "USDT");

            leverageModel.setMarketRiskParams(
                marketId,
                sigmaBaseline,
                depthThreshold
            );

            console2.log("  ==> Risk params set successfully");
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("==> All", marketNames.length, "demo market risk parameters set!");
    }
}