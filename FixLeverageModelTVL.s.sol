// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function getTVLFromVault() external view returns (uint256);
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
    function fixTVLDecimalConversion() external;
}

interface ILeverVault {
    function totalAssets() external view returns (uint256);
}

contract FixLeverageModelTVL is Script {
    ILeverageModel constant leverageModel = ILeverageModel(0x474E2eE2911544a385eb017369e8516Ad6DcCAbd);
    ILeverVault constant leverVault = ILeverVault(0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921);

    bytes32 constant SPACEX_MARKET = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

    function run() external {
        vm.startBroadcast();

        console2.log("=== Fixing LeverageModel TVL Decimal Conversion ===");
        console2.log("LeverageModel:", address(leverageModel));
        console2.log("LeverVault:", address(leverVault));

        // Check current state
        uint256 vaultTVL = leverVault.totalAssets();
        console2.log("Vault TVL (USDT 6-decimal):", vaultTVL);
        console2.log("Vault TVL (human):", vaultTVL / 1e6, "USDT");

        uint256 beforeLeverage = leverageModel.getEffectiveMaxLeverage(SPACEX_MARKET);
        console2.log("SpaceX Leverage Before Fix:", beforeLeverage / 1e18, "x");

        // Apply the fix (this would need to be implemented in the LeverageModel contract)
        // For now, we'll create a configuration workaround
        console2.log("ISSUE: LeverageModel needs TVL decimal conversion from 6 to 18 decimals");
        console2.log("Expected WAD format:", vaultTVL * 1e12);

        vm.stopBroadcast();
    }
}