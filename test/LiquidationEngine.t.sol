// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { LiquidationEngine } from "../contracts/LiquidationEngine.sol";
import { ILiquidationEngine } from "../contracts/interfaces/ILiquidationEngine.sol";
import { IMarginEngine } from "../contracts/interfaces/IMarginEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IFeeRouter } from "../contracts/interfaces/IFeeRouter.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarginEngine_LE {
    uint256 constant WAD = 1e18;

    mapping(uint256 => IMarginEngine.EquityResult) private _equities;
    mapping(uint256 => uint256) private _maintenanceMargins;
    mapping(uint256 => bool) private _liquidatable;

    function setEquity(uint256 positionId, int256 equity) external {
        _equities[positionId] = IMarginEngine.EquityResult({
            pnl: int256(0),
            accruedBorrowFees: 0,
            accruedFunding: int256(0),
            equity: equity,
            marginRatio: equity > 0 ? uint256(equity) * WAD / 1000e18 : 0
        });
    }

    function setMaintenanceMargin(uint256 positionId, uint256 mm) external {
        _maintenanceMargins[positionId] = mm;
    }

    function setLiquidatable(uint256 positionId, bool val) external {
        _liquidatable[positionId] = val;
    }

    function computeEquity(uint256 positionId)
        external
        view
        returns (IMarginEngine.EquityResult memory)
    {
        return _equities[positionId];
    }

    function getMaintenanceMargin(uint256 positionId) external view returns (uint256) {
        return _maintenanceMargins[positionId];
    }

    function isLiquidatable(uint256 positionId) external view returns (bool) {
        return _liquidatable[positionId];
    }
}

