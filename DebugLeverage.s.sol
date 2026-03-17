// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/LeverageModelFixed.sol";
import "./contracts/interfaces/ILeverVault.sol";
import "./contracts/interfaces/IInsuranceFund.sol";
import "./contracts/interfaces/IOILimits.sol";
import "./contracts/interfaces/IMarketRegistry.sol";
import "./contracts/interfaces/IOracleAdapter.sol";

contract DebugLeverage is Script {

    // Demo markets
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant NOTHING_EVER = 0x000000000000000000000000b072263740d7c60f1aa0bf46e737f83544c7b785;

    function run() external {
        address leverageModel = vm.envAddress("LEVERAGE_MODEL");
        address vault = vm.envAddress("LEVER_VAULT");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address oiLimits = vm.envAddress("OI_LIMITS");
        address marketRegistry = vm.envAddress("MARKET_REGISTRY");
        address oracleAdapter = vm.envAddress("ORACLE_ADAPTER");

        LeverageModelFixed lm = LeverageModelFixed(leverageModel);
        ILeverVault v = ILeverVault(vault);
        IInsuranceFund ifund = IInsuranceFund(insuranceFund);
        IOILimits oil = IOILimits(oiLimits);
        IMarketRegistry mr = IMarketRegistry(marketRegistry);
        IOracleAdapter oa = IOracleAdapter(oracleAdapter);

        console.log("=== PLATFORM CEILING FACTORS ===");
        console.log("TVL (vault.totalAssets):", v.totalAssets() / 1e6, "USDT");
        console.log("Insurance balance:", ifund.getBalance() / 1e6, "USDT");
        console.log("Global utilization:", oil.getGlobalUtilization() / 1e16, "bps");
        console.log("");

        console.log("TVL Multiplier:", lm.getTVLMultiplier() / 1e16, "bps");
        console.log("IFR Multiplier:", lm.getIFRMultiplier() / 1e16, "bps");
        console.log("Util Multiplier:", lm.getUtilizationMultiplier() / 1e16, "bps");
        console.log("Platform Ceiling:", lm.getPlatformCeiling() / 1e18, "x");
        console.log("");

        // Check individual markets
        bytes32[3] memory markets = [SPACEX_IPO, US_IRAN, NOTHING_EVER];
        string[3] memory names = ["SpaceX", "US-Iran", "Nothing-Ever"];

        for (uint i = 0; i < 3; i++) {
            bytes32 marketId = markets[i];
            string memory name = names[i];

            console.log("=== MARKET:", name, "===");

            try mr.getTau(marketId) returns (uint256 tau) {
                console.log("Tau (hours):", tau / 1e18);
            } catch {
                console.log("Tau: NOT_FOUND");
            }

            try mr.isLive(marketId) returns (bool isLive) {
                console.log("Is Live:", isLive);
            } catch {
                console.log("Is Live: NOT_FOUND");
            }

            try oa.getVolatility(marketId) returns (uint256 vol) {
                console.log("Volatility:", vol / 1e16, "bps");
            } catch {
                console.log("Volatility: ERROR");
            }

            try oa.getLatestPrice(marketId) returns (IOracleAdapter.PriceData memory price) {
                console.log("PI:", price.pi / 1e16, "bps");
                console.log("Depth:", price.depth / 1e18, "tokens");
            } catch {
                console.log("PI/Depth: ERROR");
            }

            try oil.getMarketOI(marketId) returns (uint256 marketOI) {
                console.log("Market OI:", marketOI / 1e18, "tokens");
            } catch {
                console.log("Market OI: ERROR");
            }

            try lm.getMarketAdjustment(marketId) returns (uint256 mMarket) {
                console.log("M_market:", mMarket / 1e16, "bps");
            } catch {
                console.log("M_market: ERROR");
            }

            try lm.getEffectiveMaxLeverage(marketId) returns (uint256 maxLev) {
                console.log("Max Leverage:", maxLev / 1e18, "x");
            } catch {
                console.log("Max Leverage: ERROR");
            }

            console.log("---");
        }
    }
}