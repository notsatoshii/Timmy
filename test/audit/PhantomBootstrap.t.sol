// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { InsuranceFund } from "../../contracts/InsuranceFund.sol";
import { IInsuranceFund } from "../../contracts/interfaces/IInsuranceFund.sol";
import { ILeverVault } from "../../contracts/interfaces/ILeverVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract TestToken is ERC20 {
    constructor() ERC20("Test USDT", "USDT") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockVault_PB {
    uint256 private _totalAssets;
    function setTotalAssets(uint256 val) external { _totalAssets = val; }
    function totalAssets() external view returns (uint256) { return _totalAssets; }
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

/// @title PhantomBootstrapTest
/// @notice Regression tests for LEVER-BUG-4: InsuranceFund phantom bootstrap.
///
/// Root cause: Constructor set `_balance = INSURANCE_BOOTSTRAP` (10,000e6) without
/// transferring actual USDT. This inflated accounting balance caused absorbBadDebt
/// to attempt `safeTransfer` of USDT the contract did not hold, reverting every time.
///
/// Fix: `_balance = 0`. Real USDT enters only via FeeRouter calling deposit().
contract PhantomBootstrapTest is Test {

    TestToken usdt;
    MockVault_PB vault;
    InsuranceFund fund;

    address admin     = address(0xAD);
    address feeRouter = address(0xFE);
    address engine    = address(0xE1);

    function setUp() public {
        usdt  = new TestToken();
        vault = new MockVault_PB();

        fund = new InsuranceFund(admin, address(usdt), address(vault));

        vm.startPrank(admin);
        fund.grantRole(fund.FEE_ROUTER_ROLE(), feeRouter);
        fund.grantRole(fund.EXECUTION_ENGINE_ROLE(), engine);
        vm.stopPrank();

        vault.setTotalAssets(100_000e6); // $100K TVL
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Constructor starts with zero balance
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Regression: old constructor set _balance = 10_000e6 without USDT transfer.
    ///         New constructor sets _balance = 0. Fund is bootstrapped via deposit().
    function test_BUG4_constructorStartsAtZero() public view {
        assertEq(fund.getBalance(), 0, "Fund must start with zero balance (no phantom bootstrap)");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: absorbBadDebt does not revert when fund has real USDT
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice After a real deposit, absorbBadDebt should succeed and transfer actual USDT.
    ///         Old code: phantom bootstrap meant safeTransfer would revert (no USDT to send).
    ///         New code: only real deposits count, so balance and USDT tokens are always in sync.
    function test_BUG4_absorbWorksAfterRealDeposit() public {
        // Deposit real USDT: give tokens to fund + update accounting
        // Use $20K deposit with $100K TVL so floor ($5K) leaves $15K spendable
        usdt.mint(address(fund), 20_000e6);
        vm.prank(feeRouter);
        fund.deposit(20_000e6);

        assertEq(fund.getBalance(), 20_000e6, "Accounting matches real USDT");
        assertEq(usdt.balanceOf(address(fund)), 20_000e6, "Fund holds actual USDT");

        // absorbBadDebt: totalBadDebt is in WAD, returns insurancePaid in WAD
        // BUG-5 fix: SCALE converts between WAD and USDT internally
        address recipient = address(0xBEEF);
        uint256 badDebtWAD = 500e18; // $500 in WAD scale
        uint256 SCALE = 1e12;

        vm.prank(engine);
        (uint256 paidWAD,) = fund.absorbBadDebt(bytes32("MKT1"), badDebtWAD, recipient);

        assertGt(paidWAD, 0, "Insurance should pay some amount (WAD)");

        // Actual USDT transferred = paidWAD / SCALE
        uint256 paidUSDT = paidWAD / SCALE;
        assertEq(usdt.balanceOf(recipient), paidUSDT, "Recipient must receive USDT");
        assertEq(fund.getBalance(), 20_000e6 - paidUSDT, "Accounting decreases by USDT amount paid");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: absorbBadDebt with zero balance returns remainder = totalBadDebt
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice With zero balance (no deposits yet), insurance pays nothing.
    ///         Full bad debt falls to socialization. No revert.
    function test_BUG4_absorbWithZeroBalanceReturnsFullRemainder() public {
        uint256 badDebtWAD = 1_000e18; // $1000 in WAD

        vm.prank(engine);
        (uint256 paid, uint256 remainder) = fund.absorbBadDebt(bytes32("MKT1"), badDebtWAD, address(0xBEEF));

        assertEq(paid, 0, "Zero balance means zero insurance payment");
        assertEq(remainder, badDebtWAD, "Full bad debt becomes remainder for socialization");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: deposit() creates real balance that matches USDT tokens
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice After deposit, accounting balance must equal actual USDT held.
    ///         Old code: _balance = bootstrap + deposit, but USDT = deposit only (10K gap).
    ///         New code: _balance = 0 + deposit = deposit = actual USDT.
    function test_BUG4_depositAccountingMatchesTokens() public {
        usdt.mint(address(fund), 7_500e6);
        vm.prank(feeRouter);
        fund.deposit(7_500e6);

        assertEq(fund.getBalance(), usdt.balanceOf(address(fund)),
            "Accounting balance must match actual USDT in contract");
    }
}
