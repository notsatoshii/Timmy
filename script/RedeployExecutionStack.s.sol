// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/LeverageModelFixed.sol";
import "../contracts/ExecutionEngine.sol";

interface IGrantRole {
    function grantRole(bytes32 role, address account) external;
}

contract RedeployExecutionStack is Script {
    function run() external {
        vm.startBroadcast();

        // All verified-alive addresses
        address positionManager  = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
        address oiLimits         = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd;
        address marginEngine     = 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce;
        address oracleAdapter    = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
        address marketRegistry   = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;
        address feeRouter        = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F;
        address borrowFeeEngine  = 0x706578de003912C71e534949d8b8DDd5108950e1;
        address fundingRateEngine = 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe;
        address accountManager   = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
        address leverVault       = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
        address insuranceFund    = 0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8;
        address admin            = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

        // ── Step 1: Deploy LeverageModelFixed ──
        console2.log("=== Step 1: Deploy LeverageModelFixed ===");
        LeverageModelFixed newLM = new LeverageModelFixed(
            leverVault, insuranceFund, oiLimits,
            marketRegistry, oracleAdapter, admin
        );
        console2.log("LeverageModelFixed:", address(newLM));

        // Test it returns sane leverage
        bytes32 testMarket = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        uint256 maxLev = newLM.getEffectiveMaxLeverage(testMarket);
        console2.log("SpaceX maxLeverage WAD:", maxLev);
        require(maxLev >= 5e18, "Leverage still too low");

        // ── Step 2: Deploy new ExecutionEngine ──
        console2.log("=== Step 2: Deploy ExecutionEngine ===");
        ExecutionEngine newEE = new ExecutionEngine(
            positionManager, oiLimits, marginEngine,
            oracleAdapter, marketRegistry, address(newLM),
            feeRouter, borrowFeeEngine, fundingRateEngine,
            accountManager, leverVault, insuranceFund, admin
        );
        console2.log("ExecutionEngine:", address(newEE));

        // Verify it points to the right LeverageModel
        address eeLM = address(newEE.leverageModel());
        require(eeLM == address(newLM), "LeverageModel mismatch");

        // ── Step 3: Grant roles on ALL contracts that check EXECUTION_ENGINE_ROLE ──
        console2.log("=== Step 3: Grant roles ===");
        bytes32 eeRole = keccak256("EXECUTION_ENGINE_ROLE");

        // FeeRouter
        IGrantRole(feeRouter).grantRole(eeRole, address(newEE));
        console2.log("FeeRouter: EXECUTION_ENGINE_ROLE granted");

        // LeverVault
        IGrantRole(leverVault).grantRole(eeRole, address(newEE));
        console2.log("LeverVault: EXECUTION_ENGINE_ROLE granted");

        // OILimits
        IGrantRole(oiLimits).grantRole(eeRole, address(newEE));
        console2.log("OILimits: EXECUTION_ENGINE_ROLE granted");

        // PositionManager - uses ENGINE role
        bytes32 engineRole = keccak256("ENGINE");
        IGrantRole(positionManager).grantRole(engineRole, address(newEE));
        console2.log("PositionManager: ENGINE role granted");

        // ── Done ──
        console2.log("=========================================");
        console2.log("DEPLOYMENT COMPLETE - UPDATE THESE FILES:");
        console2.log("=========================================");
        console2.log("deploy-env.sh LEVERAGE_MODEL=", address(newLM));
        console2.log("deploy-env.sh EXECUTION_ENGINE=", address(newEE));
        console2.log("frontend contracts.ts executionEngine=", address(newEE));

        vm.stopBroadcast();
    }
}
