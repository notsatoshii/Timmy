// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/FeeRouter.sol";
import "../contracts/InsuranceFund.sol";
import "../contracts/RewardsDistributor.sol";
import "../contracts/ExecutionEngine.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Verify FeeRouter integration and connections
contract VerifyFeeRouterIntegration is Script {
    function run() external view {
        console.log("=== VERIFYING FEEROUTER INTEGRATION ===");
        console.log("");

        // Load contract addresses
        address feeRouterAddr = vm.envAddress("FEE_ROUTER");
        address insuranceFundAddr = vm.envAddress("INSURANCE_FUND");
        address rewardsDistributorAddr = vm.envAddress("REWARDS_DISTRIBUTOR");
        address executionEngineAddr = vm.envAddress("EXECUTION_ENGINE");
        address usdtAddr = vm.envAddress("USDT_ADDRESS");

        FeeRouter feeRouter = FeeRouter(feeRouterAddr);
        InsuranceFund insuranceFund = InsuranceFund(insuranceFundAddr);

        console.log("Contract Addresses:");
        console.log("  FeeRouter:", feeRouterAddr);
        console.log("  InsuranceFund:", insuranceFundAddr);
        console.log("  RewardsDistributor:", rewardsDistributorAddr);
        console.log("  ExecutionEngine:", executionEngineAddr);
        console.log("  USDT:", usdtAddr);
        console.log("");

        // 1. Check FeeRouter state variables (connections)
        console.log("1. CHECKING FEEROUTER CONNECTIONS:");

        address feeRouterUsdt = address(feeRouter.usdt());
        address feeRouterInsurance = address(feeRouter.insuranceFund());
        address feeRouterRewards = address(feeRouter.rewardsDistributor());
        address feeRouterTreasury = feeRouter.protocolTreasury();

        console.log("  USDT connection:", feeRouterUsdt);
        console.log("    Expected:", usdtAddr);
        console.log("    Match:", feeRouterUsdt == usdtAddr ? "PASS" : "FAIL");
        console.log("");

        console.log("  InsuranceFund connection:", feeRouterInsurance);
        console.log("    Expected:", insuranceFundAddr);
        console.log("    Match:", feeRouterInsurance == insuranceFundAddr ? "PASS" : "FAIL");
        console.log("");

        console.log("  RewardsDistributor connection:", feeRouterRewards);
        console.log("    Expected:", rewardsDistributorAddr);
        console.log("    Match:", feeRouterRewards == rewardsDistributorAddr ? "PASS" : "FAIL");
        console.log("");

        console.log("  Protocol Treasury:", feeRouterTreasury);
        console.log("    Set:", feeRouterTreasury != address(0) ? "PASS" : "FAIL");
        console.log("");

        // 2. Check roles
        console.log("2. CHECKING ROLES:");

        bytes32 executionEngineRole = feeRouter.EXECUTION_ENGINE_ROLE();
        bool hasExecutionRole = feeRouter.hasRole(executionEngineRole, executionEngineAddr);
        console.log("  ExecutionEngine has EXECUTION_ENGINE_ROLE:", hasExecutionRole ? "PASS" : "FAIL");

        bytes32 feeRouterRole = insuranceFund.FEE_ROUTER_ROLE();
        bool hasFeeRouterRole = insuranceFund.hasRole(feeRouterRole, feeRouterAddr);
        console.log("  FeeRouter has FEE_ROUTER_ROLE on InsuranceFund:", hasFeeRouterRole ? "PASS" : "FAIL");
        console.log("");

        // 3. Check fee distribution functionality
        console.log("3. CHECKING FEE DISTRIBUTION:");

        uint8 currentTier = feeRouter.getCurrentTier();
        console.log("  Current tier:", currentTier);

        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = feeRouter.getCurrentSplit();
        console.log("  Current split percentages:");
        console.log("    LP:", lpPct / 1e15, "bps");
        console.log("    Protocol:", protocolPct / 1e15, "bps");
        console.log("    Insurance:", insurancePct / 1e15, "bps");

        // Verify splits add up to 100%
        uint256 totalPct = lpPct + protocolPct + insurancePct;
        console.log("  Total percentage:", totalPct * 100 / 1e18);
        console.log("  Split math correct:", totalPct == 1e18 ? "PASS" : "FAIL");
        console.log("");

        // 4. Test preview split function
        console.log("4. TESTING PREVIEW SPLIT FUNCTION:");
        uint256 testAmount = 1000e18; // 1000 USDT
        (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare) = feeRouter.previewSplit(testAmount);

        console.log("  For 1000 USDT test amount:");
        console.log("    LP share:", lpShare / 1e18);
        console.log("    Protocol share:", protocolShare / 1e18);
        console.log("    Insurance share:", insuranceShare / 1e18);

        uint256 totalShares = lpShare + protocolShare + insuranceShare;
        console.log("  Total shares:", totalShares / 1e18);
        console.log("  Preview math correct:", totalShares == testAmount ? "PASS" : "FAIL");
        console.log("");

        // 5. Check historical fee routing
        console.log("5. CHECKING FEE ROUTING HISTORY:");

        // Check different fee types
        uint256 txFees = feeRouter.getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION);
        uint256 borrowFees = feeRouter.getTotalFeesRouted(IFeeRouter.FeeType.BORROW);
        uint256 liquidationFees = feeRouter.getTotalFeesRouted(IFeeRouter.FeeType.LIQUIDATION);
        uint256 settlementFees = feeRouter.getTotalFeesRouted(IFeeRouter.FeeType.SETTLEMENT);

        console.log("  Transaction fees routed:", txFees / 1e18);
        console.log("  Borrow fees routed:", borrowFees / 1e18);
        console.log("  Liquidation fees routed:", liquidationFees / 1e18);
        console.log("  Settlement fees routed:", settlementFees / 1e18);

        uint256 totalFeesRouted = txFees + borrowFees + liquidationFees + settlementFees;
        console.log("  Total fees routed:", totalFeesRouted / 1e18);
        console.log("  Has fee activity:", totalFeesRouted > 0 ? "PASS" : "FAIL");
        console.log("");

        // 6. Check insurance fund status
        console.log("6. INSURANCE FUND STATUS:");
        uint256 insuranceBalance = insuranceFund.getBalance();
        uint256 ifr = insuranceFund.getIFR();
        bool isFullyFunded = insuranceFund.isFullyFunded();

        console.log("  Insurance fund balance:", insuranceBalance / 1e18);
        console.log("  IFR (Insurance Fund Ratio):", ifr / 1e15);
        console.log("  Is fully funded (>= 20% IFR):", isFullyFunded ? "PASS" : "FAIL");
        console.log("");

        // 7. Summary
        console.log("7. INTEGRATION SUMMARY:");

        bool allConnectionsCorrect = (feeRouterUsdt == usdtAddr) &&
                                   (feeRouterInsurance == insuranceFundAddr) &&
                                   (feeRouterRewards == rewardsDistributorAddr) &&
                                   (feeRouterTreasury != address(0));

        bool rolesCorrect = hasExecutionRole && hasFeeRouterRole;
        bool mathCorrect = (totalPct == 1e18) && (totalShares == testAmount);

        console.log("  Connections correct:", allConnectionsCorrect ? "PASS" : "FAIL");
        console.log("  Roles configured:", rolesCorrect ? "PASS" : "FAIL");
        console.log("  Fee math correct:", mathCorrect ? "PASS" : "FAIL");
        console.log("");

        if (allConnectionsCorrect && rolesCorrect && mathCorrect) {
            console.log("SUCCESS: FEEROUTER INTEGRATION VERIFICATION: PASSED");
        } else {
            console.log("ERROR: FEEROUTER INTEGRATION VERIFICATION: FAILED");
            if (!allConnectionsCorrect) console.log("  - Fix contract connections");
            if (!rolesCorrect) console.log("  - Fix role configurations");
            if (!mathCorrect) console.log("  - Fix fee calculation logic");
        }
    }
}