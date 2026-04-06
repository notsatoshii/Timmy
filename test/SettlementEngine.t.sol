// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { ISettlementEngine } from "../contracts/interfaces/ISettlementEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { IFeeRouter } from "../contracts/interfaces/IFeeRouter.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarketRegistry_SE {
    mapping(bytes32 => IMarketRegistry.Market) private _markets;

    function setMarket(
        bytes32 marketId,
        IMarketRegistry.MarketState state,
        uint8 outcome,
        uint256 externalResolutionTime
    ) external {
        _markets[marketId] = IMarketRegistry.Market({
            id: marketId,
            name: "Test",
            externalMarketId: "ext-1",
            state: state,
            category: IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            resolutionTime: block.timestamp,
            listingTime: block.timestamp > 7 days ? block.timestamp - 7 days : 0,
            allocationWeight: 15e16,
            isLive: false,
            liveStartTime: 0,
            outcome: outcome,
            externalResolutionTime: externalResolutionTime
        });
    }

    function getMarket(bytes32 marketId) external view returns (IMarketRegistry.Market memory) {
        return _markets[marketId];
    }

    function getMarketState(bytes32 marketId) external view returns (IMarketRegistry.MarketState) {
        return _markets[marketId].state;
    }
}

contract MockPositionManager_SE {
    mapping(uint256 => IPositionManager.Position) private _positions;
    mapping(bytes32 => uint256[]) private _marketPositions;

    function addPosition(
        uint256 id,
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 entryPI,
        uint256 positionSize,
        uint256 collateral,
        uint256 borrowIndex,
        int256 fundingIndex
    ) external {
        uint256 lev = collateral > 0 ? positionSize * 1e18 / collateral : type(uint256).max;
        _positions[id] = IPositionManager.Position({
            id: id,
            owner: owner,
            marketId: marketId,
            isLong: isLong,
            entryPI: entryPI,
            entryPrice: entryPI,
            positionSize: positionSize,
            collateral: collateral,
            leverage: lev,
            borrowIndex: borrowIndex,
            fundingIndex: fundingIndex,
            openTimestamp: block.timestamp,
            isOpen: true
        });
        _marketPositions[marketId].push(id);
    }

    function getPosition(uint256 positionId) external view returns (IPositionManager.Position memory) {
        return _positions[positionId];
    }

    function isPositionOpen(uint256 positionId) external view returns (bool) {
        return _positions[positionId].isOpen;
    }

    function closePosition(uint256 positionId) external {
        _positions[positionId].isOpen = false;
    }

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return _marketPositions[marketId];
    }

    function getMarketSidePositions(bytes32 marketId, bool isLong)
        external view returns (uint256[] memory)
    {
        uint256[] memory all = _marketPositions[marketId];
        uint256 count;
        for (uint256 i; i < all.length; ++i) {
            if (_positions[all[i]].isLong == isLong) ++count;
        }
        uint256[] memory result = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < all.length; ++i) {
            if (_positions[all[i]].isLong == isLong) {
                result[idx++] = all[i];
            }
        }
        return result;
    }

    function getPositionOwner(uint256 positionId) external view returns (address) {
        return _positions[positionId].owner;
    }

    function totalOpenPositions() external pure returns (uint256) { return 0; }
    function nextPositionId() external pure returns (uint256) { return 1; }
    function getUserPositions(address) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }
}

contract MockOracleAdapter_SE {
    uint256 public snapCalls;
    bytes32 public lastSnapMarketId;
    uint256 public lastSnapOutcome;

    function snapToOutcome(bytes32 marketId, uint256 outcome) external {
        ++snapCalls;
        lastSnapMarketId = marketId;
        lastSnapOutcome = outcome;
    }

    function getPI(bytes32) external pure returns (uint256) {
        return 5e17;
    }
}

contract MockBorrowFeeEngine_SE {
    mapping(bytes32 => mapping(bool => uint256)) private _indices;

    function setComputeIndexAt(bytes32 marketId, bool isLong, uint256 index) external {
        _indices[marketId][isLong] = index;
    }

    function computeIndexAt(bytes32 marketId, bool isLong, uint256)
        external view returns (uint256)
    {
        return _indices[marketId][isLong];
    }

    function getAccruedFees(uint256) external pure returns (uint256) {
        return 0;
    }

    function getBorrowIndex(bytes32 marketId, bool isLong) external view returns (uint256) {
        return _indices[marketId][isLong];
    }
}

