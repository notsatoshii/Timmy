// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/core/PositionManager.sol";
import "./contracts/core/AccountManager.sol";

contract OpenHighLeveragePositions is Script {

    // Demo markets from demo_markets.json
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant NOTHING_EVER = 0x000000000000000000000000b072263740d7c60f1aa0bf46e737f83544c7b785;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant FED_RATE = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;
    bytes32 constant ARGENTINA = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;

    struct OpenParams {
        bytes32 marketId;
        bool isLong;
        uint256 collateral;
        uint256 leverage;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address accountManager = vm.envAddress("ACCOUNT_MANAGER");

        AccountManager am = AccountManager(accountManager);

        // High leverage positions (5x-15x)
        OpenParams[] memory positions = new OpenParams[](12);

        // Position 1: Long SpaceX at 10x
        positions[0] = OpenParams(SPACEX_IPO, true, 400_000000, 10 * 1e18);

        // Position 2: Short US-Iran at 8x
        positions[1] = OpenParams(US_IRAN, false, 300_000000, 8 * 1e18);

        // Position 3: Long FIFA Spain at 7x
        positions[2] = OpenParams(FIFA_SPAIN, true, 350_000000, 7 * 1e18);

        // Position 4: Short Fed Rate at 5x
        positions[3] = OpenParams(FED_RATE, false, 500_000000, 5 * 1e18);

        // Position 5: Long Argentina at 12x
        positions[4] = OpenParams(ARGENTINA, true, 250_000000, 12 * 1e18);

        // Position 6: Short SpaceX at 6x
        positions[5] = OpenParams(SPACEX_IPO, false, 400_000000, 6 * 1e18);

        // Position 7: Long US-Iran at 9x
        positions[6] = OpenParams(US_IRAN, true, 300_000000, 9 * 1e18);

        // Position 8: Short FIFA Spain at 15x
        positions[7] = OpenParams(FIFA_SPAIN, false, 200_000000, 15 * 1e18);

        // Position 9: Long Fed Rate at 11x
        positions[8] = OpenParams(FED_RATE, true, 350_000000, 11 * 1e18);

        // Position 10: Short Argentina at 8x
        positions[9] = OpenParams(ARGENTINA, false, 400_000000, 8 * 1e18);

        // Position 11: Long SpaceX at 14x
        positions[10] = OpenParams(SPACEX_IPO, true, 250_000000, 14 * 1e18);

        // Position 12: Short US-Iran at 5x
        positions[11] = OpenParams(US_IRAN, false, 350_000000, 5 * 1e18);

        vm.startBroadcast(deployerKey);

        // Check deployer balance first
        uint256 balance = am.getBalance(vm.addr(deployerKey));
        console.log("Deployer balance:", balance / 1e6, "USDT");

        for (uint256 i = 0; i < positions.length; i++) {
            OpenParams memory params = positions[i];

            console.log("Opening position", i + 1);
            console.log("  Market:", vm.toString(params.marketId));
            console.log("  Direction:", params.isLong ? "LONG" : "SHORT");
            console.log("  Collateral:", params.collateral / 1e6, "USDT");
            console.log("  Leverage:", params.leverage / 1e18, "x");

            // Open position
            (bool success,) = executionEngine.call(
                abi.encodeWithSignature(
                    "openPosition((bytes32,bool,uint256,uint256))",
                    params
                )
            );

            if (success) {
                console.log("  SUCCESS");
            } else {
                console.log("  FAILED");
            }
            console.log("---");
        }

        vm.stopBroadcast();
    }
}