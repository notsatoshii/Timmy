// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/FeeRouter.sol";
import "../contracts/InsuranceFund.sol";

/// @notice Fix missing roles for fee flow from FeeRouter to InsuranceFund
contract FixFeeFlowRoles is Script {
    function run() external {
        vm.startBroadcast();

        // Load contract addresses from environment
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");

        console.log("FeeRouter:", feeRouter);
        console.log("InsuranceFund:", insuranceFund);
        console.log("ExecutionEngine:", executionEngine);

        // Grant ExecutionEngine the EXECUTION_ENGINE_ROLE on FeeRouter
        FeeRouter router = FeeRouter(feeRouter);
        bytes32 executionEngineRole = router.EXECUTION_ENGINE_ROLE();

        console.log("Granting EXECUTION_ENGINE_ROLE to ExecutionEngine...");
        router.grantRole(executionEngineRole, executionEngine);

        // Verify the role was granted
        bool hasExecutionRole = router.hasRole(executionEngineRole, executionEngine);
        console.log("ExecutionEngine has EXECUTION_ENGINE_ROLE:", hasExecutionRole);

        // Grant FeeRouter the FEE_ROUTER_ROLE on InsuranceFund
        InsuranceFund insurance = InsuranceFund(insuranceFund);
        bytes32 feeRouterRole = insurance.FEE_ROUTER_ROLE();

        console.log("Granting FEE_ROUTER_ROLE to FeeRouter...");
        insurance.grantRole(feeRouterRole, feeRouter);

        // Verify the role was granted
        bool hasFeeRouterRole = insurance.hasRole(feeRouterRole, feeRouter);
        console.log("FeeRouter has FEE_ROUTER_ROLE:", hasFeeRouterRole);

        vm.stopBroadcast();

        console.log("Fee flow roles fixed successfully!");
    }
}