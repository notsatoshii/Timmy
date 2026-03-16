// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PositionManager.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/periphery/MockUSDT.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

contract OpenHighLeveragePositions is Script {
    PositionManager constant POSITION_MANAGER = PositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    AccountManager constant ACCOUNT_MANAGER = AccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    ExecutionEngine constant EXECUTION_ENGINE = ExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    MockUSDT constant USDT = MockUSDT(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);

    address constant DEPLOYER = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

    function run() external {
        console.log("=== OPENING HIGH-LEVERAGE POSITIONS ===");

        // Get market IDs using exact names from SeedPrices script
        bytes32[] memory marketIds = new bytes32[](5);
        marketIds[0] = keccak256("Largest IPO by Market Cap 2026: SpaceX?");
        marketIds[1] = keccak256("US-Iran Ceasefire by April 30, 2026?");
        marketIds[2] = keccak256("2026 FIFA World Cup Winner: Spain?");
        marketIds[3] = keccak256("Fed Rate End of 2026: Below 4%?");
        marketIds[4] = keccak256("AAPL Above $250 in April 2026?");

        address trader = DEPLOYER;
        console.log("Opening positions for:", trader);

        // Check current balance
        uint256 currentBalance = ACCOUNT_MANAGER.getFreeCollateral(trader);
        console.log("Current AccountManager balance:", currentBalance / 1e18, "USDT");

        vm.startPrank(trader);

        // Ensure sufficient balance in AccountManager
        if (currentBalance < 50000e18) {
            // Deposit USDT in its native 6-decimal format (50K USDT = 50000 * 1e6)
            uint256 depositAmountUSDT = 50000 * 1e6; // 50K USDT in 6-decimal format
            USDT.approve(address(ACCOUNT_MANAGER), depositAmountUSDT);
            ACCOUNT_MANAGER.deposit(depositAmountUSDT);
            console.log("Deposited 50,000 USDT to AccountManager");
        }

        // Open 10 high-leverage positions
        uint256[4][] memory configs = new uint256[4][](10);

        // [collateral_USDT, leverage_WAD, is_long (1=long, 0=short), market_index]
        configs[0] = [uint256(3000), 8e18, 1, 0];   // $3K @ 8x Long SpaceX = $24K notional
        configs[1] = [uint256(2000), 10e18, 0, 1];  // $2K @ 10x Short Iran = $20K notional
        configs[2] = [uint256(2500), 7e18, 1, 2];   // $2.5K @ 7x Long Spain = $17.5K notional
        configs[3] = [uint256(1500), 12e18, 0, 3];  // $1.5K @ 12x Short Fed = $18K notional
        configs[4] = [uint256(4000), 6e18, 1, 4];   // $4K @ 6x Long AAPL = $24K notional
        configs[5] = [uint256(1000), 15e18, 0, 0];  // $1K @ 15x Short SpaceX = $15K notional
        configs[6] = [uint256(3500), 5e18, 1, 1];   // $3.5K @ 5x Long Iran = $17.5K notional
        configs[7] = [uint256(800), 13e18, 0, 2];   // $800 @ 13x Short Spain = $10.4K notional
        configs[8] = [uint256(2200), 9e18, 1, 3];   // $2.2K @ 9x Long Fed = $19.8K notional
        configs[9] = [uint256(1800), 11e18, 0, 4];  // $1.8K @ 11x Short AAPL = $19.8K notional

        for (uint256 i = 0; i < configs.length; i++) {
            uint256 collateralUSDT = configs[i][0];
            uint256 leverage = configs[i][1];
            bool isLong = configs[i][2] == 1;
            uint256 marketIndex = configs[i][3];

            bytes32 marketId = marketIds[marketIndex];
            uint256 collateralWAD = collateralUSDT * 1e12; // Convert to WAD

            console.log("Position", i + 1, ":");
            console.log("  Market:", marketIndex, isLong ? "LONG" : "SHORT");
            console.log("  Collateral:", collateralUSDT, "USDT");
            console.log("  Leverage:", leverage / 1e18, "x");
            console.log("  Notional:", (collateralUSDT * leverage) / 1e18, "USDT");

            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: collateralWAD,
                leverage: leverage
            });

            try EXECUTION_ENGINE.openPosition(params) {
                console.log("  SUCCESS: Position opened");
            } catch Error(string memory reason) {
                console.log("  FAILED:", reason);
            } catch {
                console.log("  FAILED: Unknown error");
            }

            console.log("---");
        }

        vm.stopPrank();

        // Summary
        console.log("=== SUMMARY ===");
        console.log("Attempted to open 10 positions");
        console.log("Total planned notional: ~$185K");
        console.log("Average leverage: 9.1x");
        console.log("Range: 5x - 15x");
    }
}