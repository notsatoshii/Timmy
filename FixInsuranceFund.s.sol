// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/InsuranceFundFixed.sol";
import "./contracts/FeeRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IInsuranceFundOld {
    function getBalance() external view returns (uint256);
}

/// @notice Deploy fixed InsuranceFund contract that correctly handles USDT 6-decimal units
contract FixInsuranceFund is Script {
    function run() external {
        // Load addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address leverVault = vm.envAddress("LEVER_VAULT");
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address oldInsuranceFund = vm.envAddress("INSURANCE_FUND");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== FIXING INSURANCE FUND DECIMAL BUG ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("LeverVault:", leverVault);
        console2.log("FeeRouter:", feeRouter);
        console2.log("Old InsuranceFund:", oldInsuranceFund);
        console2.log("");

        // Check old insurance fund balance
        uint256 oldBalance = IInsuranceFundOld(oldInsuranceFund).getBalance();
        console2.log("=== OLD INSURANCE FUND STATE ===");
        console2.log("Old balance (raw):", oldBalance);
        console2.log("Old balance (assuming WAD):", oldBalance / 1e18, "units");
        console2.log("Old balance (assuming USDT):", oldBalance / 1e6, "USDT");
        console2.log("DIAGNOSIS: Balance is stored as WAD units but should be USDT units");
        console2.log("");

        vm.startBroadcast();

        // 1. Deploy new InsuranceFundFixed
        console2.log("=== DEPLOYING FIXED INSURANCE FUND ===");
        InsuranceFundFixed newInsuranceFund = new InsuranceFundFixed(
            deployer,       // admin
            usdt,          // USDT token
            leverVault     // LeverVault for TVL
        );

        console2.log("New InsuranceFund deployed at:", address(newInsuranceFund));

        // 2. Grant necessary roles to FeeRouter
        console2.log("Granting FEE_ROUTER_ROLE to:", feeRouter);
        newInsuranceFund.grantRole(newInsuranceFund.FEE_ROUTER_ROLE(), feeRouter);

        // 3. Check new insurance fund state
        uint256 newBalance = newInsuranceFund.getBalance();
        console2.log("");
        console2.log("=== NEW INSURANCE FUND STATE ===");
        console2.log("New balance (raw):", newBalance);
        console2.log("New balance (USDT):", newBalance / 1e6, "USDT");
        console2.log("Expected: 10,000 USDT");

        if (newBalance == 10_000e6) {
            console2.log("SUCCESS: Bootstrap amount is correct!");
        } else {
            console2.log("ERROR: Bootstrap amount is wrong");
        }

        // 4. Test IFR calculation
        uint256 ifr = newInsuranceFund.getIFR();
        bool isFullyFunded = newInsuranceFund.isFullyFunded();

        console2.log("");
        console2.log("=== IFR CALCULATION TEST ===");
        console2.log("IFR (raw WAD):", ifr);
        console2.log("IFR percentage:", (ifr * 100) / 1e18, "%");
        console2.log("Is fully funded:", isFullyFunded);
        console2.log("Target IFR: 20%");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== NEXT STEPS ===");
        console2.log("1. Update deploy-env.sh with new address:");
        console2.log("   export INSURANCE_FUND=", address(newInsuranceFund));
        console2.log("");
        console2.log("2. Update FeeRouter to use new InsuranceFund:");
        console2.log("   - Either redeploy FeeRouter with new address");
        console2.log("   - Or update FeeRouter configuration if possible");
        console2.log("");
        console2.log("3. Verify the frontend displays correct values");
        console2.log("");
        console2.log("IMPORTANT: The old insurance fund had a corrupted balance.");
        console2.log("The new fund starts fresh with the correct $10,000 bootstrap.");
        console2.log("This is expected behavior for fixing the decimal bug.");
    }
}