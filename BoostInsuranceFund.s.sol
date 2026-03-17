// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IInsuranceFund {
    function deposit(uint256 amount) external;
    function getBalance() external view returns (uint256);
}

interface ILeverVault {
    function totalAssets() external view returns (uint256);
}

interface ILeverageModel {
    function getIFRMultiplier() external view returns (uint256);
    function getPlatformCeiling() external view returns (uint256);
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256);
}

contract BoostInsuranceFund is Script {

    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    address constant OLD_LEVERAGE_MODEL = 0x63B98Ec1e559E3b24199eb2115F0a57222e9818c;

    function run() external {
        address usdt = vm.envAddress("USDT_ADDRESS");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address leverVault = vm.envAddress("LEVER_VAULT");

        IERC20 token = IERC20(usdt);
        IInsuranceFund insurance = IInsuranceFund(insuranceFund);
        ILeverVault vault = ILeverVault(leverVault);
        ILeverageModel leverage = ILeverageModel(OLD_LEVERAGE_MODEL);

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== Boosting Insurance Fund for High Leverage ===");
        console2.log("USDT:", usdt);
        console2.log("Insurance Fund:", insuranceFund);
        console2.log("LeverVault:", leverVault);
        console2.log("Old LeverageModel:", OLD_LEVERAGE_MODEL);
        console2.log("Deployer:", deployer);

        // Check current state
        uint256 currentInsurance = insurance.getBalance();
        uint256 currentTVL = vault.totalAssets();
        uint256 deployerBalance = token.balanceOf(deployer);

        console2.log("\n=== Current State ===");
        console2.log("Insurance balance:", currentInsurance / 1e6, "USDT");
        console2.log("TVL:", currentTVL / 1e6, "USDT");
        console2.log("Deployer USDT balance:", deployerBalance / 1e6, "USDT");

        if (currentTVL > 0) {
            uint256 currentIFR = (currentInsurance * 1e18) / (currentTVL * 1e12); // Convert USDT decimals
            console2.log("Current IFR:", currentIFR / 1e16, "bps");
        }

        try leverage.getIFRMultiplier() returns (uint256 ifrMult) {
            console2.log("Current IFR Multiplier:", ifrMult / 1e16, "bps");
        } catch {
            console2.log("Failed to read IFR multiplier");
        }

        try leverage.getPlatformCeiling() returns (uint256 ceiling) {
            console2.log("Current Platform Ceiling:", ceiling / 1e18, "x");
        } catch {
            console2.log("Failed to read platform ceiling");
        }

        try leverage.getEffectiveMaxLeverage(SPACEX_IPO) returns (uint256 maxLev) {
            console2.log("Current SpaceX leverage:", maxLev / 1e18, "x");
        } catch {
            console2.log("Failed to read SpaceX leverage");
        }

        // Calculate needed insurance fund boost
        // Target IFR = 20% (0.20), current TVL ≈ 60M USDT
        // Needed insurance = TVL × 20% = 60M × 0.20 = 12M USDT
        uint256 targetInsurance = (currentTVL * 20) / 100; // 20% of TVL
        uint256 neededDeposit = targetInsurance > currentInsurance ? targetInsurance - currentInsurance : 0;

        console2.log("\n=== Insurance Fund Boost Calculation ===");
        console2.log("Target insurance (20% of TVL):", targetInsurance / 1e6, "USDT");
        console2.log("Needed additional deposit:", neededDeposit / 1e6, "USDT");

        if (neededDeposit > deployerBalance) {
            console2.log("WARNING: Not enough USDT balance for full boost");
            neededDeposit = deployerBalance;
        }

        if (neededDeposit < 1e6) { // Less than 1 USDT
            console2.log("Insurance fund already sufficient");
            return;
        }

        console2.log("Depositing:", neededDeposit / 1e6, "USDT to insurance fund");

        vm.startBroadcast();

        // Approve and deposit to insurance fund
        token.approve(insuranceFund, neededDeposit);
        insurance.deposit(neededDeposit);

        vm.stopBroadcast();

        console2.log("\n=== After Boost ===");
        uint256 newInsurance = insurance.getBalance();
        console2.log("New insurance balance:", newInsurance / 1e6, "USDT");

        if (currentTVL > 0) {
            uint256 newIFR = (newInsurance * 1e18) / (currentTVL * 1e12);
            console2.log("New IFR:", newIFR / 1e16, "bps");
        }

        try leverage.getIFRMultiplier() returns (uint256 ifrMult) {
            console2.log("NEW IFR Multiplier:", ifrMult / 1e16, "bps");
        } catch {
            console2.log("Failed to read new IFR multiplier");
        }

        try leverage.getPlatformCeiling() returns (uint256 ceiling) {
            console2.log("NEW Platform Ceiling:", ceiling / 1e18, "x");
        } catch {
            console2.log("Failed to read new platform ceiling");
        }

        try leverage.getEffectiveMaxLeverage(SPACEX_IPO) returns (uint256 maxLev) {
            console2.log("NEW SpaceX leverage:", maxLev / 1e18, "x");

            if (maxLev >= 5e18) {
                console2.log("SUCCESS: Leverage >= 5x");
            } else {
                console2.log("WARNING: Still low leverage");
            }
        } catch {
            console2.log("Failed to read new SpaceX leverage");
        }
    }
}