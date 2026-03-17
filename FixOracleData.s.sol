// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IOracleAdapter {
    function pushPrice(
        bytes32 marketId,
        uint256 pYes,
        uint256 pNo,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) external;

    function getLatestPrice(bytes32 marketId) external view returns (
        uint256 pRaw,
        uint256 pi,
        uint256 spread,
        uint256 depth,
        uint256 volume,
        uint256 confidence,
        uint256 timestamp
    );
}

interface ILeverageModel {
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

/// @title Fix Oracle Data for High Leverage
/// @notice Push realistic depth and price data to enable high leverage positions
contract FixOracleData is Script {

    // Market IDs that need fixing
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant ARGENTINA = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;
    bytes32 constant FED_RATE = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;

    function run() external {
        address oracleAdapter = vm.envAddress("ORACLE_ADAPTER");
        address leverageModel = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c; // The OLD one that ExecutionEngine uses

        IOracleAdapter oracle = IOracleAdapter(oracleAdapter);
        ILeverageModel leverage = ILeverageModel(leverageModel);

        console2.log("=== Fixing Oracle Data for High Leverage ===");
        console2.log("Oracle Adapter:", oracleAdapter);
        console2.log("LeverageModel (old):", leverageModel);

        vm.startBroadcast();

        // Fix SpaceX IPO market
        console2.log("\n--- SpaceX IPO Market ---");
        _fixMarket(oracle, leverage, SPACEX_IPO, "SpaceX", 65e16, 35e16); // 65% Yes, 35% No

        // Fix US-Iran market
        console2.log("\n--- US-Iran Market ---");
        _fixMarket(oracle, leverage, US_IRAN, "US-Iran", 28e16, 72e16); // 28% Yes, 72% No

        // Fix FIFA Spain market
        console2.log("\n--- FIFA Spain Market ---");
        _fixMarket(oracle, leverage, FIFA_SPAIN, "FIFA Spain", 55e16, 45e16); // 55% Yes, 45% No

        // Fix Argentina market
        console2.log("\n--- Argentina Market ---");
        _fixMarket(oracle, leverage, ARGENTINA, "Argentina", 42e16, 58e16); // 42% Yes, 58% No

        // Fix Fed Rate market
        console2.log("\n--- Fed Rate Market ---");
        _fixMarket(oracle, leverage, FED_RATE, "Fed Rate", 31e16, 69e16); // 31% Yes, 69% No

        vm.stopBroadcast();

        console2.log("\n=== Oracle Data Fix Complete ===");
        console2.log("All markets now have realistic depth and spread data");
        console2.log("This should enable high leverage positions");
    }

    function _fixMarket(
        IOracleAdapter oracle,
        ILeverageModel leverage,
        bytes32 marketId,
        string memory name,
        uint256 pYes,
        uint256 pNo
    ) internal {
        console2.log("Fixing market:", name);

        // Check current leverage
        try leverage.getEffectiveMaxLeverage(marketId) returns (uint256 currentLeverage) {
            console2.log("Current max leverage WAD:", currentLeverage);
            console2.log("Current max leverage (x):", currentLeverage / 1e18);
        } catch {
            console2.log("Current leverage: ERROR");
        }

        // Realistic market data for prediction markets
        uint256 spread = 2e16;      // 2% spread (realistic for liquid prediction markets)
        uint256 depth = 100000e18;  // 100k tokens depth (realistic for active markets)
        uint256 volume = 500000e18; // 500k volume (shows activity)

        console2.log("Pushing price data:");
        console2.log("  pYes:", pYes / 1e16, "bps");
        console2.log("  pNo:", pNo / 1e16, "bps");
        console2.log("  spread:", spread / 1e16, "bps");
        console2.log("  depth:", depth / 1e18, "tokens");
        console2.log("  volume:", volume / 1e18, "tokens");

        // Push realistic price data
        oracle.pushPrice(marketId, pYes, pNo, spread, depth, volume);

        // Check leverage after fix
        try leverage.getEffectiveMaxLeverage(marketId) returns (uint256 newLeverage) {
            console2.log("NEW max leverage WAD:", newLeverage);
            console2.log("NEW max leverage (x):", newLeverage / 1e18);

            if (newLeverage >= 5e18) {
                console2.log("SUCCESS: Leverage >= 5x");
            } else {
                console2.log("WARNING: Still low leverage");
            }
        } catch {
            console2.log("New leverage: ERROR");
        }
    }
}