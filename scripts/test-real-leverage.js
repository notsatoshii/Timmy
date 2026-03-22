// Test real on-chain leverage calculation to verify the fix
const { ethers } = require('ethers');

async function testRealLeverage() {
    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

    // Real deployed LeverageModel address (protected contract)
    const leverageModelAddr = "0x474E2eE2911544a385eb017369e8516Ad6DcCAbd";

    // Test market IDs
    const markets = [
        "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1", // Fixed market
        "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d", // Another fixed market
    ];

    // Simple ABI for the functions we need
    const leverageModelABI = [
        "function getEffectiveMaxLeverage(bytes32) view returns (uint256)",
        "function getPlatformCeiling() view returns (uint256)",
        "function getMarketAdjustment(bytes32) view returns (uint256)"
    ];

    const leverageModel = new ethers.Contract(leverageModelAddr, leverageModelABI, provider);

    console.log("Testing real on-chain leverage calculation...\n");

    try {
        const platformCeiling = await leverageModel.getPlatformCeiling();
        console.log(`Platform Ceiling: ${ethers.formatUnits(platformCeiling, 18)}x`);

        for (const marketId of markets) {
            console.log(`\nMarket: ${marketId.substring(0,10)}...`);

            const effectiveMax = await leverageModel.getEffectiveMaxLeverage(marketId);
            const marketAdjustment = await leverageModel.getMarketAdjustment(marketId);

            console.log(`  Effective Max Leverage: ${ethers.formatUnits(effectiveMax, 18)}x`);
            console.log(`  Market Adjustment: ${ethers.formatUnits(marketAdjustment, 18)}`);

            // Check if leverage is reasonable (> 5x)
            const leverageValue = parseFloat(ethers.formatUnits(effectiveMax, 18));
            if (leverageValue >= 5.0) {
                console.log(`  ✓ PASS - Leverage >= 5x`);
            } else {
                console.log(`  ✗ FAIL - Leverage < 5x`);
            }
        }

        console.log("\nReal leverage test complete.");

    } catch (error) {
        console.error("Error testing leverage:", error.message);
    }
}

testRealLeverage();