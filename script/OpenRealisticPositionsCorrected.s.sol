// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/interfaces/IPositionManager.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IAccountManager.sol";
import "../contracts/interfaces/IMarketRegistry.sol";

contract OpenRealisticPositionsCorrected is Script {
    IPositionManager constant POSITION_MANAGER = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IAccountManager constant ACCOUNT_MANAGER = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    IMarketRegistry constant MARKET_REGISTRY = IMarketRegistry(0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7);

    function run() external {
        // Use deployer wallet for realistic trading
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("Opening realistic positions with deployer:", deployer);

        // Check current balance
        uint256 balance = ACCOUNT_MANAGER.getBalance(deployer);
        console.log("AccountManager balance:", balance);
        console.log("Balance in USDT:", balance / 1e6);

        vm.startBroadcast(deployerKey);

        // Demo market IDs from actual deployment (only real markets)
        bytes32[6] memory marketIds;
        marketIds[0] = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        marketIds[1] = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // US-Iran Ceasefire
        marketIds[2] = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea; // Argentina USD
        marketIds[3] = 0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2; // FIFA 2026 Spain
        marketIds[4] = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7; // Fed Rate
        marketIds[5] = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554; // OpenSea Token

        string[6] memory marketNames = [
            "SpaceX IPO",
            "US-Iran Ceasefire",
            "Argentina USD",
            "FIFA 2026 Spain",
            "Fed Rate",
            "OpenSea Token"
        ];

        // Realistic leverage within protocol limits: 1x-3x range (protocol max is ~3x currently)
        uint256[6] memory leverageValues = [
            uint256(1), uint256(3), uint256(2), uint256(3), uint256(2), uint256(3)
        ];

        // Mix of long/short directions
        bool[6] memory directions = [
            true, false, true, false, true, false
        ];

        // Collateral amounts: 200-800 USDT range (NATIVE 6-DECIMAL FORMAT)
        // This is the key fix - use 1e6 instead of 1e18 for USDT amounts
        uint256[6] memory collateralAmounts = [
            uint256(500 * 1e6), uint256(300 * 1e6), uint256(800 * 1e6), uint256(200 * 1e6), uint256(600 * 1e6), uint256(400 * 1e6)
        ];

        console.log("Opening 6 realistic positions with available leverage...");

        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            uint256 collateral = collateralAmounts[i];
            uint256 leverage = leverageValues[i];
            bool isLong = directions[i];

            console.log("Position", i + 1, ":", marketNames[i]);
            console.log("- Leverage:", leverage, "x");
            console.log("- Direction:", isLong ? "LONG" : "SHORT");
            console.log("- Collateral:", collateral / 1e6, "USDT");

            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: collateral, // Native USDT format (6 decimals)
                leverage: leverage * 1e18 // Leverage in WAD format
            });

            try EXECUTION_ENGINE.openPosition(params) returns (uint256 positionId) {
                console.log("SUCCESS - Position ID:", positionId);
                console.log("Market:", marketNames[i]);
                console.log("Direction:", isLong ? "LONG" : "SHORT");
                console.log("Leverage:", leverage, "x");
                console.log("Collateral:", collateral / 1e6, "USDT");
                console.log("Notional:", (collateral / 1e6) * leverage, "USDT");
                console.log("");
            } catch Error(string memory reason) {
                console.log("FAILED - Market:", marketNames[i]);
                console.log("Reason:", reason);
                console.log("");
            } catch {
                console.log("FAILED - Market:", marketNames[i]);
                console.log("Unknown error");
                console.log("");
            }
        }

        vm.stopBroadcast();

        console.log("Realistic position opening complete!");
        console.log("Target: 6 positions with protocol-allowed leverage");
        console.log("Average leverage: ~2.2x");
        console.log("Total collateral range: 200-800 USDT per position");
    }
}