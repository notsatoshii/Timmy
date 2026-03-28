// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { InsuranceFund } from "../../contracts/InsuranceFund.sol";
import { IInsuranceFund } from "../../contracts/interfaces/IInsuranceFund.sol";
import { ILeverVault } from "../../contracts/interfaces/ILeverVault.sol";
import { FixedPointMath } from "../../contracts/libraries/FixedPointMath.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple ERC20
contract InsuranceTestToken is ERC20 {
    constructor() ERC20("Test USDT", "USDT") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Mock vault that returns configurable TVL
contract MockVaultForInsurance {
    uint256 private _totalAssets;
    uint256 private _socializedLosses;

    function setTotalAssets(uint256 val) external { _totalAssets = val; }
    function totalAssets() external view returns (uint256) { return _totalAssets; }
    function socializeLoss(uint256 amount) external { _socializedLosses += amount; }
    function getSocializedLosses() external view returns (uint256) { return _socializedLosses; }
}

/// @title InsuranceBadDebtTest
/// @notice Integration tests for the InsuranceFund bad debt absorption:
///         Tier-based insurance/ADL split, daily cap enforcement, floor protection,
///         and the full bad debt waterfall including LP socialization.
contract InsuranceBadDebtTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    address admin = address(0xAD);
    address liquidationEngine = address(0xBB);
    address settlementEngine = address(0xCC);
    address feeRouter = address(0xDD);

    InsuranceTestToken public usdt;
    MockVaultForInsurance public vault;
    InsuranceFund public insurance;

    function setUp() public {
        vm.startPrank(admin);

        usdt = new InsuranceTestToken();
        vault = new MockVaultForInsurance();

        // Set TVL = $10M (USDT 6-decimal denomination)
        vault.setTotalAssets(10_000_000e6);

        insurance = new InsuranceFund(admin, address(usdt), address(vault));

        // Grant roles
        insurance.grantRole(insurance.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        insurance.grantRole(insurance.SETTLEMENT_ENGINE_ROLE(), settlementEngine);
        insurance.grantRole(insurance.FEE_ROUTER_ROLE(), feeRouter);

        vm.stopPrank();
    }

    // ─── Initial State ───

    function test_initialBalance_isBootstrap() public view {
        assertEq(insurance.getBalance(), 10_000e6); // $10k bootstrap (USDT 6 decimals)
    }

    function test_initialIFR_isSmall() public view {
        // IFR = 10_000 / 10_000_000 = 0.001 = 0.1%
        uint256 ifr = insurance.getIFR();
        assertEq(ifr, 1e15); // 0.1%
    }

    // ─── Tier System ───

    function test_tier4_lowIFR() public view {
        // IFR < 5% → Tier 4: 10% insurance / 90% ADL
        (uint8 tier, uint256 insPct, uint256 adlPct) = insurance.getCurrentTier();
        assertEq(tier, 4);
        assertEq(insPct, 1e17);  // 10%
        assertEq(adlPct, 9e17);  // 90%
    }

    function test_tier3_midIFR() public {
        // Bring IFR to >5% but ≤10%: need balance > 500k (threshold is strictly >5%)
        _fundInsurance(491_000e6); // bootstrap + 491k = 501k → IFR = 5.01%
        uint256 ifr = insurance.getIFR();
        assertGt(ifr, 5e16);  // > 5%
        assertLe(ifr, 1e17);  // ≤ 10%

        (uint8 tier, uint256 insPct, uint256 adlPct) = insurance.getCurrentTier();
        assertEq(tier, 3);
        assertEq(insPct, 4e17); // 40%
        assertEq(adlPct, 6e17); // 60%
    }

    function test_tier2_highIFR() public {
        // Bring IFR to >10% but ≤15%: need balance > 1M (threshold is strictly >10%)
        _fundInsurance(991_000e6); // bootstrap + 991k = 1001k → IFR = 10.01%
        uint256 ifr = insurance.getIFR();
        assertGt(ifr, 1e17);    // > 10%
        assertLe(ifr, 15e16);   // ≤ 15%

        (uint8 tier, uint256 insPct, uint256 adlPct) = insurance.getCurrentTier();
        assertEq(tier, 2);
        assertEq(insPct, 7e17); // 70%
        assertEq(adlPct, 3e17); // 30%
    }

    function test_tier1_fullIFR() public {
        // Bring IFR > 15%: need balance > 15% of $10M = $1.5M
        _fundInsurance(1_500_000e6);
        uint256 ifr = insurance.getIFR();
        assertGt(ifr, 15e16);

        (uint8 tier, uint256 insPct,) = insurance.getCurrentTier();
        assertEq(tier, 1);
        assertEq(insPct, WAD); // 100% insurance
    }

    // ─── Bad Debt Absorption ───

    function test_absorbBadDebt_tier4_only10pct() public {
        // At tier 4 (IFR < 5%), only 10% of bad debt comes from insurance
        uint256 badDebt = 1_000e6;
        uint256 balanceBefore = insurance.getBalance();

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), balanceBefore);

        vm.prank(liquidationEngine);
        (uint256 paid, uint256 remainder) = insurance.absorbBadDebt(
            keccak256("MARKET"), badDebt, address(this)
        );

        // Insurance pays ~10% (subject to daily cap)
        assertLe(paid, badDebt * 10 / 100 + 1); // ~$100 + rounding
        assertEq(paid + remainder, badDebt);
        assertEq(insurance.getBalance(), balanceBefore - paid);
    }

    function test_absorbBadDebt_tier1_fullCoverage() public {
        _fundInsurance(2_000_000e6); // High IFR → Tier 1

        uint256 badDebt = 10_000e6;
        uint256 balanceBefore = insurance.getBalance();

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), balanceBefore);

        vm.prank(liquidationEngine);
        (uint256 paid, uint256 remainder) = insurance.absorbBadDebt(
            keccak256("MARKET"), badDebt, address(this)
        );

        // Tier 1: 100% from insurance (if within daily cap and above floor)
        assertEq(paid, badDebt);
        assertEq(remainder, 0);
        assertEq(insurance.getBalance(), balanceBefore - paid);
    }

    // ─── Daily Cap (25% of balance) ───

    function test_dailyCap_limits_singleEvent() public {
        _fundInsurance(2_000_000e6); // $2M+ balance, Tier 1
        uint256 balance = insurance.getBalance();
        uint256 dailyCap = balance * 25 / 100; // 25%

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), balance);

        // Try to absorb more than 25% in one event
        uint256 badDebt = balance; // Try full balance

        vm.prank(liquidationEngine);
        (uint256 paid,) = insurance.absorbBadDebt(keccak256("MARKET"), badDebt, address(this));

        // Should be capped at 25% of balance (may also be limited by floor)
        assertLe(paid, dailyCap + 1); // +1 for rounding
    }

    function test_dailyCap_accumulates_acrossMultipleEvents() public {
        _fundInsurance(2_000_000e6);
        uint256 balance = insurance.getBalance();
        uint256 dailyCap = balance * 25 / 100;

        // Fund the contract with actual USDT for the transfers
        _dealUSDT(address(insurance), balance);

        // First absorption: use up most of daily cap
        vm.prank(liquidationEngine);
        (uint256 paid1,) = insurance.absorbBadDebt(
            keccak256("M1"), dailyCap - 1e6, address(this)
        );

        // Second absorption: should be constrained by remaining capacity
        vm.prank(liquidationEngine);
        (uint256 paid2,) = insurance.absorbBadDebt(
            keccak256("M2"), 100_000e6, address(this)
        );

        assertLe(paid1 + paid2, dailyCap + 1);
    }

    function test_dailyCap_resets_after24h() public {
        _fundInsurance(2_000_000e6);
        uint256 balance = insurance.getBalance();

        // Fund the contract with actual USDT for the transfers
        _dealUSDT(address(insurance), balance);

        // Use up daily cap
        vm.prank(liquidationEngine);
        insurance.absorbBadDebt(keccak256("M1"), balance, address(this));

        uint256 remaining = insurance.getRemainingDailyCapacity();
        // Should be near zero (or zero)
        assertLe(remaining, 1e6);

        // Warp past 24h
        vm.warp(block.timestamp + 24 hours + 1);

        uint256 newRemaining = insurance.getRemainingDailyCapacity();
        // Should have capacity again
        assertGt(newRemaining, 0);
    }

    // ─── Floor Protection (5% of TVL) ───

    function test_floor_preventsDepletionBelowThreshold() public {
        // TVL = $10M → floor = 5% = $500k
        // Set balance to $600k (just above floor)
        _fundInsurance(590_000e6); // bootstrap + 590k = $600k
        uint256 balance = insurance.getBalance();
        uint256 floor = insurance.getFloor();

        assertEq(floor, 500_000e6); // 5% of $10M

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), balance);

        // Try to absorb $200k → would bring balance to $400k (below floor)
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 remainder) = insurance.absorbBadDebt(
            keccak256("MARKET"), 200_000e6, address(this)
        );

        // Should only pay down to floor: $600k - $500k = $100k max
        assertLe(paid, balance - floor + 1);
        assertGt(remainder, 0);
        assertGe(insurance.getBalance(), floor - 1); // Stays above floor (rounding)
    }

    // ─── Settlement Engine Access ───

    function test_settlementEngine_canAbsorbBadDebt() public {
        _fundInsurance(2_000_000e6);

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), insurance.getBalance());

        vm.prank(settlementEngine);
        (uint256 paid,) = insurance.absorbBadDebt(
            keccak256("MARKET"), 10_000e6, address(this)
        );

        assertGt(paid, 0);
    }

    // ─── Deposit (FeeRouter) ───

    function test_feeRouter_canDeposit() public {
        uint256 balanceBefore = insurance.getBalance();

        vm.prank(feeRouter);
        insurance.deposit(50_000e6);

        assertEq(insurance.getBalance(), balanceBefore + 50_000e6);
    }

    // ─── Access Control ───

    function test_unauthorized_cannotAbsorb() public {
        vm.expectRevert();
        vm.prank(address(0x999));
        insurance.absorbBadDebt(keccak256("MARKET"), 1e6, address(this));
    }

    function test_unauthorized_cannotDeposit() public {
        vm.expectRevert();
        vm.prank(address(0x999));
        insurance.deposit(1e6);
    }

    // ─── Zero Bad Debt ───

    function test_zeroBadDebt_noop() public {
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 remainder) = insurance.absorbBadDebt(
            keccak256("MARKET"), 0, address(this)
        );

        assertEq(paid, 0);
        assertEq(remainder, 0);
    }

    // ─── IFR Target and Funding Status ───

    function test_isFullyFunded_whenIFRAboveTarget() public {
        // Target = 20% → need $2M for $10M TVL
        _fundInsurance(2_000_000e6);
        assertTrue(insurance.isFullyFunded());
    }

    function test_notFullyFunded_whenIFRBelowTarget() public view {
        assertFalse(insurance.isFullyFunded());
    }

    function test_totalAbsorbed_tracks_lifetime() public {
        _fundInsurance(2_000_000e6);

        // Fund the contract with actual USDT for the transfers
        _dealUSDT(address(insurance), insurance.getBalance());

        vm.prank(liquidationEngine);
        insurance.absorbBadDebt(keccak256("M1"), 5_000e6, address(this));

        vm.prank(liquidationEngine);
        insurance.absorbBadDebt(keccak256("M2"), 3_000e6, address(this));

        assertEq(insurance.totalAbsorbed(), 5_000e6 + 3_000e6);
    }

    // ─── Combined Constraints (daily cap + floor + tier) ───

    function test_multipleConstraints_strictestWins() public {
        // Set up: balance = $600k, TVL = $10M
        // Floor = $500k → max spend from floor = $100k
        // Daily cap = 25% × $600k = $150k
        // Tier 3 (IFR ~6%): 40% insurance
        // Bad debt = $300k → tier says $120k, but floor says $100k
        _fundInsurance(590_000e6); // $600k total
        uint256 balance = insurance.getBalance();

        // Fund the contract with actual USDT for the transfer
        _dealUSDT(address(insurance), balance);

        uint256 badDebt = 300_000e6;
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 remainder) = insurance.absorbBadDebt(
            keccak256("MARKET"), badDebt, address(this)
        );

        // Floor constraint ($100k) should be strictest
        uint256 floor = insurance.getFloor();
        uint256 maxFromFloor = balance > floor ? balance - floor : 0;
        assertLe(paid, maxFromFloor + 1);
        assertEq(paid + remainder, badDebt);
    }

    // ─── Helpers ───

    function _fundInsurance(uint256 amount) internal {
        vm.prank(feeRouter);
        insurance.deposit(amount);
    }

    /// @dev Give the InsuranceFund contract actual USDT tokens so safeTransfer works
    function _dealUSDT(address to, uint256 amount) internal {
        deal(address(usdt), to, amount);
    }
}
