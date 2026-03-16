// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IMarketRegistry} from "../contracts/interfaces/IMarketRegistry.sol";

/**
 * @title ActivateMarkets
 * @notice Activate all demo markets for trading
 */
contract ActivateMarkets is Script {

    address constant MARKET_REGISTRY = 0x89398FECE023cDD8c53eFD9a7C68a227eA139e1E;

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
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");

        console2.log("=== Activating Demo Markets ===");

        vm.startBroadcast(deployerPrivateKey);

        IMarketRegistry registry = IMarketRegistry(MARKET_REGISTRY);

        for (uint256 i = 0; i < marketNames.length; i++) {
            bytes32 marketId = sha256(bytes(marketNames[i]));

            console2.log("Activating market:", i, "ID:", vm.toString(marketId));

            // Activate the market
            registry.activateMarket(marketId);

            // Set to live status (markets are currently created but not live)
            registry.setLive(marketId);

            console2.log("  ==> Market activated and set live");
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("==> All", marketNames.length, "demo markets activated and live!");
    }
}