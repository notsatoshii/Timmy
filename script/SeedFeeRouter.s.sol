// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDT} from "../contracts/periphery/MockUSDT.sol";

/**
 * @title SeedFeeRouter
 * @notice Get USDT from faucet and seed FeeRouter for fee distribution
 */
contract SeedFeeRouter is Script {

    address constant USDT = 0xf846E395219200cAeB12e802349EC67fecB28Ea8;
    address constant FEE_ROUTER = 0x304966042cfE06f5ff4347D8698B9CCa4F971335;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Seeding FeeRouter with USDT ===");

        vm.startBroadcast(deployerPrivateKey);

        IERC20 usdt = IERC20(USDT);

        // Transfer to FeeRouter from existing balance - need more for WAD calculations
        uint256 seedAmount = 1000e6;  // 1000 USDT (6 decimals)
        usdt.transfer(FEE_ROUTER, seedAmount);

        vm.stopBroadcast();

        console2.log("==> FeeRouter seeded with 100 USDT!");
    }
}