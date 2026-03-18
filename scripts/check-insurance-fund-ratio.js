#!/usr/bin/env node

// Check Insurance Fund Ratio to understand why no fees are going to insurance fund
const { ethers } = require('ethers');

async function main() {
    require('dotenv').config({ path: '.env.deploy' });

    const RPC_URL = process.env.RPC_URL || "https://sepolia.base.org";
    const INSURANCE_FUND = process.env.INSURANCE_FUND;
    const LEVER_VAULT = process.env.LEVER_VAULT;

    console.log("=== INSURANCE FUND RATIO CHECK ===\n");

    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);

    // Contract ABIs
    const insuranceFundABI = [
        "function getBalance() view returns (uint256)",
        "function getIFR() view returns (uint256)",
        "function isFullyFunded() view returns (bool)",
        "function getTVL() view returns (uint256)"
    ];

    const vaultABI = [
        "function getTotalAssets() view returns (uint256)",
        "function totalAssets() view returns (uint256)"
    ];

    try {
        const insuranceFund = new ethers.Contract(INSURANCE_FUND, insuranceFundABI, provider);
        const vault = new ethers.Contract(LEVER_VAULT, vaultABI, provider);

        console.log(`Insurance Fund: ${INSURANCE_FUND}`);
        console.log(`Lever Vault: ${LEVER_VAULT}\n`);

        // Get insurance fund balance
        const insuranceBalance = await insuranceFund.getBalance();
        console.log(`Insurance Fund Balance: ${ethers.utils.formatEther(insuranceBalance)} WAD`);
        console.log(`Insurance Fund Balance: $${(parseFloat(ethers.utils.formatEther(insuranceBalance)) * 0.001).toFixed(3)}\n`);

        // Get vault TVL (try both possible method names)
        let vaultTVL;
        try {
            vaultTVL = await vault.getTotalAssets();
            console.log(`Vault TVL (getTotalAssets): ${ethers.utils.formatEther(vaultTVL)} WAD`);
        } catch (e) {
            try {
                vaultTVL = await vault.totalAssets();
                console.log(`Vault TVL (totalAssets): ${ethers.utils.formatEther(vaultTVL)} WAD`);
            } catch (e2) {
                console.log("❌ Could not get vault TVL");
                return;
            }
        }

        console.log(`Vault TVL: $${(parseFloat(ethers.utils.formatEther(vaultTVL)) * 0.001).toFixed(3)}\n`);

        // Calculate IFR manually
        const manualIFR = insuranceBalance.mul(ethers.utils.parseEther("1")).div(vaultTVL);
        const manualIFRPercent = parseFloat(ethers.utils.formatEther(manualIFR)) * 100;

        console.log(`Manual IFR Calculation: ${ethers.utils.formatEther(manualIFR)} (${manualIFRPercent.toFixed(2)}%)\n`);

        // Get IFR from contract
        try {
            const contractIFR = await insuranceFund.getIFR();
            const contractIFRPercent = parseFloat(ethers.utils.formatEther(contractIFR)) * 100;
            console.log(`Contract IFR: ${ethers.utils.formatEther(contractIFR)} (${contractIFRPercent.toFixed(2)}%)`);
        } catch (e) {
            console.log("❌ Could not get IFR from contract:", e.message);
        }

        // Check if fully funded
        try {
            const isFullyFunded = await insuranceFund.isFullyFunded();
            console.log(`Is Fully Funded: ${isFullyFunded ? 'YES' : 'NO'}`);
        } catch (e) {
            console.log("❌ Could not check isFullyFunded:", e.message);
        }

        console.log(`\n=== ANALYSIS ===`);
        if (manualIFRPercent >= 20) {
            console.log(`✅ IFR (${manualIFRPercent.toFixed(2)}%) ≥ 20% → System in Tier 2 mode (50/50/0 split)`);
            console.log(`   This explains why Insurance Fund gets 0% of fees.`);
            console.log(`   The insurance fund is already well-funded and working as designed.`);
        } else {
            console.log(`⚠️  IFR (${manualIFRPercent.toFixed(2)}%) < 20% → Should be in Tier 1 mode (50/30/20 split)`);
            console.log(`   Insurance Fund should be receiving 20% of fees.`);
        }

    } catch (error) {
        console.error("Error:", error.message);
        process.exit(1);
    }
}

main().catch(console.error);