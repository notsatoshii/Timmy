// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../integration/IntegrationBase.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";
import "../../contracts/interfaces/IMarginEngine.sol";

/// @title DepthThresholdTest
/// @notice Regression tests for LEVER-BUG-7: Zero liquidations caused by unset depthThreshold.
///
/// Root cause: depthThreshold=0 across engines causes M_market=1.0 (no market risk adjustment),
/// making maintenance margins too lenient to trigger liquidations. Guard clauses (P01/P02) prevent
/// keeper reverts, but do not fix the underlying MM calibration.
///
/// Fix: Gate check in ExecutionEngine.openPosition rejects positions on unconfigured markets
/// (depthThreshold=0 in MarginEngine). Configuration script sets proper depthThreshold values.
contract DepthThresholdTest is IntegrationBase {

    uint256 constant COLLATERAL = 1_000e18;
    uint256 constant LEVERAGE   = 5e18; // 5x

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Gate check blocks positions on unconfigured markets
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Markets with depthThreshold=0 must reject openPosition.
    ///         This prevents positions from opening in a state where liquidations cannot fire.
    function test_BUG7_gateCheckBlocksUnconfiguredMarket() public {
        // Create a new market without configuring depthThreshold
        bytes32 unconfiguredMarket = keccak256("UNCONFIGURED_MKT");

        vm.startPrank(admin);
        registry.createMarket(
            unconfiguredMarket,
            "Unconfigured Market",
            "polymarket_unconfigured",
            block.timestamp + 48 hours,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            2e17
        );
        registry.activateMarket(unconfiguredMarket);

        // Initialize fee engine indices (required by openPosition flow)
        borrowFeeEngine.initializeMarketIndex(unconfiguredMarket);
        fundingRateEngine.initializeMarketIndex(unconfiguredMarket);

        // Push a price so oracle is not frozen
        vm.stopPrank();
        vm.prank(oracle);
        oracleAdapter.pushPrice(unconfiguredMarket, 5e17, 5e17, 1e16, 100_000e18, 50_000e18);

        // DO NOT set depthThreshold on MarginEngine (it stays 0)

        // Fund alice
        _fundUser(alice, COLLATERAL);

        // openPosition must revert with MarketNotConfigured
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__MarketNotConfigured.selector, unconfiguredMarket)
        );
        vm.prank(alice);
        executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId:   unconfiguredMarket,
            isLong:     true,
            collateral: COLLATERAL,
            leverage:   LEVERAGE
        }));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Configured markets allow position opens
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The default test market (from IntegrationBase) has depthThreshold set
    ///         to 100_000e18 via setUp. Position open must succeed.
    function test_BUG7_configuredMarketAllowsOpen() public {
        // IntegrationBase sets depthThreshold=100_000e18 for the test market
        uint256 dt = marginEngine.depthThreshold(marketId);
        assertGt(dt, 0, "Test market must have depthThreshold configured");

        // Position open succeeds
        uint256 posId = _openPosition(alice, true, COLLATERAL, LEVERAGE);
        assertGt(posId, 0, "Position must be created on configured market");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: Liquidation works with configured depth
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice With proper depthThreshold, a leveraged position moving against the trader
    ///         should become liquidatable when equity drops below maintenance margin.
    function test_BUG7_liquidationWorksWithConfiguredDepth() public {
        // Widen smoothing params to allow large PI moves (for test only)
        vm.prank(admin);
        oracleAdapter.updateSmoothingParams(marketId, IOracleAdapter.SmoothingParams({
            alpha: 9e17,       // 0.9 = near-instant smoothing
            deltaMax: 5e17,    // 50% max tick
            epsilon: 5e17,     // 50% max change per update
            spreadLimit: 5e16, // 5% max spread
            depthMin: 1e18     // $1 min depth
        }));

        // Open a 5x long at PI=0.50
        uint256 posId = _openPosition(alice, true, COLLATERAL, LEVERAGE);

        // Advance time and push PI down aggressively to trigger liquidation
        // Multiple pushes with time gaps to overcome any remaining smoothing
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 60);
            _pushPI(10e16); // PI toward 0.10
        }

        uint256 currentPI = oracleAdapter.getPI(marketId);
        // With widened smoothing (alpha=0.9, epsilon=50%), PI should be near 0.10
        assertLt(currentPI, 25e16, "PI should have dropped below 0.25");

        // With 5x leverage, deeply underwater, must be liquidatable
        bool liquidatable = marginEngine.isLiquidatable(posId);
        assertTrue(liquidatable, "Position should be liquidatable after large adverse price move");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: BorrowFeeEngine does not revert on zero depthThreshold (P01/P02 guards)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Guard clauses (P01/P02) prevent keeper crashes when depthThreshold=0.
    ///         The borrow rate is computed with M_market=1.0 (default), not reverting.
    function test_BUG7_borrowFeeDoesNotRevertOnZeroDepth() public {
        // Set depthThreshold to 0 for the market in BorrowFeeEngine
        vm.prank(admin);
        borrowFeeEngine.updateMarketRiskParams(
            marketId,
            1e17, 1e17,     // sigma
            100_000e18,     // externalDepth
            0,              // depthThreshold = 0 (unconfigured)
            0, 0            // OI
        );

        // getCurrentBorrowRate should NOT revert (P02 guard catches it)
        uint256 rate = borrowFeeEngine.getCurrentBorrowRate(marketId, true);
        // Rate should still be computed (with M_market=1.0 default)
        assertGt(rate, 0, "Borrow rate must be computed even with depthThreshold=0 (guard clause)");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: FundingRateEngine does not revert on zero depthThreshold
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Same as test 4 but for FundingRateEngine (P01 guard).
    function test_BUG7_fundingRateDoesNotRevertOnZeroDepth() public {
        // Set depthThreshold to 0 for the market in FundingRateEngine
        vm.prank(admin);
        fundingRateEngine.updateMarketRiskParams(
            marketId,
            1e17, 1e17,     // sigma
            100_000e18,     // externalDepth
            0,              // depthThreshold = 0 (unconfigured)
            0, 0            // OI
        );

        // Calling the funding rate computation should NOT revert
        // We test this by accruing the index (the keeper operation that was crashing)
        vm.prank(admin);
        fundingRateEngine.accrueFunding(marketId);
        // If we reach here without revert, the guard clause works
    }
}
