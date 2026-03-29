// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/InsuranceFund.sol";
import "../contracts/LiquidationEngine.sol";
import "../contracts/SettlementEngine.sol";
import "../contracts/FundingRateEngine.sol";
import "../contracts/MarginEngine.sol";
import "../contracts/OILimits.sol";
import "../contracts/LeverageModelFixed.sol";

interface IGrantRole {
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IOILimitsAdmin {
    function adminResetMarketOI(bytes32 marketId) external;
    function getGlobalOI() external view returns (uint256);
}

/// @title RedeployAuditFixes
/// @notice Deploys all fixed contracts from the full protocol audit
/// @dev Fixes: LEVER-001 through LEVER-014, LEVER-022
contract RedeployAuditFixes is Script {
    // ── Existing (unchanged) addresses ──
    address constant USDT              = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant MARKET_REGISTRY   = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;
    address constant ORACLE_ADAPTER    = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
    address constant ACCOUNT_MANAGER   = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant POSITION_MANAGER  = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
    address constant LEVER_VAULT       = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
    address constant FEE_ROUTER        = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F;
    address constant REWARDS_DIST      = 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0;
    address constant BORROW_FEE_ENGINE = 0x706578de003912C71e534949d8b8DDd5108950e1;
    address constant ADMIN             = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

    // Role constants
    bytes32 constant EE_ROLE       = keccak256("EXECUTION_ENGINE_ROLE");
    bytes32 constant ENGINE_ROLE   = keccak256("ENGINE");
    bytes32 constant KEEPER_ROLE   = keccak256("KEEPER_ROLE");
    bytes32 constant KEEPER        = keccak256("KEEPER");
    bytes32 constant LE_ROLE       = keccak256("LIQUIDATION_ENGINE_ROLE");
    bytes32 constant SE_ROLE       = keccak256("SETTLEMENT_ENGINE_ROLE");
    bytes32 constant FEE_ROUTER_ROLE = keccak256("FEE_ROUTER_ROLE");

    // Test market ID
    bytes32 constant TEST_MARKET = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

    function run() external {
        uint256 deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (deployerKey == 0) {
            // Read from .env.deployer
            string memory keyStr = vm.readFile(".env.deployer");
            deployerKey = vm.parseUint(keyStr);
        }

        vm.startBroadcast(deployerKey);

        console2.log("========================================");
        console2.log("  LEVER AUDIT FIX DEPLOYMENT");
        console2.log("========================================");

        // ── Step 1: Deploy OILimits (new: adminResetMarketOI) ──
        console2.log("\n=== Step 1: Deploy OILimits ===");
        OILimits newOILimits = new OILimits(
            MARKET_REGISTRY,
            LEVER_VAULT,
            POSITION_MANAGER,
            ADMIN
        );
        console2.log("OILimits:", address(newOILimits));

        // ── Step 2: Deploy InsuranceFund (new: USDT transfer, 6-decimal bootstrap) ──
        console2.log("\n=== Step 2: Deploy InsuranceFund ===");
        InsuranceFund newInsuranceFund = new InsuranceFund(
            ADMIN,
            USDT,
            LEVER_VAULT
        );
        console2.log("InsuranceFund:", address(newInsuranceFund));

        // ── Step 3: Deploy FundingRateEngine (new: AccountManager + RewardsDistributor deps) ──
        console2.log("\n=== Step 3: Deploy FundingRateEngine ===");
        FundingRateEngine newFundingRateEngine = new FundingRateEngine(
            ADMIN,
            MARKET_REGISTRY,
            address(newOILimits),
            POSITION_MANAGER,
            ACCOUNT_MANAGER,
            REWARDS_DIST
        );
        console2.log("FundingRateEngine:", address(newFundingRateEngine));

        // ── Step 4: Deploy MarginEngine (new: depthThreshold guard) ──
        console2.log("\n=== Step 4: Deploy MarginEngine ===");
        MarginEngine newMarginEngine = new MarginEngine(
            ADMIN,                          // admin_ (first param)
            POSITION_MANAGER,
            ORACLE_ADAPTER,
            MARKET_REGISTRY,
            BORROW_FEE_ENGINE,
            address(newFundingRateEngine)
        );
        console2.log("MarginEngine:", address(newMarginEngine));

        // ── Step 5: Deploy LeverageModelFixed (fix: IFR balance scaling) ──
        console2.log("\n=== Step 5: Deploy LeverageModelFixed ===");
        LeverageModelFixed newLM = new LeverageModelFixed(
            LEVER_VAULT,
            address(newInsuranceFund),
            address(newOILimits),
            MARKET_REGISTRY,
            ORACLE_ADAPTER,
            ADMIN
        );
        console2.log("LeverageModelFixed:", address(newLM));

        // ── Step 6: Deploy ExecutionEngine (fixes: PnL, closing fee, bad debt routing) ──
        console2.log("\n=== Step 6: Deploy ExecutionEngine ===");
        ExecutionEngine newEE = new ExecutionEngine(
            POSITION_MANAGER,
            address(newOILimits),
            address(newMarginEngine),
            ORACLE_ADAPTER,
            MARKET_REGISTRY,
            address(newLM),
            FEE_ROUTER,
            BORROW_FEE_ENGINE,
            address(newFundingRateEngine),
            ACCOUNT_MANAGER,
            LEVER_VAULT,
            address(newInsuranceFund),
            ADMIN
        );
        console2.log("ExecutionEngine:", address(newEE));

        // ── Step 7: Deploy LiquidationEngine (fixes: FeeRouter USDT, loss routing) ──
        console2.log("\n=== Step 7: Deploy LiquidationEngine ===");
        LiquidationEngine newLE = new LiquidationEngine(
            ADMIN,                          // admin_
            address(newMarginEngine),        // marginEngine_
            POSITION_MANAGER,               // positionManager_
            address(newEE),                  // executionEngine_
            address(newOILimits),            // oiLimits_
            ACCOUNT_MANAGER,                // accountManager_
            address(newInsuranceFund),       // insuranceFund_
            FEE_ROUTER,                     // feeRouter_
            LEVER_VAULT,                    // leverVault_
            MARKET_REGISTRY                 // marketRegistry_
        );
        console2.log("LiquidationEngine:", address(newLE));

        // ── Step 8: Deploy SettlementEngine (fixes: FeeRouter USDT, event fix) ──
        console2.log("\n=== Step 8: Deploy SettlementEngine ===");
        SettlementEngine newSE = new SettlementEngine(
            ADMIN,                          // admin_
            MARKET_REGISTRY,                // marketRegistry_
            POSITION_MANAGER,               // positionManager_
            ORACLE_ADAPTER,                 // oracleAdapter_
            BORROW_FEE_ENGINE,              // borrowFeeEngine_
            address(newFundingRateEngine),   // fundingRateEngine_
            address(newInsuranceFund),       // insuranceFund_
            FEE_ROUTER,                     // feeRouter_
            address(newOILimits),            // oiLimits_
            ACCOUNT_MANAGER,                // accountManager_
            LEVER_VAULT                     // leverVault_
        );
        console2.log("SettlementEngine:", address(newSE));

        // ── Step 9: Grant Roles ──
        console2.log("\n=== Step 9: Grant Roles ===");

        // FeeRouter: grant EXECUTION_ENGINE_ROLE to new EE
        IGrantRole(FEE_ROUTER).grantRole(EE_ROLE, address(newEE));
        console2.log("FeeRouter: EE_ROLE -> newEE");

        // LeverVault: grant EE_ROLE to ExecutionEngine + SettlementEngine, LE_ROLE to LiquidationEngine
        // FIX LEVER-BUG-6: SettlementEngine needs EE_ROLE for fundTraderPnL on winner settlements
        IGrantRole(LEVER_VAULT).grantRole(EE_ROLE, address(newEE));
        IGrantRole(LEVER_VAULT).grantRole(EE_ROLE, address(newSE));
        IGrantRole(LEVER_VAULT).grantRole(LE_ROLE, address(newLE));
        console2.log("LeverVault: EE_ROLE (EE+SE) + LE_ROLE granted");

        // OILimits: grant EE_ROLE, LE_ROLE, SE_ROLE
        IGrantRole(address(newOILimits)).grantRole(EE_ROLE, address(newEE));
        IGrantRole(address(newOILimits)).grantRole(EE_ROLE, address(newLE));
        IGrantRole(address(newOILimits)).grantRole(EE_ROLE, address(newSE));
        console2.log("OILimits: roles granted to EE, LE, SE");

        // PositionManager: grant ENGINE role
        IGrantRole(POSITION_MANAGER).grantRole(ENGINE_ROLE, address(newEE));
        IGrantRole(POSITION_MANAGER).grantRole(ENGINE_ROLE, address(newLE));
        IGrantRole(POSITION_MANAGER).grantRole(ENGINE_ROLE, address(newSE));
        console2.log("PositionManager: ENGINE roles granted");

        // AccountManager: grant ENGINE role
        IGrantRole(ACCOUNT_MANAGER).grantRole(ENGINE_ROLE, address(newEE));
        IGrantRole(ACCOUNT_MANAGER).grantRole(ENGINE_ROLE, address(newLE));
        IGrantRole(ACCOUNT_MANAGER).grantRole(ENGINE_ROLE, address(newSE));
        IGrantRole(ACCOUNT_MANAGER).grantRole(ENGINE_ROLE, address(newFundingRateEngine));
        console2.log("AccountManager: ENGINE roles granted");

        // InsuranceFund: grant roles to EE, LE, SE, FeeRouter
        IGrantRole(address(newInsuranceFund)).grantRole(EE_ROLE, address(newEE));
        IGrantRole(address(newInsuranceFund)).grantRole(LE_ROLE, address(newLE));
        IGrantRole(address(newInsuranceFund)).grantRole(SE_ROLE, address(newSE));
        IGrantRole(address(newInsuranceFund)).grantRole(FEE_ROUTER_ROLE, FEE_ROUTER);
        console2.log("InsuranceFund: roles granted");

        // MarginEngine: admin already has ADMIN_ROLE from constructor
        // KEEPER role can be granted by admin via ADMIN_ROLE later
        console2.log("MarginEngine: admin has ADMIN_ROLE from constructor");

        // BorrowFeeEngine: grant roles to new engines
        IGrantRole(BORROW_FEE_ENGINE).grantRole(EE_ROLE, address(newEE));
        console2.log("BorrowFeeEngine: EE_ROLE granted");

        // ── Step 10: Sanity checks ──
        console2.log("\n=== Step 10: Sanity Checks ===");

        // Verify LeverageModel returns sane leverage
        uint256 maxLev = newLM.getEffectiveMaxLeverage(TEST_MARKET);
        console2.log("SpaceX maxLeverage:", maxLev);
        require(maxLev >= 3e18 && maxLev <= 50e18, "Leverage out of range");

        // Verify InsuranceFund bootstrap
        uint256 ifBalance = newInsuranceFund.getBalance();
        console2.log("InsuranceFund balance:", ifBalance);
        require(ifBalance == 10_000e6, "InsuranceFund bootstrap mismatch");

        console2.log("\n========================================");
        console2.log("  DEPLOYMENT COMPLETE");
        console2.log("========================================");
        console2.log("OILimits:          ", address(newOILimits));
        console2.log("MarginEngine:      ", address(newMarginEngine));
        console2.log("InsuranceFund:     ", address(newInsuranceFund));
        console2.log("FundingRateEngine: ", address(newFundingRateEngine));
        console2.log("LeverageModel:     ", address(newLM));
        console2.log("ExecutionEngine:   ", address(newEE));
        console2.log("LiquidationEngine: ", address(newLE));
        console2.log("SettlementEngine:  ", address(newSE));

        vm.stopBroadcast();
    }
}
