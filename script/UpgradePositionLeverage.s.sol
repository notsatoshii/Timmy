// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PositionManager.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/core/MarketRegistry.sol";
import "../contracts/periphery/MockUSDT.sol";

contract UpgradePositionLeverage is Script {
    PositionManager constant POSITION_MANAGER = PositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    AccountManager constant ACCOUNT_MANAGER = AccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    ExecutionEngine constant EXECUTION_ENGINE = ExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    MarketRegistry constant MARKET_REGISTRY = MarketRegistry(0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7);
    MockUSDT constant USDT = MockUSDT(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);

    address constant TEST_WALLET = 0xB072263740D7c60f1Aa0BF46e737F83544C7b785;
    address constant DEPLOYER = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

    function run() external {
        // Get market IDs for diverse position opening
        bytes32[] memory marketIds = new bytes32[](5);
        marketIds[0] = keccak256("SpaceX IPO 2026");         // Tech category
        marketIds[1] = keccak256("US-Iran Ceasefire Q1 2026"); // Geopolitics
        marketIds[2] = keccak256("FIFA 2026 - Spain Wins");    // Sports
        marketIds[3] = keccak256("Fed Rate Below 4% by March"); // Economy
        marketIds[4] = keccak256("AAPL Above $250 by March");   // Stocks

        // Phase 1: Close existing low-leverage positions
        console.log("=== PHASE 1: CLOSING LOW-LEVERAGE POSITIONS ===");
        _closeExistingPositions();

        // Phase 2: Open realistic high-leverage positions
        console.log("=== PHASE 2: OPENING HIGH-LEVERAGE POSITIONS ===");
        _openRealisticPositions(marketIds);
    }

    function _closeExistingPositions() internal {
        uint256 nextId = POSITION_MANAGER.nextPositionId();
        console.log("Checking positions 1 through", nextId - 1);

        // Check positions owned by deployer (focus on deployer since it has funds)
        address owner = DEPLOYER;
        console.log("Checking positions for deployer:", owner);

        for (uint256 i = 1; i < nextId; i++) {
            try POSITION_MANAGER.getPosition(i) returns (IPositionManager.Position memory position) {
                if (position.owner == owner && position.isOpen) {
                    uint256 leverageDecimal = position.leverage / 1e18;
                    console.log("Position", i);
                    console.log("  Leverage:", leverageDecimal, "x");
                    console.log("  Collateral:", position.collateral / 1e18, "USDT");

                    // Close positions with leverage <= 3x
                    if (position.leverage <= 3e18) {
                        console.log("Closing low-leverage position", i);
                        vm.startPrank(owner);
                        try EXECUTION_ENGINE.closePosition(i) {
                            console.log("Closed position", i);
                        } catch Error(string memory reason) {
                            console.log("Failed to close position", i, ":", reason);
                        }
                        vm.stopPrank();
                    }
                }
            } catch {
                // Position might not exist or be readable, skip
                continue;
            }
        }
    }

    function _openRealisticPositions(bytes32[] memory marketIds) internal {
        // Position configurations: [collateral (USDT), leverage (WAD), direction (0=long, 1=short)]
        uint256[3][] memory configs = new uint256[3][](12);

        // Mix of positions with 5x-15x leverage, varying collateral
        configs[0] = [uint256(2000), 5e18, 0];   // $2K @ 5x Long  = $10K notional
        configs[1] = [uint256(1500), 7e18, 1];   // $1.5K @ 7x Short = $10.5K notional
        configs[2] = [uint256(1000), 10e18, 0];  // $1K @ 10x Long = $10K notional
        configs[3] = [uint256(800), 12e18, 1];   // $800 @ 12x Short = $9.6K notional
        configs[4] = [uint256(3000), 6e18, 0];   // $3K @ 6x Long = $18K notional
        configs[5] = [uint256(500), 15e18, 1];   // $500 @ 15x Short = $7.5K notional
        configs[6] = [uint256(2500), 8e18, 0];   // $2.5K @ 8x Long = $20K notional
        configs[7] = [uint256(1200), 9e18, 1];   // $1.2K @ 9x Short = $10.8K notional
        configs[8] = [uint256(1800), 6e18, 0];   // $1.8K @ 6x Long = $10.8K notional
        configs[9] = [uint256(700), 14e18, 1];   // $700 @ 14x Short = $9.8K notional
        configs[10] = [uint256(4000), 5e18, 0];  // $4K @ 5x Long = $20K notional
        configs[11] = [uint256(600), 13e18, 1];  // $600 @ 13x Short = $7.8K notional

        // Use deployer (has funds)
        address trader = DEPLOYER;
        console.log("Opening positions for trader:", trader);

        // Open 12 positions
        for (uint256 i = 0; i < configs.length; i++) {
            uint256 collateralUSDT = configs[i][0];
            uint256 leverage = configs[i][1];
            uint8 direction = uint8(configs[i][2]);
            bytes32 marketId = marketIds[i % marketIds.length]; // Cycle through markets

            uint256 collateralWAD = collateralUSDT * 1e12; // Convert USDT (6 dec) to WAD (18 dec)

            console.log("Opening position", i);
            console.log("  Market:", i % marketIds.length);
            console.log("  Collateral:", collateralUSDT, "USDT");
            console.log("  Leverage:", leverage / 1e18, "x");

            vm.startPrank(trader);

            // Ensure trader has enough collateral in AccountManager
            uint256 currentBalance = ACCOUNT_MANAGER.getFreeCollateral(trader);
            if (currentBalance < collateralWAD) {
                // Deposit more if needed
                uint256 needed = collateralWAD - currentBalance + 1000e18; // Extra buffer
                USDT.approve(address(ACCOUNT_MANAGER), needed);
                ACCOUNT_MANAGER.deposit(needed);
                console.log("Deposited", needed / 1e18, "USDT to AccountManager");
            }

            // Open position
            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: direction == 0, // 0 = long, 1 = short
                collateral: collateralWAD,
                leverage: leverage
            });

            try EXECUTION_ENGINE.openPosition(params) {
                console.log("Opened position successfully");
            } catch Error(string memory reason) {
                console.log("Failed to open position:", reason);
            } catch {
                console.log("Failed to open position: unknown error");
            }

            vm.stopPrank();
        }

        console.log("=== POSITION OPENING COMPLETE ===");
        console.log("Target: 12 positions with 5x+ leverage across 5 markets");
        console.log("Expected total notional: ~$130K");
    }
}