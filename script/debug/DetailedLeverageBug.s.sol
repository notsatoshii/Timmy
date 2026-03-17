// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

contract DetailedLeverageBug is Script {
    function run() external view {
        address leverageModel = 0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF;
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        console2.log("=== Detailed Leverage Analysis ===");

        // Platform ceiling components
        (bool success1, bytes memory data1) = leverageModel.staticcall(abi.encodeWithSignature("getTVLMultiplier()"));
        uint256 tvlMult = abi.decode(data1, (uint256));

        (bool success2, bytes memory data2) = leverageModel.staticcall(abi.encodeWithSignature("getIFRMultiplier()"));
        uint256 ifrMult = abi.decode(data2, (uint256));

        (bool success3, bytes memory data3) = leverageModel.staticcall(abi.encodeWithSignature("getUtilizationMultiplier()"));
        uint256 utilMult = abi.decode(data3, (uint256));

        console2.log("TVL Multiplier WAD:", tvlMult);
        console2.log("IFR Multiplier WAD:", ifrMult);
        console2.log("Util Multiplier WAD:", utilMult);

        uint256 expectedCeiling = 30e18 * tvlMult / 1e18 * ifrMult / 1e18 * utilMult / 1e18;
        console2.log("Expected ceiling WAD:", expectedCeiling);

        // Actual ceiling
        (bool success4, bytes memory data4) = leverageModel.staticcall(abi.encodeWithSignature("getPlatformCeiling()"));
        uint256 actualCeiling = abi.decode(data4, (uint256));
        console2.log("Actual ceiling WAD:", actualCeiling);

        // Compressed leverage (after R_adjusted)
        (bool success5, bytes memory data5) = leverageModel.staticcall(abi.encodeWithSignature("getCompressedLeverage(bytes32)", spacexMarketId));
        uint256 compressed = abi.decode(data5, (uint256));
        console2.log("Compressed leverage WAD:", compressed);

        // Market adjustment (M_market)
        (bool success6, bytes memory data6) = leverageModel.staticcall(abi.encodeWithSignature("getMarketAdjustment(bytes32)", spacexMarketId));
        uint256 marketAdj = abi.decode(data6, (uint256));
        console2.log("Market Adjustment WAD:", marketAdj);

        // Final leverage
        (bool success7, bytes memory data7) = leverageModel.staticcall(abi.encodeWithSignature("getEffectiveMaxLeverage(bytes32)", spacexMarketId));
        uint256 finalLev = abi.decode(data7, (uint256));
        console2.log("Final leverage WAD:", finalLev);

        console2.log("=== Problem Analysis ===");
        console2.log("R_adjusted implied WAD:", (compressed * 1e18) / actualCeiling);
        console2.log("Expected final WAD:", (compressed * marketAdj) / 1e18);
    }
}