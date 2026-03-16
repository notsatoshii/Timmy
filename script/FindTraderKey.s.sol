// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

/// @title FindTraderKey
/// @notice Find which trader private key corresponds to position owners
contract FindTraderKey is Script {

    // Target addresses from position owners
    address constant TARGET_1 = 0xB072263740D7c60f1Aa0BF46e737F83544C7b785;
    address constant TARGET_2 = 0x7fF86E0C1504fE4e4B5AeB398B27dCA124E0D381;
    address constant TARGET_3 = 0x51DfE10EAB72ba671d9D499cA15C2eD790Da39C4;

    // Some trader private keys
    uint256[10] traderKeys = [
        0x46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449, // trader_000
        0x18cd0274afd31ceb3b376e5f417fae9be83711149f2b1f7c0f5f78b021346653, // trader_001
        0xe4706a7051c55c5dadcbbcde78c8c160448de1b379f09a51b21431d1cb22b565, // trader_002
        0x33e8b2f0ff44c4b17c333c433328d87db48ba324b59cb1a265f751dcfcbc22ac, // trader_003
        0x948ac7b707a744dbfa9551bf5ae83616a06b27e28605bdb0c8df0adf5a1a8408, // trader_004
        0xf2ef1d404d19052841a4a54df1e3a56854000ab0c48d04ee5bd4ab037fbeb6bd, // trader_005
        0x93ae27e4ed31d445a293794a1138ac9ccb16d18869a67eff0f2a2f2dfe89b92d, // trader_006
        0xf8d5d699495b1a53cb1eeefcbd36099de8bd768c327959779d53d2d54e643e49, // trader_007
        0x6fdd790aa6bc211ac5254da28dab3a83d1f1b6ad1bcfe1b5a253f186bab0530b, // trader_008
        0x73ab4b1cb5a93d556e4332a964a96c3a117ef8a9679090eb5b9b52e5c77af079  // trader_009
    ];

    function run() external view {
        console.log("=== Finding Trader Private Keys ===");
        console.log("Target 1:", TARGET_1);
        console.log("Target 2:", TARGET_2);
        console.log("Target 3:", TARGET_3);

        for (uint256 i = 0; i < 10; i++) {
            address derived = vm.addr(traderKeys[i]);
            console.log("Trader", i, "address:", derived);

            if (derived == TARGET_1) {
                console.log("*** MATCH: Trader", i, "owns position 3 ***");
            }
            if (derived == TARGET_2) {
                console.log("*** MATCH: Trader", i, "owns position 10 ***");
            }
            if (derived == TARGET_3) {
                console.log("*** MATCH: Trader", i, "owns position 15 ***");
            }
        }
    }
}