contract MockFundingRateEngine_SE {
    mapping(bytes32 => int256) private _indices;

    function setComputeIndexAt(bytes32 marketId, int256 index) external {
        _indices[marketId] = index;
    }

    function computeIndexAt(bytes32 marketId, uint256) external view returns (int256) {
        return _indices[marketId];
    }

    function getAccruedFunding(uint256) external pure returns (int256) {
        return 0;
    }

    function getFundingIndex(bytes32 marketId) external view returns (int256) {
        return _indices[marketId];
    }
}

contract MockInsuranceFund_SE {
    uint256 private _insurancePaid;
    uint256 private _remainder;
    uint256 public absorbCalls;
    uint256 public lastBadDebt;

    function setAbsorbResult(uint256 insurancePaid_, uint256 remainder_) external {
        _insurancePaid = insurancePaid_;
        _remainder = remainder_;
    }

    function absorbBadDebt(bytes32, uint256 totalBadDebt, address)
        external returns (uint256, uint256)
    {
        ++absorbCalls;
        lastBadDebt = totalBadDebt;
        return (_insurancePaid, _remainder);
    }

    function getBalance() external pure returns (uint256) { return 100_000e18; }
    function getIFR() external pure returns (uint256) { return 1e17; }
}

contract MockFeeRouter_SE {
    uint256 public routeCalls;
    uint256 public totalRouted;
    uint8 public lastFeeType;

    function routeFees(IFeeRouter.FeeType feeType, uint256 amount) external {
        ++routeCalls;
        totalRouted += amount;
        lastFeeType = uint8(feeType);
    }
}

contract MockOILimits_SE {
    uint256 public decreaseCalls;

    function decreaseOI(bytes32, address, bool, uint256) external {
        ++decreaseCalls;
    }
}

contract MockAccountManager_SE {
    uint256 public releaseCalls;
    uint256 public creditCalls;
    uint256 public totalCredited;
    mapping(address => uint256) public lastCredited;

    function releaseCollateral(address, uint256) external {
        ++releaseCalls;
    }

    function creditPnL(address user, uint256 amount) external {
        ++creditCalls;
        totalCredited += amount;
        lastCredited[user] = amount;
    }

    function debitPnL(address user, uint256 amount) external returns (uint256 badDebt) {
        // Mock implementation - no bad debt
        return 0;
    }

    function transferOut(address, uint256) external {}
}

