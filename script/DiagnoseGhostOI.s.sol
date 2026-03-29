// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IOILimitsView {
    function getGlobalOI() external view returns (uint256);
    function getMarketOI(bytes32 marketId) external view returns (uint256);
    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256);
    function getGlobalOICap() external view returns (uint256);
    function getMarketOICap(bytes32 marketId) external view returns (uint256);
    function getGlobalUtilization() external view returns (uint256);
}

interface IPositionManagerView {
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory);
}

interface IMarketRegistryView {
    function getActiveMarkets() external view returns (bytes32[] memory);
}

/// @title DiagnoseGhostOI
/// @notice Diagnostic script: compares OILimits state with PositionManager for all active markets.
///         Any market where OI > 0 and positionCount == 0 has ghost OI.
/// @dev Run with: forge script script/DiagnoseGhostOI.s.sol --rpc-url $RPC_URL
contract DiagnoseGhostOI is Script {
    // Update these addresses to match your deployment
    address constant OI_LIMITS        = address(0); // TODO: set from deploy-env.sh
    address constant POSITION_MANAGER = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
    address constant MARKET_REGISTRY  = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;

    function run() external view {
        IOILimitsView oi = IOILimitsView(OI_LIMITS);
        IPositionManagerView pm = IPositionManagerView(POSITION_MANAGER);
        IMarketRegistryView reg = IMarketRegistryView(MARKET_REGISTRY);

        console2.log("========================================");
        console2.log("  GHOST OI DIAGNOSTIC");
        console2.log("========================================");

        console2.log("\nGlobal OI:    ", oi.getGlobalOI());
        console2.log("Global Cap:   ", oi.getGlobalOICap());
        console2.log("Utilization:  ", oi.getGlobalUtilization());

        bytes32[] memory markets = reg.getActiveMarkets();
        uint256 ghostCount = 0;

        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 mid = markets[i];
            uint256 marketOI = oi.getMarketOI(mid);
            uint256[] memory positions = pm.getMarketPositions(mid);
            uint256 posCount = positions.length;

            if (marketOI > 0 || posCount > 0) {
                console2.log("\n--- Market", i, "---");
                console2.log("  Market OI:      ", marketOI);
                console2.log("  Long OI:        ", oi.getSideOI(mid, true));
                console2.log("  Short OI:       ", oi.getSideOI(mid, false));
                console2.log("  Position count: ", posCount);

                if (marketOI > 0 && posCount == 0) {
                    console2.log("  >>> GHOST OI DETECTED <<<");
                    ghostCount++;
                } else if (marketOI == 0 && posCount > 0) {
                    console2.log("  >>> REVERSE GHOST: positions exist but OI is 0 <<<");
                }
            }
        }

        console2.log("\n========================================");
        console2.log("Markets with ghost OI:", ghostCount);
        console2.log("========================================");
    }
}
