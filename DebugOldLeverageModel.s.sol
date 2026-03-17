// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IOracleAdapter {
    struct PriceData {
        uint256 pRaw;
        uint256 pi;
        uint256 spread;
        uint256 depth;
        uint256 volume;
        uint256 confidence;
        uint256 timestamp;
    }

    function getLatestPrice(bytes32 marketId) external view returns (PriceData memory);
    function getVolatility(bytes32 marketId) external view returns (uint256);
    function getPI(bytes32 marketId) external view returns (uint256);
}

interface ILeverageModel {
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
    function getMarketAdjustment(bytes32 marketId) external view returns (uint256);
    function getPlatformCeiling() external view returns (uint256);
}

contract DebugOldLeverageModel is Script {

    // The OLD LeverageModel that ExecutionEngine is actually using
    address constant OLD_LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;

    // Market IDs
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;

    function run() external {
        address oracleAdapter = vm.envAddress("ORACLE_ADAPTER");

        IOracleAdapter oracle = IOracleAdapter(oracleAdapter);
        ILeverageModel leverage = ILeverageModel(OLD_LEVERAGE_MODEL);

        console2.log("=== Debugging OLD LeverageModel (ExecutionEngine's Target) ===");
        console2.log("Oracle Adapter:", oracleAdapter);
        console2.log("Old LeverageModel:", OLD_LEVERAGE_MODEL);

        // Check platform ceiling
        console2.log("\n=== Platform Ceiling ===");
        try leverage.getPlatformCeiling() returns (uint256 ceiling) {
            console2.log("Platform Ceiling WAD:", ceiling);
            console2.log("Platform Ceiling (x):", ceiling / 1e18);
        } catch {
            console2.log("Platform Ceiling: ERROR");
        }

        // Check SpaceX market in detail
        console2.log("\n=== SpaceX Market Detail ===");
        _debugMarket(oracle, leverage, SPACEX_IPO, "SpaceX");

        // Check US-Iran market in detail
        console2.log("\n=== US-Iran Market Detail ===");
        _debugMarket(oracle, leverage, US_IRAN, "US-Iran");
    }

    function _debugMarket(
        IOracleAdapter oracle,
        ILeverageModel leverage,
        bytes32 marketId,
        string memory name
    ) internal view {
        console2.log("Market:", name);

        // Oracle data
        try oracle.getLatestPrice(marketId) returns (IOracleAdapter.PriceData memory price) {
            console2.log("Oracle PI:", price.pi / 1e16, "bps");
            console2.log("Oracle Depth:", price.depth / 1e18, "tokens");
            console2.log("Oracle Spread:", price.spread / 1e16, "bps");
            console2.log("Oracle Volume:", price.volume / 1e18, "tokens");
            console2.log("Oracle Confidence:", price.confidence / 1e16, "bps");
            console2.log("Oracle Timestamp:", price.timestamp);
        } catch {
            console2.log("Oracle data: ERROR");
        }

        try oracle.getVolatility(marketId) returns (uint256 vol) {
            console2.log("Oracle Volatility:", vol / 1e16, "bps");
        } catch {
            console2.log("Oracle Volatility: ERROR");
        }

        // LeverageModel data
        try leverage.getMarketAdjustment(marketId) returns (uint256 mMarket) {
            console2.log("M_market:", mMarket / 1e16, "bps");
        } catch {
            console2.log("M_market: ERROR");
        }

        try leverage.getEffectiveMaxLeverage(marketId) returns (uint256 maxLev) {
            console2.log("Max Leverage WAD:", maxLev);
            console2.log("Max Leverage (x):", maxLev / 1e18);

            if (maxLev >= 5e18) {
                console2.log("STATUS: GOOD (>= 5x)");
            } else {
                console2.log("STATUS: TOO LOW (< 5x)");
            }
        } catch {
            console2.log("Max Leverage: ERROR");
        }

        console2.log("---");
    }
}