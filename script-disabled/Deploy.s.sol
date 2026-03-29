// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Libraries
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";
import { RiskCurves } from "../contracts/libraries/RiskCurves.sol";
import { ProbabilityIndex } from "../contracts/libraries/ProbabilityIndex.sol";

// Core contracts - Phase 1: Foundation
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";

// Phase 2: Oracle
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";

// Phase 3: Risk & Leverage
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { OILimits } from "../contracts/OILimits.sol";

// Phase 4: Fee Engines
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";

// Phase 5: Margin & Execution
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";

// Phase 6: Fee routing & LP pool
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";

// Phase 7: Terminal
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";

// Periphery
import { MockUSDT } from "../contracts/periphery/MockUSDT.sol";

/// @title Deploy — LEVER Protocol Main Deployment Script
/// @notice Deploys all contracts in correct dependency order
/// @dev Usage:
///   Base Sepolia: forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///   Base Mainnet: forge script script/Deploy.s.sol --rpc-url $BASE_RPC --broadcast --verify
contract Deploy is Script {
    // ──────────────────────────────────────────────
    // Deployment State
    // ──────────────────────────────────────────────

    struct DeploymentAddresses {
        // Libraries (deployed once, linked to all contracts)
        address fixedPointMath;
        address riskCurves;
        address probabilityIndex;

        // External dependencies
        address usdt;
        address admin;

        // Phase 1: Foundation
        address marketRegistry;
        address accountManager;
        address positionManager;

        // Phase 2: Oracle
        address oracleAdapter;

        // Phase 3: Risk & Leverage
        address leverageModel;
        address oiLimits;

        // Phase 4: Fee Engines
        address borrowFeeEngine;
        address fundingRateEngine;

        // Phase 5: Margin & Execution
        address marginEngine;
        address executionEngine;

        // Phase 6: Fee routing & LP pool
        address feeRouter;
        address insuranceFund;
        address leverVault;
        address rewardsDistributor;

        // Phase 7: Terminal
        address liquidationEngine;
        address settlementEngine;
    }

    DeploymentAddresses public addrs;

    // ──────────────────────────────────────────────
    // Configuration
    // ──────────────────────────────────────────────

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying LEVER Protocol...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        // Admin address (can be different from deployer)
        addrs.admin = vm.envOr("ADMIN_ADDRESS", deployer);
        console.log("Admin:", addrs.admin);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy in dependency order
        _deployExternalDeps();
        _deployLibraries();
        _deployPhase1Foundation();
        _deployPhase2Oracle();
        _deployPhase3RiskLeverage();  // Fee routing early
        _deployPhase4FeeEngines();    // LP pool
        _deployPhase5MarginExecution(); // Risk & leverage
        _deployPhase6FeeRoutingLP();    // Fee engines
        _deployPhase7Terminal();        // Margin & execution
        _deployPhase8Terminal();        // Terminal contracts

        vm.stopBroadcast();

        _printDeploymentSummary();
        _saveDeploymentConfig();
    }

    // ──────────────────────────────────────────────
    // External Dependencies
    // ──────────────────────────────────────────────

    function _deployExternalDeps() internal {
        // Check if USDT address provided (mainnet) or deploy MockUSDT (testnet)
        address usdtEnv = vm.envOr("USDT_ADDRESS", address(0));

        if (usdtEnv != address(0)) {
            console.log("Using provided USDT at:", usdtEnv);
            addrs.usdt = usdtEnv;
        } else {
            console.log("Deploying MockUSDT...");
            MockUSDT mockUSDT = new MockUSDT();
            addrs.usdt = address(mockUSDT);
            console.log("MockUSDT deployed at:", addrs.usdt);
        }
    }

    // ──────────────────────────────────────────────
    // Libraries (deployed once, no state)
    // ──────────────────────────────────────────────

    function _deployLibraries() internal {
        console.log("\n=== Phase 0: Libraries ===");

        // These are pure libraries - deployed once
        // Forge will handle linking automatically in contracts that use them
        console.log("Libraries will be linked automatically by Forge during compilation");
    }

    // ──────────────────────────────────────────────
    // Phase 1: Foundation (no protocol dependencies)
    // ──────────────────────────────────────────────

    function _deployPhase1Foundation() internal {
        console.log("\n=== Phase 1: Foundation ===");

        // 1. MarketRegistry (admin only)
        console.log("Deploying MarketRegistry...");
        MarketRegistry marketRegistry = new MarketRegistry(addrs.admin);
        addrs.marketRegistry = address(marketRegistry);
        console.log("MarketRegistry:", addrs.marketRegistry);

        // 2. AccountManager (admin + USDT)
        console.log("Deploying AccountManager...");
        AccountManager accountManager = new AccountManager(addrs.admin, addrs.usdt);
        addrs.accountManager = address(accountManager);
        console.log("AccountManager:", addrs.accountManager);

        // 3. PositionManager (admin only)
        console.log("Deploying PositionManager...");
        PositionManager positionManager = new PositionManager(addrs.admin);
        addrs.positionManager = address(positionManager);
        console.log("PositionManager:", addrs.positionManager);
    }

    // ──────────────────────────────────────────────
    // Phase 2: Oracle Pipeline
    // ──────────────────────────────────────────────

    function _deployPhase2Oracle() internal {
        console.log("\n=== Phase 2: Oracle ===");

        // OracleAdapter (admin + MarketRegistry)
        console.log("Deploying OracleAdapter...");
        OracleAdapter oracleAdapter = new OracleAdapter(addrs.admin, addrs.marketRegistry);
        addrs.oracleAdapter = address(oracleAdapter);
        console.log("OracleAdapter:", addrs.oracleAdapter);
    }

    // ──────────────────────────────────────────────
    // Phase 3: Fee Routing (deploy early to avoid circular deps)
    // ──────────────────────────────────────────────

    function _deployPhase3RiskLeverage() internal {
        console.log("\n=== Phase 3: Fee Routing (Early) ===");

        // Deploy FeeRouter first (no dependencies)
        console.log("Deploying FeeRouter...");
        FeeRouter feeRouter = new FeeRouter(addrs.admin);
        addrs.feeRouter = address(feeRouter);
        console.log("FeeRouter:", addrs.feeRouter);

        // Deploy InsuranceFund (needs FeeRouter)
        console.log("Deploying InsuranceFund...");
        InsuranceFund insuranceFund = new InsuranceFund(
            addrs.admin,
            addrs.usdt,
            addrs.feeRouter
        );
        addrs.insuranceFund = address(insuranceFund);
        console.log("InsuranceFund:", addrs.insuranceFund);
    }

    // ──────────────────────────────────────────────
    // Phase 4: LP Pool (deploy before risk models that need TVL)
    // ──────────────────────────────────────────────

    function _deployPhase4FeeEngines() internal {
        console.log("\n=== Phase 4: LP Pool ===");

        // NOTE: RewardsDistributor needs LeverVault, but LeverVault needs RewardsDistributor
        // We'll deploy a placeholder and redeploy later
        console.log("Deploying placeholder RewardsDistributor...");
        RewardsDistributor placeholderRewards = new RewardsDistributor(
            addrs.admin,
            addrs.usdt,
            addrs.admin // temporary placeholder - will redeploy
        );
        addrs.rewardsDistributor = address(placeholderRewards);
        console.log("Placeholder RewardsDistributor:", addrs.rewardsDistributor);

        // LeverVault (admin + USDT + RewardsDistributor)
        console.log("Deploying LeverVault...");
        LeverVault leverVault = new LeverVault(
            addrs.admin,
            addrs.usdt,
            addrs.rewardsDistributor
        );
        addrs.leverVault = address(leverVault);
        console.log("LeverVault:", addrs.leverVault);
    }

    // ──────────────────────────────────────────────
    // Phase 5: Risk & Leverage (now that we have LeverVault + InsuranceFund)
    // ──────────────────────────────────────────────

    function _deployPhase5MarginExecution() internal {
        console.log("\n=== Phase 5: Risk & Leverage ===");

        // OILimits (MarketRegistry + LeverVault)
        console.log("Deploying OILimits...");
        OILimits oiLimits = new OILimits(
            addrs.marketRegistry,
            addrs.leverVault,
            addrs.positionManager,
            addrs.admin
        );
        addrs.oiLimits = address(oiLimits);
        console.log("OILimits:", addrs.oiLimits);

        // LeverageModel (MarketRegistry + LeverVault + InsuranceFund + OILimits)
        console.log("Deploying LeverageModel...");
        LeverageModel leverageModel = new LeverageModel(
            addrs.admin,
            addrs.marketRegistry,
            addrs.leverVault,
            addrs.insuranceFund,
            addrs.oiLimits
        );
        addrs.leverageModel = address(leverageModel);
        console.log("LeverageModel:", addrs.leverageModel);
    }

    // ──────────────────────────────────────────────
    // Phase 6: Fee Engines
    // ──────────────────────────────────────────────

    function _deployPhase6FeeRoutingLP() internal {
        console.log("\n=== Phase 6: Fee Engines ===");

        // BorrowFeeEngine (MarketRegistry + OILimits + PositionManager)
        console.log("Deploying BorrowFeeEngine...");
        BorrowFeeEngine borrowFeeEngine = new BorrowFeeEngine(
            addrs.admin,
            addrs.marketRegistry,
            addrs.oiLimits,
            addrs.positionManager
        );
        addrs.borrowFeeEngine = address(borrowFeeEngine);
        console.log("BorrowFeeEngine:", addrs.borrowFeeEngine);

        // FundingRateEngine (MarketRegistry + OILimits + PositionManager)
        console.log("Deploying FundingRateEngine...");
        FundingRateEngine fundingRateEngine = new FundingRateEngine(
            addrs.admin,
            addrs.marketRegistry,
            addrs.oiLimits,
            addrs.positionManager
        );
        addrs.fundingRateEngine = address(fundingRateEngine);
        console.log("FundingRateEngine:", addrs.fundingRateEngine);

        // Update RewardsDistributor with FundingRateEngine
        console.log("Updating RewardsDistributor with FundingRateEngine...");
        _updateRewardsDistributor();
    }

    // ──────────────────────────────────────────────
    // Phase 7: Margin & Execution
    // ──────────────────────────────────────────────

    function _deployPhase7Terminal() internal {
        console.log("\n=== Phase 7: Margin & Execution ===");

        // MarginEngine (OracleAdapter + LeverageModel + BorrowFeeEngine + FundingRateEngine + PositionManager)
        console.log("Deploying MarginEngine...");
        MarginEngine marginEngine = new MarginEngine(
            addrs.admin,
            addrs.oracleAdapter,
            addrs.leverageModel,
            addrs.borrowFeeEngine,
            addrs.fundingRateEngine,
            addrs.positionManager
        );
        addrs.marginEngine = address(marginEngine);
        console.log("MarginEngine:", addrs.marginEngine);

        // ExecutionEngine (all the dependencies)
        console.log("Deploying ExecutionEngine...");
        ExecutionEngine executionEngine = new ExecutionEngine(
            addrs.positionManager,
            addrs.oiLimits,
            addrs.marginEngine,
            addrs.oracleAdapter,
            addrs.marketRegistry,
            addrs.leverageModel,
            addrs.feeRouter,
            addrs.borrowFeeEngine,
            addrs.fundingRateEngine,
            addrs.accountManager,
            addrs.leverVault,
            addrs.admin
        );
        addrs.executionEngine = address(executionEngine);
        console.log("ExecutionEngine:", addrs.executionEngine);
    }

    // ──────────────────────────────────────────────
    // Phase 8: Terminal Contracts
    // ──────────────────────────────────────────────

    function _deployPhase8Terminal() internal {
        console.log("\n=== Phase 8: Terminal ===");

        // LiquidationEngine (MarginEngine + OracleAdapter + InsuranceFund + PositionManager + AccountManager + FeeRouter)
        console.log("Deploying LiquidationEngine...");
        LiquidationEngine liquidationEngine = new LiquidationEngine(
            addrs.admin,
            addrs.marginEngine,
            addrs.oracleAdapter,
            addrs.insuranceFund,
            addrs.positionManager,
            addrs.accountManager,
            addrs.feeRouter
        );
        addrs.liquidationEngine = address(liquidationEngine);
        console.log("LiquidationEngine:", addrs.liquidationEngine);

        // SettlementEngine (depends on everything)
        console.log("Deploying SettlementEngine...");
        SettlementEngine settlementEngine = new SettlementEngine(
            addrs.admin,
            addrs.oracleAdapter,
            addrs.marginEngine,
            addrs.borrowFeeEngine,
            addrs.fundingRateEngine,
            addrs.insuranceFund,
            addrs.leverVault,
            addrs.positionManager,
            addrs.feeRouter
        );
        addrs.settlementEngine = address(settlementEngine);
        console.log("SettlementEngine:", addrs.settlementEngine);
    }

    // ──────────────────────────────────────────────
    // Handle remaining circular dependencies
    // ──────────────────────────────────────────────

    function _updateRewardsDistributor() internal {
        // Deploy new RewardsDistributor with LeverVault now that it exists
        console.log("Redeploying RewardsDistributor with LeverVault...");
        RewardsDistributor newRewardsDistributor = new RewardsDistributor(
            addrs.admin,
            addrs.usdt,
            addrs.leverVault
        );

        // Update address (old placeholder will be unused)
        addrs.rewardsDistributor = address(newRewardsDistributor);
        console.log("Final RewardsDistributor:", addrs.rewardsDistributor);

        // NOTE: LeverVault still points to old RewardsDistributor
        // Admin should call LeverVault.setRewardsDistributor() if that function exists
        console.log("WARNING: LeverVault may need manual update to new RewardsDistributor");
    }

    // ──────────────────────────────────────────────
    // Output & Config
    // ──────────────────────────────────────────────

    function _printDeploymentSummary() internal view {
        console.log("\n======================================");
        console.log("LEVER Protocol Deployment Complete");
        console.log("======================================");

        console.log("\nExternal:");
        console.log("USDT:                ", addrs.usdt);
        console.log("Admin:               ", addrs.admin);

        console.log("\nPhase 1 - Foundation:");
        console.log("MarketRegistry:      ", addrs.marketRegistry);
        console.log("AccountManager:      ", addrs.accountManager);
        console.log("PositionManager:     ", addrs.positionManager);

        console.log("\nPhase 2 - Oracle:");
        console.log("OracleAdapter:       ", addrs.oracleAdapter);

        console.log("\nPhase 3 - Fee Routing (Early):");
        console.log("FeeRouter:           ", addrs.feeRouter);
        console.log("InsuranceFund:       ", addrs.insuranceFund);

        console.log("\nPhase 4 - LP Pool:");
        console.log("RewardsDistributor:  ", addrs.rewardsDistributor);
        console.log("LeverVault:          ", addrs.leverVault);

        console.log("\nPhase 5 - Risk & Leverage:");
        console.log("OILimits:            ", addrs.oiLimits);
        console.log("LeverageModel:       ", addrs.leverageModel);

        console.log("\nPhase 6 - Fee Engines:");
        console.log("BorrowFeeEngine:     ", addrs.borrowFeeEngine);
        console.log("FundingRateEngine:   ", addrs.fundingRateEngine);

        console.log("\nPhase 7 - Margin & Execution:");
        console.log("MarginEngine:        ", addrs.marginEngine);
        console.log("ExecutionEngine:     ", addrs.executionEngine);

        console.log("\nPhase 8 - Terminal:");
        console.log("LiquidationEngine:   ", addrs.liquidationEngine);
        console.log("SettlementEngine:    ", addrs.settlementEngine);
    }

    function _saveDeploymentConfig() internal {
        string memory chainName = block.chainid == 84532 ? "base-sepolia" :
                                 block.chainid == 8453 ? "base-mainnet" : "unknown";

        string memory config = string(abi.encodePacked(
            "{\n",
            '  "network": "', chainName, '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "timestamp": ', vm.toString(block.timestamp), ',\n',
            '  "admin": "', vm.toString(addrs.admin), '",\n',
            '  "usdt": "', vm.toString(addrs.usdt), '",\n',
            '  "marketRegistry": "', vm.toString(addrs.marketRegistry), '",\n',
            '  "accountManager": "', vm.toString(addrs.accountManager), '",\n',
            '  "positionManager": "', vm.toString(addrs.positionManager), '",\n',
            '  "oracleAdapter": "', vm.toString(addrs.oracleAdapter), '",\n',
            '  "leverageModel": "', vm.toString(addrs.leverageModel), '",\n',
            '  "oiLimits": "', vm.toString(addrs.oiLimits), '",\n',
            '  "borrowFeeEngine": "', vm.toString(addrs.borrowFeeEngine), '",\n',
            '  "fundingRateEngine": "', vm.toString(addrs.fundingRateEngine), '",\n',
            '  "marginEngine": "', vm.toString(addrs.marginEngine), '",\n',
            '  "executionEngine": "', vm.toString(addrs.executionEngine), '",\n',
            '  "feeRouter": "', vm.toString(addrs.feeRouter), '",\n',
            '  "insuranceFund": "', vm.toString(addrs.insuranceFund), '",\n',
            '  "rewardsDistributor": "', vm.toString(addrs.rewardsDistributor), '",\n',
            '  "leverVault": "', vm.toString(addrs.leverVault), '",\n',
            '  "liquidationEngine": "', vm.toString(addrs.liquidationEngine), '",\n',
            '  "settlementEngine": "', vm.toString(addrs.settlementEngine), '"\n',
            "}"
        ));

        string memory filename = string(abi.encodePacked("deployments/", chainName, "-addresses.json"));
        vm.writeFile(filename, config);
        console.log("\nDeployment config saved to:", filename);
    }
}