// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/interfaces/IPositionManager.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IAccountManager.sol";
import "../contracts/interfaces/IMarketRegistry.sol";

contract ReplaceTestPositions is Script {
    IPositionManager constant POSITION_MANAGER = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IAccountManager constant ACCOUNT_MANAGER = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    IMarketRegistry constant MARKET_REGISTRY = IMarketRegistry(0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7);

    function run() external {
        // Deployer wallet
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);

        // Test wallet
        uint256 testKey = vm.envUint("TEST_PRIVATE_KEY");
        address testWallet = vm.addr(testKey);
        console.log("Test wallet:", testWallet);

        vm.startBroadcast(deployerKey);

        // Step 1: Close all existing positions for deployer with leverage ≤ 2x
        _closeLowLeveragePositions(deployer);

        vm.stopBroadcast();

        // Step 2: Switch to test wallet and close its low-leverage positions
        vm.startBroadcast(testKey);
        _closeLowLeveragePositions(testWallet);
        vm.stopBroadcast();

        // Step 3: Open new realistic high-leverage positions
        vm.startBroadcast(deployerKey);
        _openRealisticPositions(deployer, "DEPLOYER");
        vm.stopBroadcast();

        vm.startBroadcast(testKey);
        _openRealisticPositions(testWallet, "TEST_WALLET");
        vm.stopBroadcast();

        console.log("Position replacement complete!");
    }

    function _closeLowLeveragePositions(address user) internal {
        uint256[] memory positionIds = POSITION_MANAGER.getUserPositions(user);
        console.log("Checking positions for user:", user);
        console.log("Position count:", positionIds.length);

        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 positionId = positionIds[i];
            IPositionManager.Position memory position = POSITION_MANAGER.getPosition(positionId);

            if (position.id == 0) continue; // Position doesn't exist or closed

            console.log("Position ID:", positionId);
            console.log("Size:", position.positionSize);
            console.log("Collateral:", position.collateral);

            // Calculate leverage: leverage = positionSize / collateral
            uint256 leverage = position.positionSize * 1e18 / position.collateral;
            console.log("Leverage (WAD):", leverage);

            // Close if leverage ≤ 2x (2e18 in WAD)
            if (leverage <= 2e18) {
                console.log("Closing low leverage position:", positionId);
                console.log("Leverage:", leverage / 1e18);
                try EXECUTION_ENGINE.closePosition(positionId) {
                    console.log("Successfully closed position:", positionId);
                } catch Error(string memory reason) {
                    console.log("Failed to close position:", positionId);
                    console.log("Reason:", reason);
                } catch {
                    console.log("Failed to close position (unknown error):", positionId);
                }
            }
        }
    }

    function _openRealisticPositions(address user, string memory label) internal {
        // Get demo market IDs (from actual deployment)
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

        // Leverage values: 3x-15x range with 5-10x average
        uint256[6] memory leverageValues = [
            uint256(5), uint256(8), uint256(3), uint256(12), uint256(7), uint256(10)
        ];

        // Directions: mix of long/short
        bool[6] memory directions = [true, false, true, false, true, false];

        // Collateral amounts: 500-2000 USDT range
        uint256[6] memory collateralAmounts = [
            uint256(1000e18), uint256(800e18), uint256(1500e18), uint256(500e18), uint256(1200e18), uint256(2000e18)
        ];

        console.log("Opening realistic positions for:", label);
        console.log("Number of markets:", marketIds.length);

        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            uint256 collateral = collateralAmounts[i];
            uint256 leverage = leverageValues[i];
            bool isLong = directions[i];

            console.log("Opening position:", marketNames[i]);
            console.log("Leverage:", leverage);
            console.log("Direction:", isLong ? "LONG" : "SHORT");
            console.log("Collateral:", collateral / 1e18);

            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: collateral,
                leverage: leverage * 1e18
            });

            try EXECUTION_ENGINE.openPosition(params) returns (uint256 positionId) {
                console.log("Successfully opened position:", positionId);
                console.log("Market:", marketNames[i]);
                console.log("Direction:", isLong ? "LONG" : "SHORT");
                console.log("Leverage:", leverage);
            } catch Error(string memory reason) {
                console.log("Failed to open position for:", marketNames[i]);
                console.log("Reason:", reason);
            } catch {
                console.log("Failed to open position (unknown error):", marketNames[i]);
            }
        }
    }
}