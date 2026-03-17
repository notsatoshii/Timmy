// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Grant Roles to New ExecutionEngine
/// @notice Grant all necessary roles to the new ExecutionEngine for proper operation
contract GrantRolesToNewExecutionEngine is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Granting Roles to New ExecutionEngine ===");

        address newExecutionEngine = 0x15a05b36D68e88f3264157dDa034f6C1e666065b;
        console2.log("New ExecutionEngine:", newExecutionEngine);

        // Grant roles to different contracts
        address feeRouter = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F;
        address oiLimits = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd;
        address marginEngine = 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce;
        address positionManager = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
        address accountManager = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
        address leverVault = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;

        // Define the role hash that ExecutionEngine needs for each contract
        // EXECUTION_ROLE is typically keccak256("EXECUTION_ROLE")
        bytes32 EXECUTION_ROLE = keccak256("EXECUTION_ROLE");

        console2.log("\nGranting EXECUTION_ROLE to new ExecutionEngine...");

        // Grant role to FeeRouter (for collectTransactionFee)
        try IAccessControl(feeRouter).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted FeeRouter role");
        } catch Error(string memory reason) {
            console2.log("FAILED FeeRouter:", reason);
        } catch {
            console2.log("FAILED FeeRouter: Unknown error");
        }

        // Grant role to OILimits (for increaseOI/decreaseOI)
        try IAccessControl(oiLimits).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted OILimits role");
        } catch Error(string memory reason) {
            console2.log("FAILED OILimits:", reason);
        } catch {
            console2.log("FAILED OILimits: Unknown error");
        }

        // Grant role to MarginEngine (for margin validation)
        try IAccessControl(marginEngine).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted MarginEngine role");
        } catch Error(string memory reason) {
            console2.log("FAILED MarginEngine:", reason);
        } catch {
            console2.log("FAILED MarginEngine: Unknown error");
        }

        // Grant role to PositionManager (for createPosition/closePosition)
        try IAccessControl(positionManager).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted PositionManager role");
        } catch Error(string memory reason) {
            console2.log("FAILED PositionManager:", reason);
        } catch {
            console2.log("FAILED PositionManager: Unknown error");
        }

        // Grant role to AccountManager (for collateral operations)
        try IAccessControl(accountManager).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted AccountManager role");
        } catch Error(string memory reason) {
            console2.log("FAILED AccountManager:", reason);
        } catch {
            console2.log("FAILED AccountManager: Unknown error");
        }

        // Grant role to LeverVault (for funding trader PnL)
        try IAccessControl(leverVault).grantRole(EXECUTION_ROLE, newExecutionEngine) {
            console2.log("SUCCESS: Granted LeverVault role");
        } catch Error(string memory reason) {
            console2.log("FAILED LeverVault:", reason);
        } catch {
            console2.log("FAILED LeverVault: Unknown error");
        }

        vm.stopBroadcast();

        console2.log("\n=== Role Granting Complete ===");
        console2.log("Now test position opening again to verify all roles are working!");
    }
}