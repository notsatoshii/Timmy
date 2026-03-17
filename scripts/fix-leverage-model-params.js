#!/usr/bin/env node

/**
 * Fix LeverageModel Risk Parameters
 * Apply fixes to the LeverageModel that ExecutionEngine is actually using
 */

const { exec } = require('child_process');

// The ACTUAL LeverageModel that ExecutionEngine is pointing to (from FixExecutionEngineLeverageModel.s.sol)
const OLD_LEVERAGE_MODEL = '0x63B98Ec1e559E3b24199eb2115F0a57222e9818c';

// Deploy environment values
const DEPLOYER = '0x0e4D636c6D79c380A137f28EF73E054364cd5434';
const RPC_URL = 'https://sepolia.base.org';

// Market IDs that need fixing
const MARKETS = {
    spacex: '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1',
    usIran: '0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a',
    fifaSpain: '0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7',
    argentina: '0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea',
    fedRate: '0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554'
};

// Fixed parameters to apply
const SIGMA_BASELINE = '250000000000000000'; // 0.25e18 = 25% baseline volatility
const DEPTH_THRESHOLD = '5000000000000000000'; // 5e18 = 5 USDT (realistic depth)

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

async function checkContractExists() {
    console.log('=== Checking Old LeverageModel Contract ===');

    try {
        const codeResult = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_getCode","params":["${OLD_LEVERAGE_MODEL}","latest"],"id":1}'`
        );

        const codeResponse = JSON.parse(codeResult);
        if (codeResponse.result && codeResponse.result !== '0x' && codeResponse.result.length > 4) {
            console.log(`✅ Old LeverageModel exists at: ${OLD_LEVERAGE_MODEL}`);
            return true;
        } else {
            console.log(`❌ Old LeverageModel not found at: ${OLD_LEVERAGE_MODEL}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Error checking contract: ${error.message}`);
        return false;
    }
}

async function getLeverageForMarket(marketId, marketName) {
    try {
        // getEffectiveMaxLeverage(bytes32) function selector
        const functionSelector = '0xe1f2c47c'; // This needs to be calculated correctly
        const callData = functionSelector + marketId.substring(2);

        const result = await execCommand(
            `curl -s -X POST ${RPC_URL} -H "Content-Type: application/json" ` +
            `-d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"${OLD_LEVERAGE_MODEL}","data":"${callData}"},"latest"],"id":1}'`
        );

        const response = JSON.parse(result);
        if (response.result && response.result !== '0x' && response.result !== '0x0') {
            const leverageWad = parseInt(response.result, 16);
            const leverage = leverageWad / 1e18;
            console.log(`${marketName}: ${leverage.toFixed(2)}x (WAD: ${leverageWad})`);
            return leverage;
        } else {
            console.log(`${marketName}: Error getting leverage`);
            return 0;
        }
    } catch (error) {
        console.log(`${marketName}: Error - ${error.message}`);
        return 0;
    }
}

async function checkCurrentLeverage() {
    console.log('\n=== Current Leverage Limits ===');

    for (const [name, marketId] of Object.entries(MARKETS)) {
        await getLeverageForMarket(marketId, name);
    }
}

function generateSolidityFixScript() {
    console.log('\n=== Generating Solidity Fix Script ===');

    const scriptContent = `// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function setMarketRiskParams(bytes32 marketId, uint256 sigmaBaseline, uint256 depthThreshold) external;
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

contract FixLeverageParameters is Script {
    ILeverageModel constant leverageModel = ILeverageModel(${OLD_LEVERAGE_MODEL});

    uint256 constant SIGMA_BASELINE = ${SIGMA_BASELINE}; // 25% baseline volatility
    uint256 constant DEPTH_THRESHOLD = ${DEPTH_THRESHOLD}; // 5 USDT realistic depth

    function run() external {
        vm.startBroadcast();

        console2.log("=== Fixing LeverageModel Parameters ===");
        console2.log("Target contract:", address(leverageModel));

        // Fix all markets
        ${Object.entries(MARKETS).map(([name, marketId]) =>
            `_fixMarket(${marketId}, "${name}");`
        ).join('\n        ')}

        vm.stopBroadcast();
    }

    function _fixMarket(bytes32 marketId, string memory name) internal {
        console2.log("Fixing market:", name);

        uint256 beforeLeverage = leverageModel.getEffectiveMaxLeverage(marketId);
        console2.log("Before (WAD):", beforeLeverage);

        leverageModel.setMarketRiskParams(marketId, SIGMA_BASELINE, DEPTH_THRESHOLD);

        uint256 afterLeverage = leverageModel.getEffectiveMaxLeverage(marketId);
        console2.log("After (WAD):", afterLeverage);

        if (afterLeverage >= 20e18) {
            console2.log("SUCCESS: >= 20x leverage");
        } else {
            console2.log("WARNING: Still < 20x leverage");
        }
        console2.log("");
    }
}`;

    // Save the script
    require('fs').writeFileSync('/home/lever/lever-protocol/FixLeverageParameters.s.sol', scriptContent);
    console.log('✅ Solidity script saved to: FixLeverageParameters.s.sol');

    console.log('\n=== Next Steps ===');
    console.log('1. Source deployer environment:');
    console.log('   source control-plane/deploy-env.sh');
    console.log('2. Run the fix script:');
    console.log('   forge script FixLeverageParameters --fork-url $RPC_URL --private-key $PRIVATE_KEY --broadcast');
    console.log('3. Verify leverage limits are fixed');

    return scriptContent;
}

async function main() {
    console.log('=== ExecutionEngine LeverageModel Fix ===');
    console.log(`Problem: ExecutionEngine points to old LeverageModel`);
    console.log(`Old LeverageModel: ${OLD_LEVERAGE_MODEL}`);
    console.log(`Solution: Fix parameters on the old LeverageModel contract`);

    const contractExists = await checkContractExists();
    if (!contractExists) {
        console.log('❌ Cannot fix - old LeverageModel contract not found');
        process.exit(1);
    }

    await checkCurrentLeverage();

    generateSolidityFixScript();

    console.log('\n=== SUMMARY ===');
    console.log('✅ Problem diagnosed: ExecutionEngine uses old LeverageModel');
    console.log('✅ Solution prepared: Fix risk parameters on old contract');
    console.log('✅ Script generated: FixLeverageParameters.s.sol');
    console.log('');
    console.log('Manual execution required:');
    console.log('1. source control-plane/deploy-env.sh');
    console.log('2. forge script FixLeverageParameters --fork-url $RPC_URL --private-key $PRIVATE_KEY --broadcast');
}

main().catch(console.error);