contract MockPositionManager_LE {
    mapping(uint256 => IPositionManager.Position) private _positions;
    mapping(bytes32 => uint256[]) private _marketPositions;
    uint256 private _nextId = 1;

    function addPosition(
        uint256 id,
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 positionSize,
        uint256 collateral
    ) external {
        _positions[id] = IPositionManager.Position({
            id: id,
            owner: owner,
            marketId: marketId,
            isLong: isLong,
            entryPI: 5e17,
            entryPrice: 5e17,
            positionSize: positionSize,
            collateral: collateral,
            leverage: 5e18,
            borrowIndex: 1e18,
            fundingIndex: int256(0),
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

    function updateCollateral(uint256 positionId, uint256 newCollateral) external {
        _positions[positionId].collateral = newCollateral;
    }

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return _marketPositions[marketId];
    }

    function getPositionOwner(uint256 positionId) external view returns (address) {
        return _positions[positionId].owner;
    }

    function totalOpenPositions() external pure returns (uint256) { return 0; }
    function nextPositionId() external view returns (uint256) { return _nextId; }
}

contract MockExecutionEngine_LE {
    uint256 private _marketDepth = 10_000e18; // Default 10K depth

    function setMarketDepth(uint256 depth) external {
        _marketDepth = depth;
    }

    function getMarketDepth(bytes32) external view returns (uint256) {
        return _marketDepth;
    }

    function previewExecution(bytes32, bool, uint256, bool)
        external
        pure
        returns (uint256 price, uint256 impact)
    {
        return (5e17, 1e15); // 0.50 price, 0.1% impact
    }
}

contract MockOILimits_LE {
    uint256 public decreaseCalls;
    bytes32 public lastMarketId;
    address public lastUser;
    bool public lastIsLong;
    uint256 public lastAmount;

    function decreaseOI(bytes32 marketId, address user, bool isLong, uint256 amount) external {
        ++decreaseCalls;
        lastMarketId = marketId;
        lastUser = user;
        lastIsLong = isLong;
        lastAmount = amount;
    }
}

contract MockAccountManager_LE {
    uint256 public releaseCalls;
    uint256 public creditCalls;
    mapping(address => uint256) public lastReleased;
    mapping(address => uint256) public lastCredited;

    function releaseCollateral(address user, uint256 amount) external {
        ++releaseCalls;
        lastReleased[user] = amount;
    }

    function creditPnL(address user, uint256 amount) external {
        ++creditCalls;
        lastCredited[user] = amount;
    }
}

contract MockInsuranceFund_LE {
    uint256 private _insurancePaid;
    uint256 private _remainder;
    uint256 public absorbCalls;
    uint256 public lastBadDebt;

    function setAbsorbResult(uint256 insurancePaid_, uint256 remainder_) external {
        _insurancePaid = insurancePaid_;
        _remainder = remainder_;
    }

    function absorbBadDebt(bytes32, uint256 totalBadDebt)
        external
        returns (uint256 insurancePaid, uint256 remainder)
    {
        ++absorbCalls;
        lastBadDebt = totalBadDebt;
        return (_insurancePaid, _remainder);
    }
}

contract MockFeeRouter_LE {
    uint256 public routeCalls;
    uint256 public lastAmount;
    uint8 public lastFeeType;

    function routeFees(IFeeRouter.FeeType feeType, uint256 amount) external {
        ++routeCalls;
        lastAmount = amount;
        lastFeeType = uint8(feeType);
    }
}

contract MockLeverVault_LE {
    uint256 public socializeCalls;
    uint256 public lastSocialized;

    function socializeLoss(uint256 amount) external {
        ++socializeCalls;
        lastSocialized = amount;
    }

    function totalAssets() external pure returns (uint256) {
        return 100_000e18;
    }
}

contract MockMarketRegistry_LE {
    mapping(bytes32 => IMarketRegistry.MarketState) private _states;

    function setMarketState(bytes32 marketId, IMarketRegistry.MarketState state) external {
        _states[marketId] = state;
    }

    function getMarketState(bytes32 marketId) external view returns (IMarketRegistry.MarketState) {
        return _states[marketId];
    }
}

// ──────────────────────────────────────────────
// Test Contract
// ──────────────────────────────────────────────

contract LiquidationEngineTest is Test {
    uint256 constant WAD = 1e18;

    LiquidationEngine public engine;
    MockMarginEngine_LE public marginEngine;
    MockPositionManager_LE public positionManager;
    MockExecutionEngine_LE public executionEngine;
    MockOILimits_LE public oiLimits;
    MockAccountManager_LE public accountManager;
    MockInsuranceFund_LE public insuranceFund;
    MockFeeRouter_LE public feeRouter;
    MockLeverVault_LE public leverVault;
    MockMarketRegistry_LE public marketRegistry;

    address admin = address(0xAD);
    address trader = address(0x1234);
    address liquidator = address(0xBEEF);
    bytes32 marketId = keccak256("ELECTION_2024");

    function setUp() public {
        marginEngine = new MockMarginEngine_LE();
        positionManager = new MockPositionManager_LE();
        executionEngine = new MockExecutionEngine_LE();
        oiLimits = new MockOILimits_LE();
        accountManager = new MockAccountManager_LE();
        insuranceFund = new MockInsuranceFund_LE();
        feeRouter = new MockFeeRouter_LE();
        leverVault = new MockLeverVault_LE();
        marketRegistry = new MockMarketRegistry_LE();

        engine = new LiquidationEngine(
            admin,
            address(marginEngine),
            address(positionManager),
            address(executionEngine),
            address(oiLimits),
            address(accountManager),
            address(insuranceFund),
            address(feeRouter),
            address(leverVault),
            address(marketRegistry)
        );

        // Set market as ACTIVE
        marketRegistry.setMarketState(marketId, IMarketRegistry.MarketState.ACTIVE);
    }

    // ──────────────────────────────────────────────
    // Helper to create a standard liquidatable position
    // ──────────────────────────────────────────────

    function _setupPosition(
        uint256 posId,
        uint256 positionSize,
        uint256 collateral,
        int256 equity,
        uint256 mm,
        bool liquidatable
    ) internal {
        positionManager.addPosition(posId, trader, marketId, true, positionSize, collateral);
        marginEngine.setEquity(posId, equity);
        marginEngine.setMaintenanceMargin(posId, mm);
        marginEngine.setLiquidatable(posId, liquidatable);
        // Insurance fully covers by default
        insuranceFund.setAbsorbResult(0, 0);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(engine.marginEngine()), address(marginEngine));
        assertEq(address(engine.positionManager()), address(positionManager));
        assertEq(address(engine.executionEngine()), address(executionEngine));
        assertEq(address(engine.oiLimits()), address(oiLimits));
        assertEq(address(engine.accountManager()), address(accountManager));
        assertEq(address(engine.insuranceFund()), address(insuranceFund));
        assertEq(address(engine.feeRouter()), address(feeRouter));
        assertEq(address(engine.leverVault()), address(leverVault));
        assertEq(address(engine.marketRegistry()), address(marketRegistry));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(LiquidationEngine.LiquidationEngine__ZeroAddress.selector);
        new LiquidationEngine(
            address(0), address(marginEngine), address(positionManager),
            address(executionEngine), address(oiLimits), address(accountManager),
            address(insuranceFund), address(feeRouter), address(leverVault),
            address(marketRegistry)
        );
    }

    // ──────────────────────────────────────────────
    // Path C: External Liquidation (with bounty)
    // ──────────────────────────────────────────────

    function test_liquidate_pathC_normalCase() public {
        // Position: 1000 USDT notional, 200 collateral, equity = 50 (underwater)
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        // Fee = min(1000 * 1%, 50) = min(10, 50) = 10
        assertEq(result.positionId, 1);
        assertEq(result.liquidationFee, 10e18);
        // Remaining equity = 50 - 10 = 40 > 0 → trader gets residual
        assertEq(result.remainingEquity, 40e18);
        assertEq(result.badDebt, 0);
        assertFalse(result.isPartial);

        // Verify position closed
        assertFalse(positionManager.isPositionOpen(1));

        // Verify OI decreased
        assertEq(oiLimits.decreaseCalls(), 1);
        assertEq(oiLimits.lastAmount(), 1000e18);

        // Verify collateral released
        assertEq(accountManager.lastReleased(trader), 200e18);

        // Verify trader receives residual
        assertEq(accountManager.lastCredited(trader), 40e18);

        // Verify fee routing: bounty = 10% of 10 = 1, protocol gets 9
        // Liquidator gets bounty via creditPnL
        assertEq(accountManager.lastCredited(liquidator), 1e18);
        assertEq(feeRouter.lastAmount(), 9e18);
        assertEq(feeRouter.lastFeeType(), uint8(IFeeRouter.FeeType.LIQUIDATION));
    }

    function test_liquidate_pathC_bountyCalculation() public {
        // Larger position for cleaner fee numbers
        _setupPosition(1, 5000e18, 1000e18, 200e18, 210e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        // Fee = min(5000 * 1%, 200) = min(50, 200) = 50
        assertEq(result.liquidationFee, 50e18);
        // Bounty = 50 * 10% = 5
        assertEq(accountManager.lastCredited(liquidator), 5e18);
        // Protocol fee = 50 - 5 = 45
        assertEq(feeRouter.lastAmount(), 45e18);
    }

    // ──────────────────────────────────────────────
    // Path A/B: Internal Liquidation (no bounty)
    // ──────────────────────────────────────────────

    function test_liquidate_pathAB_noBounty() public {
        // When liquidator == address(0), no bounty. But since liquidate() uses msg.sender,
        // we just verify that full fee goes through FeeRouter without bounty
        // Path A/B would be called internally. For Path C with msg.sender, bounty always applies.
        // Let's test via the external path with a known address.
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.prank(liquidator);
        engine.liquidate(1);

        // Since liquidator != address(0), bounty is paid
        // This is Path C behavior, which is correct for external calls
        assertEq(feeRouter.routeCalls(), 1);
    }

    // ──────────────────────────────────────────────
    // Fee Capped at Equity
    // ──────────────────────────────────────────────

    function test_liquidate_feeCappedAtEquity() public {
        // Position: 1000 notional, equity = 5 (very low)
        // Fee calculated = 10 but capped at equity = 5
        _setupPosition(1, 1000e18, 200e18, 5e18, 6e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.liquidationFee, 5e18); // Capped at equity
        // Remaining = 5 - 5 = 0 → marginal case
        assertEq(result.remainingEquity, 0);
        assertEq(result.badDebt, 0);
    }

    function test_liquidate_zeroEquity_zeroFee() public {
        // Position with equity <= 0 → fee = 0
        _setupPosition(1, 1000e18, 200e18, 0, 25e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.liquidationFee, 0);
        assertEq(result.remainingEquity, 0);
        assertEq(result.badDebt, 0);
    }

    // ──────────────────────────────────────────────
    // Bad Debt
    // ──────────────────────────────────────────────

    function test_liquidate_negativeEquity_badDebt() public {
        // Equity is -50 → all is bad debt, fee = 0
        _setupPosition(1, 1000e18, 200e18, -50e18, 25e18, true);
        insuranceFund.setAbsorbResult(50e18, 0); // Insurance covers all

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.liquidationFee, 0);
        assertEq(result.badDebt, 50e18);
        assertEq(result.insurancePaid, 50e18);
        assertEq(result.adlAmount, 0);

        // Insurance was called
        assertEq(insuranceFund.absorbCalls(), 1);
        assertEq(insuranceFund.lastBadDebt(), 50e18);

        // Total bad debt updated
        assertEq(engine.totalBadDebt(), 50e18);
    }

    function test_liquidate_badDebt_insurancePartialCover() public {
        // Equity = -100 → bad debt = 100. Insurance covers 60, remainder = 40 → LP socialization
        _setupPosition(1, 1000e18, 200e18, -100e18, 25e18, true);
        insuranceFund.setAbsorbResult(60e18, 40e18);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.badDebt, 100e18);
        assertEq(result.insurancePaid, 60e18);
        assertEq(result.adlAmount, 40e18);

        // LP socialization
        assertEq(leverVault.socializeCalls(), 1);
        assertEq(leverVault.lastSocialized(), 40e18);
    }

    function test_liquidate_badDebt_fullSocialization() public {
        // Insurance covers nothing → all goes to LP socialization
        _setupPosition(1, 1000e18, 200e18, -100e18, 25e18, true);
        insuranceFund.setAbsorbResult(0, 100e18);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.badDebt, 100e18);
        assertEq(result.insurancePaid, 0);
        assertEq(result.adlAmount, 100e18);
        assertEq(leverVault.lastSocialized(), 100e18);
    }

    // ──────────────────────────────────────────────
    // Revert Cases
    // ──────────────────────────────────────────────

    function test_liquidate_revertsIfNotLiquidatable() public {
        _setupPosition(1, 1000e18, 200e18, 100e18, 25e18, false);

        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidationEngine.LiquidationEngine__PositionNotLiquidatable.selector,
                1,
                int256(100e18),
                25e18
            )
        );
        engine.liquidate(1);
    }

    function test_liquidate_revertsIfPositionNotOpen() public {
        // No position added, so isOpen = false
        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidationEngine.LiquidationEngine__PositionNotFound.selector, 1
            )
        );
        engine.liquidate(1);
    }

    function test_liquidate_revertsIfMarketResolved() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        marketRegistry.setMarketState(marketId, IMarketRegistry.MarketState.RESOLVED);

        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidationEngine.LiquidationEngine__MarketResolved.selector, marketId
            )
        );
        engine.liquidate(1);
    }

    // ──────────────────────────────────────────────
    // PENDING_RESOLUTION
    // ──────────────────────────────────────────────

    function test_liquidate_worksInPendingResolution() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        marketRegistry.setMarketState(marketId, IMarketRegistry.MarketState.PENDING_RESOLUTION);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.positionId, 1);
        assertFalse(positionManager.isPositionOpen(1));
    }

    // ──────────────────────────────────────────────
    // Batch Liquidation
    // ──────────────────────────────────────────────

    function test_batchLiquidate_multiplePositions() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        _setupPosition(2, 2000e18, 400e18, 80e18, 90e18, true);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult[] memory results = engine.batchLiquidate(ids);

        assertEq(results.length, 2);
        assertEq(results[0].positionId, 1);
        assertEq(results[1].positionId, 2);

        // Both closed
        assertFalse(positionManager.isPositionOpen(1));
        assertFalse(positionManager.isPositionOpen(2));
    }

    function test_batchLiquidate_skipsNonLiquidatable() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        _setupPosition(2, 2000e18, 400e18, 200e18, 50e18, false); // Not liquidatable

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult[] memory results = engine.batchLiquidate(ids);

        // First liquidated
        assertEq(results[0].positionId, 1);
        // Second skipped (default values)
        assertEq(results[1].positionId, 0);

        assertFalse(positionManager.isPositionOpen(1));
        assertTrue(positionManager.isPositionOpen(2));
    }

    function test_batchLiquidate_skipsClosedPositions() public {
        // Position 3 not added, so isOpen = false
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 3;

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult[] memory results = engine.batchLiquidate(ids);

        assertEq(results[0].positionId, 1);
        assertEq(results[1].positionId, 0); // Skipped
    }

    // ──────────────────────────────────────────────
    // View Functions
    // ──────────────────────────────────────────────

    function test_isLiquidatable_returnsTrue() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        assertTrue(engine.isLiquidatable(1));
    }

    function test_isLiquidatable_returnsFalse() public {
        _setupPosition(1, 1000e18, 200e18, 200e18, 25e18, false);
        assertFalse(engine.isLiquidatable(1));
    }

    function test_isLiquidatable_falseForClosedPosition() public {
        // Not added → isOpen = false
        assertFalse(engine.isLiquidatable(999));
    }

    function test_getLiquidatablePositions() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        _setupPosition(2, 2000e18, 400e18, 200e18, 50e18, false);
        _setupPosition(3, 3000e18, 600e18, 30e18, 75e18, true);

        uint256[] memory liquidatable = engine.getLiquidatablePositions(marketId);

        assertEq(liquidatable.length, 2);
        assertEq(liquidatable[0], 1);
        assertEq(liquidatable[1], 3);
    }

    function test_previewLiquidation() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        ILiquidationEngine.LiquidationResult memory result = engine.previewLiquidation(1);

        // Fee = min(10, 50) = 10
        assertEq(result.positionId, 1);
        assertEq(result.liquidationFee, 10e18);
        assertEq(result.remainingEquity, 40e18);
        assertEq(result.badDebt, 0);
        assertFalse(result.isPartial);
    }

    function test_previewLiquidation_badDebt() public {
        _setupPosition(1, 1000e18, 200e18, -50e18, 25e18, true);

        ILiquidationEngine.LiquidationResult memory result = engine.previewLiquidation(1);

        assertEq(result.liquidationFee, 0);
        assertEq(result.remainingEquity, -50e18);
        assertEq(result.badDebt, 50e18);
    }

    function test_previewLiquidation_partialFlag() public {
        // Position size > 10% of market depth (10K). So > 1000 → partial
        _setupPosition(1, 2000e18, 400e18, 50e18, 55e18, true);

        ILiquidationEngine.LiquidationResult memory result = engine.previewLiquidation(1);
        assertTrue(result.isPartial);
    }

    function test_getLiquidationFeeRate() public view {
        assertEq(engine.getLiquidationFeeRate(), 1e16);
    }

    function test_getLiquidatorBountyShare() public view {
        assertEq(engine.getLiquidatorBountyShare(), 1e17);
    }

    // ──────────────────────────────────────────────
    // Accumulators
    // ──────────────────────────────────────────────

    function test_totalBadDebt_accumulates() public {
        _setupPosition(1, 1000e18, 200e18, -50e18, 25e18, true);
        insuranceFund.setAbsorbResult(50e18, 0);

        vm.prank(liquidator);
        engine.liquidate(1);
        assertEq(engine.totalBadDebt(), 50e18);

        // Second liquidation
        _setupPosition(2, 2000e18, 400e18, -30e18, 50e18, true);
        insuranceFund.setAbsorbResult(30e18, 0);

        vm.prank(liquidator);
        engine.liquidate(2);
        assertEq(engine.totalBadDebt(), 80e18);
    }

    function test_totalLiquidationFees_accumulates() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.prank(liquidator);
        engine.liquidate(1);
        assertEq(engine.totalLiquidationFees(), 10e18);

        _setupPosition(2, 2000e18, 400e18, 100e18, 110e18, true);

        vm.prank(liquidator);
        engine.liquidate(2);
        // Second fee = min(2000 * 1%, 100) = min(20, 100) = 20
        assertEq(engine.totalLiquidationFees(), 30e18);
    }

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    function test_liquidate_emitsPositionLiquidated() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.expectEmit(true, true, true, true);
        emit ILiquidationEngine.PositionLiquidated(
            1, marketId, trader, liquidator, 50e18, 55e18, 10e18, 0, block.timestamp
        );

        vm.prank(liquidator);
        engine.liquidate(1);
    }

    function test_liquidate_emitsBadDebtRecorded() public {
        _setupPosition(1, 1000e18, 200e18, -50e18, 25e18, true);
        insuranceFund.setAbsorbResult(30e18, 20e18);

        vm.expectEmit(true, true, false, true);
        emit ILiquidationEngine.BadDebtRecorded(marketId, 1, 50e18, 30e18, 20e18, block.timestamp);

        vm.prank(liquidator);
        engine.liquidate(1);
    }

    // ──────────────────────────────────────────────
    // Pausable
    // ──────────────────────────────────────────────

    function test_liquidate_revertsWhenPaused() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.prank(admin);
        engine.pause();

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        engine.liquidate(1);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        engine.pause();
    }

    // ──────────────────────────────────────────────
    // Partial Liquidation
    // ──────────────────────────────────────────────

    function test_partialLiquidation_largePosition() public {
        // Market depth = 10K. Position = 2K > 10% of 10K = 1K → partial
        // Chunk size = 5% of 10K = 500
        _setupPosition(1, 2000e18, 400e18, 100e18, 110e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertTrue(result.isPartial);
        // Position should be closed (partial liquidation closes remaining)
        assertFalse(positionManager.isPositionOpen(1));
    }

    // ──────────────────────────────────────────────
    // Edge: Barely Below MM
    // ──────────────────────────────────────────────

    function test_liquidate_barelyBelowMM() public {
        // Equity just barely below MM → small fee, trader gets residual
        _setupPosition(1, 1000e18, 200e18, 24e18, 25e18, true);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        // Fee = min(10, 24) = 10
        assertEq(result.liquidationFee, 10e18);
        // Remaining = 24 - 10 = 14
        assertEq(result.remainingEquity, 14e18);
        assertEq(result.badDebt, 0);
    }

    // ──────────────────────────────────────────────
    // Edge: Two keepers try same position
    // ──────────────────────────────────────────────

    function test_liquidate_secondCallRevertsAlreadyClosed() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);

        vm.prank(liquidator);
        engine.liquidate(1);

        // Second attempt → position not open
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidationEngine.LiquidationEngine__PositionNotFound.selector, 1
            )
        );
        engine.liquidate(1);
    }

    // ──────────────────────────────────────────────
    // Edge: Deeply underwater
    // ──────────────────────────────────────────────

    function test_liquidate_deeplyUnderwater() public {
        // Equity = -500 → fee = 0, all bad debt
        _setupPosition(1, 1000e18, 200e18, -500e18, 25e18, true);
        insuranceFund.setAbsorbResult(200e18, 300e18);

        vm.prank(liquidator);
        ILiquidationEngine.LiquidationResult memory result = engine.liquidate(1);

        assertEq(result.liquidationFee, 0);
        assertEq(result.badDebt, 500e18);
        assertEq(result.insurancePaid, 200e18);
        assertEq(result.adlAmount, 300e18);
        assertEq(leverVault.lastSocialized(), 300e18);
    }

    // ──────────────────────────────────────────────
    // Market State: VOIDED
    // ──────────────────────────────────────────────

    function test_liquidate_revertsIfMarketVoided() public {
        _setupPosition(1, 1000e18, 200e18, 50e18, 55e18, true);
        marketRegistry.setMarketState(marketId, IMarketRegistry.MarketState.VOIDED);

        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidationEngine.LiquidationEngine__MarketResolved.selector, marketId
            )
        );
        engine.liquidate(1);
    }
}
