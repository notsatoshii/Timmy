// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOracleAdapter} from "../contracts/interfaces/IOracleAdapter.sol";

/**
 * @title SeedPrices
 * @notice Set initial prices for all demo markets
 */
contract SeedPrices is Script {

    address constant ORACLE_ADAPTER = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;

    // Market names and their initial probabilities from demo_markets.json
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

    // Initial probabilities from demo_markets.json (as WAD)
    uint256[] public initialProbabilities = [
        0.88e18, // SpaceX IPO: 88%
        0.35e18, // US-Iran Ceasefire: 35%
        0.42e18, // Nothing Ever Happens: 42%
        0.22e18, // FIFA Spain: 22%
        0.55e18, // Fed Rate Below 4%: 55%
        0.30e18, // SpaceX Ackman: 30%
        0.60e18, // AAPL $250: 60%
        0.45e18, // OpenSea Token: 45%
        0.40e18, // Fed Rate Cut: 40%
        0.65e18  // Argentina USD: 65%
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Seeding Initial Prices ===");

        vm.startBroadcast(deployerPrivateKey);

        IOracleAdapter oracle = IOracleAdapter(ORACLE_ADAPTER);

        for (uint256 i = 0; i < marketNames.length; i++) {
            bytes32 marketId = sha256(bytes(marketNames[i]));
            uint256 pi = initialProbabilities[i];

            console2.log("Setting price for market:", i);
            console2.log("  Market ID:", vm.toString(marketId));
            console2.log("  Initial PI:", pi / 1e16, "basis points");

            // Push price with pYes and pNo format
            uint256 pYes = pi;
            uint256 pNo = 1e18 - pi;  // pNo = 1 - pYes

            oracle.pushPrice(
                marketId,
                pYes,         // pYes probability
                pNo,          // pNo probability (1 - pYes)
                200e14,       // spread: 2% (200 basis points in WAD)
                1000e18,      // depth: 1000 units
                5000e18       // volume: 5000 units
            );

            console2.log("  ==> Price set successfully");
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("==> All", marketNames.length, "demo market prices set!");
    }
}