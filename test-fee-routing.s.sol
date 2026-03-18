// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IFeeRouter {
    enum FeeType { BORROW, TRANSACTION, LIQUIDATION, SETTLEMENT }

    function routeFees(FeeType feeType, uint256 amount) external;
    function getCurrentTier() external view returns (uint8 tier);
    function getCurrentSplit() external view returns (uint256 lpPct, uint256 protocolPct, uint256 insurancePct);
    function previewSplit(uint256 amount) external view returns (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare);
    function getTotalFeesRouted(FeeType feeType) external view returns (uint256);
    function protocolTreasury() external view returns (address);
}

interface IInsuranceFund {
    function getBalance() external view returns (uint256);
    function getIFR() external view returns (uint256);
    function isFullyFunded() external view returns (bool);
}

interface IRewardsDistributor {
    function getPendingRewards(address user) external view returns (uint256);
}

interface ILeverVault {
    function totalAssets() external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

/// @notice Test script to verify fee routing is working correctly
contract TestFeeRouting is Script {

    uint256 constant TEST_FEE_AMOUNT = 1000e18; // 1000 USDT test fee
    uint256 constant LARGE_DEPOSIT = 30_000_000e18; // 30M USDT to test tier switching

    function run() external {
        // Load contract addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address rewardsDistributor = vm.envAddress("REWARDS_DISTRIBUTOR");
        address leverVault = vm.envAddress("LEVER_VAULT");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== LEVER PROTOCOL FEE ROUTING TEST ===");
        console2.log("Date: 2026-03-18");
        console2.log("Deployer:", deployer);
        console2.log("");

        // Initialize contract interfaces
        IERC20 token = IERC20(usdt);
        IFeeRouter router = IFeeRouter(feeRouter);
        IInsuranceFund insurance = IInsuranceFund(insuranceFund);
        ILeverVault vault = ILeverVault(leverVault);

        // Check initial state
        console2.log("=== INITIAL STATE ===");
        uint256 deployerBalance = token.balanceOf(deployer);
        uint256 initialInsurance = insurance.getBalance();
        uint256 initialTVL = vault.totalAssets();
        uint256 initialIFR = insurance.getIFR();
        uint8 currentTier = router.getCurrentTier();
        bool isFullyFunded = insurance.isFullyFunded();

        console2.log("Deployer USDT balance:", deployerBalance / 1e18, "USDT");
        console2.log("Insurance Fund balance:", initialInsurance / 1e18, "USDT");
        console2.log("LeverVault TVL:", initialTVL / 1e18, "USDT");
        console2.log("Current IFR:", initialIFR / 1e16, "bps");
        console2.log("Current tier:", currentTier);
        console2.log("Is fully funded:", isFullyFunded);
        console2.log("");

        // Show current split
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = router.getCurrentSplit();
        console2.log("Current fee split:");
        console2.log("  LP:", (lpPct * 100) / 1e18, "%");
        console2.log("  Protocol:", (protocolPct * 100) / 1e18, "%");
        console2.log("  Insurance:", (insurancePct * 100) / 1e18, "%");
        console2.log("");

        // Test 1: Preview fee split
        console2.log("=== TEST 1: PREVIEW FEE SPLIT ===");
        (uint256 lpPreview, uint256 protocolPreview, uint256 insurancePreview) = router.previewSplit(TEST_FEE_AMOUNT);
        console2.log("For", TEST_FEE_AMOUNT / 1e18, "USDT fee:");
        console2.log("  LP would get:", lpPreview / 1e18, "USDT");
        console2.log("  Protocol would get:", protocolPreview / 1e18, "USDT");
        console2.log("  Insurance would get:", insurancePreview / 1e18, "USDT");
        console2.log("");

        // Test 2: Actually route fees (simulate)
        console2.log("=== TEST 2: SIMULATE FEE ROUTING ===");
        if (deployerBalance >= TEST_FEE_AMOUNT) {
            vm.startBroadcast();

            // Approve FeeRouter to spend USDT
            token.approve(feeRouter, TEST_FEE_AMOUNT);

            // Get balances before
            uint256 insuranceBefore = insurance.getBalance();
            address treasury = router.protocolTreasury();
            uint256 treasuryBefore = token.balanceOf(treasury);

            console2.log("Routing", TEST_FEE_AMOUNT / 1e18, "USDT as borrow fee...");

            // Route the fee
            router.routeFees(IFeeRouter.FeeType.BORROW, TEST_FEE_AMOUNT);

            // Check balances after
            uint256 insuranceAfter = insurance.getBalance();
            uint256 treasuryAfter = token.balanceOf(treasury);

            console2.log("Insurance balance change:", (insuranceAfter - insuranceBefore) / 1e18, "USDT");
            console2.log("Treasury balance change:", (treasuryAfter - treasuryBefore) / 1e18, "USDT");

            vm.stopBroadcast();
        } else {
            console2.log("Not enough USDT balance to test fee routing");
        }
        console2.log("");

        // Test 3: Test tier switching by adding TVL
        console2.log("=== TEST 3: TEST TIER SWITCHING ===");
        if (deployerBalance >= LARGE_DEPOSIT && currentTier == 2) {
            console2.log("Current tier is 2, testing tier switch by adding TVL...");

            vm.startBroadcast();

            // Approve vault to spend USDT
            token.approve(leverVault, LARGE_DEPOSIT);

            // Deposit to vault to increase TVL
            vault.deposit(LARGE_DEPOSIT, deployer);

            vm.stopBroadcast();

            // Check new state
            uint256 newTVL = vault.totalAssets();
            uint256 newIFR = insurance.getIFR();
            uint8 newTier = router.getCurrentTier();
            bool newFullyFunded = insurance.isFullyFunded();

            console2.log("After large deposit:");
            console2.log("  New TVL:", newTVL / 1e18, "USDT");
            console2.log("  New IFR:", newIFR / 1e16, "bps");
            console2.log("  New tier:", newTier);
            console2.log("  Still fully funded:", newFullyFunded);

            (uint256 newLpPct, uint256 newProtocolPct, uint256 newInsurancePct) = router.getCurrentSplit();
            console2.log("New fee split:");
            console2.log("  LP:", (newLpPct * 100) / 1e18, "%");
            console2.log("  Protocol:", (newProtocolPct * 100) / 1e18, "%");
            console2.log("  Insurance:", (newInsurancePct * 100) / 1e18, "%");

            if (newTier == 1) {
                console2.log("SUCCESS: Tier switched back to 1! Insurance will receive 20% of new fees.");
            } else {
                console2.log("INFO: Still in tier 2. Insurance fund is still overfunded relative to TVL.");
            }
        } else if (currentTier == 1) {
            console2.log("Already in tier 1 - insurance fund is receiving 20% of fees");
        } else {
            console2.log("Not enough USDT balance to test large deposit");
        }
        console2.log("");

        // Test 4: Check fee routing totals
        console2.log("=== TEST 4: HISTORICAL FEE TOTALS ===");
        uint256 borrowTotal = router.getTotalFeesRouted(IFeeRouter.FeeType.BORROW);
        uint256 txTotal = router.getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION);
        uint256 liqTotal = router.getTotalFeesRouted(IFeeRouter.FeeType.LIQUIDATION);
        uint256 settleTotal = router.getTotalFeesRouted(IFeeRouter.FeeType.SETTLEMENT);

        console2.log("Total fees routed by type:");
        console2.log("  Borrow:", borrowTotal / 1e18, "USDT");
        console2.log("  Transaction:", txTotal / 1e18, "USDT");
        console2.log("  Liquidation:", liqTotal / 1e18, "USDT");
        console2.log("  Settlement:", settleTotal / 1e18, "USDT");
        console2.log("  Total:", (borrowTotal + txTotal + liqTotal + settleTotal) / 1e18, "USDT");
        console2.log("");

        // Summary and diagnosis
        console2.log("=== DIAGNOSIS SUMMARY ===");
        if (currentTier == 2 && initialTVL < 1e18) {
            console2.log("FINDING: Insurance Fund not growing because:");
            console2.log("  1. TVL is near zero (", initialTVL, "wei)");
            console2.log("  2. Insurance Fund has large balance (", initialInsurance / 1e18, "USDT)");
            console2.log("  3. IFR = balance/TVL is extremely high");
            console2.log("  4. System is in Tier 2 (50/50/0 split)");
            console2.log("  5. No new fees flow to insurance (working as designed)");
            console2.log("");
            console2.log("SOLUTION: Add LP deposits to increase TVL > 25M USDT");
            console2.log("  This will lower IFR below 20% and switch to Tier 1 (50/30/20 split)");
        } else if (currentTier == 1) {
            console2.log("FINDING: Fee routing is working correctly");
            console2.log("  Insurance Fund is receiving 20% of all fees");
        } else {
            console2.log("FINDING: Insurance Fund is legitimately fully funded");
            console2.log("  IFR >= 20% target, so system uses Tier 2 (50/50/0 split)");
            console2.log("  This is normal protocol behavior");
        }
    }
}