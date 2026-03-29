// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IOILimitsReset {
    function adminResetMarketOIFull(bytes32 marketId, address[] calldata affectedUsers) external;
    function adminResetMarketOI(bytes32 marketId) external;
    function getGlobalOI() external view returns (uint256);
    function getMarketOI(bytes32 marketId) external view returns (uint256);
    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256);
}

interface IPositionManagerCheck {
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory);
}

interface IMarketRegistryList {
    function getActiveMarkets() external view returns (bytes32[] memory);
}

/// @title ResetGhostOI
/// @notice Safely resets ghost OI for all affected markets using adminResetMarketOIFull.
/// @dev Run with: forge script script/ResetGhostOI.s.sol --rpc-url $RPC_URL --broadcast
///
/// IMPORTANT: Before running this script:
///   1. Run DiagnoseGhostOI.s.sol first to confirm which markets have ghost OI
///   2. Pause ExecutionEngine to prevent new position opens during reset
///   3. Enumerate affected users from OIIncreased events for each ghost market
///   4. Update the AFFECTED_USERS mapping below with the correct addresses
contract ResetGhostOI is Script {
    // Update these addresses to match your deployment
    address constant OI_LIMITS        = address(0); // TODO: set from deploy-env.sh
    address constant POSITION_MANAGER = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
    address constant MARKET_REGISTRY  = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;

    function run() external {
        IOILimitsReset oi = IOILimitsReset(OI_LIMITS);
        IPositionManagerCheck pm = IPositionManagerCheck(POSITION_MANAGER);
        IMarketRegistryList reg = IMarketRegistryList(MARKET_REGISTRY);

        console2.log("========================================");
        console2.log("  GHOST OI RESET");
        console2.log("========================================");
        console2.log("Global OI before:", oi.getGlobalOI());

        bytes32[] memory markets = reg.getActiveMarkets();

        vm.startBroadcast();

        uint256 resetCount = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 mid = markets[i];
            uint256 marketOI = oi.getMarketOI(mid);
            uint256 posCount = pm.getMarketPositions(mid).length;

            if (marketOI > 0 && posCount == 0) {
                console2.log("\nResetting market", i);
                console2.log("  OI before:      ", marketOI);
                console2.log("  Long OI:        ", oi.getSideOI(mid, true));
                console2.log("  Short OI:       ", oi.getSideOI(mid, false));

                // Build affected users list for this market.
                // TODO: populate from OIIncreased event scan for each market.
                // For now, use empty list (clears global/market/side OI but not per-user).
                // Per-user OI must be cleared in a follow-up call with the correct list.
                address[] memory users = _getAffectedUsers(mid);

                oi.adminResetMarketOIFull(mid, users);
                resetCount++;

                console2.log("  OI after:       ", oi.getMarketOI(mid));
            }
        }

        vm.stopBroadcast();

        console2.log("\n========================================");
        console2.log("Markets reset:", resetCount);
        console2.log("Global OI after:", oi.getGlobalOI());
        console2.log("========================================");
    }

    /// @dev Override this function with actual user addresses per market.
    ///      Build the list by querying OIIncreased events from the old OILimits contract:
    ///      cast logs --from-block 0 --address $OLD_OI_LIMITS "OIIncreased(bytes32,bool,uint256,uint256)"
    function _getAffectedUsers(bytes32 /* marketId */) internal pure returns (address[] memory) {
        // TODO: populate with actual affected users per market
        // Example:
        // address[] memory users = new address[](2);
        // users[0] = 0x1234...;
        // users[1] = 0x5678...;
        // return users;
        return new address[](0);
    }
}
