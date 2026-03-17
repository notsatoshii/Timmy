// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

contract CheckLeverageBug is Script {
    function run() external view {
        address leverageModel = 0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF;
        address vault = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        console2.log("=== Leverage Model Debug ===");

        // Check vault totalAssets (USDT 6-decimal)
        (bool success1, bytes memory data1) = vault.staticcall(abi.encodeWithSignature("totalAssets()"));
        require(success1, "Vault call failed");
        uint256 totalAssets = abi.decode(data1, (uint256));
        console2.log("Vault totalAssets (USDT):", totalAssets);
        console2.log("This equals ~$", totalAssets / 1e6, "M USD");

        // Check TVL multiplier
        (bool success2, bytes memory data2) = leverageModel.staticcall(abi.encodeWithSignature("getTVLMultiplier()"));
        require(success2, "TVL multiplier call failed");
        uint256 tvlMult = abi.decode(data2, (uint256));
        console2.log("TVL Multiplier (WAD):", tvlMult);
        console2.log("This equals:", tvlMult / 1e16, "basis points");

        // Check platform ceiling
        (bool success3, bytes memory data3) = leverageModel.staticcall(abi.encodeWithSignature("getPlatformCeiling()"));
        require(success3, "Platform ceiling call failed");
        uint256 ceiling = abi.decode(data3, (uint256));
        console2.log("Platform Ceiling (WAD):", ceiling);
        console2.log("This equals ~", ceiling / 1e18, "x leverage");

        // Check effective max leverage for SpaceX
        (bool success4, bytes memory data4) = leverageModel.staticcall(abi.encodeWithSignature("getEffectiveMaxLeverage(bytes32)", spacexMarketId));
        require(success4, "Max leverage call failed");
        uint256 maxLev = abi.decode(data4, (uint256));
        console2.log("SpaceX Max Leverage (WAD):", maxLev);
        console2.log("This equals ~", maxLev / 1e18, "x leverage");

        console2.log("=== Analysis ===");
        uint256 expectedWadTvl = totalAssets * 1e12; // Convert USDT to WAD
        console2.log("Expected TVL in WAD:", expectedWadTvl);

        uint256 tvlMaturity = 50_000_000e18; // $50M in WAD
        uint256 ratio = expectedWadTvl * 1e18 / tvlMaturity; // WAD division
        console2.log("TVL/Maturity ratio (WAD):", ratio);
        console2.log("sqrt(ratio) should be ~", sqrt(ratio) / 1e18, "if calculations are correct");
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}