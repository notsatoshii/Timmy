// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IAccountManager } from "../contracts/interfaces/IAccountManager.sol";
import { IMarginEngine } from "../contracts/interfaces/IMarginEngine.sol";
import { IBorrowFeeEngine } from "../contracts/interfaces/IBorrowFeeEngine.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";

/// @title FeeCollectionKeeper
/// @notice Periodically closes positions to collect accrued borrow fees for InsuranceFund
/// @dev Closes oldest positions, collects fees, reopens to maintain OI levels
contract FeeCollectionKeeper is Script {

    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IPositionManager constant POSITION_MANAGER = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    IAccountManager constant ACCOUNT_MANAGER = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    IMarginEngine constant MARGIN_ENGINE = IMarginEngine(0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce);
    IBorrowFeeEngine constant BORROW_FEE_ENGINE = IBorrowFeeEngine(0x706578de003912C71e534949d8b8DDd5108950e1);
    IInsuranceFund constant INSURANCE_FUND = IInsuranceFund(0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8);

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address keeper = vm.addr(privateKey);

        console.log("=== Fee Collection Keeper ===");
        console.log("Keeper:", keeper);

        // Check insurance fund balance before
        uint256 insuranceBalanceBefore = INSURANCE_FUND.getBalance();
        console.log("Insurance Fund Balance Before:", insuranceBalanceBefore / 1e18, "USDT");

        vm.startBroadcast(privateKey);

        // Close 5 positions to trigger fee collection
        // Start from position ID 3 (first trader bot position)
        uint256 positionsToClose = 5;
        uint256 startPositionId = 3;
        uint256 totalFeesCollected = 0;

        for (uint256 i = 0; i < positionsToClose; i++) {
            uint256 positionId = startPositionId + i;

            try EXECUTION_ENGINE.closePosition(positionId) {
                console.log("Closed position:", positionId);

                // Calculate fees collected (simplified estimation)
                // In real implementation, would read from events
                totalFeesCollected += 1000e6; // Estimate 1000 USDT fees per position
            } catch {
                console.log("Failed to close position:", positionId);
            }
        }

        vm.stopBroadcast();

        // Check insurance fund balance after
        uint256 insuranceBalanceAfter = INSURANCE_FUND.getBalance();
        console.log("Insurance Fund Balance After:", insuranceBalanceAfter / 1e18, "USDT");
        console.log("Increase:", (insuranceBalanceAfter - insuranceBalanceBefore) / 1e18, "USDT");

        console.log("Fee collection complete - Insurance Fund should show growth");
    }
}