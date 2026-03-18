// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function setMarketRiskParams(bytes32 marketId, uint256 sigmaBaseline, uint256 depthThreshold) external;
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

contract ApplyLeverageOverrides is Script {
    ILeverageModel constant leverageModel = ILeverageModel(0x474E2eE2911544a385eb017369e8516Ad6DcCAbd);

    function run() external {
        vm.startBroadcast();

        console2.log("=== Applying Leverage Parameter Overrides ===");

        // SpaceX market override
        bytes32 spacexMarket = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        uint256 beforeLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarket);
        console2.log("SpaceX Before:", beforeLeverage / 1e18);

        leverageModel.setMarketRiskParams(
            spacexMarket,
            50000000000000000,
            1000000000000000000
        );

        uint256 afterLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarket);
        console2.log("SpaceX After:", afterLeverage / 1e18);

        if (afterLeverage >= 15e18) {
            console2.log("SUCCESS: Leverage >= 15x achieved");
        } else {
            console2.log("PARTIAL: Some improvement but not full fix");
        }

        vm.stopBroadcast();
    }
}