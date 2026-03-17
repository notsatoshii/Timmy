// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function setMarketRiskParams(bytes32 marketId, uint256 sigmaBaseline, uint256 depthThreshold) external;
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

contract FixLeverageParameters is Script {
    ILeverageModel constant leverageModel = ILeverageModel(0x63B98Ec1e559E3b24199eb2115F0a57222e9818c);

    uint256 constant SIGMA_BASELINE = 250000000000000000; // 25% baseline volatility
    uint256 constant DEPTH_THRESHOLD = 5000000000000000000; // 5 USDT realistic depth

    function run() external {
        vm.startBroadcast();

        console2.log("=== Fixing LeverageModel Parameters ===");
        console2.log("Target contract:", address(leverageModel));

        // Fix all markets
        _fixMarket(0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1, "spacex");
        _fixMarket(0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a, "usIran");
        _fixMarket(0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7, "fifaSpain");
        _fixMarket(0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea, "argentina");
        _fixMarket(0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554, "fedRate");

        vm.stopBroadcast();
    }

    function _fixMarket(bytes32 marketId, string memory name) internal {
        console2.log("Fixing market:", name);

        uint256 beforeLeverage = leverageModel.getEffectiveMaxLeverage(marketId);
        console2.log("Before (WAD):", beforeLeverage);

        leverageModel.setMarketRiskParams(marketId, SIGMA_BASELINE, DEPTH_THRESHOLD);

        uint256 afterLeverage = leverageModel.getEffectiveMaxLeverage(marketId);
        console2.log("After (WAD):", afterLeverage);

        if (afterLeverage >= 20e18) {
            console2.log("SUCCESS: >= 20x leverage");
        } else {
            console2.log("WARNING: Still < 20x leverage");
        }
        console2.log("");
    }
}