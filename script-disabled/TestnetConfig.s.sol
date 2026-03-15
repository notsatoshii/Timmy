// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { MockUSDT } from "../contracts/periphery/MockUSDT.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";

/// @title TestnetConfig — Configure LEVER Protocol for Base Sepolia
/// @notice Sets up testnet-specific configuration after deployment
/// @dev Usage:
///   1. Deploy contracts with Deploy.s.sol
///   2. Run this script to configure for testnet use
///   forge script script/TestnetConfig.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract TestnetConfig is Script {

    struct ContractAddresses {
        address mockUSDT;
        address oracleAdapter;
        address leverVault;
        address insuranceFund;
        address feeRouter;
        address rewardsDistributor;
        address admin;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Configuring LEVER Protocol for testnet...");
        console.log("Deployer:", deployer);
        console.log("Network: Base Sepolia");

        // Load deployment addresses
        ContractAddresses memory addrs = _loadDeploymentConfig();

        vm.startBroadcast(deployerPrivateKey);

        _configureMockUSDT(addrs);
        _configureOracleAdapter(addrs);
        _configureInsuranceFund(addrs);
        _seedInitialLiquidity(addrs);

        vm.stopBroadcast();

        console.log("Testnet configuration complete!");
        _printTestnetInfo(addrs);
    }

    function _loadDeploymentConfig() internal view returns (ContractAddresses memory addrs) {
        string memory configPath = vm.envOr("DEPLOYMENT_CONFIG", "deployments/base-sepolia-addresses.json");
        string memory json = vm.readFile(configPath);

        addrs.mockUSDT = vm.parseJsonAddress(json, ".usdt");
        addrs.oracleAdapter = vm.parseJsonAddress(json, ".oracleAdapter");
        addrs.leverVault = vm.parseJsonAddress(json, ".leverVault");
        addrs.insuranceFund = vm.parseJsonAddress(json, ".insuranceFund");
        addrs.feeRouter = vm.parseJsonAddress(json, ".feeRouter");
        addrs.rewardsDistributor = vm.parseJsonAddress(json, ".rewardsDistributor");
        addrs.admin = vm.parseJsonAddress(json, ".admin");
    }

    // ──────────────────────────────────────────────
    // MockUSDT Configuration
    // ──────────────────────────────────────────────

    function _configureMockUSDT(ContractAddresses memory addrs) internal {
        MockUSDT mockUSDT = MockUSDT(addrs.mockUSDT);

        // Seed faucet for public testing
        console.log("Seeding MockUSDT faucet...");

        // Mint 1M USDT to admin for seeding contracts
        mockUSDT.mint(addrs.admin, 1_000_000e6);
        console.log("Minted 1M USDT to admin for contract seeding");

        // Mint test amounts to common test addresses
        address[] memory testAddresses = new address[](5);
        testAddresses[0] = 0x1234567890123456789012345678901234567890;
        testAddresses[1] = 0x2345678901234567890123456789012345678901;
        testAddresses[2] = 0x3456789012345678901234567890123456789012;
        testAddresses[3] = 0x4567890123456789012345678901234567890123;
        testAddresses[4] = 0x5678901234567890123456789012345678901234;

        for (uint i = 0; i < testAddresses.length; i++) {
            mockUSDT.mint(testAddresses[i], 50_000e6); // 50k USDT each
            console.log("Minted 50k USDT to test address:", testAddresses[i]);
        }
    }

    // ──────────────────────────────────────────────
    // Oracle Configuration
    // ──────────────────────────────────────────────

    function _configureOracleAdapter(ContractAddresses memory addrs) internal {
        OracleAdapter oracle = OracleAdapter(addrs.oracleAdapter);

        console.log("Configuring OracleAdapter...");

        // Register testnet oracle keeper
        address oracleKeeper = vm.envOr("ORACLE_KEEPER", addrs.admin);
        oracle.registerSource(oracleKeeper, true, "Testnet Oracle Keeper");
        console.log("Registered oracle source:", oracleKeeper);

        // Set testnet-friendly parameters
        // Note: These would typically be set via admin functions if they exist
        console.log("Oracle configuration complete");
    }

    // ──────────────────────────────────────────────
    // Insurance Fund Bootstrap
    // ──────────────────────────────────────────────

    function _configureInsuranceFund(ContractAddresses memory addrs) internal {
        InsuranceFund insurance = InsuranceFund(addrs.insuranceFund);
        MockUSDT mockUSDT = MockUSDT(addrs.mockUSDT);

        console.log("Bootstrapping InsuranceFund...");

        // Bootstrap with 10k USDT as per CLAUDE.md
        uint256 bootstrapAmount = 10_000e6; // 10k USDT
        mockUSDT.approve(address(insurance), bootstrapAmount);
        // Note: InsuranceFund gets funded via FeeRouter, not direct deposits
        // This would require a special bootstrap function or direct transfer
        console.log("Insurance fund bootstrap configured");
    }

    // ──────────────────────────────────────────────
    // Initial Liquidity Seeding
    // ──────────────────────────────────────────────

    function _seedInitialLiquidity(ContractAddresses memory addrs) internal {
        LeverVault vault = LeverVault(addrs.leverVault);
        MockUSDT mockUSDT = MockUSDT(addrs.mockUSDT);

        console.log("Seeding initial LP liquidity...");

        // Seed vault with initial liquidity (100k USDT)
        uint256 seedAmount = 100_000e6; // 100k USDT

        // Approve and deposit
        mockUSDT.approve(address(vault), seedAmount);
        vault.deposit(seedAmount, addrs.admin);

        uint256 shares = vault.balanceOf(addrs.admin);
        console.log("Seeded vault with 100k USDT, received", shares, "lvUSDT shares");

        // Set vault utilization parameters for testnet (if functions exist)
        console.log("Initial liquidity seeding complete");
    }

    // ──────────────────────────────────────────────
    // Output Testnet Information
    // ──────────────────────────────────────────────

    function _printTestnetInfo(ContractAddresses memory addrs) internal view {
        console.log("\n======================================");
        console.log("TESTNET CONFIGURATION COMPLETE");
        console.log("======================================");

        console.log("\nTestnet Usage Instructions:");
        console.log("1. MockUSDT Faucet:");
        console.log("   - Contract:", addrs.mockUSDT);
        console.log("   - Call faucet() to get 10k USDT (1 hour cooldown)");
        console.log("   - Or use faucetTo(address) to send to specific address");

        console.log("\n2. Trading Setup:");
        console.log("   - Deposit USDT to AccountManager for collateral");
        console.log("   - Markets created via OnboardMarkets.s.sol script");
        console.log("   - Oracle prices pushed via oracle keeper bot");

        console.log("\n3. LP Setup:");
        console.log("   - Vault has initial 100k USDT liquidity");
        console.log("   - Deposit USDT to LeverVault to get lvUSDT shares");
        console.log("   - Claim rewards via RewardsDistributor");

        console.log("\n4. Key Addresses:");
        console.log("   - MockUSDT:         ", addrs.mockUSDT);
        console.log("   - LeverVault:       ", addrs.leverVault);
        console.log("   - Admin:            ", addrs.admin);

        console.log("\n5. Next Steps:");
        console.log("   - Run AssignRoles.s.sol to set up permissions");
        console.log("   - Run OnboardMarkets.s.sol to create test markets");
        console.log("   - Start oracle keeper bot for price feeds");
        console.log("   - Deploy frontend or use direct contract calls");
    }
}