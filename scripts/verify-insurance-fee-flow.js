#!/usr/bin/env node

// Verify FeeRouter to Insurance Fund fee flow
const { ethers } = require('ethers');

async function main() {
    // Load config
    require('dotenv').config({ path: '.env.deploy' });

    const RPC_URL = process.env.RPC_URL || "https://sepolia.base.org";
    const FEE_ROUTER = process.env.FEE_ROUTER;
    const INSURANCE_FUND = process.env.INSURANCE_FUND;
    const USDT_ADDRESS = process.env.USDT_ADDRESS;

    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);

    console.log("=== INSURANCE FUND FEE FLOW VERIFICATION ===\n");

    // FeeRouter ABI (events only)
    const feeRouterABI = [
        "event FeesRouted(uint8 indexed feeType, uint256 amount, uint256 lpShare, uint256 protocolShare, uint256 insuranceShare, uint8 tier)"
    ];

    // Insurance Fund ABI (events only)
    const insuranceFundABI = [
        "event FundsDeposited(uint256 amount, uint256 newBalance, uint256 timestamp)",
        "function getBalance() view returns (uint256)"
    ];

    // USDT ABI (minimal)
    const usdtABI = [
        "event Transfer(address indexed from, address indexed to, uint256 value)",
        "function balanceOf(address) view returns (uint256)"
    ];

    const feeRouter = new ethers.Contract(FEE_ROUTER, feeRouterABI, provider);
    const insuranceFund = new ethers.Contract(INSURANCE_FUND, insuranceFundABI, provider);
    const usdt = new ethers.Contract(USDT_ADDRESS, usdtABI, provider);

    try {
        // Get recent blocks to check
        const currentBlock = await provider.getBlockNumber();
        const fromBlock = Math.max(currentBlock - 10000, 0); // Last ~10k blocks

        console.log(`Checking blocks ${fromBlock} to ${currentBlock}`);
        console.log(`FeeRouter: ${FEE_ROUTER}`);
        console.log(`Insurance Fund: ${INSURANCE_FUND}`);
        console.log(`USDT: ${USDT_ADDRESS}\n`);

        // 1. Check recent fee routing events
        console.log("=== RECENT FEE ROUTING EVENTS ===");
        const feeEvents = await feeRouter.queryFilter("FeesRouted", fromBlock);

        if (feeEvents.length === 0) {
            console.log("❌ No fee routing events found in recent blocks");
        } else {
            console.log(`✅ Found ${feeEvents.length} fee routing events`);

            // Show last 3 events
            const recentEvents = feeEvents.slice(-3);
            recentEvents.forEach((event, i) => {
                const args = event.args;
                console.log(`\n${i + 1}. Block ${event.blockNumber}:`);
                console.log(`   Fee Type: ${args.feeType}`);
                console.log(`   Total Amount: ${ethers.utils.formatUnits(args.amount, 6)} USDT`);
                console.log(`   LP Share: ${ethers.utils.formatUnits(args.lpShare, 6)} USDT`);
                console.log(`   Protocol Share: ${ethers.utils.formatUnits(args.protocolShare, 6)} USDT`);
                console.log(`   Insurance Share: ${ethers.utils.formatUnits(args.insuranceShare, 6)} USDT`);
                console.log(`   Tier: ${args.tier}`);
            });
        }

        // 2. Check USDT transfers to Insurance Fund
        console.log("\n=== USDT TRANSFERS TO INSURANCE FUND ===");
        const transferFilter = usdt.filters.Transfer(null, INSURANCE_FUND);
        const transfers = await usdt.queryFilter(transferFilter, fromBlock);

        if (transfers.length === 0) {
            console.log("❌ No USDT transfers to Insurance Fund found");
        } else {
            console.log(`✅ Found ${transfers.length} USDT transfers to Insurance Fund`);

            // Show last 3 transfers
            const recentTransfers = transfers.slice(-3);
            recentTransfers.forEach((event, i) => {
                const args = event.args;
                console.log(`\n${i + 1}. Block ${event.blockNumber}:`);
                console.log(`   From: ${args.from}`);
                console.log(`   Amount: ${ethers.utils.formatUnits(args.value, 6)} USDT`);
                console.log(`   From FeeRouter: ${args.from === FEE_ROUTER ? '✅' : '❌'}`);
            });
        }

        // 3. Check Insurance Fund deposit events
        console.log("\n=== INSURANCE FUND DEPOSITS ===");
        const depositEvents = await insuranceFund.queryFilter("FundsDeposited", fromBlock);

        if (depositEvents.length === 0) {
            console.log("❌ No deposit events found");
        } else {
            console.log(`✅ Found ${depositEvents.length} deposit events`);

            // Show last 3 deposits
            const recentDeposits = depositEvents.slice(-3);
            recentDeposits.forEach((event, i) => {
                const args = event.args;
                console.log(`\n${i + 1}. Block ${event.blockNumber}:`);
                console.log(`   Deposit Amount: ${ethers.utils.formatUnits(args.amount, 6)} USDT`);
                console.log(`   New Internal Balance: ${ethers.utils.formatEther(args.newBalance)} WAD`);
                console.log(`   Timestamp: ${new Date(args.timestamp * 1000).toISOString()}`);
            });
        }

        // 4. Current balances
        console.log("\n=== CURRENT BALANCES ===");
        const actualBalance = await usdt.balanceOf(INSURANCE_FUND);
        const trackedBalance = await insuranceFund.getBalance();

        console.log(`Actual USDT Balance: ${ethers.utils.formatUnits(actualBalance, 6)} USDT`);
        console.log(`Tracked Internal Balance: ${ethers.utils.formatEther(trackedBalance)} WAD`);

        const balancesMatch = actualBalance.mul(ethers.utils.parseEther("1")).div(ethers.utils.parseUnits("1", 6)).eq(trackedBalance);
        console.log(`Balances Match: ${balancesMatch ? '✅' : '❌'}`);

        if (!balancesMatch) {
            console.log(`\n⚠️  MISMATCH DETECTED:`);
            console.log(`   Actual:  ${actualBalance} (raw USDT wei)`);
            console.log(`   Tracked: ${trackedBalance} (raw WAD)`);
            console.log(`   Expected tracked: ${actualBalance.mul(ethers.utils.parseEther("1")).div(ethers.utils.parseUnits("1", 6))}`);
        }

        // 5. Fee flow assessment
        console.log("\n=== FEE FLOW ASSESSMENT ===");

        const hasRecentFees = feeEvents.length > 0;
        const hasRecentTransfers = transfers.length > 0 && transfers.some(t => t.args.from === FEE_ROUTER);
        const hasRecentDeposits = depositEvents.length > 0;

        console.log(`Recent fee routing: ${hasRecentFees ? '✅' : '❌'}`);
        console.log(`FeeRouter → Insurance transfers: ${hasRecentTransfers ? '✅' : '❌'}`);
        console.log(`Insurance fund deposits: ${hasRecentDeposits ? '✅' : '❌'}`);

        if (hasRecentFees && hasRecentTransfers && hasRecentDeposits) {
            console.log(`\n✅ FEE FLOW IS WORKING CORRECTLY`);
        } else if (!hasRecentFees) {
            console.log(`\n⚠️  NO RECENT FEE ACTIVITY (may be normal if no trading)`);
        } else {
            console.log(`\n❌ FEE FLOW HAS ISSUES - MISSING COMPONENTS`);
        }

    } catch (error) {
        console.error("Error:", error.message);
        process.exit(1);
    }
}

main().catch(console.error);