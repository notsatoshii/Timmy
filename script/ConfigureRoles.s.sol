// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all contracts for role configuration
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { OILimits } from "../contracts/OILimits.sol";

/// @title ConfigureRoles — Role configuration for LEVER Protocol (Phase 4)
/// @notice Grants all necessary roles across deployed contracts
/// @dev Usage: forge script script/ConfigureRoles.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract ConfigureRoles is Script {

    struct AllAddresses {
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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LEVER Role Configuration (Phase 4) ===");
        console.log("Deployer:", deployer);

        // Load all deployments
        AllAddresses memory addr = _loadAllAddresses();

        // Load role config
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address oracleKeeper = vm.envAddress("ORACLE_KEEPER");
        address marketManager = vm.envOr("MARKET_MANAGER", admin);

        console.log("Admin:", admin);
        console.log("Oracle Keeper:", oracleKeeper);
        console.log("Market Manager:", marketManager);

        vm.startBroadcast(deployerPrivateKey);

        // Grant basic roles
        _grantBasicRoles(addr, admin, oracleKeeper, marketManager);

        // Grant engine roles (cross-contract permissions)
        _grantEngineRoles(addr);

        // Grant fee router roles
        _grantFeeRouterRoles(addr);

        vm.stopBroadcast();

        console.log("=== Role Configuration Complete ===");
    }

    function _loadAllAddresses() internal view returns (AllAddresses memory addr) {
        string memory coreJson = vm.readFile("core-deployment.json");
        string memory poolJson = vm.readFile("pool-deployment.json");
        string memory enginesJson = vm.readFile("engines-deployment.json");

        // Core contracts
        addr.marketRegistry = vm.parseJsonAddress(coreJson, ".marketRegistry");
        addr.oracleAdapter = vm.parseJsonAddress(coreJson, ".oracleAdapter");
        addr.accountManager = vm.parseJsonAddress(coreJson, ".accountManager");
        addr.positionManager = vm.parseJsonAddress(coreJson, ".positionManager");

        // Pool contracts
        addr.leverVault = vm.parseJsonAddress(poolJson, ".leverVault");
        addr.rewardsDistributor = vm.parseJsonAddress(poolJson, ".rewardsDistributor");
        addr.insuranceFund = vm.parseJsonAddress(poolJson, ".insuranceFund");
        addr.feeRouter = vm.parseJsonAddress(poolJson, ".feeRouter");

        // Engine contracts
        addr.leverageModel = vm.parseJsonAddress(enginesJson, ".leverageModel");
        addr.oiLimits = vm.parseJsonAddress(enginesJson, ".oiLimits");
        addr.borrowFeeEngine = vm.parseJsonAddress(enginesJson, ".borrowFeeEngine");
        addr.fundingRateEngine = vm.parseJsonAddress(enginesJson, ".fundingRateEngine");
        addr.marginEngine = vm.parseJsonAddress(enginesJson, ".marginEngine");
        addr.executionEngine = vm.parseJsonAddress(enginesJson, ".executionEngine");
        addr.liquidationEngine = vm.parseJsonAddress(enginesJson, ".liquidationEngine");
        addr.settlementEngine = vm.parseJsonAddress(enginesJson, ".settlementEngine");
    }

    function _grantBasicRoles(
        AllAddresses memory addr,
        address admin,
        address oracleKeeper,
        address marketManager
    ) internal {
        console.log("Granting basic roles...");

        // MarketRegistry roles
        MarketRegistry registry = MarketRegistry(addr.marketRegistry);
        registry.grantRole(registry.MARKET_MANAGER(), marketManager);
        registry.grantRole(registry.ORACLE(), oracleKeeper);
        registry.grantRole(registry.KEEPER(), oracleKeeper);
        console.log("  MarketRegistry roles granted");

        // OracleAdapter roles
        OracleAdapter oracle = OracleAdapter(addr.oracleAdapter);
        oracle.grantRole(oracle.ORACLE(), oracleKeeper);
        oracle.grantRole(oracle.KEEPER(), oracleKeeper);
        oracle.grantRole(oracle.SETTLEMENT(), admin); // Admin can push settlement prices
        console.log("  OracleAdapter roles granted");

        // BorrowFeeEngine & FundingRateEngine roles
        BorrowFeeEngine(addr.borrowFeeEngine).grantRole(
            BorrowFeeEngine(addr.borrowFeeEngine).KEEPER_ROLE(),
            oracleKeeper
        );
        FundingRateEngine(addr.fundingRateEngine).grantRole(
            FundingRateEngine(addr.fundingRateEngine).KEEPER_ROLE(),
            oracleKeeper
        );
        console.log("  Fee engine roles granted");

        // LiquidationEngine & SettlementEngine roles
        LiquidationEngine(addr.liquidationEngine).grantRole(
            LiquidationEngine(addr.liquidationEngine).KEEPER_ROLE(),
            oracleKeeper
        );
        SettlementEngine(addr.settlementEngine).grantRole(
            SettlementEngine(addr.settlementEngine).KEEPER_ROLE(),
            oracleKeeper
        );
        console.log("  Terminal engine roles granted");
    }

    function _grantEngineRoles(AllAddresses memory addr) internal {
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
        LeverVault(addr.leverVault).grantRole(
            LeverVault(addr.leverVault).EXECUTION_ENGINE_ROLE(),
            addr.executionEngine
        );
        OILimits(addr.oiLimits).grantRole(
            OILimits(addr.oiLimits).EXECUTION_ENGINE_ROLE(),
            addr.executionEngine
        );
        console.log("  ExecutionEngine roles granted");

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
        console.log("  LiquidationEngine roles granted");

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
        console.log("  SettlementEngine roles granted");

        // RewardsDistributor roles
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
        console.log("  RewardsDistributor roles granted");
    }

    function _grantFeeRouterRoles(AllAddresses memory addr) internal {
        console.log("Granting fee router roles...");

        FeeRouter router = FeeRouter(addr.feeRouter);

        router.grantRole(router.BORROW_FEE_ENGINE_ROLE(), addr.borrowFeeEngine);
        router.grantRole(router.EXECUTION_ENGINE_ROLE(), addr.executionEngine);
        router.grantRole(router.LIQUIDATION_ENGINE_ROLE(), addr.liquidationEngine);
        router.grantRole(router.SETTLEMENT_ENGINE_ROLE(), addr.settlementEngine);

        console.log("  FeeRouter roles granted");
    }
}