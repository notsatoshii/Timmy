// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockUSDT} from "../contracts/periphery/MockUSDT.sol";

/**
 * @title MintToFeeRouter
 * @notice Mint massive amount of USDT to FeeRouter to handle WAD calculations
 */
contract MintToFeeRouter is Script {

    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant FEE_ROUTER = 0x304966042cfE06f5ff4347D8698B9CCa4F971335;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Minting USDT to FeeRouter for WAD calculations ===");

        vm.startBroadcast(deployerPrivateKey);

        MockUSDT usdt = MockUSDT(USDT);

        // Mint 1 trillion USDT to cover any WAD fee calculations
        // This is only for testnet - production would need proper decimal handling
        uint256 mintAmount = 1_000_000_000_000e6;  // 1 trillion USDT (6 decimals)
        usdt.mint(FEE_ROUTER, mintAmount);

        vm.stopBroadcast();

        console2.log("==> Minted 1 trillion USDT to FeeRouter for testnet use!");
    }
}