// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Risk & Leverage contracts
import { LeverageModel } from "../contracts/LeverageModel.sol";
import { OILimits } from "../contracts/OILimits.sol";

// Engine contracts
import { BorrowFeeEngine } from "../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../contracts/FundingRateEngine.sol";
import { MarginEngine } from "../contracts/MarginEngine.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";

/// @title DeployEngines — Engine deployment (Phase 3)
/// @notice Deploys all risk, fee, and execution engines
/// @dev Usage: forge script script/DeployEngines.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract DeployEngines is Script {

    struct EngineAddresses {
        address leverageModel;
        address oiLimits;
        address borrowFeeEngine;
        address fundingRateEngine;
        address marginEngine;
        address executionEngine;
        address liquidationEngine;
        address settlementEngine;
    }

    function run() external returns (EngineAddresses memory addresses) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LEVER Engines Deployment (Phase 3) ===");
        console.log("Deployer:", deployer);

        // Load previous deployments
        string memory coreJson = vm.readFile("core-deployment.json");
        string memory poolJson = vm.readFile("pool-deployment.json");

        address marketRegistry = vm.parseJsonAddress(coreJson, ".marketRegistry");
        address oracleAdapter = vm.parseJsonAddress(coreJson, ".oracleAdapter");
        address accountManager = vm.parseJsonAddress(coreJson, ".accountManager");
        address positionManager = vm.parseJsonAddress(coreJson, ".positionManager");
        address leverVault = vm.parseJsonAddress(poolJson, ".leverVault");
        address insuranceFund = vm.parseJsonAddress(poolJson, ".insuranceFund");
        address feeRouter = vm.parseJsonAddress(poolJson, ".feeRouter");
        address rewardsDistributor = vm.parseJsonAddress(poolJson, ".rewardsDistributor");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Risk & OI systems
        addresses.oiLimits = _deployOILimits(deployer, marketRegistry, leverVault, positionManager);
        addresses.leverageModel = _deployLeverageModel(
            deployer, leverVault, insuranceFund, addresses.oiLimits, marketRegistry, oracleAdapter
        );

        // Phase 2: Fee engines
        addresses.borrowFeeEngine = _deployBorrowFeeEngine(deployer, marketRegistry, addresses.oiLimits, positionManager);
        addresses.fundingRateEngine = _deployFundingRateEngine(deployer, marketRegistry, addresses.oiLimits, positionManager, accountManager, rewardsDistributor);

        // Phase 3: Margin & execution
        addresses.marginEngine = _deployMarginEngine(
            deployer, positionManager, oracleAdapter, marketRegistry, addresses.borrowFeeEngine, addresses.fundingRateEngine
        );

        addresses.executionEngine = _deployExecutionEngine(
            deployer, positionManager, addresses.oiLimits, addresses.marginEngine, oracleAdapter,
            marketRegistry, addresses.leverageModel, feeRouter, addresses.borrowFeeEngine,
            addresses.fundingRateEngine, accountManager, leverVault, insuranceFund
        );

        // Phase 4: Terminal engines
        addresses.liquidationEngine = _deployLiquidationEngine(
            deployer, addresses.marginEngine, oracleAdapter, positionManager, accountManager,
            addresses.borrowFeeEngine, addresses.fundingRateEngine, leverVault, insuranceFund, feeRouter
        );

        addresses.settlementEngine = _deploySettlementEngine(
            deployer, oracleAdapter, positionManager, accountManager, addresses.borrowFeeEngine,
            addresses.fundingRateEngine, leverVault, insuranceFund, feeRouter, marketRegistry, addresses.oiLimits
        );

        vm.stopBroadcast();

        _saveEnginesConfig(addresses);

        console.log("=== Engines Deployment Complete ===");
        _logAddresses(addresses);

        return addresses;
    }

    // ──────────────────────────────────────────────
    // Deployment Functions
    // ──────────────────────────────────────────────

    function _deployOILimits(address deployer, address marketRegistry, address leverVault, address positionMgr) internal returns (address) {
        console.log("Deploying OILimits...");
        address addr = address(new OILimits(marketRegistry, leverVault, positionMgr, deployer));
        console.log("OILimits deployed:", addr);
        return addr;
    }

    function _deployLeverageModel(
        address deployer, address leverVault, address insuranceFund, address oiLimits,
        address marketRegistry, address oracleAdapter
    ) internal returns (address) {
        console.log("Deploying LeverageModel...");
        address addr = address(new LeverageModel(leverVault, insuranceFund, oiLimits, marketRegistry, oracleAdapter, deployer));
        console.log("LeverageModel deployed:", addr);
        return addr;
    }

    function _deployBorrowFeeEngine(
        address deployer, address marketRegistry, address oiLimits, address positionManager
    ) internal returns (address) {
        console.log("Deploying BorrowFeeEngine...");
        address addr = address(new BorrowFeeEngine(deployer, marketRegistry, oiLimits, positionManager));
        console.log("BorrowFeeEngine deployed:", addr);
        return addr;
    }

    function _deployFundingRateEngine(
        address deployer, address marketRegistry, address oiLimits, address positionManager,
        address accountManager, address rewardsDistributor
    ) internal returns (address) {
        console.log("Deploying FundingRateEngine...");
        address addr = address(new FundingRateEngine(deployer, marketRegistry, oiLimits, positionManager, accountManager, rewardsDistributor));
        console.log("FundingRateEngine deployed:", addr);
        return addr;
    }

    function _deployMarginEngine(
        address deployer, address positionManager, address oracleAdapter, address marketRegistry,
        address borrowFeeEngine, address fundingRateEngine
    ) internal returns (address) {
        console.log("Deploying MarginEngine...");
        address addr = address(new MarginEngine(deployer, positionManager, oracleAdapter, marketRegistry, borrowFeeEngine, fundingRateEngine));
        console.log("MarginEngine deployed:", addr);
        return addr;
    }

    function _deployExecutionEngine(
        address deployer, address positionManager, address oiLimits, address marginEngine,
        address oracleAdapter, address marketRegistry, address leverageModel, address feeRouter,
        address borrowFeeEngine, address fundingRateEngine, address accountManager, address leverVault,
        address insuranceFund
    ) internal returns (address) {
        console.log("Deploying ExecutionEngine...");
        address addr = address(new ExecutionEngine(
            positionManager, oiLimits, marginEngine, oracleAdapter, marketRegistry, leverageModel,
            feeRouter, borrowFeeEngine, fundingRateEngine, accountManager, leverVault, insuranceFund, deployer
        ));
        console.log("ExecutionEngine deployed:", addr);
        return addr;
    }

    function _deployLiquidationEngine(
        address deployer, address marginEngine, address oracleAdapter, address positionManager,
        address accountManager, address borrowFeeEngine, address fundingRateEngine,
        address leverVault, address insuranceFund, address feeRouter
    ) internal returns (address) {
        console.log("Deploying LiquidationEngine...");
        address addr = address(new LiquidationEngine(
            deployer, marginEngine, oracleAdapter, positionManager, accountManager,
            borrowFeeEngine, fundingRateEngine, leverVault, insuranceFund, feeRouter
        ));
        console.log("LiquidationEngine deployed:", addr);
        return addr;
    }

    function _deploySettlementEngine(
        address deployer, address oracleAdapter, address positionManager, address accountManager,
        address borrowFeeEngine, address fundingRateEngine, address leverVault, address insuranceFund,
        address feeRouter, address marketRegistry, address oiLimits
    ) internal returns (address) {
        console.log("Deploying SettlementEngine...");
        address addr = address(new SettlementEngine(
            deployer, marketRegistry, positionManager, oracleAdapter, borrowFeeEngine,
            fundingRateEngine, insuranceFund, feeRouter, oiLimits, accountManager, leverVault
        ));
        console.log("SettlementEngine deployed:", addr);
        return addr;
    }

    function _saveEnginesConfig(EngineAddresses memory addr) internal {
        string memory config = string(abi.encodePacked(
            '{\n',
            '  "leverageModel": "', vm.toString(addr.leverageModel), '",\n',
            '  "oiLimits": "', vm.toString(addr.oiLimits), '",\n',
            '  "borrowFeeEngine": "', vm.toString(addr.borrowFeeEngine), '",\n',
            '  "fundingRateEngine": "', vm.toString(addr.fundingRateEngine), '",\n',
            '  "marginEngine": "', vm.toString(addr.marginEngine), '",\n',
            '  "executionEngine": "', vm.toString(addr.executionEngine), '",\n',
            '  "liquidationEngine": "', vm.toString(addr.liquidationEngine), '",\n',
            '  "settlementEngine": "', vm.toString(addr.settlementEngine), '"\n',
            '}'
        ));

        vm.writeFile("engines-deployment.json", config);
        console.log("Engines deployment config saved to engines-deployment.json");
    }

    function _logAddresses(EngineAddresses memory addr) internal view {
        console.log("LeverageModel:     ", addr.leverageModel);
        console.log("OILimits:          ", addr.oiLimits);
        console.log("BorrowFeeEngine:   ", addr.borrowFeeEngine);
        console.log("FundingRateEngine: ", addr.fundingRateEngine);
        console.log("MarginEngine:      ", addr.marginEngine);
        console.log("ExecutionEngine:   ", addr.executionEngine);
        console.log("LiquidationEngine: ", addr.liquidationEngine);
        console.log("SettlementEngine:  ", addr.settlementEngine);
    }
}