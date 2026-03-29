// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { IOracleAdapter } from "../contracts/interfaces/IOracleAdapter.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { OILimits } from "../contracts/OILimits.sol";

/// @title ConfigureMarketRiskParams
/// @notice Sets depthThreshold and risk parameters for all registered markets across all engines.
///         Run BEFORE deploying the gate check in ExecutionEngine to avoid blocking opens.
///
/// Usage:
///   forge script script/ConfigureMarketRiskParams.s.sol --rpc-url $RPC_URL --broadcast
///
/// NOTE: This script reads oracle depth data via oracleAdapter.getLatestPrice().depth.
///       If a market has no oracle data yet, it uses DEFAULT_DEPTH as fallback.
contract ConfigureMarketRiskParams is Script {

    // ── Defaults ──
    uint256 constant DEFAULT_SIGMA      = 1e17;     // 10% baseline volatility
    uint256 constant DEFAULT_DEPTH      = 50_000e18; // $50K default depth (WAD)

    // ── Deployed addresses (read from env or hardcode for testnet) ──
    // These should match deploy-env.sh values
    address constant MARGIN_ENGINE      = address(0); // TODO: fill from deploy-env.sh
    address constant BORROW_FEE_ENGINE  = address(0);
    address constant FUNDING_RATE_ENGINE = address(0);
    address constant ORACLE_ADAPTER     = address(0);
    address constant MARKET_REGISTRY    = address(0);
    address constant OI_LIMITS          = address(0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MarginEngine margin       = MarginEngine(MARGIN_ENGINE);
        BorrowFeeEngine borrow    = BorrowFeeEngine(BORROW_FEE_ENGINE);
        FundingRateEngine funding  = FundingRateEngine(FUNDING_RATE_ENGINE);
        IOracleAdapter oracle     = IOracleAdapter(ORACLE_ADAPTER);
        IMarketRegistry registry  = IMarketRegistry(MARKET_REGISTRY);
        OILimits oiLimits         = OILimits(OI_LIMITS);

        bytes32[] memory markets = registry.getActiveMarkets();
        uint256 globalOI = oiLimits.getGlobalOI();

        console2.log("Configuring risk params for", markets.length, "markets");

        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 mktId = markets[i];

            // Read oracle depth (fallback to default if no data)
            uint256 depth;
            try oracle.getLatestPrice(mktId) returns (IOracleAdapter.PriceData memory data) {
                depth = data.depth > 0 ? data.depth : DEFAULT_DEPTH;
            } catch {
                depth = DEFAULT_DEPTH;
            }

            uint256 marketOI = oiLimits.getMarketOI(mktId);

            // Set depthThreshold = depth (Depth_Factor = 1.0 when depth matches threshold)
            margin.updateMarketRiskParams(
                mktId, DEFAULT_SIGMA, DEFAULT_SIGMA, depth, depth, marketOI, globalOI, 0
            );
            borrow.updateMarketRiskParams(
                mktId, DEFAULT_SIGMA, DEFAULT_SIGMA, depth, depth, marketOI, globalOI
            );
            funding.updateMarketRiskParams(
                mktId, DEFAULT_SIGMA, DEFAULT_SIGMA, depth, depth, marketOI, globalOI
            );

            console2.log("  Configured market", i);
            console2.log("    depth:", depth);
            console2.log("    marketOI:", marketOI);
        }

        console2.log("Done. Configured", markets.length, "markets across 3 engines.");

        vm.stopBroadcast();
    }
}
