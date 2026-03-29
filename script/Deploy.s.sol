// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Libraries
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";
import { RiskCurves } from "../contracts/libraries/RiskCurves.sol";
import { ProbabilityIndex } from "../contracts/libraries/ProbabilityIndex.sol";

// Core contracts
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";

// Risk & Leverage
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { OILimits } from "../contracts/OILimits.sol";

// Engines
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";

// Fee routing & Pool
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";

// Terminal contracts
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";

// Mock token for testnet
import { MockUSDT } from "../contracts/periphery/MockUSDT.sol";

/// @title Deploy — Complete LEVER Protocol deployment script
/// @notice Deploys all contracts in correct dependency order for Base Sepolia testnet
/// @dev Usage:
///   forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///
/// Environment variables required:
///   - PRIVATE_KEY: Deployer private key
///   - USDT_ADDRESS: USDT token address (or deploy MockUSDT if empty)
///   - PROTOCOL_TREASURY: Protocol treasury address (defaults to deployer)
///   - BASE_SEPOLIA_RPC: RPC endpoint
///   - BASESCAN_API_KEY: For contract verification
contract Deploy is Script {

    struct DeploymentAddresses {
        address usdt;
        address marketRegistry;
        address oracleAdapter;
        address accountManager;
        address positionManager;
        address leverageModel;
        address oiLimits;
        address borrowFeeEngine;
        address fundingRateEngine;
        address marginEngine;
        address executionEngine;
        address feeRouter;
        address insuranceFund;
        address leverVault;
        address rewardsDistributor;
        address liquidationEngine;
        address settlementEngine;
    }

    function run() external returns (DeploymentAddresses memory addresses) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address protocolTreasury = vm.envOr("PROTOCOL_TREASURY", deployer);

        console.log("=== LEVER Protocol Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Protocol Treasury:", protocolTreasury);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: USDT (Mock or use existing)
        addresses.usdt = _deployOrGetUSDT();

        // Phase 2: Foundation contracts (no dependencies)
        addresses.marketRegistry = _deployMarketRegistry();
        addresses.accountManager = _deployAccountManager(addresses.usdt);
        addresses.positionManager = _deployPositionManager();

        // Phase 3: Oracle pipeline
        addresses.oracleAdapter = _deployOracleAdapter(addresses.marketRegistry);

        // Phase 4: LP Pool & Fee destinations
        // CIRCULAR DEPENDENCY ISSUE: LeverVault needs RewardsDistributor, RewardsDistributor needs LeverVault
        // Solution: Deploy placeholder RewardsDistributor, then LeverVault, then redeploy RewardsDistributor

        console.log("STEP 4a: Deploy placeholder RewardsDistributor...");
        address placeholderRewards = address(new RewardsDistributor(deployer, addresses.usdt, address(0x1111111111111111111111111111111111111111)));

        console.log("STEP 4b: Deploy LeverVault with placeholder...");
        addresses.leverVault = _deployLeverVault(addresses.usdt, placeholderRewards);

        console.log("STEP 4c: Deploy real RewardsDistributor...");
        addresses.rewardsDistributor = _deployRewardsDistributor(addresses.usdt, addresses.leverVault);

        console.log("STEP 4d: Deploy InsuranceFund and FeeRouter...");
        addresses.insuranceFund = _deployInsuranceFund(addresses.usdt, addresses.leverVault);
        addresses.feeRouter = _deployFeeRouter(
            protocolTreasury,
            addresses.usdt,
            addresses.insuranceFund,
            addresses.rewardsDistributor
        );

        // Phase 5: OI & Risk (now that vault is available)
        addresses.oiLimits = _deployOILimits(
            addresses.marketRegistry,
            addresses.leverVault,
            addresses.positionManager
        );

        addresses.leverageModel = _deployLeverageModel(
            addresses.leverVault,
            addresses.insuranceFund,
            addresses.oiLimits,
            addresses.marketRegistry,
            addresses.oracleAdapter
        );

        // Phase 6: Fee engines
        addresses.borrowFeeEngine = _deployBorrowFeeEngine(
            addresses.marketRegistry,
            addresses.oiLimits,
            addresses.positionManager
        );

        addresses.fundingRateEngine = _deployFundingRateEngine(
            addresses.marketRegistry,
            addresses.oiLimits,
            addresses.positionManager,
            addresses.accountManager,
            addresses.rewardsDistributor
        );

        // Phase 7: Margin & Execution
        addresses.marginEngine = _deployMarginEngine(
            addresses.positionManager,
            addresses.oracleAdapter,
            addresses.marketRegistry,
            addresses.borrowFeeEngine,
            addresses.fundingRateEngine
        );

        addresses.executionEngine = _deployExecutionEngine(
            addresses.positionManager,
            addresses.oiLimits,
            addresses.marginEngine,
            addresses.oracleAdapter,
            addresses.marketRegistry,
            addresses.leverageModel,
            addresses.feeRouter,
            addresses.borrowFeeEngine,
            addresses.fundingRateEngine,
            addresses.accountManager,
            addresses.leverVault,
            addresses.insuranceFund
        );

        // Phase 8: Terminal contracts
        addresses.liquidationEngine = _deployLiquidationEngine(
            addresses.marginEngine,
            addresses.oracleAdapter,
            addresses.positionManager,
            addresses.accountManager,
            addresses.borrowFeeEngine,
            addresses.fundingRateEngine,
            addresses.leverVault,
            addresses.insuranceFund,
            addresses.feeRouter
        );

        addresses.settlementEngine = _deploySettlementEngine(addresses);

        // Phase 9: Update LeverVault with correct RewardsDistributor
        _updateLeverVaultRewardsDistributor(addresses);

        // Phase 10: Grant engine roles to enable operations
        _grantEngineRoles(addresses);

        vm.stopBroadcast();

        // Phase 11: Save deployment config
        _saveDeploymentConfig(addresses);

        console.log("=== Deployment Complete ===");
        _logAddresses(addresses);

        return addresses;
    }

    // ──────────────────────────────────────────────
    // Phase 1: USDT Deployment
    // ──────────────────────────────────────────────

    function _deployOrGetUSDT() internal returns (address) {
        address existingUSDT = vm.envOr("USDT_ADDRESS", address(0));

        if (existingUSDT != address(0)) {
            console.log("Using existing USDT:", existingUSDT);
            return existingUSDT;
        } else {
            console.log("Deploying MockUSDT...");
            MockUSDT mockUSDT = new MockUSDT();
            console.log("MockUSDT deployed:", address(mockUSDT));
            return address(mockUSDT);
        }
    }

    // ──────────────────────────────────────────────
    // Phase 2: Foundation Contracts
    // ──────────────────────────────────────────────

    function _deployMarketRegistry() internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying MarketRegistry...");
        MarketRegistry registry = new MarketRegistry(deployer);
        console.log("MarketRegistry deployed:", address(registry));
        return address(registry);
    }

    function _deployAccountManager(address usdt) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying AccountManager...");
        AccountManager manager = new AccountManager(deployer, usdt);
        console.log("AccountManager deployed:", address(manager));
        return address(manager);
    }

    function _deployPositionManager() internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying PositionManager...");
        PositionManager manager = new PositionManager(deployer);
        console.log("PositionManager deployed:", address(manager));
        return address(manager);
    }

    // ──────────────────────────────────────────────
    // Phase 3: Oracle Pipeline
    // ──────────────────────────────────────────────

    function _deployOracleAdapter(address marketRegistry) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying OracleAdapter...");
        OracleAdapter oracle = new OracleAdapter(deployer, marketRegistry);
        console.log("OracleAdapter deployed:", address(oracle));
        return address(oracle);
    }

    // ──────────────────────────────────────────────
    // Phase 4: Initial Fee Destinations (to resolve circular deps)
    // ──────────────────────────────────────────────

    function _deployRewardsDistributor(
        address usdt,
        address leverVault
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying RewardsDistributor...");
        RewardsDistributor distributor = new RewardsDistributor(deployer, usdt, leverVault);
        console.log("RewardsDistributor deployed:", address(distributor));
        return address(distributor);
    }

    function _deployLeverVault(
        address usdt,
        address rewardsDistributor
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying LeverVault...");
        LeverVault vault = new LeverVault(deployer, usdt, rewardsDistributor);
        console.log("LeverVault deployed:", address(vault));
        return address(vault);
    }

    function _deployInsuranceFund(address usdt, address leverVault) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying InsuranceFund...");
        InsuranceFund fund = new InsuranceFund(deployer, usdt, leverVault);
        console.log("InsuranceFund deployed:", address(fund));
        return address(fund);
    }

    function _deployFeeRouter(
        address protocolTreasury,
        address usdt,
        address insuranceFund,
        address rewardsDistributor
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying FeeRouter...");
        FeeRouter router = new FeeRouter(
            deployer,
            usdt,
            insuranceFund,
            rewardsDistributor,
            protocolTreasury
        );
        console.log("FeeRouter deployed:", address(router));
        return address(router);
    }

    // ──────────────────────────────────────────────
    // Phase 5: OI & Risk
    // ──────────────────────────────────────────────

    function _deployOILimits(
        address marketRegistry,
        address leverVault,
        address positionMgr
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying OILimits...");
        OILimits limits = new OILimits(marketRegistry, leverVault, positionMgr, deployer);
        console.log("OILimits deployed:", address(limits));
        return address(limits);
    }

    function _deployLeverageModel(
        address leverVault,
        address insuranceFund,
        address oiLimits,
        address marketRegistry,
        address oracleAdapter
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying LeverageModel...");
        LeverageModel model = new LeverageModel(
            leverVault,
            insuranceFund,
            oiLimits,
            marketRegistry,
            oracleAdapter,
            deployer
        );
        console.log("LeverageModel deployed:", address(model));
        return address(model);
    }

    // ──────────────────────────────────────────────
    // Phase 6: Fee Engines
    // ──────────────────────────────────────────────

    function _deployBorrowFeeEngine(
        address marketRegistry,
        address oiLimits,
        address positionManager
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying BorrowFeeEngine...");
        BorrowFeeEngine engine = new BorrowFeeEngine(
            deployer,
            marketRegistry,
            oiLimits,
            positionManager
        );
        console.log("BorrowFeeEngine deployed:", address(engine));
        return address(engine);
    }

    function _deployFundingRateEngine(
        address marketRegistry,
        address oiLimits,
        address positionManager,
        address accountManager,
        address rewardsDistributor
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying FundingRateEngine...");
        FundingRateEngine engine = new FundingRateEngine(
            deployer,
            marketRegistry,
            oiLimits,
            positionManager,
            accountManager,
            rewardsDistributor
        );
        console.log("FundingRateEngine deployed:", address(engine));
        return address(engine);
    }

    // ──────────────────────────────────────────────
    // Phase 7: Margin & Execution
    // ──────────────────────────────────────────────

    function _deployMarginEngine(
        address positionManager,
        address oracleAdapter,
        address marketRegistry,
        address borrowFeeEngine,
        address fundingRateEngine
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying MarginEngine...");
        MarginEngine engine = new MarginEngine(
            deployer,
            positionManager,
            oracleAdapter,
            marketRegistry,
            borrowFeeEngine,
            fundingRateEngine
        );
        console.log("MarginEngine deployed:", address(engine));
        return address(engine);
    }

    function _deployExecutionEngine(
        address positionManager,
        address oiLimits,
        address marginEngine,
        address oracleAdapter,
        address marketRegistry,
        address leverageModel,
        address feeRouter,
        address borrowFeeEngine,
        address fundingRateEngine,
        address accountManager,
        address leverVault,
        address insuranceFund
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying ExecutionEngine...");
        ExecutionEngine engine = new ExecutionEngine(
            positionManager,
            oiLimits,
            marginEngine,
            oracleAdapter,
            marketRegistry,
            leverageModel,
            feeRouter,
            borrowFeeEngine,
            fundingRateEngine,
            accountManager,
            leverVault,
            insuranceFund,
            deployer
        );
        console.log("ExecutionEngine deployed:", address(engine));
        return address(engine);
    }

    // ──────────────────────────────────────────────
    // Phase 8: Terminal Contracts
    // ──────────────────────────────────────────────

    function _deployLiquidationEngine(
        address marginEngine,
        address oracleAdapter,
        address positionManager,
        address accountManager,
        address borrowFeeEngine,
        address fundingRateEngine,
        address leverVault,
        address insuranceFund,
        address feeRouter
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying LiquidationEngine...");
        LiquidationEngine engine = new LiquidationEngine(
            deployer,
            marginEngine,
            oracleAdapter,
            positionManager,
            accountManager,
            borrowFeeEngine,
            fundingRateEngine,
            leverVault,
            insuranceFund,
            feeRouter
        );
        console.log("LiquidationEngine deployed:", address(engine));
        return address(engine);
    }

    function _deploySettlementEngine(
        DeploymentAddresses memory addresses
    ) internal returns (address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying SettlementEngine...");
        SettlementEngine engine = new SettlementEngine(
            deployer,
            addresses.marketRegistry,
            addresses.positionManager,
            addresses.oracleAdapter,
            addresses.borrowFeeEngine,
            addresses.fundingRateEngine,
            addresses.insuranceFund,
            addresses.feeRouter,
            addresses.oiLimits,
            addresses.accountManager,
            addresses.leverVault
        );
        console.log("SettlementEngine deployed:", address(engine));
        return address(engine);
    }

    // ──────────────────────────────────────────────
    // Phase 9: Fix Circular Dependencies
    // ──────────────────────────────────────────────

    function _updateLeverVaultRewardsDistributor(DeploymentAddresses memory addr) internal view {
        console.log("Checking LeverVault RewardsDistributor configuration...");

        console.log("WARNING: LeverVault points to placeholder RewardsDistributor");
        console.log("  Real RewardsDistributor deployed at:", addr.rewardsDistributor);
        console.log("  LeverVault internal rewardsDistributor address is a placeholder");
        console.log("  This requires manual admin action or contract redeployment to fully resolve");
    }

    // ──────────────────────────────────────────────
    // Phase 10: Grant Engine Roles
    // ──────────────────────────────────────────────

    function _grantEngineRoles(DeploymentAddresses memory addr) internal {
        console.log("Granting engine roles...");

        // ExecutionEngine gets ENGINE role on AccountManager & PositionManager
        AccountManager(addr.accountManager).grantRole(
            AccountManager(addr.accountManager).ENGINE(),
            addr.executionEngine
        );
        PositionManager(addr.positionManager).grantRole(
            PositionManager(addr.positionManager).ENGINE(),
            addr.executionEngine
        );
        console.log("  ExecutionEngine -> ENGINE roles");

        // LiquidationEngine gets ENGINE roles
        AccountManager(addr.accountManager).grantRole(
            AccountManager(addr.accountManager).ENGINE(),
            addr.liquidationEngine
        );
        PositionManager(addr.positionManager).grantRole(
            PositionManager(addr.positionManager).ENGINE(),
            addr.liquidationEngine
        );
        LeverVault(addr.leverVault).grantRole(
            LeverVault(addr.leverVault).LIQUIDATION_ENGINE_ROLE(),
            addr.liquidationEngine
        );
        InsuranceFund(addr.insuranceFund).grantRole(
            InsuranceFund(addr.insuranceFund).LIQUIDATION_ENGINE_ROLE(),
            addr.liquidationEngine
        );
        console.log("  LiquidationEngine -> ENGINE roles");

        // SettlementEngine gets ENGINE roles
        AccountManager(addr.accountManager).grantRole(
            AccountManager(addr.accountManager).ENGINE(),
            addr.settlementEngine
        );
        PositionManager(addr.positionManager).grantRole(
            PositionManager(addr.positionManager).ENGINE(),
            addr.settlementEngine
        );
        LeverVault(addr.leverVault).grantRole(
            LeverVault(addr.leverVault).EXECUTION_ENGINE_ROLE(),
            addr.settlementEngine
        );
        InsuranceFund(addr.insuranceFund).grantRole(
            InsuranceFund(addr.insuranceFund).SETTLEMENT_ENGINE_ROLE(),
            addr.settlementEngine
        );
        console.log("  SettlementEngine -> ENGINE roles");

        // Grant ExecutionEngine role to LeverVault
        LeverVault(addr.leverVault).grantRole(
            LeverVault(addr.leverVault).EXECUTION_ENGINE_ROLE(),
            addr.executionEngine
        );

        // Grant fee router roles
        FeeRouter(addr.feeRouter).grantRole(
            FeeRouter(addr.feeRouter).BORROW_FEE_ENGINE_ROLE(),
            addr.borrowFeeEngine
        );
        FeeRouter(addr.feeRouter).grantRole(
            FeeRouter(addr.feeRouter).EXECUTION_ENGINE_ROLE(),
            addr.executionEngine
        );
        FeeRouter(addr.feeRouter).grantRole(
            FeeRouter(addr.feeRouter).LIQUIDATION_ENGINE_ROLE(),
            addr.liquidationEngine
        );
        FeeRouter(addr.feeRouter).grantRole(
            FeeRouter(addr.feeRouter).SETTLEMENT_ENGINE_ROLE(),
            addr.settlementEngine
        );

        // Grant RewardsDistributor roles
        RewardsDistributor(addr.rewardsDistributor).grantRole(
            RewardsDistributor(addr.rewardsDistributor).FEE_ROUTER_ROLE(),
            addr.feeRouter
        );
        RewardsDistributor(addr.rewardsDistributor).grantRole(
            RewardsDistributor(addr.rewardsDistributor).FUNDING_RATE_ENGINE_ROLE(),
            addr.fundingRateEngine
        );
        RewardsDistributor(addr.rewardsDistributor).grantRole(
            RewardsDistributor(addr.rewardsDistributor).LEVER_VAULT_ROLE(),
            addr.leverVault
        );

        console.log("Engine roles granted.");
    }

    // ──────────────────────────────────────────────
    // Phase 11: Save Configuration
    // ──────────────────────────────────────────────

    function _saveDeploymentConfig(DeploymentAddresses memory addr) internal {
        string memory part1 = string(abi.encodePacked(
            '{\n',
            '  "usdt": "', vm.toString(addr.usdt), '",\n',
            '  "marketRegistry": "', vm.toString(addr.marketRegistry), '",\n',
            '  "oracleAdapter": "', vm.toString(addr.oracleAdapter), '",\n',
            '  "accountManager": "', vm.toString(addr.accountManager), '",\n',
            '  "positionManager": "', vm.toString(addr.positionManager), '",\n',
            '  "leverageModel": "', vm.toString(addr.leverageModel), '",\n',
            '  "oiLimits": "', vm.toString(addr.oiLimits), '",\n'
        ));

        string memory part2 = string(abi.encodePacked(
            '  "borrowFeeEngine": "', vm.toString(addr.borrowFeeEngine), '",\n',
            '  "fundingRateEngine": "', vm.toString(addr.fundingRateEngine), '",\n',
            '  "marginEngine": "', vm.toString(addr.marginEngine), '",\n',
            '  "executionEngine": "', vm.toString(addr.executionEngine), '",\n',
            '  "feeRouter": "', vm.toString(addr.feeRouter), '",\n',
            '  "insuranceFund": "', vm.toString(addr.insuranceFund), '",\n',
            '  "leverVault": "', vm.toString(addr.leverVault), '",\n'
        ));

        string memory part3 = string(abi.encodePacked(
            '  "rewardsDistributor": "', vm.toString(addr.rewardsDistributor), '",\n',
            '  "liquidationEngine": "', vm.toString(addr.liquidationEngine), '",\n',
            '  "settlementEngine": "', vm.toString(addr.settlementEngine), '"\n',
            '}'
        ));

        string memory config = string(abi.encodePacked(part1, part2, part3));
        vm.writeFile("deployment.json", config);
        console.log("Deployment config saved to deployment.json");
    }

    function _logAddresses(DeploymentAddresses memory addr) internal view {
        console.log("USDT:                ", addr.usdt);
        console.log("MarketRegistry:      ", addr.marketRegistry);
        console.log("OracleAdapter:       ", addr.oracleAdapter);
        console.log("AccountManager:      ", addr.accountManager);
        console.log("PositionManager:     ", addr.positionManager);
        console.log("LeverageModel:       ", addr.leverageModel);
        console.log("OILimits:            ", addr.oiLimits);
        console.log("BorrowFeeEngine:     ", addr.borrowFeeEngine);
        console.log("FundingRateEngine:   ", addr.fundingRateEngine);
        console.log("MarginEngine:        ", addr.marginEngine);
        console.log("ExecutionEngine:     ", addr.executionEngine);
        console.log("FeeRouter:           ", addr.feeRouter);
        console.log("InsuranceFund:       ", addr.insuranceFund);
        console.log("LeverVault:          ", addr.leverVault);
        console.log("RewardsDistributor:  ", addr.rewardsDistributor);
        console.log("LiquidationEngine:   ", addr.liquidationEngine);
        console.log("SettlementEngine:    ", addr.settlementEngine);
    }
}