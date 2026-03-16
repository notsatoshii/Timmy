// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../contracts/interfaces/ILeverageModel.sol";
import "../../contracts/interfaces/IMarketRegistry.sol";

contract CheckMarketLimits is Script {
    // Known market IDs from existing positions
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN_CEASEFIRE = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant ARGENTINA_USD = 0xe73fd3dd8b7c2f1e5a9c6d3f0b4a7e1d8c5f2a9b6e3c0f4d7a1e5b8c2f6d9a3e;

    // Contract addresses
    address constant LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;
    address constant MARKET_REGISTRY = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;

    function run() external view {
        ILeverageModel lm = ILeverageModel(LEVERAGE_MODEL);
        IMarketRegistry mr = IMarketRegistry(MARKET_REGISTRY);

        bytes32[] memory marketIds = new bytes32[](4);
        marketIds[0] = SPACEX_IPO;
        marketIds[1] = US_IRAN_CEASEFIRE;
        marketIds[2] = FIFA_SPAIN;
        marketIds[3] = ARGENTINA_USD;

        string[] memory marketNames = new string[](4);
        marketNames[0] = "SpaceX IPO";
        marketNames[1] = "US-Iran Ceasefire";
        marketNames[2] = "FIFA Spain";
        marketNames[3] = "Argentina USD";

        console.log("=== Market Leverage Limits ===");

        for (uint256 i = 0; i < marketIds.length; i++) {
            console.log("Market:", marketNames[i]);
            console.log("  Market ID:", vm.toString(marketIds[i]));

            try mr.getMarketState(marketIds[i]) returns (IMarketRegistry.MarketState state) {
                console.log("  State:", uint8(state), "(0=LISTED, 1=ACTIVE, 2=PENDING, 3=RESOLVED)");

                try lm.getEffectiveMaxLeverage(marketIds[i]) returns (uint256 maxLeverage) {
                    uint256 leverageReadable = maxLeverage / 1e18;
                    console.log("  Max Leverage:", leverageReadable, "x");
                } catch {
                    console.log("  Max Leverage: ERROR");
                }
            } catch {
                console.log("  Market NOT FOUND");
            }

            console.log("");
        }
    }
}