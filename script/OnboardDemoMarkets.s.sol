// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/MarketRegistry.sol";

/// @title Demo Market Onboarding Script
/// @notice Creates demo markets from demo_markets.json for seeding bots
contract OnboardDemoMarkets is Script {
    MarketRegistry public marketRegistry;

    struct MarketParams {
        string name;
        uint256 resolutionTime;
        IMarketRegistry.MarketCategory category;
        uint256 allocationWeight;
        bytes32 externalId;
    }

    function run() external {
        marketRegistry = MarketRegistry(vm.envAddress("MARKET_REGISTRY"));

        vm.startBroadcast();

        // Create demo markets

        // Largest IPO by Market Cap 2026: SpaceX?
        marketRegistry.createMarket(
            0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1,
            "Largest IPO by Market Cap 2026: SpaceX?",
            "spacex-ipo-2026",
            1798588800,
            IMarketRegistry.MarketCategory(0),
            40000000000000000
        );

        // US-Iran Ceasefire by April 30, 2026?
        marketRegistry.createMarket(
            0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a,
            "US-Iran Ceasefire by April 30, 2026?",
            "us-iran-ceasefire-2026",
            1777507200,
            IMarketRegistry.MarketCategory(1),
            25000000000000000
        );

        // Nothing Ever Happens: 2026
        marketRegistry.createMarket(
            0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d,
            "Nothing Ever Happens: 2026",
            "nothing-ever-happens-2026",
            1798588800,
            IMarketRegistry.MarketCategory(2),
            15000000000000000
        );

        // 2026 FIFA World Cup Winner: Spain?
        marketRegistry.createMarket(
            0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2,
            "2026 FIFA World Cup Winner: Spain?",
            "fifa-worldcup-spain-2026",
            1784419200,
            IMarketRegistry.MarketCategory(0),
            40000000000000000
        );

        // Fed Rate End of 2026: Below 4%?
        marketRegistry.createMarket(
            0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7,
            "Fed Rate End of 2026: Below 4%?",
            "fed-rate-below-4-2026",
            1796688000,
            IMarketRegistry.MarketCategory(1),
            25000000000000000
        );

        // SpaceX IPO via Ackman SPAR?
        marketRegistry.createMarket(
            0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2,
            "SpaceX IPO via Ackman SPAR?",
            "spacex-ackman-spar",
            1798675200,
            IMarketRegistry.MarketCategory(0),
            40000000000000000
        );

        // AAPL Above $250 in April 2026?
        marketRegistry.createMarket(
            0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554,
            "AAPL Above $250 in April 2026?",
            "aapl-250-april-2026",
            1777507200,
            IMarketRegistry.MarketCategory(0),
            40000000000000000
        );

        // OpenSea Token Launch by 2026?
        marketRegistry.createMarket(
            0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc,
            "OpenSea Token Launch by 2026?",
            "opensea-token-2026",
            1798675200,
            IMarketRegistry.MarketCategory(0),
            40000000000000000
        );

        // Fed April 2026: Rate Cut?
        marketRegistry.createMarket(
            0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f,
            "Fed April 2026: Rate Cut?",
            "fed-rate-cut-april-2026",
            1777334400,
            IMarketRegistry.MarketCategory(1),
            25000000000000000
        );

        // Argentina USD Rate Above 1500 ARS End of 2026?
        marketRegistry.createMarket(
            0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea,
            "Argentina USD Rate Above 1500 ARS End of 2026?",
            "argentina-usd-1500-2026",
            1798675200,
            IMarketRegistry.MarketCategory(1),
            25000000000000000
        );

        vm.stopBroadcast();

        console2.log("Demo markets created successfully");
        console2.log("Total markets:", vm.envUint("DEMO_MARKET_COUNT"));
    }
}