// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "contracts/MarginEngine.sol";
import "contracts/core/OracleAdapter.sol";
import "contracts/OILimits.sol";

/**
 * @title SetMarginEngineParams
 * @notice Set risk parameters in MarginEngine for all 10 demo markets
 * @dev MarginEngine needs its own risk parameters to validate margin checks
 */
contract SetMarginEngineParams is Script {

    function run() external {
        // Get contract addresses from environment
        address marginEngineAddr = vm.envAddress("MARGIN_ENGINE");
        address oracleAdapterAddr = vm.envAddress("ORACLE_ADAPTER");
        address oiLimitsAddr = vm.envAddress("OI_LIMITS");

        MarginEngine marginEngine = MarginEngine(marginEngineAddr);
        OracleAdapter oracle = OracleAdapter(oracleAdapterAddr);
        OILimits oiLimits = OILimits(oiLimitsAddr);

        // Use deployer private key (has ADMIN role)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Market IDs from OnboardDemoMarkets.s.sol - start with working ones only
        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        marketIds[1] = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // US-Iran Ceasefire
        marketIds[2] = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7; // Fed Rate Below 4%

        string[] memory marketNames = new string[](3);
        marketNames[0] = "SpaceX IPO";
        marketNames[1] = "US-Iran Ceasefire";
        marketNames[2] = "Fed Rate Below 4%";

        console.log("=== Setting MarginEngine Risk Parameters ===");

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < 3; i++) {
            bytes32 marketId = marketIds[i];
            string memory marketName = marketNames[i];

            console.log("\nSetting parameters for:", marketName);
            console.log("Market ID:", vm.toString(marketId));

            // Get current values from oracle
            IOracleAdapter.PriceData memory priceData = oracle.getLatestPrice(marketId);
            uint256 marketOI = oiLimits.getMarketOI(marketId);
            uint256 globalOI = oiLimits.getGlobalOI();

            // Set standard risk parameters
            uint256 sigmaCurrent = oracle.getVolatility(marketId); // Current volatility from oracle
            uint256 sigmaBaseline = 25e16; // 25% baseline volatility (0.25 in WAD)
            uint256 externalDepth = priceData.depth; // Depth from oracle
            uint256 depthThreshold = 500e18; // 500 USDT threshold (in WAD)
            uint256 marketUtilization = 0; // Will be calculated by system

            console.log("- Baseline volatility: 25%");
            console.log("- Current volatility:", sigmaCurrent / 1e16, "bps");
            console.log("- External depth:", priceData.depth / 1e18, "USDT");
            console.log("- Depth threshold: 500 USDT");
            console.log("- Market OI:", marketOI / 1e18, "USDT");

            marginEngine.updateMarketRiskParams(
                marketId,
                sigmaCurrent,
                sigmaBaseline,
                externalDepth,
                depthThreshold,
                marketOI,
                globalOI,
                marketUtilization
            );

            console.log("Parameters set successfully");
        }

        vm.stopBroadcast();

        console.log("\n=== MarginEngine Risk Parameters Complete ===");
        console.log("3 main demo markets configured");
        console.log("Position opening should now work");
    }
}