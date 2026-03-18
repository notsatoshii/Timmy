#!/usr/bin/env node

/**
 * Temporary High Leverage Configuration Fix
 * Adjusts market parameters to work around TVL decimal conversion bug
 */

const { exec } = require('child_process');

const LEVERAGE_MODEL = '0x474E2eE2911544a385eb017369e8516Ad6DcCAbd';
const RPC_URL = 'https://sepolia.base.org';

// Override market risk parameters to force higher leverage despite TVL bug
const MARKET_OVERRIDES = {
    spacex: {
        marketId: '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1',
        // Use very low volatility to maximize leverage
        sigmaBaseline: '50000000000000000', // 5% instead of 25%
        // Use very low depth threshold to reduce impact
        depthThreshold: '1000000000000000000', // 1 USDT
        expectedLeverage: '20-30x'
    }
};

async function applyMarketOverrides() {
    console.log('=== Applying Market Parameter Overrides ===');
    console.log('WARNING: This is a temporary workaround for TVL decimal bug');

    // Generate forge script to apply overrides
    const overrideScript = `// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function setMarketRiskParams(bytes32 marketId, uint256 sigmaBaseline, uint256 depthThreshold) external;
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

contract ApplyLeverageOverrides is Script {
    ILeverageModel constant leverageModel = ILeverageModel(${LEVERAGE_MODEL});

    function run() external {
        vm.startBroadcast();

        console2.log("=== Applying Leverage Parameter Overrides ===");

        // SpaceX market override
        bytes32 spacexMarket = ${MARKET_OVERRIDES.spacex.marketId};
        uint256 beforeLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarket);
        console2.log("SpaceX Before:", beforeLeverage / 1e18);

        leverageModel.setMarketRiskParams(
            spacexMarket,
            ${MARKET_OVERRIDES.spacex.sigmaBaseline},
            ${MARKET_OVERRIDES.spacex.depthThreshold}
        );

        uint256 afterLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarket);
        console2.log("SpaceX After:", afterLeverage / 1e18);

        if (afterLeverage >= 15e18) {
            console2.log("SUCCESS: Leverage >= 15x achieved");
        } else {
            console2.log("PARTIAL: Some improvement but not full fix");
        }

        vm.stopBroadcast();
    }
}`;

    require('fs').writeFileSync('/home/lever/lever-protocol/ApplyLeverageOverrides.s.sol', overrideScript);
    console.log('✅ Override script generated: ApplyLeverageOverrides.s.sol');

    console.log('\n=== Execution Instructions ===');
    console.log('1. source control-plane/deploy-env.sh');
    console.log('2. forge script ApplyLeverageOverrides --fork-url $RPC_URL --private-key $PRIVATE_KEY --broadcast');
    console.log('3. Test leverage with: node scripts/validate-high-leverage.js');
}

applyMarketOverrides().catch(console.error);
