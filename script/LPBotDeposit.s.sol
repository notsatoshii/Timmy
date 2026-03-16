// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/LeverVault.sol";

contract LPBotDeposit is Script {
    // Contract addresses on Base Sepolia
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant LEVER_VAULT = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;

    // Each LP bot deposits 500K USDT (6 decimals)
    uint256 constant DEPOSIT_AMOUNT = 500_000 * 1e6;

    // LP bot private keys (from control-plane/bot-wallets.json)
    string[40] lpBotKeys = [
        "ebbe844f64c499f07dc79de16fdbcbd2c0a7f1684bd6f4e1030c924405eecc6b", // lp_000
        "971f7a7d36ecb24b90faeb5bbef980892a06d4597989ef007f3c2b7958cd00c9", // lp_001
        "f331268fcfbbcfc1dc892370cb1c637acbdc9c347a4618198da3a1710db05609", // lp_002
        "d7685ba2727779e46165d565651b967ddf6782f9695d55c1afa89b171a3784b5", // lp_003
        "dd9c6721dfa25cb53638f19d9b4627283ead95e9b45230e8dec52c13ea583e65", // lp_004
        "903d237b7c7c80b2adfdb14535871cfe12c5f4bd2502e36a7b4138c876cc1bba", // lp_005
        "184d17a80cd0580d6432bf6c63e64703e2e6f695818321395c11173aa4dd2fef", // lp_006
        "856269830ee1b64061c4a61cc7bd0549c13fa90e6cad49232f0f5f42ecca91df", // lp_007
        "3bad340b6116a83281ee3e41e88d59f5edb74319e5f64d47e0889d04361f5e3e", // lp_008
        "adb89d15ed5e57a052fc62e4a2183593b5d1844d72f0557e32ff339cd25a9495", // lp_009
        "4f21bf6f25464925898e4ae9c5df86ffdbfcc46a90af81fca2924c1c1aba3c96", // lp_010
        "5ea45a017ca527775882d57f58d2b8510a7b3afae2d9122a29d596e52a037b65", // lp_011
        "e2a49f2f7669baf764af7a9637e6c87cfd3f062b2540d91c38118ea3527dd3d9", // lp_012
        "3d45836f5f7e091747f8a214dfc12bb2c45692ecfb87db636f7c0b68782fe82e", // lp_013
        "657a3111995b450a982f54d127f4052c35c7bda86c867e9647d26709246baee4", // lp_014
        "3134df240d97e6cd0dd9b6d70a9e31ca6e2b091eafbf3a01868e2c6f9ffbba78", // lp_015
        "af8b38b842eb4d199a92e4843c1fe2736f223ddf19fd7fc82c5d69b60f1dc5b8", // lp_016
        "f27839f473ff8a488d1b23886790d2841ad3029773e323a1cdb75f3fd3fdf028", // lp_017
        "11784763c7d66893682d2fbbbbfac880323dc1abe92bc44bfd660d03d0d34a08", // lp_018
        "863319caed2efc2c6578bf7c97e4eab6c6409ba5163a6217dd98fb710042b7f8", // lp_019
        "8275db05adb3b1e8585371cf6583b7f77bbd0eece8b84d0fb27e69ea2872abe8", // lp_020
        "ff6cb4b2719bae34b62ebf9dfb10540c9cc5b554ae0bdbfd560399c7597170c4", // lp_021
        "c2d8550bf5bf05a25a29b85d40402252d1cbcf4021770745ac1b327262b603fe", // lp_022
        "126e3de5f0adb12e2ea6d3a3860cc4e340e556497d9d77e7564358e61da0e3c7", // lp_023
        "0e79ce7da466b619cc1c384ac660d08975f01a44b028ccc5d39d3a56a178b6ab", // lp_024
        "cf043b73c7cc3eb49312b734058e53cbd7a4662472a287a49200e0e2f6b185f0", // lp_025
        "674ee4fc6ba7fc4fd71d9e9ef51722e6168535d3aac1cbb51dc5c65f2b804e8f", // lp_026
        "7352a1dc09d4d2ef0d00ae303e017369e463a12870427f12639673684ecaa20b", // lp_027
        "d2cb793bbcc73f15f2c5df1e9b4e8f3320f0d9d839fc22349462787be1e67273", // lp_028
        "e6272628ec7af288ac68d92ddb658ea693323e3e10f6875147ca5bfcfa503ae4", // lp_029
        "79dd01b2b154c61cd1a66c8df542a7cc8946d887596dea382e51ddcac39bd425", // lp_030
        "53ff186352d141a77f5cbafdfe9a2ad26817d9c35b28ae64d33cb0e749168625", // lp_031
        "2bb92b7e92ec9ae09a8ed46cf1a900bbadf4c1c26e606a33f1fdf0d26791ee31", // lp_032
        "821468be7e819b8c2e332a0fbc42c868e3f363c246df23d338f6e4968bfa57e7", // lp_033
        "6ed122158186fd8a0a40e916d63d06f5b326bb72fa142b52efa43f5f025baf5d", // lp_034
        "c79fd4a10d624ba494aa57a07bfc2c5b9d784b13bf9ea08eda7c0a58f2c55362", // lp_035
        "0209942206e5a4a9ce0505afa9430e842e06bb327ebd74e5a9fe5b709005e28c", // lp_036
        "a8fd42ac1f3638a4c1087ddc5150ffc3d48e508d6ea77807007d785d10e0c8a0", // lp_037
        "bac84519f3a76579dec7ef2514a7fb06ebe5ff52d451953eba216ab72f680f3d", // lp_038
        "11922442629a61585535e2744d3dc4f20ab55fee88f40ef5d4dd38e6b05bdb5f"  // lp_039
    ];

    function run() external {
        console.log("Starting LP bot deposits...");

        IERC20 usdt = IERC20(USDT);
        LeverVault vault = LeverVault(LEVER_VAULT);

        // Record initial TVL
        uint256 initialTVL = vault.totalAssets();
        console.log("Initial TVL:", initialTVL);

        // Process each LP bot
        for (uint i = 0; i < 40; i++) {
            uint256 privateKey = vm.parseUint(string.concat("0x", lpBotKeys[i]));
            address lpBot = vm.addr(privateKey);

            console.log("Processing LP bot", i);
            console.log("  Address:", lpBot);

            // Check bot's USDT balance
            uint256 balance = usdt.balanceOf(lpBot);
            console.log("  USDT balance:", balance);

            if (balance < DEPOSIT_AMOUNT) {
                console.log("  ERROR: Insufficient balance");
                console.log("  Need:", DEPOSIT_AMOUNT);
                continue;
            }

            // Switch to bot's context
            vm.startBroadcast(privateKey);

            // Step 1: Approve vault to spend USDT
            usdt.approve(LEVER_VAULT, DEPOSIT_AMOUNT);
            console.log("  Approved USDT amount:", DEPOSIT_AMOUNT);

            // Step 2: Deposit to vault
            uint256 shares = vault.deposit(DEPOSIT_AMOUNT, lpBot);
            console.log("  Deposited USDT:", DEPOSIT_AMOUNT);
            console.log("  Received shares:", shares);

            vm.stopBroadcast();

            // 1 second delay between bots to avoid nonce collisions
            if (i < 39) {
                console.log("  Waiting 1 second...");
                vm.sleep(1000);
            }
        }

        // Check final TVL
        uint256 finalTVL = vault.totalAssets();
        console.log("Final TVL:", finalTVL);
        console.log("TVL increase:", finalTVL - initialTVL);
        console.log("Expected increase:", 40 * DEPOSIT_AMOUNT);

        // Verify expected increase
        uint256 expectedIncrease = 40 * DEPOSIT_AMOUNT; // 20M USDT
        uint256 actualIncrease = finalTVL - initialTVL;

        if (actualIncrease >= expectedIncrease * 99 / 100) { // Allow for small rounding differences
            console.log("SUCCESS: TVL increased as expected!");
        } else {
            console.log("WARNING: TVL increase less than expected");
        }
    }
}