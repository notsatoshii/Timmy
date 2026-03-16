// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/core/LeverageModel.sol";

contract CheckMaxLeverage is Script {

    // Demo markets
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant NOTHING_EVER = 0x000000000000000000000000b072263740d7c60f1aa0bf46e737f83544c7b785;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant FED_RATE = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;
    bytes32 constant ARGENTINA = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;

    function run() external view {
        address leverageModel = vm.envAddress("LEVERAGE_MODEL");
        LeverageModel model = LeverageModel(leverageModel);

        bytes32[] memory markets = new bytes32[](6);
        markets[0] = SPACEX_IPO;
        markets[1] = US_IRAN;
        markets[2] = NOTHING_EVER;
        markets[3] = FIFA_SPAIN;
        markets[4] = FED_RATE;
        markets[5] = ARGENTINA;

        string[] memory names = new string[](6);
        names[0] = "SpaceX IPO";
        names[1] = "US-Iran";
        names[2] = "Nothing Ever";
        names[3] = "FIFA Spain";
        names[4] = "Fed Rate";
        names[5] = "Argentina";

        console.log("Market leverage limits:");
        console.log("======================");

        for (uint256 i = 0; i < markets.length; i++) {
            uint256 maxLev = model.getEffectiveMaxLeverage(markets[i]);
            console.log(names[i], ":", maxLev / 1e18, ".", (maxLev % 1e18) / 1e16, "x");
        }
    }
}