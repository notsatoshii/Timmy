// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";
import "../../contracts/interfaces/IAccountManager.sol";
import "../../contracts/interfaces/ILeverageModel.sol";

contract OpenRealisticPositions is Script {
    // Known working market IDs
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;        // Max 1x
    bytes32 constant US_IRAN_CEASEFIRE = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // Max 2x
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;        // Max 3x

    // Contract addresses
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;

    struct PositionSpec {
        bytes32 marketId;
        bool isLong;
        uint256 collateral; // In USDT (6 decimals)
        uint256 leverage;   // In WAD (18 decimals)
        string description;
    }

    function run() external {
        IExecutionEngine ee = IExecutionEngine(EXECUTION_ENGINE);
        IAccountManager am = IAccountManager(ACCOUNT_MANAGER);
        ILeverageModel lm = ILeverageModel(LEVERAGE_MODEL);

        // Check leverage limits first
        console.log("=== Checking actual market leverage limits ===");
        console.log("SpaceX IPO max leverage:", lm.getEffectiveMaxLeverage(SPACEX_IPO) / 1e18);
        console.log("US-Iran max leverage:", lm.getEffectiveMaxLeverage(US_IRAN_CEASEFIRE) / 1e18);
        console.log("FIFA Spain max leverage:", lm.getEffectiveMaxLeverage(FIFA_SPAIN) / 1e18);

        // Define positions that respect actual leverage limits
        PositionSpec[] memory positions = new PositionSpec[](15);

        // SpaceX IPO (1x max) - use 1x
        positions[0] = PositionSpec(SPACEX_IPO, true, 2000e6, 1e18, "Long SpaceX IPO 1x");
        positions[1] = PositionSpec(SPACEX_IPO, false, 1500e6, 1e18, "Short SpaceX IPO 1x");
        positions[2] = PositionSpec(SPACEX_IPO, true, 1000e6, 1e18, "Long SpaceX IPO 1x");
        positions[3] = PositionSpec(SPACEX_IPO, false, 800e6, 1e18, "Short SpaceX IPO 1x");
        positions[4] = PositionSpec(SPACEX_IPO, true, 1200e6, 1e18, "Long SpaceX IPO 1x");

        // US-Iran Ceasefire (2x max) - use 2x
        positions[5] = PositionSpec(US_IRAN_CEASEFIRE, false, 1000e6, 2e18, "Short US-Iran Ceasefire 2x");
        positions[6] = PositionSpec(US_IRAN_CEASEFIRE, true, 800e6, 2e18, "Long US-Iran Ceasefire 2x");
        positions[7] = PositionSpec(US_IRAN_CEASEFIRE, false, 600e6, 2e18, "Short US-Iran Ceasefire 2x");
        positions[8] = PositionSpec(US_IRAN_CEASEFIRE, true, 900e6, 2e18, "Long US-Iran Ceasefire 2x");
        positions[9] = PositionSpec(US_IRAN_CEASEFIRE, false, 700e6, 2e18, "Short US-Iran Ceasefire 2x");

        // FIFA Spain (3x max) - use 3x
        positions[10] = PositionSpec(FIFA_SPAIN, true, 500e6, 3e18, "Long FIFA Spain 3x");
        positions[11] = PositionSpec(FIFA_SPAIN, false, 600e6, 3e18, "Short FIFA Spain 3x");
        positions[12] = PositionSpec(FIFA_SPAIN, true, 400e6, 3e18, "Long FIFA Spain 3x");
        positions[13] = PositionSpec(FIFA_SPAIN, false, 700e6, 3e18, "Short FIFA Spain 3x");
        positions[14] = PositionSpec(FIFA_SPAIN, true, 550e6, 3e18, "Long FIFA Spain 3x");

        console.log("=== Opening 15 positions with maximum allowed leverage ===");
        console.log("SpaceX: 5 positions at 1x leverage");
        console.log("US-Iran: 5 positions at 2x leverage");
        console.log("FIFA: 5 positions at 3x leverage");

        vm.startBroadcast();

        uint256 initialBalance = am.getFreeCollateral(msg.sender);
        console.log("Initial free collateral:", initialBalance / 1e6);

        uint256 successCount = 0;

        for (uint256 i = 0; i < positions.length; i++) {
            PositionSpec memory pos = positions[i];

            console.log("Opening position", i + 1);
            console.log("  Description:", pos.description);

            try ee.openPosition(IExecutionEngine.OpenParams({
                marketId: pos.marketId,
                isLong: pos.isLong,
                collateral: pos.collateral * 1e12, // Convert USDT to WAD
                leverage: pos.leverage
            })) {
                console.log("  SUCCESS - Position opened");
                successCount++;
            } catch Error(string memory reason) {
                console.log("  FAILED:", reason);
            } catch {
                console.log("  FAILED - unknown error");
            }
        }

        uint256 finalBalance = am.getFreeCollateral(msg.sender);
        console.log("Final free collateral:", finalBalance / 1e6);
        console.log("Successfully opened positions:", successCount);
        console.log("Total attempted:", positions.length);

        vm.stopBroadcast();

        console.log("=== Realistic position opening complete ===");
    }
}