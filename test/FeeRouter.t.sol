// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { IFeeRouter } from "../contracts/interfaces/IFeeRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockUSDT {
    string public name = "Mock USDT";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
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

contract MockInsuranceFund {
    bool private _fullyFunded;
    uint256 private _ifr;
    uint256 public totalDeposited;

    function setFullyFunded(bool val) external {
        _fullyFunded = val;
    }

    function setIFR(uint256 val) external {
        _ifr = val;
    }

    function isFullyFunded() external view returns (bool) {
        return _fullyFunded;
    }

    function getIFR() external view returns (uint256) {
        return _ifr;
    }

    function deposit(uint256 amount) external {
        totalDeposited += amount;
    }
}

contract MockRewardsDistributor {
    uint256 public totalDeposited;

    function depositRewards(uint256 amount) external {
        totalDeposited += amount;
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract FeeRouterTest is Test {
    uint256 constant WAD = 1e18;

    FeeRouter public router;
    MockUSDT public usdt;
    MockInsuranceFund public insuranceFund;
    MockRewardsDistributor public rewardsDistributor;

    address admin = address(0xAD);
    address treasury = address(0x71EA);
    address borrowEngine = address(0xBE);
    address executionEngine = address(0xEE);
    address liquidationEngine = address(0x1E);
    address settlementEngine = address(0x5E);
    address unauthorized = address(0xBAD);

    function setUp() public {
        usdt = new MockUSDT();
        insuranceFund = new MockInsuranceFund();
        rewardsDistributor = new MockRewardsDistributor();

        router = new FeeRouter(
            admin,
            address(usdt),
            address(insuranceFund),
            address(rewardsDistributor),
            treasury
        );

        // Grant roles
        vm.startPrank(admin);
        router.grantRole(router.BORROW_FEE_ENGINE_ROLE(), borrowEngine);
        router.grantRole(router.EXECUTION_ENGINE_ROLE(), executionEngine);
        router.grantRole(router.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        router.grantRole(router.SETTLEMENT_ENGINE_ROLE(), settlementEngine);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(router.usdt()), address(usdt));
        assertEq(address(router.insuranceFund()), address(insuranceFund));
        assertEq(address(router.rewardsDistributor()), address(rewardsDistributor));
        assertEq(router.protocolTreasury(), treasury);
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(FeeRouter.FeeRouter__ZeroAddress.selector);
        new FeeRouter(address(0), address(usdt), address(insuranceFund), address(rewardsDistributor), treasury);
    }

    function test_constructor_revertsOnZeroUsdt() public {
        vm.expectRevert(FeeRouter.FeeRouter__ZeroAddress.selector);
        new FeeRouter(admin, address(0), address(insuranceFund), address(rewardsDistributor), treasury);
    }

    function test_constructor_revertsOnZeroInsuranceFund() public {
        vm.expectRevert(FeeRouter.FeeRouter__ZeroAddress.selector);
        new FeeRouter(admin, address(usdt), address(0), address(rewardsDistributor), treasury);
    }

    function test_constructor_revertsOnZeroRewardsDistributor() public {
        vm.expectRevert(FeeRouter.FeeRouter__ZeroAddress.selector);
        new FeeRouter(admin, address(usdt), address(insuranceFund), address(0), treasury);
    }

    function test_constructor_revertsOnZeroTreasury() public {
        vm.expectRevert(FeeRouter.FeeRouter__ZeroAddress.selector);
        new FeeRouter(admin, address(usdt), address(insuranceFund), address(rewardsDistributor), address(0));
    }

    // ──────────────────────────────────────────────
    // routeFees — Tier 1 (50/30/20)
    // ──────────────────────────────────────────────

    function test_routeFees_tier1_splitCorrectly() public {
        uint256 amount = 1000e18;
        _fundRouter(amount);

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // LP: 50% = 500
        assertEq(usdt.balanceOf(address(rewardsDistributor)), 500e18);
        assertEq(rewardsDistributor.totalDeposited(), 500e18);

        // Protocol: 30% = 300
        assertEq(usdt.balanceOf(treasury), 300e18);

        // Insurance: 20% = 200
        assertEq(usdt.balanceOf(address(insuranceFund)), 200e18);
        assertEq(insuranceFund.totalDeposited(), 200e18);
    }

    function test_routeFees_tier1_sumEqualsAmount() public {
        // Use an amount that causes rounding: 1e18 + 1 (odd wei)
        uint256 amount = 1e18 + 1;
        _fundRouter(amount);

        vm.prank(executionEngine);
        router.routeFees(IFeeRouter.FeeType.TRANSACTION, amount);

        uint256 lpBal = usdt.balanceOf(address(rewardsDistributor));
        uint256 protocolBal = usdt.balanceOf(treasury);
        uint256 insuranceBal = usdt.balanceOf(address(insuranceFund));

        // Must sum exactly
        assertEq(lpBal + protocolBal + insuranceBal, amount);
    }

    function test_routeFees_tier1_allFeeTypes() public {
        uint256 amount = 100e18;

        // BORROW
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);
        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.BORROW), amount);

        // LIQUIDATION
        _fundRouter(amount);
        vm.prank(liquidationEngine);
        router.routeFees(IFeeRouter.FeeType.LIQUIDATION, amount);
        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.LIQUIDATION), amount);

        // SETTLEMENT
        _fundRouter(amount);
        vm.prank(settlementEngine);
        router.routeFees(IFeeRouter.FeeType.SETTLEMENT, amount);
        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.SETTLEMENT), amount);
    }

    // ──────────────────────────────────────────────
    // routeFees — Tier 2 (50/50/0)
    // ──────────────────────────────────────────────

    function test_routeFees_tier2_splitCorrectly() public {
        insuranceFund.setFullyFunded(true);

        uint256 amount = 1000e18;
        _fundRouter(amount);

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // LP: 50% = 500
        assertEq(usdt.balanceOf(address(rewardsDistributor)), 500e18);

        // Protocol: 50% = 500
        assertEq(usdt.balanceOf(treasury), 500e18);

        // Insurance: 0%
        assertEq(usdt.balanceOf(address(insuranceFund)), 0);
        assertEq(insuranceFund.totalDeposited(), 0);
    }

    function test_routeFees_tier2_sumEqualsAmount() public {
        insuranceFund.setFullyFunded(true);

        uint256 amount = 1e18 + 1;
        _fundRouter(amount);

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        uint256 lpBal = usdt.balanceOf(address(rewardsDistributor));
        uint256 protocolBal = usdt.balanceOf(treasury);

        assertEq(lpBal + protocolBal, amount);
    }

    // ──────────────────────────────────────────────
    // routeFees — Tier change event
    // ──────────────────────────────────────────────

    function test_routeFees_emitsTierChanged() public {
        uint256 amount = 100e18;

        // First call at tier 1 — no TierChanged event
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // Switch to tier 2
        insuranceFund.setFullyFunded(true);
        insuranceFund.setIFR(2e17); // 20%

        _fundRouter(amount);
        vm.prank(borrowEngine);
        // Should emit TierChanged(1, 2, 2e17)
        vm.expectEmit(false, false, false, true);
        emit IFeeRouter.TierChanged(1, 2, 2e17);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);
    }

    // ──────────────────────────────────────────────
    // routeFees — Reverts
    // ──────────────────────────────────────────────

    function test_routeFees_revertsOnZeroAmount() public {
        vm.prank(borrowEngine);
        vm.expectRevert(IFeeRouter.FeeRouter__ZeroAmount.selector);
        router.routeFees(IFeeRouter.FeeType.BORROW, 0);
    }

    function test_routeFees_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.FeeRouter__UnauthorizedCaller.selector, unauthorized));
        router.routeFees(IFeeRouter.FeeType.BORROW, 100e18);
    }

    function test_routeFees_revertsWhenPaused() public {
        vm.prank(admin);
        router.pause();

        _fundRouter(100e18);
        vm.prank(borrowEngine);
        vm.expectRevert();
        router.routeFees(IFeeRouter.FeeType.BORROW, 100e18);
    }

    // ──────────────────────────────────────────────
    // collectTransactionFee
    // ──────────────────────────────────────────────

    function test_collectTransactionFee_computesFeeCorrectly() public {
        uint256 notional = 10_000e18;
        uint256 expectedFee = 10e18; // 0.10% of 10,000 = 10

        _fundRouter(expectedFee);

        vm.prank(executionEngine);
        uint256 fee = router.collectTransactionFee(notional);

        assertEq(fee, expectedFee);
    }

    function test_collectTransactionFee_routesThroughSplit() public {
        uint256 notional = 10_000e18;
        uint256 expectedFee = 10e18;

        _fundRouter(expectedFee);

        vm.prank(executionEngine);
        router.collectTransactionFee(notional);

        // LP: 50% of 10 = 5
        assertEq(usdt.balanceOf(address(rewardsDistributor)), 5e18);
        // Protocol: 30% of 10 = 3
        assertEq(usdt.balanceOf(treasury), 3e18);
        // Insurance: 20% of 10 = 2
        assertEq(usdt.balanceOf(address(insuranceFund)), 2e18);
    }

    function test_collectTransactionFee_tracksTotalFeesRouted() public {
        uint256 notional = 10_000e18;
        uint256 expectedFee = 10e18;

        _fundRouter(expectedFee);

        vm.prank(executionEngine);
        router.collectTransactionFee(notional);

        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION), expectedFee);
    }

    function test_collectTransactionFee_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        router.collectTransactionFee(10_000e18);
    }

    function test_collectTransactionFee_zeroNotionalReturnsZero() public {
        vm.prank(executionEngine);
        uint256 fee = router.collectTransactionFee(0);
        assertEq(fee, 0);
    }

    function test_collectTransactionFee_revertsWhenPaused() public {
        vm.prank(admin);
        router.pause();

        vm.prank(executionEngine);
        vm.expectRevert();
        router.collectTransactionFee(10_000e18);
    }

    // ──────────────────────────────────────────────
    // View functions
    // ──────────────────────────────────────────────

    function test_getCurrentTier_returnsTier1WhenNotFullyFunded() public view {
        assertEq(router.getCurrentTier(), 1);
    }

    function test_getCurrentTier_returnsTier2WhenFullyFunded() public {
        insuranceFund.setFullyFunded(true);
        assertEq(router.getCurrentTier(), 2);
    }

    function test_getCurrentSplit_tier1() public view {
        (uint256 lp, uint256 protocol, uint256 insurance) = router.getCurrentSplit();
        assertEq(lp, 5e17);
        assertEq(protocol, 3e17);
        assertEq(insurance, 2e17);
    }

    function test_getCurrentSplit_tier2() public {
        insuranceFund.setFullyFunded(true);
        (uint256 lp, uint256 protocol, uint256 insurance) = router.getCurrentSplit();
        assertEq(lp, 5e17);
        assertEq(protocol, 5e17);
        assertEq(insurance, 0);
    }

    function test_previewSplit_tier1() public view {
        (uint256 lp, uint256 protocol, uint256 insurance) = router.previewSplit(1000e18);
        assertEq(lp, 500e18);
        assertEq(protocol, 300e18);
        assertEq(insurance, 200e18);
    }

    function test_previewSplit_tier2() public {
        insuranceFund.setFullyFunded(true);
        (uint256 lp, uint256 protocol, uint256 insurance) = router.previewSplit(1000e18);
        assertEq(lp, 500e18);
        assertEq(protocol, 500e18);
        assertEq(insurance, 0);
    }

    function test_previewSplit_roundingConsistency() public view {
        uint256 amount = 333e18 + 7; // awkward amount
        (uint256 lp, uint256 protocol, uint256 insurance) = router.previewSplit(amount);
        assertEq(lp + protocol + insurance, amount);
    }

    // ──────────────────────────────────────────────
    // Pause / Unpause
    // ──────────────────────────────────────────────

    function test_pause_onlyAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        router.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        router.pause();

        vm.prank(unauthorized);
        vm.expectRevert();
        router.unpause();
    }

    function test_unpause_allowsRouting() public {
        vm.prank(admin);
        router.pause();

        vm.prank(admin);
        router.unpause();

        uint256 amount = 100e18;
        _fundRouter(amount);

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        assertEq(usdt.balanceOf(address(rewardsDistributor)), 50e18);
    }

    // ──────────────────────────────────────────────
    // Access control — all authorized roles work
    // ──────────────────────────────────────────────

    function test_routeFees_allAuthorizedRoles() public {
        uint256 amount = 100e18;

        // borrowEngine
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // executionEngine
        _fundRouter(amount);
        vm.prank(executionEngine);
        router.routeFees(IFeeRouter.FeeType.TRANSACTION, amount);

        // liquidationEngine
        _fundRouter(amount);
        vm.prank(liquidationEngine);
        router.routeFees(IFeeRouter.FeeType.LIQUIDATION, amount);

        // settlementEngine
        _fundRouter(amount);
        vm.prank(settlementEngine);
        router.routeFees(IFeeRouter.FeeType.SETTLEMENT, amount);
    }

    // ──────────────────────────────────────────────
    // Tier flipping between calls
    // ──────────────────────────────────────────────

    function test_routeFees_tierFlipsBetweenCalls() public {
        uint256 amount = 100e18;

        // Tier 1
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);
        assertEq(usdt.balanceOf(address(insuranceFund)), 20e18);

        // Switch to tier 2
        insuranceFund.setFullyFunded(true);
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // Insurance balance unchanged (no new deposits)
        assertEq(insuranceFund.totalDeposited(), 20e18);

        // Switch back to tier 1
        insuranceFund.setFullyFunded(false);
        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        // Insurance gets more
        assertEq(insuranceFund.totalDeposited(), 40e18);
    }

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    function test_routeFees_emitsFeesRouted() public {
        uint256 amount = 1000e18;
        _fundRouter(amount);

        vm.expectEmit(true, false, false, true);
        emit IFeeRouter.FeesRouted(
            uint8(IFeeRouter.FeeType.BORROW),
            1000e18,
            500e18,  // lpShare
            300e18,  // protocolShare
            200e18,  // insuranceShare
            1        // tier
        );

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);
    }

    // ──────────────────────────────────────────────
    // Cumulative tracking
    // ──────────────────────────────────────────────

    function test_totalFeesRouted_accumulates() public {
        uint256 amount = 100e18;

        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        _fundRouter(amount);
        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.BORROW), 200e18);
        assertEq(router.getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION), 0);
    }

    // ──────────────────────────────────────────────
    // Small amounts
    // ──────────────────────────────────────────────

    function test_routeFees_smallAmount_1Wei() public {
        uint256 amount = 1;
        _fundRouter(amount);

        vm.prank(borrowEngine);
        router.routeFees(IFeeRouter.FeeType.BORROW, amount);

        uint256 lpBal = usdt.balanceOf(address(rewardsDistributor));
        uint256 protocolBal = usdt.balanceOf(treasury);
        uint256 insuranceBal = usdt.balanceOf(address(insuranceFund));
        assertEq(lpBal + protocolBal + insuranceBal, amount);
    }

    // ──────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────

    function _fundRouter(uint256 amount) internal {
        usdt.mint(address(router), amount);
    }
}
