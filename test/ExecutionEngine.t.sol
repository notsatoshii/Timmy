// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ExecutionEngine } from "../contracts/ExecutionEngine.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";
import { IOracleAdapter } from "../contracts/interfaces/IOracleAdapter.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

contract MockMarketRegistry {
    struct MockMarket {
        uint256 tau;
        bool live;
        uint256 allocationWeight;
        IMarketRegistry.MarketState state;
    }

    mapping(bytes32 => MockMarket) public markets;

    function setMarket(bytes32 id, uint256 tau, bool live_, uint256 weight, IMarketRegistry.MarketState state_) external {
        markets[id] = MockMarket(tau, live_, weight, state_);
    }

    function getTau(bytes32 id) external view returns (uint256) {
        return markets[id].tau;
    }

    function isLive(bytes32 id) external view returns (bool) {
        return markets[id].live;
    }

    function getAllocationWeight(bytes32 id) external view returns (uint256) {
        return markets[id].allocationWeight;
    }

    function getMarketState(bytes32 id) external view returns (IMarketRegistry.MarketState) {
        return markets[id].state;
    }
}

contract MockOracleAdapter {
    mapping(bytes32 => uint256) private _pi;
    mapping(bytes32 => bool) private _frozen;

    function setPI(bytes32 marketId, uint256 pi) external {
        _pi[marketId] = pi;
    }

    function setFrozen(bytes32 marketId, bool frozen) external {
        _frozen[marketId] = frozen;
    }

    function getPI(bytes32 marketId) external view returns (uint256) {
        return _pi[marketId];
    }

    function isFrozen(bytes32 marketId) external view returns (bool) {
        return _frozen[marketId];
    }
}

contract MockOILimits {
    uint256 private _globalOI;
    mapping(bytes32 => uint256) private _marketOI;
    mapping(bytes32 => uint256) private _longOI;
    mapping(bytes32 => uint256) private _shortOI;
    mapping(bytes32 => mapping(address => uint256)) private _userOI;
    mapping(bytes32 => uint256) private _marketOICap;

    bool public revertOnIncrease;

    function setMarketOICap(bytes32 marketId, uint256 cap) external {
        _marketOICap[marketId] = cap;
    }

    function setSideOI(bytes32 marketId, bool isLong, uint256 amount) external {
        if (isLong) {
            _longOI[marketId] = amount;
        } else {
            _shortOI[marketId] = amount;
        }
        _marketOI[marketId] = _longOI[marketId] + _shortOI[marketId];
        _globalOI = _marketOI[marketId]; // Simplified
    }

    function setRevertOnIncrease(bool val) external {
        revertOnIncrease = val;
    }

    function increaseOI(bytes32, address, bool, uint256) external view {
        if (revertOnIncrease) revert("OI limit breached");
    }

    function decreaseOI(bytes32, address, bool, uint256) external pure {
        // no-op for tests
    }

    function getMarketOICap(bytes32 marketId) external view returns (uint256) {
        return _marketOICap[marketId];
    }

    function getMarketOI(bytes32 marketId) external view returns (uint256) {
        return _marketOI[marketId];
    }

    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256) {
        return isLong ? _longOI[marketId] : _shortOI[marketId];
    }

    function getGlobalOI() external view returns (uint256) {
        return _globalOI;
    }

    function getUserOI(bytes32 marketId, address user) external view returns (uint256) {
        return _userOI[marketId][user];
    }
}

contract MockLeverageModel {
    uint256 private _maxLeverage = 30e18; // Default 30×

    function setMaxLeverage(uint256 val) external {
        _maxLeverage = val;
    }

    function getEffectiveMaxLeverage(bytes32) external view returns (uint256) {
        return _maxLeverage;
    }

    function validateLeverage(bytes32, uint256 leverage) external view returns (bool) {
        return leverage <= _maxLeverage;
    }
}

contract MockMarginEngine {
    bool private _valid = true;
    uint8 private _failedCheck;
    bool private _canRemove = true;

    function setValid(bool val, uint8 failedCheck_) external {
        _valid = val;
        _failedCheck = failedCheck_;
    }

    function setCanRemoveCollateral(bool val) external {
        _canRemove = val;
    }

    function validateMarginChecks(bytes32, address, bool, uint256, uint256)
        external
        view
        returns (bool, uint8)
    {
        return (_valid, _failedCheck);
    }

    function canRemoveCollateral(uint256, uint256) external view returns (bool) {
        return _canRemove;
    }
}

