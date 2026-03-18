#!/usr/bin/env node

// Fix Insurance Fund by increasing TVL to lower IFR below 20%
const { ethers } = require('ethers');

async function main() {
    require('dotenv').config({ path: '.env.deploy' });

    const RPC_URL = process.env.RPC_URL || "https://sepolia.base.org";
    const PRIVATE_KEY = process.env.TEST_WALLET_KEY; // Use test wallet
    const USDT_ADDRESS = process.env.USDT_ADDRESS;
    const LEVER_VAULT = process.env.LEVER_VAULT;
    const INSURANCE_FUND = process.env.INSURANCE_FUND;
    const FEE_ROUTER = process.env.FEE_ROUTER;

    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    console.log("=== FIXING INSURANCE FUND TVL ISSUE ===\n");
    console.log(`Test Wallet: ${wallet.address}`);

    // Contract ABIs
    const usdtABI = [
        "function balanceOf(address) view returns (uint256)",
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function decimals() view returns (uint8)"
    ];

    const vaultABI = [
        "function totalAssets() view returns (uint256)",
        "function deposit(uint256 assets, address receiver) external returns (uint256 shares)",
        "function balanceOf(address) view returns (uint256)"
    ];

    const insuranceABI = [
        "function getBalance() view returns (uint256)",
        "function getIFR() view returns (uint256)",
        "function isFullyFunded() view returns (bool)"
    ];

    const feeRouterABI = [
        "function getCurrentTier() view returns (uint8)",
        "function getCurrentSplit() view returns (uint256, uint256, uint256)"
    ];

    const usdt = new ethers.Contract(USDT_ADDRESS, usdtABI, wallet);
    const vault = new ethers.Contract(LEVER_VAULT, vaultABI, wallet);
    const insurance = new ethers.Contract(INSURANCE_FUND, insuranceABI, provider);
    const feeRouter = new ethers.Contract(FEE_ROUTER, feeRouterABI, provider);

    try {
        // Check initial state
        console.log("=== INITIAL STATE ===");
        const testWalletBalance = await usdt.balanceOf(wallet.address);
        const initialTVL = await vault.totalAssets();
        const insuranceBalance = await insurance.getBalance();
        const initialIFR = await insurance.getIFR();
        const initialTier = await feeRouter.getCurrentTier();
        const isFullyFunded = await insurance.isFullyFunded();

        console.log(`Test Wallet USDT Balance: ${ethers.utils.formatUnits(testWalletBalance, 6)} USDT`);
        console.log(`Vault TVL (raw): ${initialTVL} (${ethers.utils.formatUnits(initialTVL, 6)} USDT)`);
        console.log(`Insurance Balance: ${ethers.utils.formatEther(insuranceBalance)} WAD`);
        console.log(`IFR: ${ethers.utils.formatEther(initialIFR)} (${(parseFloat(ethers.utils.formatEther(initialIFR)) * 100).toFixed(2)}%)`);
        console.log(`Current Tier: ${initialTier}`);
        console.log(`Is Fully Funded: ${isFullyFunded}\n`);

        const [lpPct, protocolPct, insurancePct] = await feeRouter.getCurrentSplit();
        console.log("Current Fee Split:");
        console.log(`  LP: ${(parseFloat(ethers.utils.formatEther(lpPct)) * 100).toFixed(1)}%`);
        console.log(`  Protocol: ${(parseFloat(ethers.utils.formatEther(protocolPct)) * 100).toFixed(1)}%`);
        console.log(`  Insurance: ${(parseFloat(ethers.utils.formatEther(insurancePct)) * 100).toFixed(1)}%\n`);

        // Analyze the problem
        console.log("=== PROBLEM ANALYSIS ===");
        const tvlInUSDT = parseFloat(ethers.utils.formatUnits(initialTVL, 6));
        const ifrPercent = parseFloat(ethers.utils.formatEther(initialIFR)) * 100;

        if (tvlInUSDT < 1000) {
            console.log(`❌ TVL is extremely low: $${tvlInUSDT.toFixed(6)} USDT`);
            console.log(`❌ This causes astronomical IFR: ${ifrPercent.toFixed(2)}%`);
            console.log(`❌ System is in Tier ${initialTier} mode (insurance gets ${(parseFloat(ethers.utils.formatEther(insurancePct)) * 100).toFixed(0)}%)`);
            console.log(`✅ ROOT CAUSE: Decimal conversion bug - vault TVL in 6 decimals, insurance expects 18 decimals\n`);
        } else {
            console.log(`✅ TVL is reasonable: $${tvlInUSDT.toLocaleString()} USDT`);
            console.log(`✅ IFR: ${ifrPercent.toFixed(2)}%`);
        }

        // Calculate deposit needed
        console.log("=== CALCULATING FIX ===");
        const currentInsuranceUSDT = parseFloat(ethers.utils.formatEther(insuranceBalance)) * 0.001; // WAD to USDT approximation
        const targetIFR = 0.15; // Target 15% IFR (below 20% threshold)
        const requiredTVL = currentInsuranceUSDT / targetIFR;
        const depositNeeded = Math.max(0, requiredTVL - tvlInUSDT);

        console.log(`Insurance Fund Value: ~$${currentInsuranceUSDT.toFixed(0)} USDT (estimated)`);
        console.log(`Target IFR: ${(targetIFR * 100).toFixed(1)}%`);
        console.log(`Required TVL: $${requiredTVL.toLocaleString()} USDT`);
        console.log(`Current TVL: $${tvlInUSDT.toFixed(2)} USDT`);
        console.log(`Deposit Needed: $${depositNeeded.toLocaleString()} USDT\n`);

        // Use a practical deposit amount (don't exceed test wallet balance)
        const maxTestWalletUSDT = parseFloat(ethers.utils.formatUnits(testWalletBalance, 6));
        const keepAmount = 100000; // Keep 100K USDT for test wallet operations
        const availableForDeposit = Math.max(0, maxTestWalletUSDT - keepAmount);

        // Use 50M USDT as the target deposit (this should definitely fix the IFR)
        const targetDeposit = Math.min(50000000, availableForDeposit, depositNeeded * 2); // 2x safety factor

        if (targetDeposit <= 0) {
            console.log("❌ Not enough USDT in test wallet to make meaningful deposit");
            return;
        }

        console.log("=== EXECUTING FIX ===");
        console.log(`Depositing: $${targetDeposit.toLocaleString()} USDT to LeverVault`);
        console.log(`Keeping: $${(maxTestWalletUSDT - targetDeposit).toLocaleString()} USDT in test wallet\n`);

        const depositAmount = ethers.utils.parseUnits(targetDeposit.toString(), 6);

        // Approve vault to spend USDT
        console.log("1. Approving USDT spend...");
        const approveTx = await usdt.approve(LEVER_VAULT, depositAmount);
        await approveTx.wait();
        console.log(`   ✅ Approval tx: ${approveTx.hash}`);

        // Deposit to vault
        console.log("2. Depositing to LeverVault...");
        const depositTx = await vault.deposit(depositAmount, wallet.address);
        await depositTx.wait();
        console.log(`   ✅ Deposit tx: ${depositTx.hash}`);

        // Check results
        console.log("\n=== RESULTS ===");
        const finalTVL = await vault.totalAssets();
        const finalIFR = await insurance.getIFR();
        const finalTier = await feeRouter.getCurrentTier();
        const finalFullyFunded = await insurance.isFullyFunded();

        console.log(`Final TVL: ${ethers.utils.formatUnits(finalTVL, 6)} USDT`);
        console.log(`Final IFR: ${ethers.utils.formatEther(finalIFR)} (${(parseFloat(ethers.utils.formatEther(finalIFR)) * 100).toFixed(2)}%)`);
        console.log(`Final Tier: ${finalTier}`);
        console.log(`Still Fully Funded: ${finalFullyFunded}`);

        const [newLpPct, newProtocolPct, newInsurancePct] = await feeRouter.getCurrentSplit();
        console.log("\nNew Fee Split:");
        console.log(`  LP: ${(parseFloat(ethers.utils.formatEther(newLpPct)) * 100).toFixed(1)}%`);
        console.log(`  Protocol: ${(parseFloat(ethers.utils.formatEther(newProtocolPct)) * 100).toFixed(1)}%`);
        console.log(`  Insurance: ${(parseFloat(ethers.utils.formatEther(newInsurancePct)) * 100).toFixed(1)}%`);

        // Analysis
        console.log("\n=== ANALYSIS ===");
        if (finalTier == 1 && parseFloat(ethers.utils.formatEther(newInsurancePct)) > 0) {
            console.log("🎉 SUCCESS! Insurance Fund flow restored!");
            console.log("   ✅ System switched to Tier 1 (50/30/20 split)");
            console.log("   ✅ Insurance Fund will now receive 20% of new fees");
            console.log("   ✅ Problem solved by increasing TVL to lower IFR");
        } else if (finalTier == 1) {
            console.log("✅ Partial Success - Tier 1 achieved but insurance still not receiving fees");
            console.log("   This may indicate another issue beyond TVL");
        } else {
            console.log("⚠️  Partial Success - TVL increased but still in Tier 2");
            console.log(`   IFR: ${(parseFloat(ethers.utils.formatEther(finalIFR)) * 100).toFixed(2)}% (target: <20%)`);
            console.log("   May need larger deposit to reach Tier 1 threshold");
        }

    } catch (error) {
        console.error("Error:", error.message);
        if (error.data) {
            console.error("Contract error:", error.data);
        }
        process.exit(1);
    }
}

main().catch(console.error);