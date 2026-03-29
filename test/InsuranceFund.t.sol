// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockUSDT_IF {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockLeverVault {
    uint256 private _totalAssets;

    function setTotalAssets(uint256 val) external {
        _totalAssets = val;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract InsuranceFundTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant BOOTSTRAP = 10_000e6;

    InsuranceFund public fund;
    MockUSDT_IF public usdt;
    MockLeverVault public vault;

    address admin = address(0xAD);
    address feeRouter = address(0xFE);
    address liquidationEngine = address(0x1E);
    address settlementEngine = address(0x5E);
    address unauthorized = address(0xBAD);

    function setUp() public {
        usdt = new MockUSDT_IF();
        vault = new MockLeverVault();

        fund = new InsuranceFund(admin, address(usdt), address(vault));

        vm.startPrank(admin);
        fund.grantRole(fund.FEE_ROUTER_ROLE(), feeRouter);
        fund.grantRole(fund.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        fund.grantRole(fund.SETTLEMENT_ENGINE_ROLE(), settlementEngine);
        vm.stopPrank();

        // Default TVL: $100K (6-decimal USDT denomination)
        vault.setTotalAssets(100_000e6);

        // Give InsuranceFund USDT balance so safeTransfer works in absorbBadDebt
        deal(address(usdt), address(fund), 1_000_000e6);

        // FIX LEVER-BUG-4: Constructor no longer sets phantom bootstrap.
        // Explicitly deposit real USDT to bootstrap the fund for tests.
        vm.prank(feeRouter);
        fund.deposit(BOOTSTRAP);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsZeroBalance() public {
        // BUG-4: constructor no longer sets phantom bootstrap; starts at 0
        InsuranceFund freshFund = new InsuranceFund(admin, address(usdt), address(vault));
        assertEq(freshFund.getBalance(), 0, "New fund must start with zero balance");
    }

    function test_constructor_setsImmutables() public view {
        assertEq(address(fund.usdt()), address(usdt));
        assertEq(address(fund.leverVault()), address(vault));
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(InsuranceFund.InsuranceFund__ZeroAddress.selector);
        new InsuranceFund(address(0), address(usdt), address(vault));
    }

    function test_constructor_revertsOnZeroUsdt() public {
        vm.expectRevert(InsuranceFund.InsuranceFund__ZeroAddress.selector);
        new InsuranceFund(admin, address(0), address(vault));
    }

    function test_constructor_revertsOnZeroVault() public {
        vm.expectRevert(InsuranceFund.InsuranceFund__ZeroAddress.selector);
        new InsuranceFund(admin, address(usdt), address(0));
    }

    // ──────────────────────────────────────────────
    // Deposit
    // ──────────────────────────────────────────────

    function test_deposit_increasesBalance() public {
        vm.prank(feeRouter);
        fund.deposit(500e6);
        assertEq(fund.getBalance(), BOOTSTRAP + 500e6);
    }

    function test_deposit_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit IInsuranceFund.FundsDeposited(500e6, BOOTSTRAP + 500e6, block.timestamp);

        vm.prank(feeRouter);
        fund.deposit(500e6);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(feeRouter);
        vm.expectRevert(InsuranceFund.InsuranceFund__ZeroAmount.selector);
        fund.deposit(0);
    }

    function test_deposit_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        fund.deposit(100e6);
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(admin);
        fund.pause();

        vm.prank(feeRouter);
        vm.expectRevert();
        fund.deposit(100e6);
    }

    // ──────────────────────────────────────────────
    // getIFR
    // ──────────────────────────────────────────────

    function test_getIFR_correctCalculation() public view {
        // Balance = 10_000e6, TVL = 100_000e6 → IFR = 10%
        uint256 ifr = fund.getIFR();
        assertEq(ifr, 1e17); // 0.10 in WAD
    }

    function test_getIFR_returnsWADWhenTVLZero() public {
        vault.setTotalAssets(0);
        assertEq(fund.getIFR(), WAD);
    }

    function test_getIFR_afterDeposit() public {
        // Deposit 10K more → balance = 20K, TVL = 100K → IFR = 20%
        vm.prank(feeRouter);
        fund.deposit(10_000e6);
        assertEq(fund.getIFR(), 2e17);
    }

    // ──────────────────────────────────────────────
    // isFullyFunded
    // ──────────────────────────────────────────────

    function test_isFullyFunded_falseWhenBelow20Pct() public view {
        // IFR = 10% < 20%
        assertFalse(fund.isFullyFunded());
    }

    function test_isFullyFunded_trueAt20Pct() public {
        // Need balance = 20% of 100K = 20K. Already 10K, deposit 10K more.
        vm.prank(feeRouter);
        fund.deposit(10_000e6);
        assertTrue(fund.isFullyFunded());
    }

    function test_isFullyFunded_trueAbove20Pct() public {
        vm.prank(feeRouter);
        fund.deposit(30_000e6);
        assertTrue(fund.isFullyFunded());
    }

    // ──────────────────────────────────────────────
    // getCurrentTier
    // ──────────────────────────────────────────────

    function test_getCurrentTier_tier3_at10PctIFR() public view {
        // IFR = 10% exactly → ifr (1e17) is NOT > TIER_2_THRESHOLD (1e17) → falls through
        // 1e17 > 5e16 (TIER_3) → true → tier 3
        (uint8 tier, uint256 iPct, uint256 aPct) = fund.getCurrentTier();
        assertEq(tier, 3);
        assertEq(iPct, 4e17);
        assertEq(aPct, 6e17);
    }

    function test_getCurrentTier_tier1_above15Pct() public {
        // Need IFR > 15%. Balance = 16K for TVL = 100K → 16%
        vm.prank(feeRouter);
        fund.deposit(6_000e6);
        (uint8 tier, uint256 iPct, uint256 aPct) = fund.getCurrentTier();
        assertEq(tier, 1);
        assertEq(iPct, WAD);
        assertEq(aPct, 0);
    }

    function test_getCurrentTier_tier2_between10and15Pct() public {
        // Need IFR between 10% and 15% (exclusive). Balance = 12K, TVL = 100K → 12%
        vm.prank(feeRouter);
        fund.deposit(2_000e6);
        (uint8 tier, uint256 iPct, uint256 aPct) = fund.getCurrentTier();
        assertEq(tier, 2);
        assertEq(iPct, 7e17);
        assertEq(aPct, 3e17);
    }

    function test_getCurrentTier_tier4_below5Pct() public {
        // Need IFR < 5%. TVL = 1M → Balance = 10K → IFR = 1%
        vault.setTotalAssets(1_000_000e6);
        (uint8 tier, uint256 iPct, uint256 aPct) = fund.getCurrentTier();
        assertEq(tier, 4);
        assertEq(iPct, 1e17);
        assertEq(aPct, 9e17);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — Basic
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_basicAbsorption() public {
        // IFR = 10% → tier 3 (40% insurance). Bad debt = $1000
        // insuranceTarget = 1000 * 0.4 = 400
        // dailyCap = 10000 * 0.25 = 2500 → ok
        // floor = 100000 * 0.05 = 5000, maxSpend = 10000 - 5000 = 5000 → ok
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));

        assertEq(paid, 400e18);
        assertEq(rem, 600e18);
        assertEq(fund.getBalance(), BOOTSTRAP - 400e6);
        assertEq(fund.totalAbsorbed(), 400e6);
    }

    function test_absorbBadDebt_zeroBadDebt() public {
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 0, address(this));
        assertEq(paid, 0);
        assertEq(rem, 0);
    }

    function test_absorbBadDebt_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IInsuranceFund.BadDebtAbsorbed(bytes32("MKT1"), 1000e18, 400e18, 600e18, block.timestamp);

        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
    }

    function test_absorbBadDebt_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        fund.absorbBadDebt(bytes32("MKT1"), 1000e6, address(this));
    }

    function test_absorbBadDebt_revertsWhenPaused() public {
        vm.prank(admin);
        fund.pause();

        vm.prank(liquidationEngine);
        vm.expectRevert();
        fund.absorbBadDebt(bytes32("MKT1"), 1000e6, address(this));
    }

    function test_absorbBadDebt_settlementEngineCanCall() public {
        vm.prank(settlementEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
        assertEq(paid, 400e18);
        assertEq(rem, 600e18);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — Tier 1 (IFR > 15%)
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_tier1_100PctInsurance() public {
        // Set IFR > 15%: balance = 16K, TVL = 100K
        vm.prank(feeRouter);
        fund.deposit(6_000e6);
        // Balance = 16K, IFR = 16%

        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));

        // 100% insurance → paid = $1000
        assertEq(paid, 1000e18);
        assertEq(rem, 0);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — Daily Cap
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_dailyCapLimitsSpending() public {
        // Keep IFR well above 15% so tier stays at 1 (100% insurance) throughout
        vm.prank(feeRouter);
        fund.deposit(30_000e6);
        // Balance = 40K, TVL = 100K, IFR = 40% → tier 1 (100%)
        // dailyCap = 40K * 25% = 10K

        // First absorb $8K → ok (tier 1, 100%)
        vm.prank(liquidationEngine);
        (uint256 paid1,) = fund.absorbBadDebt(bytes32("MKT1"), 8000e18, address(this));
        assertEq(paid1, 8000e18);

        // Balance = 32K. dailyCap = 32K * 0.25 = 8K. spent = 8K. remaining = 0.
        vm.prank(liquidationEngine);
        (uint256 paid2, uint256 rem2) = fund.absorbBadDebt(bytes32("MKT1"), 3000e18, address(this));
        assertEq(paid2, 0);
        assertEq(rem2, 3000e18);
    }

    function test_absorbBadDebt_dailyCapResetsAfter24h() public {
        // Keep IFR well above 15% throughout
        vm.prank(feeRouter);
        fund.deposit(30_000e6);
        // Balance = 40K, IFR = 40% → tier 1

        // Exhaust daily cap: 40K * 0.25 = 10K
        vm.prank(liquidationEngine);
        (uint256 paid1,) = fund.absorbBadDebt(bytes32("MKT1"), 10_000e18, address(this));
        assertEq(paid1, 10_000e18);
        // Balance = 30K, spent = 10K

        // Cap exhausted (30K * 0.25 = 7.5K < spent 10K)
        vm.prank(liquidationEngine);
        (uint256 paid2,) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
        assertEq(paid2, 0);

        // Advance 24h → window resets
        vm.warp(block.timestamp + 24 hours);

        // Balance = 30K, new dailyCap = 30K * 0.25 = 7.5K
        vm.prank(liquidationEngine);
        (uint256 paid3, uint256 rem3) = fund.absorbBadDebt(bytes32("MKT1"), 5000e18, address(this));
        assertEq(paid3, 5000e18);
        assertEq(rem3, 0);
    }

    function test_absorbBadDebt_multipleBadDebtsSameBlock() public {
        // Keep IFR well above 15% throughout
        vm.prank(feeRouter);
        fund.deposit(30_000e6);
        // Balance = 40K, IFR = 40% → tier 1. dailyCap = 10K

        vm.prank(liquidationEngine);
        (uint256 paid1,) = fund.absorbBadDebt(bytes32("MKT1"), 5000e18, address(this));
        assertEq(paid1, 5000e18);
        // Balance = 35K, spent = 5K

        // Second event same block. dailyCap = 35K * 0.25 = 8.75K. remaining = 8.75K - 5K = 3.75K
        vm.prank(liquidationEngine);
        (uint256 paid2,) = fund.absorbBadDebt(bytes32("MKT2"), 3000e18, address(this));
        assertEq(paid2, 3000e18);
        // Balance = 32K, spent = 8K

        // Third event. dailyCap = 32K * 0.25 = 8K. remaining = 8K - 8K = 0
        vm.prank(liquidationEngine);
        (uint256 paid3, uint256 rem3) = fund.absorbBadDebt(bytes32("MKT3"), 2000e18, address(this));
        assertEq(paid3, 0);
        assertEq(rem3, 2000e18);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — Floor Constraint
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_floorPreventsDepletion() public {
        // TVL = 100K, floor = 5K. Balance = 10K. maxSpend = 10K - 5K = 5K.
        // IFR = 10% → tier 3 (40% insurance). Bad debt = $50K.
        // insuranceTarget = 50K * 0.4 = 20K
        // dailyCap = 10K * 0.25 = 2.5K → constrains first
        vm.prank(liquidationEngine);
        (uint256 paid,) = fund.absorbBadDebt(bytes32("MKT1"), 50_000e18, address(this));
        assertEq(paid, 2_500e18);
    }

    function test_absorbBadDebt_fundAtFloor_paysNothing() public {
        // TVL = 200K, floor = 10K. Balance = 10K. maxSpend = 0.
        vault.setTotalAssets(200_000e6);

        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
        assertEq(paid, 0);
        assertEq(rem, 1000e18);
    }

    function test_absorbBadDebt_floorConstraintBinds() public {
        // TVL = 110K, floor = 5.5K, balance = 10K, maxSpend = 4.5K
        vault.setTotalAssets(110_000e6);
        // IFR = 10K/110K ≈ 9.09% → tier 3 (40%). Bad debt = $20K
        // insuranceTarget = 20K * 0.4 = 8K
        // dailyCap = 10K * 0.25 = 2.5K → binds first
        vm.prank(liquidationEngine);
        (uint256 paid,) = fund.absorbBadDebt(bytes32("MKT1"), 20_000e18, address(this));
        assertEq(paid, 2_500e18);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — Bad debt exceeds fund
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_badDebtExceedsFund() public {
        // TVL = 10M → IFR = 10K/10M = 0.1% → tier 4 (10%). Floor = 500K > balance → maxSpend = 0
        vault.setTotalAssets(10_000_000e6);
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 1_000_000e18, address(this));
        assertEq(paid, 0);
        assertEq(rem, 1_000_000e18);
    }

    // ──────────────────────────────────────────────
    // absorbBadDebt — TVL near zero
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_tvlNearZero_floorNearZero() public {
        vault.setTotalAssets(100e6); // TVL = $100
        // IFR = 10K/100 = 100 WAD → tier 1 (100%)
        // floor = 100 * 0.05 = 5. maxSpend = 10K - 5 = 9995
        // dailyCap = 10K * 0.25 = 2.5K
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 2000e18, address(this));
        assertEq(paid, 2000e18);
        assertEq(rem, 0);
    }

    function test_absorbBadDebt_tvlZero_fundCanSpend() public {
        vault.setTotalAssets(0);
        // IFR = WAD → tier 1, 100% insurance
        // floor = 0, maxSpend = 10K
        // dailyCap = 10K * 0.25 = 2.5K
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 2000e18, address(this));
        assertEq(paid, 2000e18);
        assertEq(rem, 0);
    }

    // ──────────────────────────────────────────────
    // View functions
    // ──────────────────────────────────────────────

    function test_getRemainingDailyCapacity_full() public view {
        // No spending yet. dailyCap = 10K * 0.25 = 2.5K
        assertEq(fund.getRemainingDailyCapacity(), 2_500e6);
    }

    function test_getRemainingDailyCapacity_afterSpending() public {
        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
        // Paid 400 (tier 3, 40%). Balance = 9600. dailyCap = 9600*0.25 = 2400. remaining = 2400 - 400 = 2000
        assertEq(fund.getRemainingDailyCapacity(), 2000e6);
    }

    function test_getRemainingDailyCapacity_resetsAfterWindow() public {
        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));

        vm.warp(block.timestamp + 24 hours);

        // Window expired → full capacity. Balance = 9600, cap = 2400
        assertEq(fund.getRemainingDailyCapacity(), 2400e6);
    }

    function test_getFloor() public view {
        assertEq(fund.getFloor(), 5_000e6);
    }

    function test_getTarget() public view {
        assertEq(fund.getTarget(), 20_000e6);
    }

    function test_totalAbsorbed_accumulates() public {
        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));

        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT2"), 500e18, address(this));

        // Tier 3 (40%): 400 + 200 = 600 USDT
        assertEq(fund.totalAbsorbed(), 600e6);
    }

    // ──────────────────────────────────────────────
    // Pause / Unpause
    // ──────────────────────────────────────────────

    function test_pause_onlyAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        fund.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        fund.pause();

        vm.prank(unauthorized);
        vm.expectRevert();
        fund.unpause();
    }

    function test_unpause_restoresFunctionality() public {
        vm.prank(admin);
        fund.pause();

        vm.prank(admin);
        fund.unpause();

        vm.prank(feeRouter);
        fund.deposit(100e6);
        assertEq(fund.getBalance(), BOOTSTRAP + 100e6);
    }

    // ──────────────────────────────────────────────
    // Edge: daily cap recalculates on balance change
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_dailyCapUsesCurrentBalance() public {
        // IFR well above 15% → tier 1 throughout
        vm.prank(feeRouter);
        fund.deposit(30_000e6);
        // Balance = 40K

        // Absorb $10K (daily cap = 40K * 0.25 = 10K) → drains full daily cap
        vm.prank(liquidationEngine);
        (uint256 paid,) = fund.absorbBadDebt(bytes32("MKT1"), 10_000e18, address(this));
        assertEq(paid, 10_000e18);
        // Balance = 30K, dailySpent = 10K

        // No capacity left (30K * 0.25 = 7.5K < 10K spent)
        vm.prank(liquidationEngine);
        (uint256 paid2,) = fund.absorbBadDebt(bytes32("MKT1"), 1000e18, address(this));
        assertEq(paid2, 0);

        // Next window
        vm.warp(block.timestamp + 24 hours);
        // Balance = 30K, new daily cap = 30K * 0.25 = 7.5K
        vm.prank(liquidationEngine);
        (uint256 paid3,) = fund.absorbBadDebt(bytes32("MKT1"), 10_000e18, address(this));
        assertEq(paid3, 7_500e18);
    }

    // ──────────────────────────────────────────────
    // Edge: interaction between all three constraints
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_allConstraintsInteract() public {
        // balance = 10K, TVL = 150K
        vault.setTotalAssets(150_000e6);
        // IFR = 10K/150K ≈ 6.67% → tier 3 (40% insurance)
        // floor = 150K * 5% = 7.5K, maxSpend = 10K - 7.5K = 2.5K
        // dailyCap = 10K * 25% = 2.5K
        // Bad debt = $10K → insuranceTarget = 4K → min(4K, 2.5K, 2.5K) = 2.5K
        vm.prank(liquidationEngine);
        (uint256 paid, uint256 rem) = fund.absorbBadDebt(bytes32("MKT1"), 10_000e18, address(this));
        assertEq(paid, 2_500e18);
        assertEq(rem, 7_500e18);
    }

    // ──────────────────────────────────────────────
    // DailyCapReset event
    // ──────────────────────────────────────────────

    function test_absorbBadDebt_emitsDailyCapResetOnNewWindow() public {
        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 100e18, address(this));

        vm.warp(block.timestamp + 24 hours);

        // Balance after first absorb: 10K - 40 = 9960 USDT. In WAD: 9960e18. Cap = 9960e18 * 0.25 = 2490e18
        uint256 expectedCapWAD = 2_490e18;

        vm.expectEmit(false, false, false, true);
        emit IInsuranceFund.DailyCapReset(expectedCapWAD, block.timestamp);

        vm.prank(liquidationEngine);
        fund.absorbBadDebt(bytes32("MKT1"), 100e18, address(this));
    }
}