contract MockFeeRouter {
    uint256 public constant TX_FEE_RATE = 1e15; // 0.10% = 10 bps

    function collectTransactionFee(uint256 notional) external pure returns (uint256) {
        return (notional * TX_FEE_RATE) / 1e18;
    }

    function routeFees(uint8, uint256) external {
        // no-op for tests
    }
}

contract MockAccountManager {
    mapping(address => uint256) public balances;
    mapping(address => uint256) public locked;

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }

    function lockCollateral(address user, uint256 amount) external {
        locked[user] += amount;
    }

    function releaseCollateral(address user, uint256 amount) external {
        locked[user] -= amount;
    }

    function creditPnL(address user, uint256 amount) external {
        balances[user] += amount;
    }

    function debitPnL(address user, uint256 amount) external returns (uint256 badDebt) {
        if (amount > balances[user]) {
            badDebt = amount - balances[user];
            balances[user] = 0;
        } else {
            balances[user] -= amount;
        }
    }

    function transferOut(address, uint256) external {}

    function assignPosition(address, uint256) external {}

    function removePosition(address, uint256) external {}

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function getFreeCollateral(address user) external view returns (uint256) {
        return balances[user] - locked[user];
    }

    function getLockedCollateral(address user) external view returns (uint256) {
        return locked[user];
    }

    function getUserPositions(address) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }
}

contract MockLeverVault_EE {
    uint256 public fundCalls;
    address public lastRecipient;
    uint256 public lastAmount;
    int256 private _netUnrealizedPnL;

    function fundTraderPnL(address recipient, uint256 amount) external {
        ++fundCalls;
        lastRecipient = recipient;
        lastAmount = amount;
    }

    function updateUnrealizedPnL(int256 newPnL) external {
        _netUnrealizedPnL = newPnL;
    }

    function getNetUnrealizedPnL() external view returns (int256) {
        return _netUnrealizedPnL;
    }

    function socializeLoss(uint256) external {}
}

contract MockBorrowFeeEngine {
    uint256 private _borrowIndex = 1e18;
    uint256 private _accruedFees;

    function setBorrowIndex(uint256 val) external {
        _borrowIndex = val;
    }

    function setAccruedFees(uint256 val) external {
        _accruedFees = val;
    }

    function getBorrowIndex(bytes32, bool) external view returns (uint256) {
        return _borrowIndex;
    }

    function getAccruedFees(uint256) external view returns (uint256) {
        return _accruedFees;
    }
}

contract MockFundingRateEngine {
    int256 private _fundingIndex;
    int256 private _accruedFunding;

    function setFundingIndex(int256 val) external {
        _fundingIndex = val;
    }

    function setAccruedFunding(int256 val) external {
        _accruedFunding = val;
    }

    function getFundingIndex(bytes32) external view returns (int256) {
        return _fundingIndex;
    }

    function getAccruedFunding(uint256) external view returns (int256) {
        return _accruedFunding;
    }
}

