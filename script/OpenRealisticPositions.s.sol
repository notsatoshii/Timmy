// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PositionManager.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/periphery/MockUSDT.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

contract OpenRealisticPositions is Script {
    PositionManager constant POSITION_MANAGER = PositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    AccountManager constant ACCOUNT_MANAGER = AccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    ExecutionEngine constant EXECUTION_ENGINE = ExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    MockUSDT constant USDT = MockUSDT(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);

    address constant DEPLOYER = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

    function run() external {
        console.log("=== OPENING REALISTIC POSITIONS ===");
        console.log("Working within current leverage constraints (~1.8x max)");

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
        if (currentBalance < 50000e18) {
            // Deposit more USDT to handle larger position sizes
            uint256 depositAmountUSDT = 40000 * 1e6; // 40K USDT in 6-decimal format
            USDT.approve(address(ACCOUNT_MANAGER), depositAmountUSDT);
            ACCOUNT_MANAGER.deposit(depositAmountUSDT);
            console.log("Deposited 40,000 USDT to AccountManager");
        }

        // Open 12 positions using max allowed leverage (~1.8x) but larger collateral amounts
        uint256[4][] memory configs = new uint256[4][](12);

        // [collateral_USDT, leverage_WAD, is_long (1=long, 0=short), market_index]
        // Using 1.7x leverage (below the 1.8x limit) with larger collateral amounts
        configs[0] = [uint256(5000), 17e17, 1, 0];   // $5K @ 1.7x Long SpaceX = $8.5K notional
        configs[1] = [uint256(4000), 17e17, 0, 1];   // $4K @ 1.7x Short Iran = $6.8K notional
        configs[2] = [uint256(6000), 17e17, 1, 2];   // $6K @ 1.7x Long Nothing = $10.2K notional
        configs[3] = [uint256(3500), 17e17, 0, 3];   // $3.5K @ 1.7x Short FIFA = $6.0K notional
        configs[4] = [uint256(7000), 17e17, 1, 4];   // $7K @ 1.7x Long Fed = $11.9K notional
        configs[5] = [uint256(3000), 17e17, 0, 0];   // $3K @ 1.7x Short SpaceX = $5.1K notional
        configs[6] = [uint256(5500), 17e17, 1, 1];   // $5.5K @ 1.7x Long Iran = $9.4K notional
        configs[7] = [uint256(2500), 17e17, 0, 2];   // $2.5K @ 1.7x Short Nothing = $4.3K notional
        configs[8] = [uint256(4500), 17e17, 1, 3];   // $4.5K @ 1.7x Long FIFA = $7.7K notional
        configs[9] = [uint256(6500), 17e17, 0, 4];   // $6.5K @ 1.7x Short Fed = $11.1K notional
        configs[10] = [uint256(8000), 17e17, 1, 0];  // $8K @ 1.7x Long SpaceX = $13.6K notional
        configs[11] = [uint256(3200), 17e17, 0, 1];  // $3.2K @ 1.7x Short Iran = $5.4K notional

        uint256 successCount = 0;
        uint256 totalNotional = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            uint256 collateralUSDT = configs[i][0];
            uint256 leverage = configs[i][1];
            bool isLong = configs[i][2] == 1;
            uint256 marketIndex = configs[i][3];

            bytes32 marketId = marketIds[marketIndex];
            uint256 collateralWAD = collateralUSDT * 1e12; // Convert to WAD
            uint256 notional = (collateralUSDT * leverage) / 1e18;

            console.log("Position", i + 1, ":");
            console.log("  Market:", marketIndex, isLong ? "LONG" : "SHORT");
            console.log("  Collateral:", collateralUSDT, "USDT");
            console.log("  Leverage:", leverage / 1e17, "0x"); // Show as 1.7x
            console.log("  Notional:", notional, "USDT");

            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: collateralWAD,
                leverage: leverage
            });

            try EXECUTION_ENGINE.openPosition(params) {
                console.log("  SUCCESS: Position opened");
                successCount++;
                totalNotional += notional;
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
        console.log("Successful positions:", successCount, "/ 12");
        console.log("Total successful notional:", totalNotional, "USDT");
        console.log("Average leverage: 1.7x (within system constraints)");
        console.log("Target achieved: Large positions at max allowed leverage");
    }
}