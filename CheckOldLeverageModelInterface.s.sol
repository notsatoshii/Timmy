// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ILeverageModel {
    function setMarketRiskParams(bytes32 marketId, uint256 sigmaBaseline, uint256 depthThreshold) external;
    function getMarketRiskParams(bytes32 marketId) external view returns (uint256 sigmaBaseline, uint256 depthThreshold);
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

interface IAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
}

contract CheckOldLeverageModelInterface is Script {

    address constant OLD_LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;
    bytes32 constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

    function run() external {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        ILeverageModel leverage = ILeverageModel(OLD_LEVERAGE_MODEL);
        IAccessControl access = IAccessControl(OLD_LEVERAGE_MODEL);

        console2.log("=== Checking Old LeverageModel Interface ===");
        console2.log("Contract:", OLD_LEVERAGE_MODEL);
        console2.log("Deployer:", deployer);

        // Check if deployer has KEEPER role
        try access.hasRole(KEEPER_ROLE, deployer) returns (bool hasRole) {
            console2.log("Has KEEPER role:", hasRole);

            if (!hasRole) {
                console2.log("Attempting to grant KEEPER role...");
                vm.startBroadcast();
                try access.grantRole(KEEPER_ROLE, deployer) {
                    console2.log("KEEPER role granted successfully");
                } catch {
                    console2.log("Failed to grant KEEPER role");
                }
                vm.stopBroadcast();
            }
        } catch {
            console2.log("KEEPER role check failed - contract might not have AccessControl");
        }

        // Try to read current market risk params
        console2.log("\n=== Current Market Risk Params ===");
        try leverage.getMarketRiskParams(SPACEX_IPO) returns (uint256 sigma, uint256 depth) {
            console2.log("SpaceX sigma baseline:", sigma / 1e16, "bps");
            console2.log("SpaceX depth threshold:", depth / 1e18, "tokens");
        } catch {
            console2.log("Failed to read market risk params");
        }

        // Check current leverage
        try leverage.getEffectiveMaxLeverage(SPACEX_IPO) returns (uint256 currentLev) {
            console2.log("SpaceX current leverage:", currentLev / 1e18, "x");
        } catch {
            console2.log("Failed to read current leverage");
        }

        // Try to set better market risk params
        console2.log("\n=== Setting Better Market Risk Params ===");
        vm.startBroadcast();
        try leverage.setMarketRiskParams(SPACEX_IPO, 25e16, 1e18) { // 25% volatility, 1 token depth
            console2.log("Successfully set market risk params");

            // Check leverage after update
            try leverage.getEffectiveMaxLeverage(SPACEX_IPO) returns (uint256 newLev) {
                console2.log("SpaceX NEW leverage:", newLev / 1e18, "x");
            } catch {
                console2.log("Failed to read new leverage");
            }
        } catch {
            console2.log("Failed to set market risk params");
        }
        vm.stopBroadcast();
    }
}