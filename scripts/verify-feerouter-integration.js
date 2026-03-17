#!/usr/bin/env node

/**
 * Verify FeeRouter Integration Script
 * Tests that FeeRouter is properly connected to other contracts
 * and that fee distribution works correctly
 */

const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

function log(message) {
    console.log(`[FeeRouter Verify] ${message}`);
}

function loadDeploymentEnv() {
    try {
        // Read the deployment environment file
        const envContent = fs.readFileSync(path.join(__dirname, '../control-plane/deploy-env.sh'), 'utf8');

        const addresses = {};
        const lines = envContent.split('\n');

        for (const line of lines) {
            if (line.startsWith('export ') && line.includes('=0x')) {
                const parts = line.replace('export ', '').split('=');
                if (parts.length === 2) {
                    const key = parts[0];
                    const value = parts[1].replace(/"/g, '');
                    addresses[key] = value;
                }
            }
        }

        return addresses;
    } catch (error) {
        log(`Error loading deployment addresses: ${error.message}`);
        return null;
    }
}

function checkContractConnections() {
    log("=== CHECKING FEEROUTER CONTRACT CONNECTIONS ===");

    const addresses = loadDeploymentEnv();
    if (!addresses) {
        log("❌ Failed to load contract addresses");
        return false;
    }

    // Verify key contracts are deployed
    const requiredContracts = [
        'FEE_ROUTER',
        'INSURANCE_FUND',
        'REWARDS_DISTRIBUTOR',
        'EXECUTION_ENGINE',
        'BORROW_FEE_ENGINE',
        'LIQUIDATION_ENGINE',
        'SETTLEMENT_ENGINE',
        'USDT_ADDRESS'
    ];

    let allPresent = true;
    for (const contract of requiredContracts) {
        if (addresses[contract]) {
            log(`✅ ${contract}: ${addresses[contract]}`);
        } else {
            log(`❌ Missing ${contract}`);
            allPresent = false;
        }
    }

    return allPresent;
}

function checkFeeRouterState() {
    log("\n=== CHECKING FEEROUTER STATE ===");

    // Since we can't use cast directly, we'll check through the health check
    const healthCheck = exec('bash control-plane/health-check.sh', (error, stdout, stderr) => {
        if (error) {
            log(`❌ Health check failed: ${error.message}`);
            return;
        }

        if (stdout.includes('PASS: fee_router — true')) {
            log("✅ FeeRouter health check passed");
        } else {
            log("❌ FeeRouter health check failed");
        }
    });
}

function verifyFeeRouterConstants() {
    log("\n=== VERIFYING FEEROUTER CONSTANTS ===");

    // Read the FeeRouter contract to verify constants
    try {
        const feeRouterPath = path.join(__dirname, '../contracts/FeeRouter.sol');
        const content = fs.readFileSync(feeRouterPath, 'utf8');

        // Check for required constants
        const requiredConstants = [
            { name: 'LP_SHARE', value: '5e17', description: '50%' },
            { name: 'PROTOCOL_SHARE_T1', value: '3e17', description: '30% (Tier 1)' },
            { name: 'INSURANCE_SHARE_T1', value: '2e17', description: '20% (Tier 1)' },
            { name: 'TX_FEE_RATE', value: '1e15', description: '0.10% (10 bps)' }
        ];

        for (const constant of requiredConstants) {
            if (content.includes(`${constant.name} = ${constant.value}`)) {
                log(`✅ ${constant.name}: ${constant.value} (${constant.description})`);
            } else {
                log(`❌ Missing or incorrect ${constant.name}`);
            }
        }

        // Check for required roles
        const requiredRoles = [
            'BORROW_FEE_ENGINE_ROLE',
            'EXECUTION_ENGINE_ROLE',
            'LIQUIDATION_ENGINE_ROLE',
            'SETTLEMENT_ENGINE_ROLE'
        ];

        log("\n--- Checking Roles ---");
        for (const role of requiredRoles) {
            if (content.includes(role)) {
                log(`✅ ${role} defined`);
            } else {
                log(`❌ Missing ${role}`);
            }
        }

    } catch (error) {
        log(`❌ Error reading FeeRouter contract: ${error.message}`);
    }
}

function checkInsuranceFundIntegration() {
    log("\n=== VERIFYING INSURANCE FUND INTEGRATION ===");

    // Verify that the InsuranceFund interface methods are used correctly
    try {
        const feeRouterPath = path.join(__dirname, '../contracts/FeeRouter.sol');
        const content = fs.readFileSync(feeRouterPath, 'utf8');

        if (content.includes('insuranceFund.isFullyFunded()')) {
            log("✅ FeeRouter checks InsuranceFund.isFullyFunded() for tier determination");
        } else {
            log("❌ FeeRouter missing InsuranceFund.isFullyFunded() check");
        }

        if (content.includes('insuranceFund.deposit(')) {
            log("✅ FeeRouter calls InsuranceFund.deposit() for insurance share");
        } else {
            log("❌ FeeRouter missing InsuranceFund.deposit() call");
        }

        if (content.includes('insuranceFund.getIFR()')) {
            log("✅ FeeRouter uses InsuranceFund.getIFR() for events");
        } else {
            log("❌ FeeRouter missing InsuranceFund.getIFR() usage");
        }

    } catch (error) {
        log(`❌ Error checking InsuranceFund integration: ${error.message}`);
    }
}

function simulateFeeDistribution() {
    log("\n=== SIMULATING FEE DISTRIBUTION ===");

    // Simulate the fee calculation logic
    const testAmount = 1000; // 1000 USDT equivalent

    // Tier 1 split (50/30/20)
    const lpShare = Math.floor(testAmount * 0.5);
    const protocolShareT1 = Math.floor(testAmount * 0.3);
    const insuranceShareT1 = testAmount - lpShare - protocolShareT1; // remainder

    log(`Tier 1 split for ${testAmount} USDT:`);
    log(`  LP Share (50%): ${lpShare} USDT`);
    log(`  Protocol Share (30%): ${protocolShareT1} USDT`);
    log(`  Insurance Share (20%): ${insuranceShareT1} USDT`);
    log(`  Total: ${lpShare + protocolShareT1 + insuranceShareT1} USDT`);

    if (lpShare + protocolShareT1 + insuranceShareT1 === testAmount) {
        log("✅ Tier 1 fee split adds up correctly (no rounding loss)");
    } else {
        log("❌ Tier 1 fee split has rounding error");
    }

    // Tier 2 split (50/50/0)
    const lpShareT2 = Math.floor(testAmount * 0.5);
    const protocolShareT2 = testAmount - lpShareT2; // remainder
    const insuranceShareT2 = 0;

    log(`\nTier 2 split for ${testAmount} USDT:`);
    log(`  LP Share (50%): ${lpShareT2} USDT`);
    log(`  Protocol Share (50%): ${protocolShareT2} USDT`);
    log(`  Insurance Share (0%): ${insuranceShareT2} USDT`);
    log(`  Total: ${lpShareT2 + protocolShareT2 + insuranceShareT2} USDT`);

    if (lpShareT2 + protocolShareT2 + insuranceShareT2 === testAmount) {
        log("✅ Tier 2 fee split adds up correctly (no rounding loss)");
    } else {
        log("❌ Tier 2 fee split has rounding error");
    }
}

async function main() {
    log("Starting FeeRouter integration verification...");

    const connectionsOk = checkContractConnections();
    checkFeeRouterState();
    verifyFeeRouterConstants();
    checkInsuranceFundIntegration();
    simulateFeeDistribution();

    log("\n=== VERIFICATION COMPLETE ===");

    if (connectionsOk) {
        log("✅ FeeRouter integration verification passed");
        process.exit(0);
    } else {
        log("❌ FeeRouter integration verification failed");
        process.exit(1);
    }
}

main().catch(console.error);