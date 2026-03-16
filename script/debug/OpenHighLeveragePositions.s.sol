// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";
import "../../contracts/interfaces/IAccountManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenHighLeveragePositions is Script {
    // Market IDs (SHA256 hashes of market names)
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN_CEASEFIRE = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant NOTHING_EVER_HAPPENS = 0xd6b094e6c3f73df8e41baa9c8b8ff2c6bc3426cb5e9d15b6e7b8f3e7c53a26de;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant FED_RATE_BELOW_4 = 0xa05b17b35e0067d4f8be7fce8b3a6b7d8cba4f2c19fb5e71b9f7e8ac3d6c0b2a;
    bytes32 constant AAPL_250 = 0xf8b7e6c9d3a2c5f8e1b4d7a0c3f6e9b2d5c8f1a4e7b0d3c6f9a2e5b8c1f4d7e0;
    bytes32 constant OPENSEA_TOKEN = 0x7c4d2f1a8e5b9c6f3a7d0e4b8c1f5a9e2d6c0f4a8e2c5b9f3a6d1c4f8a0e3b7d;
    bytes32 constant ARGENTINA_USD = 0xe73fd3dd8b7c2f1e5a9c6d3f0b4a7e1d8c5f2a9b6e3c0f4d7a1e5b8c2f6d9a3e;

    // Contract addresses
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;

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
        IERC20 usdt = IERC20(USDT);

        // Define 12 high-leverage positions across 8 markets
        PositionSpec[] memory positions = new PositionSpec[](12);

        positions[0] = PositionSpec(SPACEX_IPO, true, 1000e6, 8e18, "Long SpaceX IPO 8x");
        positions[1] = PositionSpec(US_IRAN_CEASEFIRE, false, 800e6, 6e18, "Short US-Iran Ceasefire 6x");
        positions[2] = PositionSpec(FIFA_SPAIN, true, 600e6, 10e18, "Long FIFA Spain 10x");
        positions[3] = PositionSpec(FED_RATE_BELOW_4, false, 1200e6, 5e18, "Short Fed Rate 5x");
        positions[4] = PositionSpec(AAPL_250, true, 500e6, 12e18, "Long AAPL $250 12x");
        positions[5] = PositionSpec(OPENSEA_TOKEN, false, 700e6, 7e18, "Short OpenSea Token 7x");
        positions[6] = PositionSpec(ARGENTINA_USD, true, 900e6, 9e18, "Long Argentina USD 9x");
        positions[7] = PositionSpec(NOTHING_EVER_HAPPENS, false, 600e6, 11e18, "Short Nothing Ever Happens 11x");
        positions[8] = PositionSpec(SPACEX_IPO, false, 800e6, 6e18, "Short SpaceX IPO 6x");
        positions[9] = PositionSpec(FIFA_SPAIN, false, 400e6, 15e18, "Short FIFA Spain 15x");
        positions[10] = PositionSpec(US_IRAN_CEASEFIRE, true, 1000e6, 5e18, "Long US-Iran Ceasefire 5x");
        positions[11] = PositionSpec(FED_RATE_BELOW_4, true, 700e6, 8e18, "Long Fed Rate 8x");

        console.log("=== Opening 12 high-leverage positions ===");
        console.log("Leverage range: 5x to 15x, Average: 8.25x");

        vm.startBroadcast();

        // Check initial collateral balance
        uint256 initialBalance = am.getFreeCollateral(msg.sender);
        console.log("Initial free collateral:", initialBalance / 1e6);

        for (uint256 i = 0; i < positions.length; i++) {
            PositionSpec memory pos = positions[i];

            console.log("Opening position", i + 1);
            console.log("  Description:", pos.description);
            console.log("  Collateral:", pos.collateral / 1e6, "USDT");
            console.log("  Leverage:", pos.leverage / 1e18, "x");

            try ee.openPosition(IExecutionEngine.OpenParams({
                marketId: pos.marketId,
                isLong: pos.isLong,
                collateral: pos.collateral * 1e12, // Convert USDT to WAD
                leverage: pos.leverage
            })) {
                console.log("  Position opened successfully");
            } catch Error(string memory reason) {
                console.log("  Failed to open position:", reason);
            } catch {
                console.log("  Failed to open position - unknown error");
            }
        }

        // Check final collateral balance
        uint256 finalBalance = am.getFreeCollateral(msg.sender);
        console.log("Final free collateral:", finalBalance / 1e6);

        vm.stopBroadcast();

        console.log("=== High-leverage position opening complete ===");
    }
}