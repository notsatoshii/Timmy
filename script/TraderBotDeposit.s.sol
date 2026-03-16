// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/ILeverageModel.sol";

/**
 * @title TraderBotDeposit
 * @notice Each of 30 trader bots deposits collateral to AccountManager,
 *         then opens a random position (random market, direction, 2x leverage).
 */
contract TraderBotDeposit is Script {

    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;
    address constant LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;

    // Deposit 50K USDT to AccountManager (6 decimals)
    uint256 constant DEPOSIT_AMOUNT = 50_000 * 1e6;

    // Position collateral: 2K USDT (6 decimals)
    uint256 constant POSITION_COLLATERAL = 2_000 * 1e6;

    // 10 demo market IDs
    bytes32[10] marketIds = [
        bytes32(0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1), // 0: SpaceX IPO
        bytes32(0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a), // 1: US-Iran Ceasefire
        bytes32(0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d), // 2: Nothing Ever Happens
        bytes32(0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2), // 3: FIFA Spain
        bytes32(0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7), // 4: Fed Rate Below 4%
        bytes32(0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2), // 5: SpaceX Ackman
        bytes32(0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554), // 6: AAPL $250
        bytes32(0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc), // 7: OpenSea Token
        bytes32(0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f), // 8: Fed April Rate Cut
        bytes32(0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea)  // 9: Argentina USD
    ];

    // 30 trader bot private keys
    string[30] traderKeys = [
        "46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449", // trader_000
        "18cd0274afd31ceb3b376e5f417fae9be83711149f2b1f7c0f5f78b021346653", // trader_001
        "e4706a7051c55c5dadcbbcde78c8c160448de1b379f09a51b21431d1cb22b565", // trader_002
        "33e8b2f0ff44c4b17c333c433328d87db48ba324b59cb1a265f751dcfcbc22ac", // trader_003
        "948ac7b707a744dbfa9551bf5ae83616a06b27e28605bdb0c8df0adf5a1a8408", // trader_004
        "f2ef1d404d19052841a4a54df1e3a56854000ab0c48d04ee5bd4ab037fbeb6bd", // trader_005
        "93ae27e4ed31d445a293794a1138ac9ccb16d18869a67eff0f2a2f2dfe89b92d", // trader_006
        "f8d5d699495b1a53cb1eeefcbd36099de8bd768c327959779d53d2d54e643e49", // trader_007
        "6fdd790aa6bc211ac5254da28dab3a83d1f1b6ad1bcfe1b5a253f186bab0530b", // trader_008
        "73ab4b1cb5a93d556e4332a964a96c3a117ef8a9679090eb5b9b52e5c77af079", // trader_009
        "efdcf0525c7904f69e4ed591ac1cbc3bcc083807a4722ffeb47c0eb2dbdf20ea", // trader_010
        "a0c621225f66adb373d01b01c6b8c032defb4254688f831e721bba283cff97b5", // trader_011
        "96e763522cbab91177b644db05328e811dda7d6579b0691785c2fe36d1ce0cd3", // trader_012
        "b245f32e84d47ae3d90f8ed591acf304ae75926f960b7c7d78cf92f9ce901cd0", // trader_013
        "958356aea8137e0d8387da958d7330db9d49d32058a9cfee25a3b2ffdb173519", // trader_014
        "7104bc0cc1c24fce34301949c27733021ec711d02c60db319606164ea15b3295", // trader_015
        "ab44e121d6f68364b9175e7112011dde97dca114ff0f6a466ecef575180543aa", // trader_016
        "712ec8566caeafbffb77ef1b9e321f099bf6f05dedd7a5e09d4d14116f9b6303", // trader_017
        "87edf75f45add029564417ba04adc9e8d7f566c0b9cc0f51bd4ae9484dd6d81d", // trader_018
        "055c30c6467b330231d2fded7ea14ddc8ca5938f394d1471c9360e7540a5a1b6", // trader_019
        "2506ae8e1f634d8cbdd46612a0161710f13be781886dcfc2ede3f9e260a2a6f5", // trader_020
        "d6b988357f23dea099f6ddae496189e9a25aa0ca5c2866bc3843510d0ea2307b", // trader_021
        "eb9620425aaada188adb4196718a35361e850a1f17a2ffec955716a5a0d26c0f", // trader_022
        "50eea013153434a3d0f11382526bc41167d68a30f87c3cec3e7a95a18df6cc6d", // trader_023
        "b9e19dbc64e31496483f78da23363b37ed93fb5412bb600ef74530912d15a138", // trader_024
        "34ecc8d0756499aec22bd04390411bd74f210f5e555746fe774a9ce8f509aa5f", // trader_025
        "455ef2d47dd597dabf1aca8aa447c883989f59e5ee23c6752d1d15f9e779561f", // trader_026
        "87c9ac5bce370a33b40eda8fa91e11afa31b11c2e9cc28da36e76a326b3c2abc", // trader_027
        "cb2a3dd5320e2d8dec6a9341849fbac68dab2214acf98b841a4734bb0449c06f", // trader_028
        "a5de86024b27142d285e1c48c0297bebb0be5c9736f8d8465d2120f84b49ac84"  // trader_029
    ];

    function run() external {
        console.log("=== Trader Bot Deposit & Position Opening ===");
        console.log("Bots: 30 | Deposit: 50K USDT each | Position: 2K USDT collateral");

        IERC20 usdt = IERC20(USDT);
        ExecutionEngine engine = ExecutionEngine(EXECUTION_ENGINE);
        ILeverageModel levModel = ILeverageModel(LEVERAGE_MODEL);

        uint256 depositCount;
        uint256 positionCount;
        uint256 skipCount;

        for (uint256 i = 0; i < 30; i++) {
            uint256 privateKey = vm.parseUint(string.concat("0x", traderKeys[i]));
            address trader = vm.addr(privateKey);

            uint256 usdtBalance = usdt.balanceOf(trader);
            console.log("--- Trader", i, "---");
            console.log("  Address:", trader);
            console.log("  USDT balance:", usdtBalance);

            if (usdtBalance < DEPOSIT_AMOUNT) {
                console.log("  SKIP: Insufficient USDT");
                skipCount++;
                continue;
            }

            // Pick market and direction deterministically
            uint256 marketIndex = i % 10;
            bool isLong = (i % 2 == 0);

            // Query max leverage for this market
            uint256 maxLev = levModel.getEffectiveMaxLeverage(marketIds[marketIndex]);
            console.log("  Market", marketIndex, "max leverage:", maxLev);

            // Use min(maxLev, desired) — desired is 2x but cap at what market allows
            uint256 leverage = maxLev < 2e18 ? maxLev : 2e18;

            // Need at least 1x to open a position
            if (leverage < 1e18) {
                leverage = 1e18;
            }

            vm.startBroadcast(privateKey);

            // Step 1: Approve USDT to AccountManager
            usdt.approve(ACCOUNT_MANAGER, DEPOSIT_AMOUNT);

            // Step 2: Deposit to AccountManager
            AccountManager(ACCOUNT_MANAGER).deposit(DEPOSIT_AMOUNT);
            console.log("  Deposited 50K USDT to AccountManager");
            depositCount++;

            // Step 3: Open position with dynamic leverage
            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketIds[marketIndex],
                isLong: isLong,
                collateral: POSITION_COLLATERAL,
                leverage: leverage
            });

            uint256 positionId = engine.openPosition(params);
            console.log("  Position opened! ID:", positionId);
            console.log("  Market:", marketIndex, isLong ? "LONG" : "SHORT");
            console.log("  Leverage used:", leverage);
            positionCount++;

            vm.stopBroadcast();

            // 1s delay between bots to avoid nonce collisions
            if (i < 29) {
                vm.sleep(1000);
            }
        }

        console.log("\n=== Results ===");
        console.log("Deposits:", depositCount);
        console.log("Positions opened:", positionCount);
        console.log("Skipped:", skipCount);
    }
}
