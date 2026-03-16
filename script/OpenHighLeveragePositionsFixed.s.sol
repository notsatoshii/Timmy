// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PositionManager.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/periphery/MockUSDT.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

contract OpenHighLeveragePositionsFixed is Script {
    PositionManager constant POSITION_MANAGER = PositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    AccountManager constant ACCOUNT_MANAGER = AccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    ExecutionEngine constant EXECUTION_ENGINE = ExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    MockUSDT constant USDT = MockUSDT(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);

    address constant DEPLOYER = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

    function run() external {
        console.log("=== OPENING HIGH-LEVERAGE POSITIONS ===");

        // Use exact market IDs from the SeedPrices broadcast results
        bytes32[] memory marketIds = new bytes32[](5);
        marketIds[0] = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        marketIds[1] = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // US-Iran Ceasefire
        marketIds[2] = 0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d; // Nothing Ever Happens
        marketIds[3] = 0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2; // FIFA Spain
        marketIds[4] = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7; // Fed Rate

        address trader = DEPLOYER;
        console.log("Opening positions for:", trader);

        // Check current balance
        uint256 currentBalance = ACCOUNT_MANAGER.getFreeCollateral(trader);
        console.log("Current AccountManager balance:", currentBalance / 1e18, "USDT");

        vm.startPrank(trader);

        // Ensure sufficient balance in AccountManager
        if (currentBalance < 30000e18) {
            // Deposit USDT in its native 6-decimal format (30K should be enough)
            uint256 depositAmountUSDT = 30000 * 1e6; // 30K USDT in 6-decimal format
            USDT.approve(address(ACCOUNT_MANAGER), depositAmountUSDT);
            ACCOUNT_MANAGER.deposit(depositAmountUSDT);
            console.log("Deposited 30,000 USDT to AccountManager");
        }

        // Open 10 high-leverage positions with realistic sizes
        uint256[4][] memory configs = new uint256[4][](10);

        // [collateral_USDT, leverage_WAD, is_long (1=long, 0=short), market_index]
        configs[0] = [uint256(2000), 5e18, 1, 0];   // $2K @ 5x Long SpaceX = $10K notional
        configs[1] = [uint256(1500), 7e18, 0, 1];   // $1.5K @ 7x Short Iran = $10.5K notional
        configs[2] = [uint256(1000), 8e18, 1, 2];   // $1K @ 8x Long Nothing = $8K notional
        configs[3] = [uint256(1200), 10e18, 0, 3];  // $1.2K @ 10x Short FIFA = $12K notional
        configs[4] = [uint256(3000), 6e18, 1, 4];   // $3K @ 6x Long Fed = $18K notional
        configs[5] = [uint256(800), 12e18, 0, 0];   // $800 @ 12x Short SpaceX = $9.6K notional
        configs[6] = [uint256(2500), 5e18, 1, 1];   // $2.5K @ 5x Long Iran = $12.5K notional
        configs[7] = [uint256(600), 15e18, 0, 2];   // $600 @ 15x Short Nothing = $9K notional
        configs[8] = [uint256(1800), 8e18, 1, 3];   // $1.8K @ 8x Long FIFA = $14.4K notional
        configs[9] = [uint256(1400), 9e18, 0, 4];   // $1.4K @ 9x Short Fed = $12.6K notional

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
        console.log("Total planned notional: ~$117K");
        console.log("Average leverage: 8.5x");
        console.log("Range: 5x - 15x");
    }
}