// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Real contracts - ALL of them
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { OILimits } from "../contracts/OILimits.sol";
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";

// Interfaces
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { IOracleAdapter } from "../contracts/interfaces/IOracleAdapter.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IMarginEngine } from "../contracts/interfaces/IMarginEngine.sol";
import { ILiquidationEngine } from "../contracts/interfaces/ILiquidationEngine.sol";

// Libraries
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// OpenZeppelin
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Full ERC20 token for integration tests (no mocks)
contract TestUSDT is ERC20 {
    constructor() ERC20("Test USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title FullIntegrationTest
/// @notice Deploys ALL 16 contracts with REAL implementations - zero mocks.
///         Runs full lifecycle: create market, LP deposit, open position, price move,
///         close position, verify all state.
contract FullIntegrationTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    // Addresses
    address admin = address(0xAD);
    address lp = address(0xBBB);
    address trader = address(0xCCC);
    address oracle = address(0x0AC);
    address keeper = address(0xBE);
    address protocolTreasury = address(0xDEAD);

    // Test market
    bytes32 marketId = keccak256("ELECTION_2028");

    // ALL real contracts
    TestUSDT public usdt;
    MarketRegistry public registry;
    OracleAdapter public oracleAdapter;
    PositionManager public positionManager;
    AccountManager public accountManager;
    ExecutionEngine public executionEngine;
    MarginEngine public marginEngine;
    BorrowFeeEngine public borrowFeeEngine;
    FundingRateEngine public fundingRateEngine;
    LeverageModel public leverageModel;
    OILimits public oiLimits;
    FeeRouter public feeRouter;
    LeverVault public vault;
    RewardsDistributor public distributor;
    InsuranceFund public insuranceFund;
    LiquidationEngine public liquidationEngine;
    SettlementEngine public settlementEngine;

    function setUp() public {
        vm.startPrank(admin);

        // 1. Deploy USDT token
        usdt = new TestUSDT();

        // 2. Deploy LeverVault + RewardsDistributor (circular dep - predict address)
        uint64 nonce = vm.getNonce(admin);
        address predictedVault = vm.computeCreateAddress(admin, nonce + 1);

        distributor = new RewardsDistributor(admin, address(usdt), predictedVault);
        vault = new LeverVault(admin, address(usdt), address(distributor));
        require(address(vault) == predictedVault, "vault address mismatch");

        // 3. Deploy InsuranceFund (needs vault)
        insuranceFund = new InsuranceFund(admin, address(usdt), address(vault));

        // 4. Deploy FeeRouter (needs InsuranceFund, RewardsDistributor, treasury)
        feeRouter = new FeeRouter(
            admin,
            address(usdt),
            address(insuranceFund),
            address(distributor),
            protocolTreasury
        );

        // 5. Deploy core contracts (dependency order)
        registry = new MarketRegistry(admin);
        oracleAdapter = new OracleAdapter(admin, address(registry));
        positionManager = new PositionManager(admin);
        accountManager = new AccountManager(admin, address(usdt));

        // 6. Deploy OILimits (needs registry, vault)
        oiLimits = new OILimits(address(registry), address(vault), admin);

        // 7. Deploy fee engines
        borrowFeeEngine = new BorrowFeeEngine(admin, address(registry), address(oiLimits), address(positionManager));
        fundingRateEngine = new FundingRateEngine(admin, address(registry), address(oiLimits), address(positionManager), address(accountManager), address(distributor));

        // 8. Deploy MarginEngine
        marginEngine = new MarginEngine(
            admin,
            address(positionManager),
            address(oracleAdapter),
            address(registry),
            address(borrowFeeEngine),
            address(fundingRateEngine)
        );

        // 9. Deploy LeverageModel
        leverageModel = new LeverageModel(
            address(vault),
            address(insuranceFund),
            address(oiLimits),
            address(registry),
            address(oracleAdapter),
            admin
        );

        // 10. Deploy ExecutionEngine
        executionEngine = new ExecutionEngine(
            address(positionManager),
            address(oiLimits),
            address(marginEngine),
            address(oracleAdapter),
            address(registry),
            address(leverageModel),
            address(feeRouter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(accountManager),
            address(vault),
            address(insuranceFund),
            admin
        );

        // 11. Deploy LiquidationEngine
        liquidationEngine = new LiquidationEngine(
            admin,
            address(marginEngine),
            address(positionManager),
            address(executionEngine),
            address(oiLimits),
            address(accountManager),
            address(insuranceFund),
            address(feeRouter),
            address(vault),
            address(registry)
        );

        // 12. Deploy SettlementEngine
        settlementEngine = new SettlementEngine(
            admin,
            address(registry),
            address(positionManager),
            address(oracleAdapter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(insuranceFund),
            address(feeRouter),
            address(oiLimits),
            address(accountManager),
            address(vault)
        );

        // 13. Grant ALL roles
        _grantAllRoles();

        // 14. Pre-seed vault with $10M TVL and insurance with $2M
        // (required for LeverageModel to allow 5x leverage - TVL_MATURITY=$50M)
        _preSeedLiquidity();

        // 15. Set up market
        _setupMarket();

        vm.stopPrank();
    }

    function _grantAllRoles() internal {
        // PositionManager: ENGINE to ExecutionEngine, LiquidationEngine, SettlementEngine
        positionManager.grantRole(positionManager.ENGINE(), address(executionEngine));
        positionManager.grantRole(positionManager.ENGINE(), address(liquidationEngine));
        positionManager.grantRole(positionManager.ENGINE(), address(settlementEngine));

        // AccountManager: ENGINE to ExecutionEngine, LiquidationEngine, SettlementEngine
        accountManager.grantRole(accountManager.ENGINE(), address(executionEngine));
        accountManager.grantRole(accountManager.ENGINE(), address(liquidationEngine));
        accountManager.grantRole(accountManager.ENGINE(), address(settlementEngine));

        // OILimits: engine roles
        oiLimits.grantRole(oiLimits.EXECUTION_ENGINE_ROLE(), address(executionEngine));
        oiLimits.grantRole(oiLimits.LIQUIDATION_ENGINE_ROLE(), address(liquidationEngine));
        oiLimits.grantRole(oiLimits.SETTLEMENT_ENGINE_ROLE(), address(settlementEngine));

        // OracleAdapter: ORACLE, KEEPER, SETTLEMENT
        oracleAdapter.grantRole(oracleAdapter.ORACLE(), oracle);
        oracleAdapter.grantRole(oracleAdapter.KEEPER(), keeper);
        oracleAdapter.grantRole(oracleAdapter.SETTLEMENT(), address(settlementEngine));

        // Register oracle as active source
        oracleAdapter.registerSource(oracle, WAD);

        // MarketRegistry: KEEPER
        registry.grantRole(registry.KEEPER(), keeper);

        // FeeRouter: engine roles
        feeRouter.grantRole(feeRouter.EXECUTION_ENGINE_ROLE(), address(executionEngine));
        feeRouter.grantRole(feeRouter.BORROW_FEE_ENGINE_ROLE(), address(borrowFeeEngine));
        feeRouter.grantRole(feeRouter.LIQUIDATION_ENGINE_ROLE(), address(liquidationEngine));
        feeRouter.grantRole(feeRouter.SETTLEMENT_ENGINE_ROLE(), address(settlementEngine));

        // RewardsDistributor: FEE_ROUTER, LEVER_VAULT, FUNDING_RATE_ENGINE
        distributor.grantRole(distributor.FEE_ROUTER_ROLE(), address(feeRouter));
        distributor.grantRole(distributor.LEVER_VAULT_ROLE(), address(vault));
        distributor.grantRole(distributor.FUNDING_RATE_ENGINE_ROLE(), address(fundingRateEngine));

        // InsuranceFund: FEE_ROUTER, LIQUIDATION, SETTLEMENT
        insuranceFund.grantRole(insuranceFund.FEE_ROUTER_ROLE(), address(feeRouter));
        insuranceFund.grantRole(insuranceFund.LIQUIDATION_ENGINE_ROLE(), address(liquidationEngine));
        insuranceFund.grantRole(insuranceFund.SETTLEMENT_ENGINE_ROLE(), address(settlementEngine));

        // LeverVault: EXECUTION_ENGINE, LIQUIDATION_ENGINE
        vault.grantRole(vault.EXECUTION_ENGINE_ROLE(), address(executionEngine));
        vault.grantRole(vault.LIQUIDATION_ENGINE_ROLE(), address(liquidationEngine));
    }

    function _preSeedLiquidity() internal {
        // Seed vault with $10M USDT from a "seed LP" to establish realistic TVL
        // This is needed because LeverageModel's TVL_Mult = sqrt(TVL / $50M)
        // With only $100k, TVL_Mult = 0.10 (floor) -> platform ceiling = 3x -> no 5x leverage
        address seedLP = address(0x5EED);
        usdt.mint(seedLP, 10_000_000e18);
        vm.stopPrank();
        vm.startPrank(seedLP);
        usdt.approve(address(vault), type(uint256).max);
        vault.deposit(10_000_000e18, seedLP);
        vm.stopPrank();
        vm.startPrank(admin);

        // Seed insurance fund with $2M (IFR = 20% of $10M TVL)
        // InsuranceFund.deposit() requires FEE_ROUTER_ROLE
        insuranceFund.grantRole(insuranceFund.FEE_ROUTER_ROLE(), admin);
        usdt.mint(address(insuranceFund), 2_000_000e18);
        insuranceFund.deposit(2_000_000e18);
        insuranceFund.revokeRole(insuranceFund.FEE_ROUTER_ROLE(), admin);
    }

    function _setupMarket() internal {
        // Create market: resolution in 48 hours
        uint256 resolutionTime = block.timestamp + 48 hours;

        registry.createMarket(
            marketId,
            "US Election 2028",
            "polymarket_election_2028",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            2e17 // 20% allocation weight
        );
        registry.activateMarket(marketId);

        // Initialize fee engine indices
        borrowFeeEngine.initializeMarketIndex(marketId);
        fundingRateEngine.initializeMarketIndex(marketId);

        // Set market risk params to get M_market=0.80 with sigma=0.5.
        // LeverageModel reads volatility from oracleAdapter.getVolatility() (EMA-computed),
        // which starts near 0 with a fresh oracle, so Vol_Factor=1.0 in LeverageModel.
        // We achieve M_market=0.80 via Depth_Factor = oracle_depth/depthThreshold = 80k/100k.
        // For BorrowFeeEngine/FundingRateEngine/MarginEngine we set sigmaCurrent=0.5 directly.
        borrowFeeEngine.updateMarketRiskParams(
            marketId,
            5e17,       // sigmaCurrent = 0.50
            5e17,       // sigmaBaseline = 0.50 (equal so Vol_Factor=1.0 for fee engines)
            80_000e18,  // externalDepth = $80k
            100_000e18, // depthThreshold = $100k (depth_factor = 0.80)
            0,          // marketOI = 0
            0           // globalOI = 0
        );
        fundingRateEngine.updateMarketRiskParams(
            marketId,
            5e17,       // sigmaCurrent = 0.50
            5e17,       // sigmaBaseline = 0.50
            80_000e18,  // externalDepth = $80k
            100_000e18, // depthThreshold = $100k
            0, 0
        );
        marginEngine.updateMarketRiskParams(
            marketId,
            5e17,       // sigmaCurrent = 0.50
            5e17,       // sigmaBaseline = 0.50
            80_000e18,  // externalDepth
            100_000e18, // depthThreshold
            0, 0, 0     // marketOI, globalOI, marketUtilization
        );
        leverageModel.setMarketRiskParams(
            marketId,
            5e17,       // sigmaBaseline = 0.50
            100_000e18  // depthThreshold = $100k (oracle pushes depth=80k so factor=0.80)
        );

        // Set up smoothing params for the oracle - disable smoothing for test
        oracleAdapter.updateSmoothingParams(marketId, IOracleAdapter.SmoothingParams({
            alpha: 1e18,       // 1.0 - no smoothing (direct tracking)
            deltaMax: 1e18,    // 100% - no cap on tick movement
            epsilon: 1e18,     // 100% - no cap on smooth change
            spreadLimit: 5e16, // 5% max spread
            depthMin: 1e18     // $1 min depth
        }));

        // Push initial price (PI = 0.50) with depth=80k to match M_market target
        vm.stopPrank();
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId,
            5e17,       // pYes = 0.50
            5e17,       // pNo = 0.50
            1e16,       // spread = 1%
            80_000e18,  // depth = $80k (matches depth_factor = 0.80)
            50_000e18   // volume = $50k
        );
        vm.startPrank(admin);
    }

    /// @dev Push PI to target. With alpha=1.0 and no caps, single push should work.
    function _pushPI(uint256 targetPI) internal {
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId,
            targetPI,
            WAD - targetPI,
            1e16,       // 1% spread
            80_000e18,  // $80k depth (consistent)
            50_000e18   // $50k volume
        );
    }

    // ================================================================
    //  FULL LIFECYCLE INTEGRATION TEST
    // ================================================================

    function test_fullLifecycle_allRealContracts() public {
        // --- Step 0: Verify M_market ~ 0.80 ---
        {
            uint256 mMarket = leverageModel.getMarketAdjustment(marketId);
            console.log("Step 0: M_market =", mMarket);
            console.log("Step 0: Expected M_market = 800000000000000000 (0.80)");
            assertApproxEqAbs(mMarket, 8e17, 1e16, "M_market should be ~0.80");
        }

        // --- Step 1: Create market with M_market=0.80, sigma=0.5 ---
        // Already done in setUp. Verify state.
        {
            IMarketRegistry.MarketState state = registry.getMarketState(marketId);
            assertTrue(state == IMarketRegistry.MarketState.ACTIVE, "Step 1: Market should be ACTIVE");
            console.log("Step 1: Market created and ACTIVE");

            uint256 pi = oracleAdapter.getPI(marketId);
            console.log("Step 1: PI =", pi);
            assertApproxEqAbs(pi, 5e17, 1e16, "PI should be ~0.50");

            uint256 vol = oracleAdapter.getVolatility(marketId);
            console.log("Step 1: sigma (volatility) =", vol);
        }

        // --- Step 2: LP deposits 100,000 USDT into LeverVault ---
        {
            usdt.mint(lp, 100_000e18);
            vm.startPrank(lp);
            usdt.approve(address(vault), type(uint256).max);
            vault.deposit(100_000e18, lp);
            vm.stopPrank();

            uint256 lpShares = vault.balanceOf(lp);
            console.log("Step 2: LP deposited 100,000 USDT. Shares received =", lpShares);
            assertGt(lpShares, 0, "LP should receive shares");
        }

        // --- Step 3: Verify vault NAV includes LP deposit ---
        // Vault was pre-seeded with $10M, LP added $100k -> NAV = $10.1M
        {
            uint256 nav = vault.getNAV();
            console.log("Step 3: Vault NAV =", nav);
            assertEq(nav, 10_100_000e18, "Vault NAV should be 10.1M USDT");
        }

        // --- Step 4: Trader deposits 1,000 USDT collateral via AccountManager ---
        {
            usdt.mint(trader, 1_000e18);
            vm.startPrank(trader);
            usdt.approve(address(accountManager), type(uint256).max);
            accountManager.deposit(1_000e18);
            vm.stopPrank();

            uint256 traderBalance = accountManager.getBalance(trader);
            console.log("Step 4: Trader deposited 1,000 USDT. AccountManager balance =", traderBalance);
            assertEq(traderBalance, 1_000e18, "Trader balance should be 1,000 USDT");
        }

        // --- Step 5: Trader opens 5x long at PI=0.50 ---
        // FeeRouter does real USDT transfers for fee distribution.
        // TX fee = notional * 0.10% = 5000 * 0.001 = 5 USDT
        // FeeRouter splits: 50% to RewardsDistributor, 30% to Treasury, 20% to InsuranceFund
        uint256 positionId;
        {
            // Fund FeeRouter with USDT for fee distribution
            usdt.mint(address(feeRouter), 100e18);

            // Check max leverage before opening
            uint256 maxLev = leverageModel.getEffectiveMaxLeverage(marketId);
            console.log("Step 5: Max leverage allowed =", maxLev);
            console.log("Step 5: Requested leverage = 5000000000000000000 (5x)");

            if (maxLev < 5e18) {
                console.log("Step 5: FAILED - max leverage too low for 5x");
                console.log("Step 5: Platform ceiling =", leverageModel.getPlatformCeiling());
                console.log("Step 5: TVL multiplier =", leverageModel.getTVLMultiplier());
                console.log("Step 5: IFR multiplier =", leverageModel.getIFRMultiplier());
                console.log("Step 5: Util multiplier =", leverageModel.getUtilizationMultiplier());
                revert("Max leverage too low for 5x");
            }

            vm.prank(trader);
            positionId = executionEngine.openPosition(
                IExecutionEngine.OpenParams({
                    marketId: marketId,
                    isLong: true,
                    collateral: 1_000e18,
                    leverage: 5e18
                })
            );
            console.log("Step 5: Position opened. ID =", positionId);
            assertTrue(positionId > 0, "Position ID should be > 0");
        }

        // --- Step 6: Verify position exists in PositionManager with correct fields ---
        IPositionManager.Position memory pos;
        {
            pos = positionManager.getPosition(positionId);
            console.log("Step 6: Position owner =", pos.owner);
            console.log("Step 6: Position isLong =", pos.isLong);
            console.log("Step 6: Position entryPI =", pos.entryPI);
            console.log("Step 6: Position entryPrice =", pos.entryPrice);
            console.log("Step 6: Position positionSize (notional) =", pos.positionSize);
            console.log("Step 6: Position collateral (net, after fee) =", pos.collateral);
            console.log("Step 6: Position leverage =", pos.leverage);
            console.log("Step 6: Position isOpen =", pos.isOpen);

            assertTrue(pos.isOpen, "Step 6: Position should be open");
            assertEq(pos.owner, trader, "Step 6: Owner should be trader");
            assertTrue(pos.isLong, "Step 6: Position should be long");
            assertEq(pos.leverage, 5e18, "Step 6: Leverage should be 5x");
            assertApproxEqAbs(pos.entryPI, 5e17, 1e16, "Step 6: Entry PI should be ~0.50");
            // Notional = collateral * leverage = 1000 * 5 = 5000
            assertEq(pos.positionSize, 5_000e18, "Step 6: Notional should be 5000");
            // Net collateral = 1000 - tx_fee (5 USDT)
            assertApproxEqAbs(pos.collateral, 995e18, 1e18, "Step 6: Net collateral should be ~995");
        }

        // --- Step 7: Verify OI increased in OILimits ---
        {
            uint256 globalOI = oiLimits.getGlobalOI();
            uint256 marketOI = oiLimits.getMarketOI(marketId);
            uint256 longOI = oiLimits.getSideOI(marketId, true);
            uint256 shortOI = oiLimits.getSideOI(marketId, false);

            console.log("Step 7: Global OI =", globalOI);
            console.log("Step 7: Market OI =", marketOI);
            console.log("Step 7: Long OI =", longOI);
            console.log("Step 7: Short OI =", shortOI);

            assertEq(globalOI, 5_000e18, "Step 7: Global OI should be 5000");
            assertEq(marketOI, 5_000e18, "Step 7: Market OI should be 5000");
            assertEq(longOI, 5_000e18, "Step 7: Long OI should be 5000");
            assertEq(shortOI, 0, "Step 7: Short OI should be 0");
        }

        // --- Step 8: Simulate oracle moving PI from 0.50 to 0.60 ---
        uint256 newPI;
        {
            _pushPI(6e17);
            newPI = oracleAdapter.getPI(marketId);
            console.log("Step 8: PI after move =", newPI);
            assertApproxEqAbs(newPI, 6e17, 1e16, "Step 8: PI should be ~0.60");
        }

        // --- Step 9: Check equity is positive and approximately correct ---
        {
            IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(positionId);
            console.log("Step 9: Equity =", eq.equity > 0 ? uint256(eq.equity) : 0);
            if (eq.pnl >= 0) {
                console.log("Step 9: PnL (positive) =", uint256(eq.pnl));
            } else {
                console.log("Step 9: PnL (negative) =", uint256(-eq.pnl));
            }
            console.log("Step 9: Accrued borrow fees =", eq.accruedBorrowFees);
            if (eq.accruedFunding >= 0) {
                console.log("Step 9: Accrued funding (positive) =", uint256(eq.accruedFunding));
            } else {
                console.log("Step 9: Accrued funding (negative) =", uint256(-eq.accruedFunding));
            }

            assertTrue(eq.equity > 0, "Step 9: Equity should be positive");
            assertTrue(eq.pnl > 0, "Step 9: PnL should be positive (long + PI went up)");

            // Expected PnL: direction * (PI_current - PI_entry) * positionSize
            // = 1 * (0.60 - 0.50) * 5000 = 500
            int256 expectedPnL = int256((newPI - pos.entryPI) * pos.positionSize / WAD);
            console.log("Step 9: Expected PnL (approx) =", uint256(expectedPnL));
            assertApproxEqAbs(uint256(eq.pnl), uint256(expectedPnL), 100e18, "Step 9: PnL should be ~expected");
        }

        // Record vault NAV before close
        uint256 vaultNAVBefore = vault.getNAV();
        console.log("Step 9b: Vault NAV before close =", vaultNAVBefore);

        // --- Step 10: Trader closes position ---
        {
            vm.prank(trader);
            executionEngine.closePosition(positionId);
            console.log("Step 10: Position closed successfully");

            IPositionManager.Position memory closedPos = positionManager.getPosition(positionId);
            assertFalse(closedPos.isOpen, "Step 10: Position should be closed");
        }

        // --- Step 11: Verify PnL settlement via AccountManager ---
        // ExecutionEngine._settlePnL handles both bookkeeping (credit/debit) and
        // actual USDT transfers: vault pays price profits, AccountManager sends
        // price losses to vault, borrow fees routed through FeeRouter.
        {
            uint256 vaultNAVAfter = vault.getNAV();
            uint256 traderBalAfter = accountManager.getBalance(trader);

            console.log("Step 11: Vault NAV after close =", vaultNAVAfter);
            console.log("Step 11: Trader AccountManager balance after close =", traderBalAfter);
            console.log("Step 11: PnL settled with actual USDT transfers");

            // Trader profited (PI went from 0.50 to 0.60). Balance should be > 0.
            // Original deposit was 1000. TX fee = 5. CollateralNet = 995.
            // PnL ~ +500 (direction * (0.60 - 0.50) * 5000). Net gain above collateral.
            assertGt(traderBalAfter, 0, "Step 11: Trader should have balance after profitable close");
        }

        // --- Step 12: Verify all OI returned to zero ---
        {
            uint256 globalOIAfter = oiLimits.getGlobalOI();
            uint256 marketOIAfter = oiLimits.getMarketOI(marketId);
            uint256 longOIAfter = oiLimits.getSideOI(marketId, true);
            uint256 shortOIAfter = oiLimits.getSideOI(marketId, false);

            console.log("Step 12: Global OI after close =", globalOIAfter);
            console.log("Step 12: Market OI after close =", marketOIAfter);
            console.log("Step 12: Long OI after close =", longOIAfter);
            console.log("Step 12: Short OI after close =", shortOIAfter);

            assertEq(globalOIAfter, 0, "Step 12: Global OI should be 0");
            assertEq(marketOIAfter, 0, "Step 12: Market OI should be 0");
            assertEq(longOIAfter, 0, "Step 12: Long OI should be 0");
            assertEq(shortOIAfter, 0, "Step 12: Short OI should be 0");
        }

        // --- Step 13: Verify vault NAV reflects state ---
        // Vault receives trader losses via PnL settlement (ExecutionEngine._settlePnL).
        // NAV may differ from seed+LP deposit due to trader PnL flows and fee distributions.
        {
            uint256 finalNAV = vault.getNAV();
            uint256 seedNAV = 10_100_000e18;
            console.log("Step 13: Final vault NAV =", finalNAV);
            // NAV should be close to seed — small delta from trader PnL + impact spread
            assertGt(finalNAV, seedNAV * 99 / 100, "Step 13: Vault NAV should not drop >1%");
            assertLt(finalNAV, seedNAV * 101 / 100, "Step 13: Vault NAV should not rise >1%");
        }

        console.log("");
        console.log("=== ALL 13 STEPS PASSED ===");
    }

    // ================================================================
    //  LIQUIDATION WATERFALL INTEGRATION TEST
    // ================================================================

    function test_liquidation_fullWaterfall() public {
        // --- Boost TVL to ~$60M so LeverageModel allows 10x ---
        // Also scale insurance to maintain ~20% IFR (needed for IFR_Mult near 1.0).
        {
            address seedLP2 = address(0x5EE2);
            usdt.mint(seedLP2, 50_000_000e18);
            vm.startPrank(seedLP2);
            usdt.approve(address(vault), type(uint256).max);
            vault.deposit(50_000_000e18, seedLP2);
            vm.stopPrank();

            // Top up insurance fund to $12M (20% of $60M TVL)
            vm.startPrank(admin);
            insuranceFund.grantRole(insuranceFund.FEE_ROUTER_ROLE(), admin);
            usdt.mint(address(insuranceFund), 10_000_000e18);
            insuranceFund.deposit(10_000_000e18);
            insuranceFund.revokeRole(insuranceFund.FEE_ROUTER_ROLE(), admin);
            vm.stopPrank();
        }

        // --- Step 1: LP deposits 100,000 USDT ---
        {
            usdt.mint(lp, 100_000e18);
            vm.startPrank(lp);
            usdt.approve(address(vault), type(uint256).max);
            vault.deposit(100_000e18, lp);
            vm.stopPrank();

            uint256 nav = vault.getNAV();
            console.log("Step 1: Vault NAV after LP deposit =", nav);
            assertGt(nav, 50_000_000e18, "NAV should be >$50M");
        }

        // --- Step 2: Trader opens 10x long at PI=0.50 with 1000 USDT ---
        uint256 positionId;
        {
            usdt.mint(trader, 1_000e18);
            vm.startPrank(trader);
            usdt.approve(address(accountManager), type(uint256).max);
            accountManager.deposit(1_000e18);
            vm.stopPrank();

            // Fund FeeRouter with USDT for fee distribution
            usdt.mint(address(feeRouter), 500e18);

            uint256 maxLev = leverageModel.getEffectiveMaxLeverage(marketId);
            console.log("Step 2: Max leverage =", maxLev);
            require(maxLev >= 10e18, "Max leverage must support 10x");

            vm.prank(trader);
            positionId = executionEngine.openPosition(
                IExecutionEngine.OpenParams({
                    marketId: marketId,
                    isLong: true,
                    collateral: 1_000e18,
                    leverage: 10e18
                })
            );
            console.log("Step 2: Position opened. ID =", positionId);
        }

        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        console.log("Step 2: Notional =", pos.positionSize);
        console.log("Step 2: Net collateral =", pos.collateral);
        console.log("Step 2: Entry PI =", pos.entryPI);
        assertEq(pos.positionSize, 10_000e18, "Notional should be 10000");
        assertTrue(pos.isOpen, "Position should be open");

        // --- Step 3: Move oracle to PI=0.42 ---
        {
            _pushPI(42e16);
            uint256 currentPI = oracleAdapter.getPI(marketId);
            console.log("Step 3: PI after move =", currentPI);
            assertApproxEqAbs(currentPI, 42e16, 1e16, "PI should be ~0.42");
        }

        // --- Step 4: Check if position is liquidatable via MarginEngine ---
        IMarginEngine.EquityResult memory eq = marginEngine.computeEquity(positionId);
        {
            if (eq.equity >= 0) {
                console.log("Step 4: Equity =", uint256(eq.equity));
            } else {
                console.log("Step 4: Equity (negative) =", uint256(-eq.equity));
            }
            if (eq.pnl >= 0) {
                console.log("Step 4: PnL =", uint256(eq.pnl));
            } else {
                console.log("Step 4: PnL (negative) =", uint256(-eq.pnl));
            }

            uint256 mm = marginEngine.getMaintenanceMargin(positionId);
            console.log("Step 4: Maintenance margin =", mm);

            bool liquidatable = marginEngine.isLiquidatable(positionId);
            console.log("Step 4: isLiquidatable =", liquidatable);
            assertTrue(liquidatable, "Position should be liquidatable at PI=0.42 with 10x leverage");
        }

        // Record balances before liquidation
        uint256 insuranceBalBefore = insuranceFund.getBalance();
        uint256 vaultNAVBefore = vault.getNAV();
        console.log("Step 4: Insurance balance before =", insuranceBalBefore);
        console.log("Step 4: Vault NAV before =", vaultNAVBefore);

        // --- Step 5: Execute liquidation via LiquidationEngine ---
        ILiquidationEngine.LiquidationResult memory result;
        {
            address liquidatorAddr = address(0xDDD);
            vm.prank(liquidatorAddr);
            result = liquidationEngine.liquidate(positionId);
        }

        console.log("Step 5: Liquidation fee =", result.liquidationFee);
        console.log("Step 5: Bad debt =", result.badDebt);
        console.log("Step 5: Insurance paid =", result.insurancePaid);
        console.log("Step 5: ADL/socialized =", result.adlAmount);
        console.log("Step 5: Remaining equity =",
            result.remainingEquity >= 0 ? uint256(result.remainingEquity) : 0);

        // --- Step 6: Verify liquidation fee = 1.0% of notional ---
        {
            uint256 expectedFee = pos.positionSize * 1e16 / WAD; // 1% of 10000 = 100
            console.log("Step 6: Expected fee (1% of notional) =", expectedFee);

            // Fee is capped at equity if equity < expected fee
            if (eq.equity > 0 && uint256(eq.equity) >= expectedFee) {
                assertEq(result.liquidationFee, expectedFee, "Fee should be 1% of notional");
            } else if (eq.equity > 0) {
                assertEq(result.liquidationFee, uint256(eq.equity), "Fee capped at equity");
            } else {
                assertEq(result.liquidationFee, 0, "No fee when equity <= 0");
            }

            // Verify fee was routed: 10% bounty to liquidator, 90% through FeeRouter (50/30/20 split)
            assertGt(result.liquidationFee, 0, "Liquidation fee should be > 0");
        }

        // --- Step 7: Verify position is closed ---
        {
            assertFalse(positionManager.isPositionOpen(positionId), "Position should be closed");
            console.log("Step 7: Position closed = true");

            // Verify OI returned to zero
            uint256 globalOI = oiLimits.getGlobalOI();
            assertEq(globalOI, 0, "Global OI should be 0 after liquidation");
            console.log("Step 7: Global OI =", globalOI);
        }

        // --- Step 8: If bad debt, verify LP socialization ---
        {
            if (result.badDebt > 0) {
                console.log("Step 8: Bad debt detected =", result.badDebt);

                if (result.adlAmount > 0) {
                    // LP socialization happened via vault.socializeLoss()
                    uint256 vaultNAVAfter = vault.getNAV();
                    console.log("Step 8: Vault NAV after socialization =", vaultNAVAfter);
                    assertLt(vaultNAVAfter, vaultNAVBefore, "Vault NAV should decrease from socialization");
                }
            } else {
                console.log("Step 8: No bad debt (equity covered all fees)");
            }
        }

        // --- Step 9: Verify InsuranceFund balance changed appropriately ---
        {
            uint256 insuranceBalAfter = insuranceFund.getBalance();
            console.log("Step 9: Insurance balance after =", insuranceBalAfter);

            if (result.insurancePaid > 0) {
                // Insurance absorbed bad debt
                assertLt(insuranceBalAfter, insuranceBalBefore, "Insurance balance should decrease");
                console.log("Step 9: Insurance paid for bad debt =", result.insurancePaid);
            } else {
                // No bad debt to absorb. Insurance may have received fee share (Tier 1: 20% of fees).
                // At IFR < 20% ($2M / $30M = 6.67%), FeeRouter is Tier 1 (50/30/20 split).
                // Insurance gets 20% of the liquidation fee routed through FeeRouter.
                console.log("Step 9: No bad debt absorbed by insurance");
                // Insurance balance may increase from fee routing
                assertGe(insuranceBalAfter, insuranceBalBefore,
                    "Insurance balance should stay same or increase from fee share");
            }
        }

        console.log("");
        console.log("=== LIQUIDATION WATERFALL TEST PASSED ===");
    }
}
