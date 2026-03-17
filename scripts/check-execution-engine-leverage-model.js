#!/usr/bin/env node

/**
 * Check what LeverageModel address ExecutionEngine is currently using
 */

const { exec } = require('child_process');

// Load current addresses from deploy-env.sh
const CONTRACTS = {
    EXECUTION_ENGINE: '0x15a05b36D68e88f3264157dDa034f6C1e666065b',
    LEVERAGE_MODEL: '0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF',
};

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

async function checkLeverageModelReference() {
    console.log('=== Checking ExecutionEngine LeverageModel Reference ===');

    try {
        // leverageModel() function selector (first 4 bytes of keccak256("leverageModel()"))
        // For immutable address variables, this is typically stored as a public getter
        const functionSelector = '0xfc57d4df'; // leverageModel() selector

        console.log(`Querying ExecutionEngine at: ${CONTRACTS.EXECUTION_ENGINE}`);
        console.log(`Expected LeverageModel at: ${CONTRACTS.LEVERAGE_MODEL}`);

        const result = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"${CONTRACTS.EXECUTION_ENGINE}","data":"${functionSelector}"},"latest"],"id":1}'`
        );

        const response = JSON.parse(result);

        if (response.result && response.result !== '0x' && response.result !== '0x0') {
            // Convert hex result to address (remove 0x and take last 40 characters, add 0x back)
            const leverageModelAddress = '0x' + response.result.slice(-40);

            console.log(`\nActual LeverageModel in ExecutionEngine: ${leverageModelAddress}`);
            console.log(`Expected LeverageModel (deploy-env.sh): ${CONTRACTS.LEVERAGE_MODEL}`);

            if (leverageModelAddress.toLowerCase() === CONTRACTS.LEVERAGE_MODEL.toLowerCase()) {
                console.log('✅ MATCH: ExecutionEngine is using the correct LeverageModel');
                return true;
            } else {
                console.log('❌ MISMATCH: ExecutionEngine is using an old LeverageModel address');
                console.log(`Gap: ExecutionEngine points to ${leverageModelAddress}`);
                console.log(`     but deploy-env.sh has ${CONTRACTS.LEVERAGE_MODEL}`);
                return false;
            }
        } else {
            console.log('❌ ERROR: Could not query leverageModel() from ExecutionEngine');
            console.log('This might mean:');
            console.log('1. The function selector is wrong');
            console.log('2. The ExecutionEngine contract doesn\'t have a leverageModel() getter');
            console.log('3. The contract is not deployed or accessible');
            return false;
        }

    } catch (error) {
        console.log(`❌ ERROR: ${error.message}`);
        return false;
    }
}

async function checkBothContractsDeployed() {
    console.log('\n=== Checking Contract Deployment Status ===');

    const contracts = [
        { name: 'ExecutionEngine', address: CONTRACTS.EXECUTION_ENGINE },
        { name: 'LeverageModel', address: CONTRACTS.LEVERAGE_MODEL },
    ];

    for (const contract of contracts) {
        try {
            const codeResult = await execCommand(
                `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
                `-d '{"jsonrpc":"2.0","method":"eth_getCode","params":["${contract.address}","latest"],"id":1}'`
            );

            const codeResponse = JSON.parse(codeResult);
            if (codeResponse.result && codeResponse.result !== '0x' && codeResponse.result.length > 4) {
                console.log(`✅ ${contract.name}: Deployed at ${contract.address}`);
            } else {
                console.log(`❌ ${contract.name}: No bytecode at ${contract.address}`);
            }
        } catch (error) {
            console.log(`❌ ${contract.name}: Error checking deployment - ${error.message}`);
        }
    }
}

async function main() {
    await checkBothContractsDeployed();
    const isMatched = await checkLeverageModelReference();

    console.log('\n=== DIAGNOSIS ===');
    if (isMatched) {
        console.log('The ExecutionEngine is using the correct LeverageModel address.');
        console.log('The leverage limitation issue must be caused by something else.');
        console.log('Possible causes:');
        console.log('1. LeverageModel parameters are set too restrictively');
        console.log('2. Market risk factors are causing low leverage limits');
        console.log('3. TVL/IFR/Utilization multipliers are reducing platform ceiling');
    } else {
        console.log('FOUND THE PROBLEM: ExecutionEngine is using an outdated LeverageModel address.');
        console.log('This is an immutable reference, so ExecutionEngine cannot be updated.');
        console.log('Solutions:');
        console.log('1. Deploy the fixed LeverageModel to the address ExecutionEngine expects');
        console.log('2. Or find a way to update the reference without redeploying ExecutionEngine');
    }
}

main().catch(console.error);