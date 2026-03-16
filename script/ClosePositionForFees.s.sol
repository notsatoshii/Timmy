// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";

/// @title ClosePositionForFees
/// @notice Close a position to trigger borrow fee collection
contract ClosePositionForFees is Script {

    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IInsuranceFund constant INSURANCE_FUND = IInsuranceFund(0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8);

    function run() external {
        console.log("=== Close Position to Trigger Fee Collection ===");

        // Check insurance fund balance before
        uint256 insuranceBalanceBefore = INSURANCE_FUND.getBalance();
        console.log("Insurance Fund Balance Before:", insuranceBalanceBefore / 1e18, "USDT");

        // Use trader_000 private key (owner of some positions)
        uint256 traderKey = 0x46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449;
        address trader = vm.addr(traderKey);

        console.log("Trader Address:", trader);

        vm.startBroadcast(traderKey);

        // Try to close position 3 (if owned by this trader)
        try EXECUTION_ENGINE.closePosition(3) {
            console.log("Successfully closed position 3");
        } catch {
            console.log("Failed to close position 3 - trying position 10");

            try EXECUTION_ENGINE.closePosition(10) {
                console.log("Successfully closed position 10");
            } catch {
                console.log("Failed to close position 10 - trying position 15");

                try EXECUTION_ENGINE.closePosition(15) {
                    console.log("Successfully closed position 15");
                } catch {
                    console.log("Failed to close any positions");
                }
            }
        }

        vm.stopBroadcast();

        // Check insurance fund balance after
        uint256 insuranceBalanceAfter = INSURANCE_FUND.getBalance();
        uint256 increase = insuranceBalanceAfter - insuranceBalanceBefore;

        console.log("Insurance Fund Balance After:", insuranceBalanceAfter / 1e18, "USDT");
        console.log("Insurance Fund Increase:", increase / 1e18, "USDT");

        if (increase > 0) {
            console.log("SUCCESS: Fee collection working!");
            console.log("InsuranceFund grew by", increase / 1e18, "USDT");
        } else {
            console.log("No position closed or no fees collected");
        }
    }
}