contract MockLeverVault_SE {
    uint256 public socializeCalls;
    uint256 public lastSocialized;

    function socializeLoss(uint256 amount) external {
        ++socializeCalls;
        lastSocialized = amount;
    }

    function fundTraderPnL(address recipient, uint256 amount) external {
        // Mock implementation - no actual transfer
    }

    function totalAssets() external pure returns (uint256) {
        return 100_000e18;
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract SettlementEngineTest is Test {
    uint256 constant WAD = 1e18;

    SettlementEngine public engine;
    MockMarketRegistry_SE public marketRegistry;
    MockPositionManager_SE public positionManager;
    MockOracleAdapter_SE public oracleAdapter;
    MockBorrowFeeEngine_SE public borrowFeeEngine;
    MockFundingRateEngine_SE public fundingRateEngine;
    MockInsuranceFund_SE public insuranceFund;
    MockFeeRouter_SE public feeRouter;
    MockOILimits_SE public oiLimits;
    MockAccountManager_SE public accountManager;
    MockLeverVault_SE public leverVault;

    address admin = address(0xAD);
    address keeper = address(0xBE);
    address alice = address(0xA1);
    address bob = address(0xB0);
    address charlie = address(0xC3);

    bytes32 marketId = keccak256("ELECTION_2024");
    bytes32 keeperRole;

    function setUp() public {
        // Set block.timestamp to a reasonable value to avoid underflows
        vm.warp(1_700_000_000);

        marketRegistry = new MockMarketRegistry_SE();
        positionManager = new MockPositionManager_SE();
        oracleAdapter = new MockOracleAdapter_SE();
        borrowFeeEngine = new MockBorrowFeeEngine_SE();
        fundingRateEngine = new MockFundingRateEngine_SE();
        insuranceFund = new MockInsuranceFund_SE();
        feeRouter = new MockFeeRouter_SE();
        oiLimits = new MockOILimits_SE();
        accountManager = new MockAccountManager_SE();
        leverVault = new MockLeverVault_SE();

        engine = new SettlementEngine(
            admin,
            address(marketRegistry),
            address(positionManager),
            address(oracleAdapter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(insuranceFund),
            address(feeRouter),
            address(oiLimits),
            address(accountManager),
            address(leverVault)
        );

        // Grant KEEPER_ROLE
        keeperRole = engine.KEEPER_ROLE();
        vm.prank(admin);
        engine.grantRole(keeperRole, keeper);

        // Default: borrow index = 1e18 (no fees), funding index = 0
        borrowFeeEngine.setComputeIndexAt(marketId, true, WAD);
        borrowFeeEngine.setComputeIndexAt(marketId, false, WAD);
        fundingRateEngine.setComputeIndexAt(marketId, 0);

        // Default: insurance absorbs all (no remainder)
        insuranceFund.setAbsorbResult(0, 0);
    }

    // ──────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────

    function _setupResolvedMarket(uint8 outcome) internal {
        marketRegistry.setMarket(
            marketId,
            IMarketRegistry.MarketState.RESOLVED,
            outcome,
            block.timestamp - 1 hours
        );
    }

    function _setupVoidedMarket() internal {
        marketRegistry.setMarket(
            marketId,
            IMarketRegistry.MarketState.VOIDED,
            2,
            0
        );
    }

    // ──────────────────────────────────────────────
    // settleMarket — Happy Path
    // ──────────────────────────────────────────────

    function test_settleMarket_outcome1_longWins() public {
        _setupResolvedMarket(1);

        // Alice: long, entry=0.50, size=1000, coll=200
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);
        // Bob: short, entry=0.50, size=500, coll=100
        positionManager.addPosition(2, bob, marketId, false, 5e17, 500e18, 100e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        assertEq(oracleAdapter.snapCalls(), 1);
        assertEq(oracleAdapter.lastSnapOutcome(), WAD);

        ISettlementEngine.MarketSettlementSummary memory summary = engine.getMarketSettlement(marketId);
        assertEq(summary.outcome, 1);
        assertEq(summary.winnerCount, 1);
        assertEq(summary.loserCount, 1);

        // Alice: PnL = +500, equity = 700, fee = 2, payout = 698
        assertEq(summary.totalWinnerPayout, 698e18);
        assertEq(summary.feesCollected, 2e18);

        // Bob: PnL = -250, equity = -150 → bad debt = 150
        assertEq(summary.totalBadDebt, 150e18);
    }

    function test_settleMarket_outcome0_shortWins() public {
        _setupResolvedMarket(0);

        positionManager.addPosition(1, alice, marketId, true, 6e17, 1000e18, 200e18, WAD, 0);
        positionManager.addPosition(2, bob, marketId, false, 6e17, 500e18, 300e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        assertEq(oracleAdapter.lastSnapOutcome(), 0);

        ISettlementEngine.MarketSettlementSummary memory summary = engine.getMarketSettlement(marketId);
        assertEq(summary.outcome, 0);
        assertEq(summary.winnerCount, 1);
        assertEq(summary.loserCount, 1);

        // Bob (short, winner): PnL = +300, equity = 600, fee = 1, payout = 599
        assertEq(summary.totalWinnerPayout, 599e18);

        // Alice (long, loser): PnL = -600, equity = -400 → bad debt = 400
        assertEq(summary.totalBadDebt, 400e18);
    }

    function test_settleMarket_emptyMarket() public {
        _setupResolvedMarket(1);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.MarketSettlementSummary memory summary = engine.getMarketSettlement(marketId);
        assertEq(summary.totalPositions, 0);
        assertEq(summary.totalBadDebt, 0);
        assertEq(summary.totalWinnerPayout, 0);
    }

    // ──────────────────────────────────────────────
    // settleMarket — Access Control
    // ──────────────────────────────────────────────

    function test_settleMarket_revertsIfNotKeeper() public {
        _setupResolvedMarket(1);

        vm.prank(alice);
        vm.expectRevert();
        engine.settleMarket(marketId);
    }

    function test_settleMarket_revertsIfNotResolved() public {
        marketRegistry.setMarket(marketId, IMarketRegistry.MarketState.ACTIVE, 0, 0);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.SettlementEngine__MarketNotResolved.selector, marketId)
        );
        engine.settleMarket(marketId);
    }

    function test_settleMarket_revertsIfAlreadySettled() public {
        _setupResolvedMarket(1);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SettlementEngine.SettlementEngine__MarketAlreadySettled.selector, marketId)
        );
        engine.settleMarket(marketId);
    }

    function test_settleMarket_revertsOnInvalidOutcome() public {
        marketRegistry.setMarket(marketId, IMarketRegistry.MarketState.RESOLVED, 2, block.timestamp);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.SettlementEngine__InvalidOutcome.selector, 2)
        );
        engine.settleMarket(marketId);
    }

    // ──────────────────────────────────────────────
    // claimSettlement
    // ──────────────────────────────────────────────

    function test_claimSettlement_winnerGetsPayout() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);

        assertTrue(result.isWinner);
        assertEq(result.payout, 698e18);
        assertEq(result.settlementFee, 2e18);

        assertEq(oiLimits.decreaseCalls(), 1);
        assertEq(accountManager.releaseCalls(), 1);
        assertEq(accountManager.lastCredited(alice), 698e18);
        assertEq(feeRouter.routeCalls(), 1);
        assertEq(feeRouter.lastFeeType(), uint8(IFeeRouter.FeeType.SETTLEMENT));

        assertTrue(engine.isSettled(1));
    }

    function test_claimSettlement_loserGetsRemainingEquity() public {
        _setupResolvedMarket(1);
        // Bob: short, entry=0.80, size=500, coll=500
        // PnL = -100, equity = 400
        positionManager.addPosition(1, bob, marketId, false, 8e17, 500e18, 500e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);

        assertFalse(result.isWinner);
        assertEq(result.payout, 400e18);
        assertEq(result.settlementFee, 0);
        assertEq(result.badDebt, 0);
    }

    function test_claimSettlement_revertsIfAlreadyClaimed() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        engine.claimSettlement(1);

        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.SettlementEngine__PositionAlreadySettled.selector, 1)
        );
        engine.claimSettlement(1);
    }

    function test_claimSettlement_revertsIfMarketNotSettled() public {
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);
        marketRegistry.setMarket(marketId, IMarketRegistry.MarketState.ACTIVE, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(SettlementEngine.SettlementEngine__MarketNotSettled.selector, marketId)
        );
        engine.claimSettlement(1);
    }

    // ──────────────────────────────────────────────
    // ADL (Auto-Deleveraging)
    // ──────────────────────────────────────────────

    function test_adl_haircutsWinners() public {
        _setupResolvedMarket(1);

        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);
        positionManager.addPosition(2, bob, marketId, false, 5e17, 1000e18, 100e18, WAD, 0);

        // Insurance covers 300, remainder = 100
        insuranceFund.setAbsorbResult(300e18, 100e18);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        // haircut = 100 / 698
        uint256 expectedHaircut = uint256(100e18) * WAD / 698e18;
        assertEq(engine.getADLHaircut(marketId), expectedHaircut);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);
        uint256 expectedPayout = uint256(698e18) * (WAD - expectedHaircut) / WAD;
        assertApproxEqAbs(result.payout, expectedPayout, 1);
    }

    function test_adl_haircutCappedAtWAD_lpSocialization() public {
        _setupResolvedMarket(1);

        // Alice: long, winner. entry=0.90, size=100, coll=100
        // PnL = +10, equity = 110, fee = 0.2, payout = 109.8
        positionManager.addPosition(1, alice, marketId, true, 9e17, 100e18, 100e18, WAD, 0);

        // Bob: short, loser. entry=0.20, size=1000, coll=100
        // PnL = -800, equity = -700 → bad debt = 700
        positionManager.addPosition(2, bob, marketId, false, 2e17, 1000e18, 100e18, WAD, 0);

        insuranceFund.setAbsorbResult(0, 700e18);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        assertEq(engine.getADLHaircut(marketId), WAD);

        // LP socialization = 700 - 109.8 = 590.2
        uint256 expectedSocialized = 700e18 - 1098e17;
        assertApproxEqAbs(leverVault.lastSocialized(), expectedSocialized / 1e12, 1e15 / 1e12); // USDT format (6 decimals)
        assertEq(leverVault.socializeCalls(), 1);
    }

    function test_adl_noWinners_allLPSocialization() public {
        _setupResolvedMarket(1);

        positionManager.addPosition(1, bob, marketId, false, 5e17, 500e18, 100e18, WAD, 0);
        positionManager.addPosition(2, charlie, marketId, false, 5e17, 300e18, 50e18, WAD, 0);

        insuranceFund.setAbsorbResult(0, 400e18);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        assertEq(leverVault.socializeCalls(), 1);
        assertEq(leverVault.lastSocialized(), 400e18 / 1e12); // USDT format (6 decimals)
    }

    // ──────────────────────────────────────────────
    // Fee Freezing
    // ──────────────────────────────────────────────

    function test_feesFrozenAtExternalTimestamp() public {
        _setupResolvedMarket(1);

        // borrow index = 1.05 → 5% fees
        borrowFeeEngine.setComputeIndexAt(marketId, true, 105e16);
        borrowFeeEngine.setComputeIndexAt(marketId, false, 105e16);

        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);

        // PnL = 500, borrow = 50, equity = 650, fee = 2, payout = 648
        assertEq(result.payout, 648e18);
    }

    function test_fundingFrozenAtExternalTimestamp() public {
        _setupResolvedMarket(1);

        // Funding index = 0.01 (longs paid)
        fundingRateEngine.setComputeIndexAt(marketId, 1e16);

        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);

        // PnL = 500, funding = -10, equity = 690, fee = 2, payout = 688
        assertEq(result.payout, 688e18);
    }

    // ──────────────────────────────────────────────
    // Void Settlement
    // ──────────────────────────────────────────────

    function test_settleVoid_refundsEquity() public {
        _setupVoidedMarket();

        positionManager.addPosition(1, alice, marketId, true, 6e17, 1000e18, 200e18, WAD, 0);
        positionManager.addPosition(2, bob, marketId, false, 4e17, 500e18, 100e18, WAD, 0);

        vm.prank(keeper);
        engine.settleVoid(marketId);

        // PnL = 0 for void. No settlement fee.
        assertEq(accountManager.lastCredited(alice), 200e18);
        assertEq(accountManager.lastCredited(bob), 100e18);
        assertEq(accountManager.creditCalls(), 2);
        assertEq(oiLimits.decreaseCalls(), 2);

        assertTrue(engine.isSettled(1));
        assertTrue(engine.isSettled(2));

        assertEq(feeRouter.routeCalls(), 0);
    }

    function test_settleVoid_deductsBorrowFees() public {
        _setupVoidedMarket();

        borrowFeeEngine.setComputeIndexAt(marketId, true, 110e16);
        borrowFeeEngine.setComputeIndexAt(marketId, false, 110e16);

        positionManager.addPosition(1, alice, marketId, true, 6e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleVoid(marketId);

        // equity = 200 - 100 = 100
        assertEq(accountManager.lastCredited(alice), 100e18);
    }

    function test_settleVoid_revertsIfNotVoided() public {
        marketRegistry.setMarket(marketId, IMarketRegistry.MarketState.ACTIVE, 0, 0);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SettlementEngine.SettlementEngine__MarketNotVoided.selector, marketId)
        );
        engine.settleVoid(marketId);
    }

    function test_settleVoid_revertsIfNotKeeper() public {
        _setupVoidedMarket();

        vm.prank(alice);
        vm.expectRevert();
        engine.settleVoid(marketId);
    }

    // ──────────────────────────────────────────────
    // Edge Cases
    // ──────────────────────────────────────────────

    function test_winnerEquityLessThanFee() public {
        _setupResolvedMarket(1);

        // entry=0.999, size=1000, coll=1.5
        // PnL = 1.0, equity = 2.5, fee = 2.0, payout = 0.5
        positionManager.addPosition(1, alice, marketId, true, 999e15, 1000e18, 15e17, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);
        assertTrue(result.isWinner);
        assertEq(result.payout, 5e17);
    }

    function test_winnerEquityZeroAfterFee() public {
        _setupResolvedMarket(1);

        // entry=0.998, size=1000, coll=0
        // PnL = 2.0, equity = 2.0, fee = 2.0, payout = 0
        positionManager.addPosition(1, alice, marketId, true, 998e15, 1000e18, 0, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);
        assertTrue(result.isWinner);
        assertEq(result.payout, 0);
        assertEq(result.settlementFee, 2e18);
    }

    function test_singlePosition() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 500e18, 100e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);
        assertTrue(result.isWinner);
        // PnL = 250, equity = 350, fee = 1, payout = 349
        assertEq(result.payout, 349e18);
    }

    function test_permissionlessClaim() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        vm.prank(charlie);
        ISettlementEngine.SettlementResult memory result = engine.claimSettlement(1);

        assertTrue(result.isWinner);
        assertEq(accountManager.lastCredited(alice), 698e18);
    }

    // ──────────────────────────────────────────────
    // View Functions
    // ──────────────────────────────────────────────

    function test_previewSettlement() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.SettlementResult memory preview = engine.previewSettlement(1);
        assertTrue(preview.isWinner);
        assertEq(preview.payout, 698e18);
    }

    function test_getUnsettledPositions() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);
        positionManager.addPosition(2, bob, marketId, false, 5e17, 500e18, 500e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        uint256[] memory unsettled = engine.getUnsettledPositions(marketId);
        assertEq(unsettled.length, 2);

        engine.claimSettlement(1);

        unsettled = engine.getUnsettledPositions(marketId);
        assertEq(unsettled.length, 1);
        assertEq(unsettled[0], 2);
    }

    function test_isFullySettled() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        assertFalse(engine.isFullySettled(marketId));

        engine.claimSettlement(1);

        assertTrue(engine.isFullySettled(marketId));
    }

    // ──────────────────────────────────────────────
    // Pausable
    // ──────────────────────────────────────────────

    function test_pauseUnpause() public {
        _setupResolvedMarket(1);
        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);

        vm.prank(admin);
        engine.pause();

        vm.prank(keeper);
        vm.expectRevert();
        engine.settleMarket(marketId);

        vm.prank(admin);
        engine.unpause();

        vm.prank(keeper);
        engine.settleMarket(marketId);
    }

    // ──────────────────────────────────────────────
    // Constructor validation
    // ──────────────────────────────────────────────

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(SettlementEngine.SettlementEngine__ZeroAddress.selector);
        new SettlementEngine(
            address(0),
            address(marketRegistry),
            address(positionManager),
            address(oracleAdapter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(insuranceFund),
            address(feeRouter),
            address(oiLimits),
            address(accountManager),
            address(leverVault)
        );
    }

    // ──────────────────────────────────────────────
    // Multiple positions with mixed results
    // ──────────────────────────────────────────────

    function test_multiplePositions_mixedOutcomes() public {
        _setupResolvedMarket(1);

        positionManager.addPosition(1, alice, marketId, true, 5e17, 1000e18, 200e18, WAD, 0);
        positionManager.addPosition(2, bob, marketId, true, 6e17, 500e18, 100e18, WAD, 0);
        positionManager.addPosition(3, charlie, marketId, true, 4e17, 800e18, 160e18, WAD, 0);
        positionManager.addPosition(4, alice, marketId, false, 5e17, 600e18, 120e18, WAD, 0);
        positionManager.addPosition(5, bob, marketId, false, 7e17, 400e18, 200e18, WAD, 0);

        vm.prank(keeper);
        engine.settleMarket(marketId);

        ISettlementEngine.MarketSettlementSummary memory summary = engine.getMarketSettlement(marketId);
        assertEq(summary.winnerCount, 3);
        assertEq(summary.loserCount, 2);
        assertEq(summary.totalPositions, 5);

        for (uint256 i = 1; i <= 5; ++i) {
            engine.claimSettlement(i);
            assertTrue(engine.isSettled(i));
        }

        assertTrue(engine.isFullySettled(marketId));
    }
}
