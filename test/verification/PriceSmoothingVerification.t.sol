// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { OracleAdapter } from "../../contracts/core/OracleAdapter.sol";
import { MarketRegistry } from "../../contracts/core/MarketRegistry.sol";
import { IOracleAdapter } from "../../contracts/interfaces/IOracleAdapter.sol";
import { IMarketRegistry } from "../../contracts/interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "../../contracts/libraries/FixedPointMath.sol";

/// @title Price Smoothing Verification
/// @notice Comprehensive verification of OracleAdapter EMA smoothing with real-world price patterns
/// @dev Tests smoothing behavior with Polymarket-style price data sequences
contract PriceSmoothingVerificationTest is Test {
    using FixedPointMath for uint256;

    OracleAdapter public oracle;
    MarketRegistry public registry;

    address public admin = address(0xA);
    address public oracleRole = address(0xB);
    address public keeper = address(0xC);

    uint256 constant WAD = 1e18;
    bytes32 constant MARKET_ID = keccak256("ELECTION_MARKET");
    bytes32 constant VOLATILE_MARKET = keccak256("SPORTS_MARKET");

    uint256 public resolutionTime;

    function setUp() public {
        vm.warp(1_703_000_000); // Real timestamp ~Dec 2023
        resolutionTime = block.timestamp + 30 days;

        // Deploy contracts
        registry = new MarketRegistry(admin);
        oracle = new OracleAdapter(admin, address(registry));

        // Setup roles and sources
        vm.startPrank(admin);
        oracle.grantRole(oracle.ORACLE(), oracleRole);
        oracle.grantRole(oracle.KEEPER(), keeper);
        oracle.registerSource(oracleRole, WAD);

        // Create markets
        registry.createMarket(
            MARKET_ID,
            "2024 US Presidential Election",
            "polymarket-trump-biden-final",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
        registry.activateMarket(MARKET_ID);

        registry.createMarket(
            VOLATILE_MARKET,
            "NFL Chiefs Win Super Bowl",
            "polymarket-chiefs-superbowl",
            block.timestamp + 7 days,
            IMarketRegistry.MarketCategory.MEDIUM_LIQUIDITY,
            0.3e18
        );
        registry.activateMarket(VOLATILE_MARKET);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────
    // Real Price Sequences (Based on Polymarket Data)
    // ─────────────────────────────────────────────────────

    /// @dev Simulates election market price evolution over 24 hours
    function test_emaSmoothing_electionMarketSequence() public {
        // Real-world election market price sequence (similar to Trump vs Biden)
        // Starting at 51% and trending upward with some volatility
        uint256[] memory prices = new uint256[](48); // 30-min intervals
        uint256[] memory spreads = new uint256[](48);
        uint256[] memory volumes = new uint256[](48);

        // Initialize realistic sequence
        prices[0] = 0.510e18;   // 51.0%
        prices[1] = 0.512e18;   // +0.2%
        prices[2] = 0.508e18;   // -0.4%
        prices[3] = 0.515e18;   // +0.7%
        prices[4] = 0.520e18;   // +0.5%
        prices[5] = 0.518e18;   // -0.2%
        prices[6] = 0.525e18;   // +0.7%
        prices[7] = 0.530e18;   // +0.5%
        prices[8] = 0.528e18;   // -0.2%
        prices[9] = 0.535e18;   // +0.7%
        prices[10] = 0.540e18;  // +0.5%
        prices[11] = 0.545e18;  // +0.5%

        // Fill remaining with gradual trend + noise
        for (uint256 i = 12; i < 48; i++) {
            if (i % 3 == 0) {
                prices[i] = prices[i-1] + 0.002e18; // +0.2% trend
            } else if (i % 5 == 0) {
                prices[i] = prices[i-1] - 0.001e18; // -0.1% pullback
            } else {
                prices[i] = prices[i-1] + 0.001e18; // +0.1% continuation
            }
        }

        // Realistic spreads and volumes
        for (uint256 i = 0; i < 48; i++) {
            spreads[i] = 0.008e18 + (i % 3) * 0.001e18; // 0.8-1.0%
            volumes[i] = 50000e18 + (i % 7) * 10000e18;  // 50k-110k USDT
        }

        // Push sequence and verify smoothing behavior
        _pushPrice(MARKET_ID, prices[0], WAD - prices[0], spreads[0], 100000e18, volumes[0]);
        uint256 initialPI = oracle.getPI(MARKET_ID);
        assertEq(initialPI, prices[0], "First price should equal pRaw");

        uint256 maxSingleMove = 0;
        uint256 totalRawMove = 0;
        uint256 totalSmoothedMove = 0;

        for (uint256 i = 1; i < 24; i++) { // Test first 12 hours
            vm.warp(block.timestamp + 30 minutes);

            uint256 piBefore = oracle.getPI(MARKET_ID);
            _pushPrice(MARKET_ID, prices[i], WAD - prices[i], spreads[i], 100000e18, volumes[i]);
            uint256 piAfter = oracle.getPI(MARKET_ID);

            // Track movements
            uint256 rawMove = _absDiff(prices[i], prices[i-1]);
            uint256 smoothedMove = _absDiff(piAfter, piBefore);

            if (smoothedMove > maxSingleMove) {
                maxSingleMove = smoothedMove;
            }

            totalRawMove += rawMove;
            totalSmoothedMove += smoothedMove;

            // Verify smoothing constraints
            assertTrue(smoothedMove <= 0.01e18, "Single move exceeded epsilon");
            assertTrue(piAfter <= WAD, "PI above 1.0");
            assertTrue(piAfter >= 0, "PI below 0");

            emit log_named_decimal_uint("Block", block.timestamp, 0);
            emit log_named_decimal_uint("Raw Price", prices[i], 18);
            emit log_named_decimal_uint("Smoothed PI", piAfter, 18);
            emit log_named_decimal_uint("Raw Move", rawMove, 18);
            emit log_named_decimal_uint("Smoothed Move", smoothedMove, 18);
        }

        // Verify overall smoothing effectiveness
        assertTrue(totalSmoothedMove < totalRawMove, "Total smoothed movement should be less than raw");
        assertTrue(maxSingleMove <= 0.01e18, "Max single move should not exceed epsilon");

        uint256 finalPI = oracle.getPI(MARKET_ID);
        uint256 finalRaw = prices[23];

        // PI should be trending toward final raw price but lagging
        assertTrue(finalPI < finalRaw, "Smoothed PI should lag upward trend");
        assertTrue(finalPI > initialPI, "PI should move in trend direction");

        emit log_named_decimal_uint("Final Raw", finalRaw, 18);
        emit log_named_decimal_uint("Final PI", finalPI, 18);
        emit log_named_decimal_uint("Total Raw Movement", totalRawMove, 18);
        emit log_named_decimal_uint("Total Smoothed Movement", totalSmoothedMove, 18);
    }

    /// @dev Tests volatile sports market with sudden price spikes
    function test_emaSmoothing_volatileSportsMarket() public {
        // Sports market: news-driven volatility
        uint256[] memory prices = new uint256[](20);
        uint256[] memory spreads = new uint256[](20);

        // Normal trading
        prices[0] = 0.28e18;   // 28%
        prices[1] = 0.29e18;   // +1%
        prices[2] = 0.275e18;  // -1.5%
        prices[3] = 0.285e18;  // +1%

        // Sudden spike (news: key player injury)
        prices[4] = 0.35e18;   // +6.5% - REJECTED by deltaMax (5%)
        prices[5] = 0.32e18;   // +3.5% from previous valid
        prices[6] = 0.33e18;   // +1%

        // Consolidation
        prices[7] = 0.325e18;  // -0.5%
        prices[8] = 0.330e18;  // +0.5%
        prices[9] = 0.328e18;  // -0.2%

        // Wide spreads due to uncertainty
        for (uint256 i = 0; i < 10; i++) {
            spreads[i] = i < 4 ? 0.01e18 : 0.08e18; // Wide spreads after spike
        }

        // Initialize
        _pushPrice(VOLATILE_MARKET, prices[0], WAD - prices[0], spreads[0], 50000e18, 25000e18);

        uint256 rejectedCount = 0;
        uint256 acceptedCount = 1; // First update always accepted

        for (uint256 i = 1; i < 10; i++) {
            vm.warp(block.timestamp + 5 minutes);

            uint256 piBefore = oracle.getPI(VOLATILE_MARKET);

            // Check if this update should be rejected
            uint256 rawMove = _absDiff(prices[i], prices[i-1]);
            if (rawMove > 0.05e18) { // deltaMax = 5%
                // Should be rejected
                vm.expectEmit(true, false, false, false);
                emit IOracleAdapter.UpdateRejected(VOLATILE_MARKET, "TICK_TOO_LARGE", prices[i], block.timestamp);
                rejectedCount++;
            } else if (spreads[i] > 0.10e18) { // spreadLimit = 10%
                // Should be rejected for wide spread
                vm.expectEmit(true, false, false, false);
                emit IOracleAdapter.UpdateRejected(VOLATILE_MARKET, "SPREAD_TOO_WIDE", prices[i], block.timestamp);
                rejectedCount++;
            } else {
                acceptedCount++;
            }

            _pushPrice(VOLATILE_MARKET, prices[i], WAD - prices[i], spreads[i], 50000e18, 25000e18);

            uint256 piAfter = oracle.getPI(VOLATILE_MARKET);

            // If accepted, verify smoothing constraints
            if (rawMove <= 0.05e18 && spreads[i] <= 0.10e18) {
                uint256 piMove = _absDiff(piAfter, piBefore);
                assertTrue(piMove <= 0.01e18, "PI move exceeded epsilon");
            } else {
                // Should be rejected, PI unchanged
                assertEq(piAfter, piBefore, "PI should not change on rejection");
            }
        }

        assertTrue(rejectedCount > 0, "Should have rejected some updates");
        assertTrue(acceptedCount > rejectedCount, "Should accept more than reject");

        // Verify volatility built up
        uint256 sigma = oracle.getVolatility(VOLATILE_MARKET);
        assertGt(sigma, 0, "Volatility should increase");

        emit log_named_uint("Rejected updates", rejectedCount);
        emit log_named_uint("Accepted updates", acceptedCount);
        emit log_named_decimal_uint("Final volatility", sigma, 18);
    }

    /// @dev Tests convergence behavior over extended period
    function test_emaSmoothing_convergenceBehavior() public {
        // Simulate market trending from 45% to 55% over 2 hours
        uint256 startPrice = 0.45e18;
        uint256 targetPrice = 0.55e18;
        uint256 steps = 24; // 5-min intervals

        // Initialize
        _pushPrice(MARKET_ID, startPrice, WAD - startPrice, 0.01e18, 100000e18, 50000e18);

        uint256[] memory convergenceSteps = new uint256[](steps + 1);
        convergenceSteps[0] = oracle.getPI(MARKET_ID);

        // Push target price repeatedly
        for (uint256 i = 1; i <= steps; i++) {
            vm.warp(block.timestamp + 5 minutes);
            _pushPrice(MARKET_ID, targetPrice, WAD - targetPrice, 0.01e18, 100000e18, 50000e18);
            convergenceSteps[i] = oracle.getPI(MARKET_ID);

            // Verify monotonic convergence
            assertGe(convergenceSteps[i], convergenceSteps[i-1], "Should converge monotonically");
            assertLe(convergenceSteps[i], targetPrice, "Should not overshoot target");
        }

        uint256 finalPI = convergenceSteps[steps];
        uint256 convergencePercent = ((finalPI - startPrice) * 100e18) / (targetPrice - startPrice);

        // After 2 hours of consistent signal, should be 80%+ converged
        assertGe(convergencePercent, 80e18, "Should be 80%+ converged after 2 hours");

        emit log_named_decimal_uint("Start price", startPrice, 18);
        emit log_named_decimal_uint("Target price", targetPrice, 18);
        emit log_named_decimal_uint("Final PI", finalPI, 18);
        emit log_named_decimal_uint("Convergence %", convergencePercent, 18);
    }

    /// @dev Tests time weighting effect near resolution
    function test_emaSmoothing_timeWeightingNearResolution() public {
        // Create market with 2 hours left
        bytes32 nearMarket = keccak256("NEAR_RESOLUTION");
        vm.startPrank(admin);
        registry.createMarket(
            nearMarket,
            "Near Resolution Market",
            "polymarket-near",
            block.timestamp + 2 hours,
            IMarketRegistry.MarketCategory.LOW_LIQUIDITY,
            0.5e18
        );
        registry.activateMarket(nearMarket);
        vm.stopPrank();

        // Initialize both markets
        _pushPrice(MARKET_ID, 0.50e18, 0.50e18, 0.01e18, 100000e18, 50000e18); // 30 days left
        _pushPrice(nearMarket, 0.50e18, 0.50e18, 0.01e18, 100000e18, 50000e18); // 2 hours left

        // Move close to resolution (1 hour left)
        vm.warp(block.timestamp + 1 hours);

        // Push same update to both
        uint256 newPrice = 0.52e18; // +2% move
        _pushPrice(MARKET_ID, newPrice, WAD - newPrice, 0.01e18, 100000e18, 50000e18);
        _pushPrice(nearMarket, newPrice, WAD - newPrice, 0.01e18, 100000e18, 50000e18);

        uint256 piFar = oracle.getPI(MARKET_ID);
        uint256 piNear = oracle.getPI(nearMarket);

        // Far market should move more due to higher time weight
        assertGt(piFar, piNear, "Far market should move more");

        // Near-resolution market should have very light smoothing
        uint256 nearMove = piNear - 0.50e18;
        uint256 farMove = piFar - 0.50e18;

        assertTrue(nearMove < farMove, "Near market should move less");
        assertTrue(farMove > nearMove * 2, "Time weighting should be significant");

        emit log_named_decimal_uint("Far market PI", piFar, 18);
        emit log_named_decimal_uint("Near market PI", piNear, 18);
        emit log_named_decimal_uint("Far move", farMove, 18);
        emit log_named_decimal_uint("Near move", nearMove, 18);
    }

    /// @dev Tests confidence scoring with real market data quality
    function test_emaSmoothing_confidenceScoring() public {
        IOracleAdapter.SmoothingParams memory params = IOracleAdapter.SmoothingParams({
            alpha: 3e17,        // 0.30
            deltaMax: 5e16,     // 0.05
            epsilon: 1e16,      // 0.01
            spreadLimit: 1e17,  // 0.10
            depthMin: 50000e18  // 50k depth minimum
        });

        vm.prank(admin);
        oracle.updateSmoothingParams(MARKET_ID, params);

        // High quality update: tight spread, good depth, low vol
        _pushPrice(MARKET_ID, 0.50e18, 0.50e18, 0.005e18, 200000e18, 100000e18);
        IOracleAdapter.PriceData memory data1 = oracle.getLatestPrice(MARKET_ID);

        // Build some volatility
        vm.warp(block.timestamp + 60);
        _pushPrice(MARKET_ID, 0.52e18, 0.48e18, 0.006e18, 180000e18, 90000e18);

        vm.warp(block.timestamp + 60);
        _pushPrice(MARKET_ID, 0.48e18, 0.52e18, 0.007e18, 160000e18, 80000e18);

        // Low quality update: wide spread, low depth, high vol
        vm.warp(block.timestamp + 60);
        _pushPrice(MARKET_ID, 0.505e18, 0.495e18, 0.08e18, 30000e18, 20000e18);
        IOracleAdapter.PriceData memory data2 = oracle.getLatestPrice(MARKET_ID);

        // High quality should have higher confidence
        assertGt(data1.confidence, data2.confidence, "High quality should have higher confidence");

        // Low depth should result in lower confidence
        assertLt(data2.confidence, WAD / 2, "Low depth should reduce confidence");

        emit log_named_decimal_uint("High quality confidence", data1.confidence, 18);
        emit log_named_decimal_uint("Low quality confidence", data2.confidence, 18);
    }

    /// @dev Tests full smoothing pipeline with custom parameters
    function test_emaSmoothing_customParameters() public {
        // Conservative smoothing for stable market
        IOracleAdapter.SmoothingParams memory conservativeParams = IOracleAdapter.SmoothingParams({
            alpha: 1e17,        // 0.10 (low alpha = more smoothing)
            deltaMax: 2e16,     // 0.02 (tight tick limit)
            epsilon: 5e15,      // 0.005 (very small max change)
            spreadLimit: 5e16,  // 0.05 (tight spread limit)
            depthMin: 100000e18 // 100k depth requirement
        });

        vm.prank(admin);
        oracle.updateSmoothingParams(MARKET_ID, conservativeParams);

        // Initialize
        _pushPrice(MARKET_ID, 0.50e18, 0.50e18, 0.01e18, 150000e18, 100000e18);

        // Try small move (should be accepted)
        vm.warp(block.timestamp + 60);
        _pushPrice(MARKET_ID, 0.515e18, 0.485e18, 0.01e18, 150000e18, 100000e18);
        uint256 pi1 = oracle.getPI(MARKET_ID);
        uint256 move1 = pi1 - 0.50e18;

        // Move should be very small due to low alpha and tight epsilon
        assertLe(move1, 0.005e18, "Conservative params should limit movement");

        // Try larger move (should be rejected)
        vm.warp(block.timestamp + 60);
        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.UpdateRejected(MARKET_ID, "TICK_TOO_LARGE", 0.525e18, block.timestamp);
        _pushPrice(MARKET_ID, 0.525e18, 0.475e18, 0.01e18, 150000e18, 100000e18);

        uint256 pi2 = oracle.getPI(MARKET_ID);
        assertEq(pi2, pi1, "Rejected update should not change PI");

        // Try good move with wide spread (should be rejected)
        vm.warp(block.timestamp + 60);
        vm.expectEmit(true, false, false, false);
        emit IOracleAdapter.UpdateRejected(MARKET_ID, "SPREAD_TOO_WIDE", 0.510e18, block.timestamp);
        _pushPrice(MARKET_ID, 0.510e18, 0.490e18, 0.08e18, 150000e18, 100000e18);

        uint256 pi3 = oracle.getPI(MARKET_ID);
        assertEq(pi3, pi2, "Wide spread should be rejected");

        emit log_named_decimal_uint("Conservative move", move1, 18);
        assertLe(move1, 0.005e18, "Conservative settings should heavily smooth");
    }

    // ─────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────

    function _pushPrice(
        bytes32 marketId,
        uint256 pYes,
        uint256 pNo,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) internal {
        vm.prank(oracleRole);
        oracle.pushPrice(marketId, pYes, pNo, spread, depth, volume);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }
}