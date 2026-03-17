// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/LeverageModelFixed.sol";
import "../contracts/ExecutionEngine.sol";

interface IGrantRole {
    function grantRole(bytes32 role, address account) external;
    function EXECUTION_ENGINE_ROLE() external view returns (bytes32);
}

contract RedeployExecutionStack is Script {
    function run() external {
        vm.startBroadcast();

        // All verified-alive addresses
        address positionManager = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
        address oiLimits        = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd;
        address marginEngine    = 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce;
        address oracleAdapter   = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
        address marketRegistry  = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;
        address feeRouter       = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F;
        address borrowFeeEngine = 0x706578de003912C71e534949d8b8DDd5108950e1;
        address fundingRateEngine = 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe;
        address accountManager  = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
        address leverVault      = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
        address insuranceFund   = 0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8;
        address admin           = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

        // ── Step 1: Deploy LeverageModelFixed ──
        console2.log("=== Step 1: Deploy LeverageModelFixed ===");
        LeverageModelFixed newLM = new LeverageModelFixed(
            leverVault, insuranceFund, oiLimits,
            marketRegistry, oracleAdapter, admin
        );
        console2.log("LeverageModelFixed:", address(newLM));

        // Test it
        bytes32 testMarket = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        uint256 maxLev = newLM.getEffectiveMaxLeverage(testMarket);
        console2.log("SpaceX maxLeverage:", maxLev);
        require(maxLev >= 5e18, "Leverage still too low");

        // ── Step 2: Deploy new ExecutionEngine with fixed LeverageModel ──
        console2.log("=== Step 2: Deploy ExecutionEngine ===");
        ExecutionEngine newEE = new ExecutionEngine(
            positionManager, oiLimits, marginEngine,
            oracleAdapter, marketRegistry, address(newLM),
            feeRouter, borrowFeeEngine, fundingRateEngine,
            accountManager, leverVault, admin
        );
        console2.log("ExecutionEngine:", address(newEE));

        // Verify it points to the right LeverageModel
        address eeLM = address(newEE.leverageModel());
        console2.log("EE.leverageModel:", eeLM);
        require(eeLM == address(newLM), "LeverageModel mismatch");

        // ── Step 3: Grant EXECUTION_ENGINE_ROLE on FeeRouter and LeverVault ──
        console2.log("=== Step 3: Grant roles ===");
        bytes32 eeRole = keccak256("EXECUTION_ENGINE_ROLE");

        IGrantRole(feeRouter).grantRole(eeRole, address(newEE));
        console2.log("FeeRouter: role granted");

        IGrantRole(leverVault).grantRole(eeRole, address(newEE));
        console2.log("LeverVault: role granted");

        // ── Done ──
        console2.log("=== DEPLOYMENT COMPLETE ===");
        console2.log("UPDATE deploy-env.sh with:");
        console2.log("  LEVERAGE_MODEL=", address(newLM));
        console2.log("  EXECUTION_ENGINE=", address(newEE));

        vm.stopBroadcast();
    }
}
