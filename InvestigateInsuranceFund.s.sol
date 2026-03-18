// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/InsuranceFund.sol";
import "./contracts/FeeRouter.sol";
import "./contracts/LeverVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Comprehensive investigation of Insurance Fund not growing
contract InvestigateInsuranceFund is Script {
    function run() external view {
        // Load contract addresses
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address leverVault = vm.envAddress("LEVER_VAULT");
        address usdt = vm.envAddress("USDT_ADDRESS");

        console.log("=== INSURANCE FUND GROWTH INVESTIGATION ===");
        console.log("Date: 2026-03-18");
        console.log("");

        // 1. Current balances
        uint256 insuranceBalance = InsuranceFund(insuranceFund).getBalance();
        uint256 vaultTVL = LeverVault(leverVault).totalAssets();
        uint256 vaultShares = LeverVault(leverVault).totalSupply();

        console.log("=== CURRENT STATE ===");
        console.log("Insurance Fund Balance:", insuranceBalance / 1e18, "USDT");
        console.log("LeverVault TVL:", vaultTVL / 1e18, "USDT");
        console.log("LeverVault TVL (wei):", vaultTVL);
        console.log("LeverVault Shares:", vaultShares / 1e18, "lvUSDT");
        console.log("");

        // 2. IFR calculation
        uint256 ifr = InsuranceFund(insuranceFund).getIFR();
        uint256 target = InsuranceFund(insuranceFund).getTarget();
        uint256 floor = InsuranceFund(insuranceFund).getFloor();
        bool isFullyFunded = InsuranceFund(insuranceFund).isFullyFunded();

        console.log("=== INSURANCE FUND RATIO (IFR) ===");
        console.log("Current IFR:", ifr / 1e18, "(WAD units)");
        console.log("IFR Target (20%):", target / 1e18, "USDT");
        console.log("IFR Floor (5%):", floor / 1e18, "USDT");
        console.log("Is Fully Funded:", isFullyFunded);
        console.log("");

        if (vaultTVL > 0) {
            console.log("IFR Calculation:");
            console.log("  Balance:", insuranceBalance / 1e18, "USDT");
            console.log("  TVL:", vaultTVL / 1e18, "USDT");
            console.log("  IFR Percentage:", (ifr * 100) / 1e18, "%");
        } else {
            console.log("WARNING: TVL is essentially zero, causing infinite IFR!");
        }
        console.log("");

        // 3. Fee router tier and split
        uint8 tier = FeeRouter(feeRouter).getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = FeeRouter(feeRouter).getCurrentSplit();

        console.log("=== FEE ROUTING ===");
        console.log("Current Tier:", tier);
        console.log("Fee Split:");
        console.log("  LP:", (lpPct * 100) / 1e18, "%");
        console.log("  Protocol:", (protocolPct * 100) / 1e18, "%");
        console.log("  Insurance:", (insurancePct * 100) / 1e18, "%");
        console.log("");

        // 4. Fee totals
        uint256 txFeesRouted = FeeRouter(feeRouter).getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION);
        uint256 borrowFeesRouted = FeeRouter(feeRouter).getTotalFeesRouted(IFeeRouter.FeeType.BORROW);

        console.log("=== TOTAL FEES ROUTED ===");
        console.log("Transaction fees:", txFeesRouted / 1e18, "USDT");
        console.log("Borrow fees:", borrowFeesRouted / 1e18, "USDT");
        console.log("Total protocol fees:", (txFeesRouted + borrowFeesRouted) / 1e18, "USDT");
        console.log("");

        // 5. Analysis and diagnosis
        console.log("=== DIAGNOSIS ===");

        if (vaultTVL < 1e18) {
            console.log("ROOT CAUSE: TVL is essentially zero");
            console.log("  TVL in wei:", vaultTVL);
            console.log("  TVL in USDT:", vaultTVL / 1e18);
            console.log("");
            console.log("IMPACT:");
            console.log("  1. IFR = insurance_balance / TVL = huge number");
            console.log("  2. isFullyFunded() returns true (IFR > 20% target)");
            console.log("  3. FeeRouter switches to Tier 2 (50/50/0 split)");
            console.log("  4. Insurance fund receives 0% of new fees");
            console.log("");
            console.log("SOLUTION:");
            console.log("  Need LP deposits to increase TVL, which will:");
            console.log("  - Lower IFR to reasonable levels");
            console.log("  - Switch back to Tier 1 (50/30/20 split)");
            console.log("  - Resume 20% fee flow to insurance fund");
        } else if (isFullyFunded) {
            console.log("Insurance fund is legitimately fully funded (IFR >= 20%)");
            console.log("This is normal protocol behavior - no fees go to insurance in Tier 2");
        } else {
            console.log("Unknown issue - insurance fund should be receiving fees");
            console.log("Check fee router role permissions and contract connections");
        }

        // 6. Recommendations
        console.log("");
        console.log("=== RECOMMENDATIONS ===");
        if (vaultTVL < 1e18) {
            console.log("1. Add LP deposits to LeverVault to establish meaningful TVL");
            console.log("2. Target TVL > 25 million USDT to bring IFR below 20%");
            console.log("3. Monitor IFR ratio: should be < 20% for Tier 1 fee routing");
            console.log("4. Expected result: FeeRouter switches to Tier 1, insurance gets 20%");
        }
    }
}