contract MockPositionManager {
    uint256 private _nextId = 1;
    mapping(uint256 => IPositionManager.Position) private _positions;

    function createPosition(
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 entryPI,
        uint256 entryPrice,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        uint256 borrowIndex,
        int256 fundingIndex
    ) external returns (uint256 positionId) {
        positionId = _nextId++;
        _positions[positionId] = IPositionManager.Position({
            id: positionId,
            owner: owner,
            marketId: marketId,
            isLong: isLong,
            entryPI: entryPI,
            entryPrice: entryPrice,
            positionSize: positionSize,
            collateral: collateral,
            leverage: leverage,
            borrowIndex: borrowIndex,
            fundingIndex: fundingIndex,
            openTimestamp: block.timestamp,
            isOpen: true
        });
    }

    function closePosition(uint256 positionId) external {
        _positions[positionId].isOpen = false;
    }

    function updateCollateral(uint256 positionId, uint256 newCollateral) external {
        _positions[positionId].collateral = newCollateral;
    }

    function getPosition(uint256 positionId) external view returns (IPositionManager.Position memory) {
        return _positions[positionId];
    }

    function isPositionOpen(uint256 positionId) external view returns (bool) {
        return _positions[positionId].isOpen;
    }
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

contract MockInsuranceFund_EE {
    function absorbBadDebt(bytes32, uint256 totalBadDebt, address) external pure returns (uint256, uint256) {
        return (totalBadDebt, 0); // Absorb everything, no remainder
    }
}

contract ExecutionEngineTest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    ExecutionEngine engine;
    MockPositionManager positionManager;
    MockOILimits oiLimits;
    MockMarginEngine marginEngine;
    MockOracleAdapter oracleAdapter;
    MockMarketRegistry registry;
    MockLeverageModel leverageModel;
    MockFeeRouter feeRouter;
    MockBorrowFeeEngine borrowFeeEngine;
    MockFundingRateEngine fundingRateEngine;
    MockAccountManager accountManager;
    MockLeverVault_EE vault;
    MockInsuranceFund_EE insuranceFund;

    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xA2);

    bytes32 marketId = keccak256("ELECTION_2026");

    function setUp() public {
        positionManager = new MockPositionManager();
        oiLimits = new MockOILimits();
        marginEngine = new MockMarginEngine();
        oracleAdapter = new MockOracleAdapter();
        registry = new MockMarketRegistry();
        leverageModel = new MockLeverageModel();
        feeRouter = new MockFeeRouter();
        borrowFeeEngine = new MockBorrowFeeEngine();
        fundingRateEngine = new MockFundingRateEngine();
        accountManager = new MockAccountManager();
        vault = new MockLeverVault_EE();
        insuranceFund = new MockInsuranceFund_EE();

        engine = new ExecutionEngine(
            address(positionManager),
            address(oiLimits),
            address(marginEngine),
            address(oracleAdapter),
            address(registry),
            address(leverageModel),
            address(feeRouter),
            address(borrowFeeEngine),
            address(fundingRateEngine),
            address(accountManager),
            address(vault),
            address(insuranceFund),
            admin
        );

        // Default market: 48h to resolution, not live, 20% allocation, ACTIVE
        registry.setMarket(
            marketId, 48e18, false, 2e17, IMarketRegistry.MarketState.ACTIVE
        );

        // Set PI = 0.50
        oracleAdapter.setPI(marketId, 5e17);

        // Market OI Cap = $1M
        oiLimits.setMarketOICap(marketId, 1_000_000e18);
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(address(engine.positionManager()), address(positionManager));
        assertEq(address(engine.oiLimits()), address(oiLimits));
        assertEq(address(engine.marginEngine()), address(marginEngine));
        assertEq(address(engine.oracleAdapter()), address(oracleAdapter));
        assertEq(address(engine.marketRegistry()), address(registry));
        assertEq(address(engine.leverageModel()), address(leverageModel));
        assertEq(address(engine.feeRouter()), address(feeRouter));
        assertEq(address(engine.borrowFeeEngine()), address(borrowFeeEngine));
        assertEq(address(engine.fundingRateEngine()), address(fundingRateEngine));
        assertEq(address(engine.accountManager()), address(accountManager));
        assertEq(address(engine.leverVault()), address(vault));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(ExecutionEngine.ExecutionEngine__ZeroAddress.selector);
        new ExecutionEngine(
            address(0), address(oiLimits), address(marginEngine),
            address(oracleAdapter), address(registry), address(leverageModel),
            address(feeRouter), address(borrowFeeEngine), address(fundingRateEngine),
            address(accountManager), address(vault), address(insuranceFund), admin
        );
    }

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    function test_maxImpact_is5Percent() public view {
        assertEq(engine.MAX_IMPACT(), 5e16);
    }

    function test_imbalanceMultiplier_is2() public view {
        assertEq(engine.IMBALANCE_MULTIPLIER(), 2e18);
    }

    // ──────────────────────────────────────────────
    // Market Depth
    // ──────────────────────────────────────────────

    function test_getMarketDepth_farFromResolution() public view {
        // 48h to resolution, not live → R ≈ 0.9817 (high)
        // Execution_Depth_Mult ≈ 0.30 + 0.9817 × 0.70 ≈ 0.9872
        // depth ≈ 1_000_000 × 0.9872 ≈ 987,200
        uint256 depth = engine.getMarketDepth(marketId);
        assertGt(depth, 900_000e18);
        assertLe(depth, 1_000_000e18);
    }

    function test_getMarketDepth_nearResolution() public {
        // Set tau = 1h → R is much lower
        registry.setMarket(marketId, 1e18, false, 2e17, IMarketRegistry.MarketState.ACTIVE);
        uint256 depth = engine.getMarketDepth(marketId);
        // At 1h, R ≈ 0.0800 (very close to resolution)
        // depth_mult ≈ 0.30 + 0.08 × 0.70 ≈ 0.356
        // depth ≈ 356,000
        assertGt(depth, 300_000e18);
        assertLt(depth, 500_000e18);
    }

    // ──────────────────────────────────────────────
    // Base Impact
    // ──────────────────────────────────────────────

    function test_computeBaseImpact_normalTrade() public view {
        // Trade = $10,000, depth ≈ $987,200
        // base_impact = 10000 / (987200 × 2) ≈ 0.00506
        uint256 impact = engine.computeBaseImpact(marketId, 10_000e18);
        assertGt(impact, 0);
        assertLt(impact, 1e16); // Less than 1%
    }

    function test_computeBaseImpact_largeTrade() public view {
        // Trade = $500,000 → impact approaches ~25%+ before cap
        uint256 impact = engine.computeBaseImpact(marketId, 500_000e18);
        assertGt(impact, 0);
    }

    // ──────────────────────────────────────────────
    // Imbalance Delta
    // ──────────────────────────────────────────────

    function test_imbalanceDelta_balanced_longTrade() public {
        // Balanced book: 100K long, 100K short
        oiLimits.setSideOI(marketId, true, 100_000e18);
        oiLimits.setSideOI(marketId, false, 100_000e18);

        // Opening a 10K long worsens balance → positive delta
        int256 delta = engine.computeImbalanceDelta(marketId, true, 10_000e18);
        assertGt(delta, 0);
    }

    function test_imbalanceDelta_longHeavy_shortTrade() public {
        // Long-heavy: 150K long, 50K short
        oiLimits.setSideOI(marketId, true, 150_000e18);
        oiLimits.setSideOI(marketId, false, 50_000e18);

        // Opening a short IMPROVES balance → negative delta
        int256 delta = engine.computeImbalanceDelta(marketId, false, 10_000e18);
        assertLt(delta, 0);
    }

    function test_imbalanceDelta_noExistingOI() public view {
        // No existing OI, opening a 10K long
        // Before: 0, After: |10K - 0| / 10K = 1.0
        // delta = 1.0 - 0 = 1.0
        int256 delta = engine.computeImbalanceDelta(marketId, true, 10_000e18);
        assertEq(delta, int256(WAD)); // Exactly 1.0
    }

    function test_imbalanceDelta_longHeavy_longTrade() public {
        // Long-heavy: 150K long, 50K short
        oiLimits.setSideOI(marketId, true, 150_000e18);
        oiLimits.setSideOI(marketId, false, 50_000e18);

        // Opening a long WORSENS balance → positive delta
        int256 delta = engine.computeImbalanceDelta(marketId, true, 10_000e18);
        assertGt(delta, 0);
    }

    // ──────────────────────────────────────────────
    // Execution Price Preview
    // ──────────────────────────────────────────────

    function test_previewExecution_longEntry() public view {
        // No existing OI → max imbalance_delta = 1.0
        // base_impact = 10K / (987200 × 2) ≈ 0.00506
        // adjustment = 1 + 1.0 × 2.0 = 3.0
        // impact = 0.00506 × 3.0 ≈ 0.01519
        // price = 0.50 × (1 + 0.01519) ≈ 0.5076
        (uint256 price, uint256 impact) = engine.previewExecution(marketId, true, 10_000e18, true);
        assertGt(price, 5e17); // > PI for long
        assertGt(impact, 0);
        assertLt(impact, 5e16); // Under MAX_IMPACT
    }

    function test_previewExecution_shortEntry() public view {
        // Short entry: price should be less than PI
        (uint256 price,) = engine.previewExecution(marketId, false, 10_000e18, true);
        assertLt(price, 5e17); // < PI for short
    }

    function test_previewExecution_longClose() public {
        // Set balanced OI, then closing a long
        oiLimits.setSideOI(marketId, true, 100_000e18);
        oiLimits.setSideOI(marketId, false, 100_000e18);

        // Closing long: exit_price = PI × (1 - impact)
        (uint256 price,) = engine.previewExecution(marketId, true, 10_000e18, false);
        assertLt(price, 5e17); // Close long → price below PI
    }

    function test_previewExecution_maxImpactCap() public {
        // Very large trade relative to depth → should cap at MAX_IMPACT
        // With no OI, imbalance_delta = 1.0, adjustment = 3.0
        // base_impact = 1M / (987200 × 2) ≈ 0.506 → × 3 ≈ 1.52 → capped at 0.05
        (uint256 price, uint256 impact) = engine.previewExecution(marketId, true, 1_000_000e18, true);
        assertEq(impact, 5e16); // Exactly MAX_IMPACT
        // price = 0.50 × (1 + 0.05) = 0.525
        assertEq(price, 525e15);
    }

    function test_previewExecution_improvingBalanceReducesImpact() public {
        // Long-heavy book: 200K long, 100K short
        oiLimits.setSideOI(marketId, true, 200_000e18);
        oiLimits.setSideOI(marketId, false, 100_000e18);

        // Short trade improves balance → should have lower impact
        (, uint256 shortImpact) = engine.previewExecution(marketId, false, 10_000e18, true);

        // Long trade worsens balance → should have higher impact
        (, uint256 longImpact) = engine.previewExecution(marketId, true, 10_000e18, true);

        assertLt(shortImpact, longImpact);
    }

    // ──────────────────────────────────────────────
    // Open Position
    // ──────────────────────────────────────────────

    function test_openPosition_happyPath() public {
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        uint256 posId = engine.openPosition(params);

        assertEq(posId, 1);

        // Verify position was created
        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.owner, alice);
        assertEq(pos.marketId, marketId);
        assertTrue(pos.isLong);
        assertTrue(pos.isOpen);
        assertEq(pos.positionSize, 5000e18); // 1000 × 5
        // Collateral should be reduced by TX fee
        // TX fee = 5000 × 0.001 = 5
        assertEq(pos.collateral, 995e18);
        assertEq(pos.leverage, 5e18);
    }

    function test_openPosition_emitsEvent() public {
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit IExecutionEngine.PositionOpened(
            1, marketId, alice, true, 995e18, 5e18, 5e17, 0, 5000e18, 0, block.timestamp
        );
        engine.openPosition(params);
    }

    function test_openPosition_shortPosition() public {
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: false,
            collateral: 2000e18,
            leverage: 3e18
        });

        vm.prank(bob);
        uint256 posId = engine.openPosition(params);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.owner, bob);
        assertFalse(pos.isLong);
        assertEq(pos.positionSize, 6000e18);
        assertLt(pos.entryPrice, 5e17); // Short entry < PI
    }

    function test_openPosition_revertsOnInactiveMarket() public {
        registry.setMarket(marketId, 48e18, false, 2e17, IMarketRegistry.MarketState.LISTED);

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__MarketNotActive.selector, marketId)
        );
        engine.openPosition(params);
    }

    function test_openPosition_revertsOnFrozenMarket() public {
        oracleAdapter.setFrozen(marketId, true);

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__MarketFrozen.selector, marketId)
        );
        engine.openPosition(params);
    }

    function test_openPosition_revertsOnExcessiveLeverage() public {
        leverageModel.setMaxLeverage(10e18);

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 15e18
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__LeverageExceedsMax.selector, 15e18, 10e18)
        );
        engine.openPosition(params);
    }

    function test_openPosition_revertsOnZeroCollateral() public {
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 0,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectRevert(ExecutionEngine.ExecutionEngine__ZeroCollateral.selector);
        engine.openPosition(params);
    }

    function test_openPosition_revertsOnZeroLeverage() public {
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 0
        });

        vm.prank(alice);
        vm.expectRevert(ExecutionEngine.ExecutionEngine__ZeroLeverage.selector);
        engine.openPosition(params);
    }

    function test_openPosition_revertsOnFailedMarginCheck() public {
        marginEngine.setValid(false, 5);

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__MarginCheckFailed.selector, 5)
        );
        engine.openPosition(params);
    }

    function test_openPosition_snapshotsBorrowAndFundingIndices() public {
        borrowFeeEngine.setBorrowIndex(1_050_000_000_000_000_000); // 1.05
        fundingRateEngine.setFundingIndex(500_000_000_000_000); // 0.0005

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        uint256 posId = engine.openPosition(params);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.borrowIndex, 1_050_000_000_000_000_000);
        assertEq(pos.fundingIndex, 500_000_000_000_000);
    }

    // ──────────────────────────────────────────────
    // Close Position
    // ──────────────────────────────────────────────

    function test_closePosition_happyPath() public {
        // Open first
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        // Close
        vm.prank(alice);
        engine.closePosition(posId);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_closePosition_emitsEvent() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit IExecutionEngine.PositionClosed(posId, marketId, alice, 0, 0, 0, 0, block.timestamp);
        engine.closePosition(posId);
    }

    function test_closePosition_revertsForNonOwner() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__NotPositionOwner.selector, posId, bob)
        );
        engine.closePosition(posId);
    }

    function test_closePosition_revertsForClosedPosition() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(alice);
        engine.closePosition(posId);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__PositionNotFound.selector, posId)
        );
        engine.closePosition(posId);
    }

    // ──────────────────────────────────────────────
    // Add/Remove Collateral
    // ──────────────────────────────────────────────

    function test_addCollateral_happyPath() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(alice);
        engine.addCollateral(posId, 500e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.collateral, 1495e18); // 995 (after tx fee) + 500
    }

    function test_addCollateral_revertsZeroAmount() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(alice);
        vm.expectRevert(ExecutionEngine.ExecutionEngine__ZeroCollateral.selector);
        engine.addCollateral(posId, 0);
    }

    function test_addCollateral_revertsForNonOwner() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutionEngine.ExecutionEngine__NotPositionOwner.selector, posId, bob)
        );
        engine.addCollateral(posId, 500e18);
    }

    function test_removeCollateral_happyPath() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        vm.prank(alice);
        engine.removeCollateral(posId, 100e18);

        IPositionManager.Position memory pos = positionManager.getPosition(posId);
        assertEq(pos.collateral, 895e18); // 995 - 100
    }

    function test_removeCollateral_revertsWhenMarginBreached() public {
        vm.prank(alice);
        uint256 posId = engine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: true,
                collateral: 1000e18,
                leverage: 5e18
            })
        );

        marginEngine.setCanRemoveCollateral(false);

        vm.prank(alice);
        vm.expectRevert();
        engine.removeCollateral(posId, 900e18);
    }

    // ──────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────

    function test_pause_blocksOperations() public {
        vm.prank(admin);
        engine.pause();

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        vm.expectRevert();
        engine.openPosition(params);
    }

    function test_pause_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        engine.pause();
    }

    function test_unpause_resumesOperations() public {
        vm.prank(admin);
        engine.pause();

        vm.prank(admin);
        engine.unpause();

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 1000e18,
            leverage: 5e18
        });

        vm.prank(alice);
        uint256 posId = engine.openPosition(params);
        assertGt(posId, 0);
    }

    // ──────────────────────────────────────────────
    // Impact Model Edge Cases
    // ──────────────────────────────────────────────

    function test_impact_zeroSizeTrade() public view {
        (uint256 price, uint256 impact) = engine.previewExecution(marketId, true, 0, true);
        assertEq(impact, 0);
        assertEq(price, 5e17); // Just PI
    }

    function test_impact_piAtBoundary_high() public {
        // PI = 0.95 → same percentage impact (PI-independent)
        oracleAdapter.setPI(marketId, 95e16);

        (, uint256 impactHigh) = engine.previewExecution(marketId, true, 10_000e18, true);

        oracleAdapter.setPI(marketId, 5e17);

        (, uint256 impactMid) = engine.previewExecution(marketId, true, 10_000e18, true);

        // Impact should be the same regardless of PI level
        assertEq(impactHigh, impactMid);
    }

    function test_impact_closingImproves_betterPricing() public {
        // Long-heavy: 200K long, 100K short
        oiLimits.setSideOI(marketId, true, 200_000e18);
        oiLimits.setSideOI(marketId, false, 100_000e18);

        // Opening a long (worsens) vs closing a long (improves)
        (, uint256 openImpact) = engine.previewExecution(marketId, true, 10_000e18, true);
        (, uint256 closeImpact) = engine.previewExecution(marketId, true, 10_000e18, false);

        // Closing should have lower impact since it improves balance
        assertLt(closeImpact, openImpact);
    }

    // ──────────────────────────────────────────────
    // Fuzz Tests
    // ──────────────────────────────────────────────

    function testFuzz_impactNeverExceedsMax(uint256 tradeSize) public view {
        tradeSize = bound(tradeSize, 1e18, 100_000_000e18); // $1 to $100M

        (, uint256 impact) = engine.previewExecution(marketId, true, tradeSize, true);
        assertLe(impact, 5e16); // Never exceeds MAX_IMPACT
    }

    function testFuzz_longEntryPriceAbovePI(uint256 tradeSize) public view {
        tradeSize = bound(tradeSize, 1e18, 100_000_000e18);

        (uint256 price,) = engine.previewExecution(marketId, true, tradeSize, true);
        assertGe(price, 5e17); // Long entry ≥ PI
    }

    function testFuzz_shortEntryPriceBelowPI(uint256 tradeSize) public view {
        tradeSize = bound(tradeSize, 1e18, 100_000_000e18);

        (uint256 price,) = engine.previewExecution(marketId, false, tradeSize, true);
        assertLe(price, 5e17); // Short entry ≤ PI
    }
}
