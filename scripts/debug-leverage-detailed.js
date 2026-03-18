#!/usr/bin/env node

/**
 * Debug leverage issue in detail to understand the exact problem
 */

const { exec } = require('child_process');

// All the addresses we need
const CONTRACTS = {
    LEVER_VAULT: '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921',
    LEVERAGE_MODEL_NEW: '0x474E2eE2911544a385eb017369e8516Ad6DcCAbd',
    LEVERAGE_MODEL_OLD: '0x63B98Ec1e559E3b24199eb2115F0a57222e9818c',
    EXECUTION_ENGINE: '0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D'
};

const SPACEX_MARKET = '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1';
const RPC_URL = 'https://sepolia.base.org';

async function execCommand(command) {
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject(error);
            } else {
                resolve(stdout.trim());
            }
        });
    });
}

async function checkContractExists(address, name) {
    try {
        const result = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_getCode","params":["${address}","latest"],"id":1}'`
        );

        const response = JSON.parse(result);
        const hasCode = response.result && response.result !== '0x' && response.result.length > 4;

        console.log(`${name}: ${hasCode ? '✅ EXISTS' : '❌ NOT FOUND'} at ${address}`);
        return hasCode;
    } catch (error) {
        console.log(`${name}: ❌ ERROR checking - ${error.message}`);
        return false;
    }
}

async function checkTVL() {
    console.log('\n=== TVL Analysis ===');

    try {
        // totalAssets() function selector: 0x01e1d114
        const result = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"${CONTRACTS.LEVER_VAULT}","data":"0x01e1d114"},"latest"],"id":1}'`
        );

        const response = JSON.parse(result);
        if (response.result) {
            const tvlRaw = BigInt(response.result);
            const tvlUSDT = Number(tvlRaw) / 1e6; // 6 decimals
            const tvlWAD = tvlRaw * BigInt(10) ** BigInt(12); // Convert to 18 decimals

            console.log(`TVL Raw (USDT format): ${tvlRaw}`);
            console.log(`TVL Human: $${tvlUSDT.toLocaleString()}`);
            console.log(`TVL WAD (what LeverageModel needs): ${tvlWAD}`);

            return { raw: tvlRaw, usdt: tvlUSDT, wad: tvlWAD };
        }
    } catch (error) {
        console.log(`TVL check failed: ${error.message}`);
        return null;
    }
}

async function checkLeverageOnBothModels() {
    console.log('\n=== Leverage Model Comparison ===');

    const models = [
        { name: 'NEW LeverageModel', address: CONTRACTS.LEVERAGE_MODEL_NEW },
        { name: 'OLD LeverageModel', address: CONTRACTS.LEVERAGE_MODEL_OLD }
    ];

    for (const model of models) {
        console.log(`\n--- ${model.name} ---`);

        try {
            // getEffectiveMaxLeverage(bytes32) - function selector: 0xe1f2c47c
            const callData = '0xe1f2c47c' + SPACEX_MARKET.substring(2);

            const result = await execCommand(
                `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
                `-d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"${model.address}","data":"${callData}"},"latest"],"id":1}'`
            );

            const response = JSON.parse(result);
            if (response.result && response.result !== '0x') {
                const leverageWad = BigInt(response.result);
                const leverage = Number(leverageWad) / 1e18;

                console.log(`SpaceX Leverage: ${leverage.toFixed(2)}x`);
                console.log(`Raw WAD: ${leverageWad}`);

                if (leverage >= 15) {
                    console.log('✅ GOOD: High leverage available');
                } else if (leverage >= 5) {
                    console.log('⚠️  PARTIAL: Moderate leverage');
                } else {
                    console.log('❌ LOW: Leverage too low');
                }
            } else {
                console.log('❌ Could not read leverage from this model');
            }
        } catch (error) {
            console.log(`Error with ${model.name}: ${error.message}`);
        }
    }
}

async function checkExecutionEnginePointing() {
    console.log('\n=== ExecutionEngine Configuration ===');

    try {
        // Check which LeverageModel the ExecutionEngine is using
        // leverageModel() function selector: 0x8a3b539c
        const result = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"${CONTRACTS.EXECUTION_ENGINE}","data":"0x8a3b539c"},"latest"],"id":1}'`
        );

        const response = JSON.parse(result);
        if (response.result && response.result !== '0x') {
            const leverageModelAddress = '0x' + response.result.slice(-40);
            console.log(`ExecutionEngine points to: ${leverageModelAddress}`);

            if (leverageModelAddress.toLowerCase() === CONTRACTS.LEVERAGE_MODEL_NEW.toLowerCase()) {
                console.log('✅ Points to NEW LeverageModel');
            } else if (leverageModelAddress.toLowerCase() === CONTRACTS.LEVERAGE_MODEL_OLD.toLowerCase()) {
                console.log('⚠️  Points to OLD LeverageModel');
            } else {
                console.log(`❓ Points to unknown LeverageModel`);
            }

            return leverageModelAddress;
        }
    } catch (error) {
        console.log(`Error checking ExecutionEngine: ${error.message}`);
        return null;
    }
}

async function main() {
    console.log('=== DETAILED LEVERAGE DEBUG ===');

    console.log('\n=== Contract Existence Check ===');
    await checkContractExists(CONTRACTS.LEVER_VAULT, 'LeverVault');
    await checkContractExists(CONTRACTS.LEVERAGE_MODEL_NEW, 'NEW LeverageModel');
    await checkContractExists(CONTRACTS.LEVERAGE_MODEL_OLD, 'OLD LeverageModel');
    await checkContractExists(CONTRACTS.EXECUTION_ENGINE, 'ExecutionEngine');

    const tvl = await checkTVL();
    await checkLeverageOnBothModels();
    const activeModel = await checkExecutionEnginePointing();

    console.log('\n=== DIAGNOSIS ===');

    if (tvl && tvl.usdt > 50000000) {
        console.log('✅ TVL is healthy: $' + tvl.usdt.toLocaleString());
    } else {
        console.log('❌ TVL issue detected');
    }

    console.log('\n=== RECOMMENDATION ===');
    if (activeModel && activeModel.toLowerCase() === CONTRACTS.LEVERAGE_MODEL_OLD.toLowerCase()) {
        console.log('🎯 Problem: ExecutionEngine uses OLD LeverageModel');
        console.log('💡 Solution: Apply parameter overrides to OLD model (which we did)');
        console.log('📋 Next: Check if overrides took effect on the OLD model');
    } else {
        console.log('🎯 Problem: ExecutionEngine may be using NEW LeverageModel');
        console.log('💡 Solution: Check TVL decimal conversion in NEW model');
    }
}

main().catch(console.error);