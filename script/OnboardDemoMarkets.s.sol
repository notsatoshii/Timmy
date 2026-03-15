// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../../contracts/core/MarketRegistry.sol";

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
            "Largest IPO by Market Cap 2026: SpaceX?",
            1798588800,
            IMarketRegistry.MarketCategory(0),
            4e+16,
            0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1
        );

        // US-Iran Ceasefire by April 30, 2026?
        marketRegistry.createMarket(
            "US-Iran Ceasefire by April 30, 2026?",
            1777507200,
            IMarketRegistry.MarketCategory(1),
            2.5e+16,
            0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a
        );

        // Nothing Ever Happens: 2026
        marketRegistry.createMarket(
            "Nothing Ever Happens: 2026",
            1798588800,
            IMarketRegistry.MarketCategory(2),
            1.5e+16,
            0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d
        );

        // 2026 FIFA World Cup Winner: Spain?
        marketRegistry.createMarket(
            "2026 FIFA World Cup Winner: Spain?",
            1784419200,
            IMarketRegistry.MarketCategory(0),
            4e+16,
            0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2
        );

        // Fed Rate End of 2026: Below 4%?
        marketRegistry.createMarket(
            "Fed Rate End of 2026: Below 4%?",
            1796688000,
            IMarketRegistry.MarketCategory(1),
            2.5e+16,
            0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7
        );

        // SpaceX IPO via Ackman SPAR?
        marketRegistry.createMarket(
            "SpaceX IPO via Ackman SPAR?",
            1798675200,
            IMarketRegistry.MarketCategory(0),
            4e+16,
            0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2
        );

        // AAPL Above $250 in April 2026?
        marketRegistry.createMarket(
            "AAPL Above $250 in April 2026?",
            1777507200,
            IMarketRegistry.MarketCategory(0),
            4e+16,
            0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554
        );

        // OpenSea Token Launch by 2026?
        marketRegistry.createMarket(
            "OpenSea Token Launch by 2026?",
            1798675200,
            IMarketRegistry.MarketCategory(0),
            4e+16,
            0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc
        );

        // Fed April 2026: Rate Cut?
        marketRegistry.createMarket(
            "Fed April 2026: Rate Cut?",
            1777334400,
            IMarketRegistry.MarketCategory(1),
            2.5e+16,
            0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f
        );

        // Argentina USD Rate Above 1500 ARS End of 2026?
        marketRegistry.createMarket(
            "Argentina USD Rate Above 1500 ARS End of 2026?",
            1798675200,
            IMarketRegistry.MarketCategory(1),
            2.5e+16,
            0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea
        );

        vm.stopBroadcast();

        console2.log("Demo markets created successfully");
        console2.log("Total markets:", vm.envUint("DEMO_MARKET_COUNT"));
    }
}