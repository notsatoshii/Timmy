// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "contracts/MarginEngine.sol";
import "contracts/core/OracleAdapter.sol";
import "contracts/OILimits.sol";

/**
 * @title SetAllMarketRiskParams
 * @notice Set risk parameters in MarginEngine for ALL 10 demo markets
 */
contract SetAllMarketRiskParams is Script {

    function run() external {
        address marginEngineAddr = vm.envAddress("MARGIN_ENGINE");
        address oracleAdapterAddr = vm.envAddress("ORACLE_ADAPTER");
        address oiLimitsAddr = vm.envAddress("OI_LIMITS");

        MarginEngine marginEngine = MarginEngine(marginEngineAddr);
        OracleAdapter oracle = OracleAdapter(oracleAdapterAddr);
        OILimits oiLimits = OILimits(oiLimitsAddr);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // All 10 demo market IDs (sha256 of market names)
        bytes32[10] memory marketIds = [
            bytes32(0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1), // SpaceX IPO
            bytes32(0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a), // US-Iran Ceasefire
            bytes32(0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d), // Nothing Ever Happens
            bytes32(0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2), // FIFA Spain
            bytes32(0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7), // Fed Rate Below 4%
            bytes32(0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2), // SpaceX Ackman
            bytes32(0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554), // AAPL $250
            bytes32(0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc), // OpenSea Token
            bytes32(0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f), // Fed April Rate Cut
            bytes32(0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea)  // Argentina USD
        ];

        uint256 globalOI = oiLimits.getGlobalOI();

        console.log("=== Setting MarginEngine Risk Parameters for ALL 10 Markets ===");

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < 10; i++) {
            bytes32 marketId = marketIds[i];

            IOracleAdapter.PriceData memory priceData = oracle.getLatestPrice(marketId);
            uint256 marketOI = oiLimits.getMarketOI(marketId);
            uint256 sigmaCurrent = oracle.getVolatility(marketId);

            console.log("Setting params for market", i);

            marginEngine.updateMarketRiskParams(
                marketId,
                sigmaCurrent,
                25e16,            // sigmaBaseline: 25%
                priceData.depth,  // externalDepth from oracle
                500e18,           // depthThreshold: 500 USDT (WAD)
                marketOI,
                globalOI,
                0                 // marketUtilization
            );
        }

        vm.stopBroadcast();

        console.log("=== All 10 markets configured ===");
    }
}
