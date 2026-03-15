// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all contracts for role assignments
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { OILimits } from "../contracts/OILimits.sol";
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";

/// @title AssignRoles — Role assignment for LEVER Protocol
/// @notice Assigns roles across all contracts based on deployment config
/// @dev Usage:
///   forge script script/AssignRoles.s.sol --rpc-url $RPC --broadcast
///   Environment variables:
///   - DEPLOYMENT_CONFIG: path to deployment JSON file
///   - ORACLE_KEEPER: oracle keeper address
///   - MARKET_MANAGER: market manager address (for creating markets)
contract AssignRoles is Script {

    struct RoleConfig {
        address admin;
        address oracleKeeper;
        address marketManager;
        address liquidator;
    }

    struct ContractAddresses {
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

        console.log("Assigning roles for LEVER Protocol...");
        console.log("Deployer:", deployer);

        // Read deployment config
        ContractAddresses memory addrs = _loadDeploymentConfig();
        RoleConfig memory roles = _loadRoleConfig();

        vm.startBroadcast(deployerPrivateKey);

        _assignMarketRegistryRoles(addrs.marketRegistry, roles);
        _assignOracleAdapterRoles(addrs.oracleAdapter, roles);
        _assignAccountManagerRoles(addrs.accountManager, roles);
        _assignPositionManagerRoles(addrs.positionManager, roles);
        _assignLeverageModelRoles(addrs.leverageModel, roles);
        _assignOILimitsRoles(addrs.oiLimits, roles);
        _assignBorrowFeeEngineRoles(addrs.borrowFeeEngine, roles);
        _assignFundingRateEngineRoles(addrs.fundingRateEngine, roles);
        _assignMarginEngineRoles(addrs.marginEngine, roles);
        _assignExecutionEngineRoles(addrs.executionEngine, roles);
        _assignFeeRouterRoles(addrs.feeRouter, roles);
        _assignInsuranceFundRoles(addrs.insuranceFund, roles);
        _assignLeverVaultRoles(addrs.leverVault, roles);
        _assignRewardsDistributorRoles(addrs.rewardsDistributor, roles);
        _assignLiquidationEngineRoles(addrs.liquidationEngine, roles);
        _assignSettlementEngineRoles(addrs.settlementEngine, roles);

        vm.stopBroadcast();

        console.log("Role assignment complete!");
    }

    function _loadDeploymentConfig() internal view returns (ContractAddresses memory addrs) {
        string memory configPath = vm.envString("DEPLOYMENT_CONFIG");
        string memory json = vm.readFile(configPath);

        addrs.marketRegistry = vm.parseJsonAddress(json, ".marketRegistry");
        addrs.oracleAdapter = vm.parseJsonAddress(json, ".oracleAdapter");
        addrs.accountManager = vm.parseJsonAddress(json, ".accountManager");
        addrs.positionManager = vm.parseJsonAddress(json, ".positionManager");
        addrs.leverageModel = vm.parseJsonAddress(json, ".leverageModel");
        addrs.oiLimits = vm.parseJsonAddress(json, ".oiLimits");
        addrs.borrowFeeEngine = vm.parseJsonAddress(json, ".borrowFeeEngine");
        addrs.fundingRateEngine = vm.parseJsonAddress(json, ".fundingRateEngine");
        addrs.marginEngine = vm.parseJsonAddress(json, ".marginEngine");
        addrs.executionEngine = vm.parseJsonAddress(json, ".executionEngine");
        addrs.feeRouter = vm.parseJsonAddress(json, ".feeRouter");
        addrs.insuranceFund = vm.parseJsonAddress(json, ".insuranceFund");
        addrs.leverVault = vm.parseJsonAddress(json, ".leverVault");
        addrs.rewardsDistributor = vm.parseJsonAddress(json, ".rewardsDistributor");
        addrs.liquidationEngine = vm.parseJsonAddress(json, ".liquidationEngine");
        addrs.settlementEngine = vm.parseJsonAddress(json, ".settlementEngine");
    }

    function _loadRoleConfig() internal view returns (RoleConfig memory roles) {
        roles.admin = vm.envOr("ADMIN_ADDRESS", vm.addr(vm.envUint("PRIVATE_KEY")));
        roles.oracleKeeper = vm.envAddress("ORACLE_KEEPER");
        roles.marketManager = vm.envOr("MARKET_MANAGER", roles.admin);
        roles.liquidator = vm.envOr("LIQUIDATOR", roles.oracleKeeper);
    }

    // ──────────────────────────────────────────────
    // Role Assignment Functions
    // ──────────────────────────────────────────────

    function _assignMarketRegistryRoles(address addr, RoleConfig memory roles) internal {
        MarketRegistry registry = MarketRegistry(addr);
        bytes32 MARKET_MANAGER = registry.MARKET_MANAGER();
        bytes32 ORACLE = registry.ORACLE();
        bytes32 KEEPER = registry.KEEPER();

        console.log("MarketRegistry roles:");
        registry.grantRole(MARKET_MANAGER, roles.marketManager);
        console.log("  MARKET_MANAGER:", roles.marketManager);

        registry.grantRole(ORACLE, roles.oracleKeeper);
        console.log("  ORACLE:", roles.oracleKeeper);

        registry.grantRole(KEEPER, roles.oracleKeeper);
        console.log("  KEEPER:", roles.oracleKeeper);
    }

    function _assignOracleAdapterRoles(address addr, RoleConfig memory roles) internal {
        OracleAdapter oracle = OracleAdapter(addr);
        bytes32 ORACLE = oracle.ORACLE();
        bytes32 KEEPER = oracle.KEEPER();
        bytes32 SETTLEMENT = oracle.SETTLEMENT();

        console.log("OracleAdapter roles:");
        oracle.grantRole(ORACLE, roles.oracleKeeper);
        console.log("  ORACLE:", roles.oracleKeeper);

        oracle.grantRole(KEEPER, roles.oracleKeeper);
        console.log("  KEEPER:", roles.oracleKeeper);

        oracle.grantRole(SETTLEMENT, roles.admin); // Admin can push settlement prices
        console.log("  SETTLEMENT:", roles.admin);
    }

    function _assignAccountManagerRoles(address addr, RoleConfig memory roles) internal {
        AccountManager manager = AccountManager(addr);
        bytes32 ENGINE_ROLE = manager.ENGINE();

        console.log("AccountManager roles:");
        console.log("  ENGINE: [set during ExecutionEngine/LiquidationEngine/SettlementEngine assignment]");
    }

    function _assignPositionManagerRoles(address addr, RoleConfig memory roles) internal {
        PositionManager manager = PositionManager(addr);
        bytes32 ENGINE_ROLE = manager.ENGINE();

        console.log("PositionManager roles:");
        console.log("  ENGINE: [set during ExecutionEngine/LiquidationEngine/SettlementEngine assignment]");
    }

    function _assignLeverageModelRoles(address addr, RoleConfig memory roles) internal {
        console.log("LeverageModel: No additional roles needed (only admin)");
    }

    function _assignOILimitsRoles(address addr, RoleConfig memory roles) internal {
        console.log("OILimits: No additional roles needed (only admin)");
    }

    function _assignBorrowFeeEngineRoles(address addr, RoleConfig memory roles) internal {
        BorrowFeeEngine engine = BorrowFeeEngine(addr);
        bytes32 KEEPER_ROLE = engine.KEEPER_ROLE();

        console.log("BorrowFeeEngine roles:");
        engine.grantRole(KEEPER_ROLE, roles.oracleKeeper);
        console.log("  KEEPER_ROLE:", roles.oracleKeeper);
    }

    function _assignFundingRateEngineRoles(address addr, RoleConfig memory roles) internal {
        FundingRateEngine engine = FundingRateEngine(addr);
        bytes32 KEEPER_ROLE = engine.KEEPER_ROLE();

        console.log("FundingRateEngine roles:");
        engine.grantRole(KEEPER_ROLE, roles.oracleKeeper);
        console.log("  KEEPER_ROLE:", roles.oracleKeeper);
    }

    function _assignMarginEngineRoles(address addr, RoleConfig memory roles) internal {
        console.log("MarginEngine: No additional roles needed (only admin)");
    }

    function _assignExecutionEngineRoles(address addr, RoleConfig memory roles) internal {
        ExecutionEngine engine = ExecutionEngine(addr);
        console.log("ExecutionEngine: Public trading interface - no special roles needed");
    }

    function _assignFeeRouterRoles(address addr, RoleConfig memory roles) internal {
        FeeRouter router = FeeRouter(addr);
        bytes32 BORROW_FEE_ENGINE_ROLE = router.BORROW_FEE_ENGINE_ROLE();
        bytes32 EXECUTION_ENGINE_ROLE = router.EXECUTION_ENGINE_ROLE();
        bytes32 LIQUIDATION_ENGINE_ROLE = router.LIQUIDATION_ENGINE_ROLE();
        bytes32 SETTLEMENT_ENGINE_ROLE = router.SETTLEMENT_ENGINE_ROLE();

        console.log("FeeRouter roles:");
        console.log("  Engine roles will be assigned when those contracts are configured");
    }

    function _assignInsuranceFundRoles(address addr, RoleConfig memory roles) internal {
        InsuranceFund fund = InsuranceFund(addr);
        bytes32 LIQUIDATION_ENGINE_ROLE = fund.LIQUIDATION_ENGINE_ROLE();
        bytes32 SETTLEMENT_ENGINE_ROLE = fund.SETTLEMENT_ENGINE_ROLE();

        console.log("InsuranceFund roles:");
        console.log("  LIQUIDATION_ENGINE_ROLE: [set during LiquidationEngine assignment]");
        console.log("  SETTLEMENT_ENGINE_ROLE: [set during SettlementEngine assignment]");
    }

    function _assignLeverVaultRoles(address addr, RoleConfig memory roles) internal {
        LeverVault vault = LeverVault(addr);
        bytes32 EXECUTION_ENGINE_ROLE = vault.EXECUTION_ENGINE_ROLE();
        bytes32 LIQUIDATION_ENGINE_ROLE = vault.LIQUIDATION_ENGINE_ROLE();

        console.log("LeverVault roles:");
        console.log("  EXECUTION_ENGINE_ROLE: [set during ExecutionEngine assignment]");
        console.log("  LIQUIDATION_ENGINE_ROLE: [set during LiquidationEngine assignment]");
    }

    function _assignRewardsDistributorRoles(address addr, RoleConfig memory roles) internal {
        RewardsDistributor distributor = RewardsDistributor(addr);
        bytes32 FEE_ROUTER_ROLE = distributor.FEE_ROUTER_ROLE();
        bytes32 FUNDING_RATE_ENGINE_ROLE = distributor.FUNDING_RATE_ENGINE_ROLE();
        bytes32 LEVER_VAULT_ROLE = distributor.LEVER_VAULT_ROLE();

        console.log("RewardsDistributor roles:");
        console.log("  These roles will be set during cross-contract configuration");
    }

    function _assignLiquidationEngineRoles(address addr, RoleConfig memory roles) internal {
        LiquidationEngine engine = LiquidationEngine(addr);
        bytes32 KEEPER_ROLE = engine.KEEPER_ROLE();

        console.log("LiquidationEngine roles:");
        engine.grantRole(KEEPER_ROLE, roles.oracleKeeper);
        console.log("  KEEPER_ROLE:", roles.oracleKeeper);
        console.log("  Note: liquidate() is permissionless - no LIQUIDATOR_ROLE needed");
    }

    function _assignSettlementEngineRoles(address addr, RoleConfig memory roles) internal {
        SettlementEngine engine = SettlementEngine(addr);
        bytes32 KEEPER_ROLE = engine.KEEPER_ROLE();

        console.log("SettlementEngine roles:");
        engine.grantRole(KEEPER_ROLE, roles.oracleKeeper);
        console.log("  KEEPER_ROLE:", roles.oracleKeeper);
        console.log("  ADMIN_ROLE: [already assigned during deployment]");
    }
}