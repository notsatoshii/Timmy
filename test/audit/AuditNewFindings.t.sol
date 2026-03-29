// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";

import { FundingRateEngine } from "../../contracts/FundingRateEngine.sol";
import { BorrowFeeEngine } from "../../contracts/BorrowFeeEngine.sol";
import { InsuranceFund } from "../../contracts/InsuranceFund.sol";
import { ExecutionEngine } from "../../contracts/ExecutionEngine.sol";

import { IPositionManager } from "../../contracts/interfaces/IPositionManager.sol";
import { IMarketRegistry } from "../../contracts/interfaces/IMarketRegistry.sol";
import { IFeeRouter } from "../../contracts/interfaces/IFeeRouter.sol";
import { IExecutionEngine } from "../../contracts/interfaces/IExecutionEngine.sol";

// ──────────────────────────────────────────────────────────────────────────────
// Shared minimal mocks
// ──────────────────────────────────────────────────────────────────────────────

contract MockMarketRegistry_ANF {
    struct MockMarket {
        uint256 tau;
        bool live;
        IMarketRegistry.MarketState state;
        bytes32[] active;
    }

    mapping(bytes32 => MockMarket) private _markets;
    bytes32[] private _active;

    function setMarket(bytes32 marketId, uint256 tau, bool live) external {
        _markets[marketId].tau = tau;
        _markets[marketId].live = live;
        _markets[marketId].state = IMarketRegistry.MarketState.ACTIVE;
    }

    function setMarketState(bytes32 marketId, IMarketRegistry.MarketState state) external {
        _markets[marketId].state = state;
    }

    function addActiveMarket(bytes32 marketId) external {
        _active.push(marketId);
    }

    function getTau(bytes32 marketId) external view returns (uint256) { return _markets[marketId].tau; }
    function isLive(bytes32 marketId) external view returns (bool) { return _markets[marketId].live; }
    function getMarketState(bytes32 marketId) external view returns (IMarketRegistry.MarketState) { return _markets[marketId].state; }
    function getActiveMarkets() external view returns (bytes32[] memory) { return _active; }
    function getAllocationWeight(bytes32) external pure returns (uint256) { return 1e18; }
}

contract MockOILimits_ANF {
    mapping(bytes32 => int256) private _imbalanceRatio;
    mapping(bytes32 => uint256) private _longOI;
    mapping(bytes32 => uint256) private _shortOI;
    mapping(bytes32 => uint256) private _marketOICap;

    function setImbalanceRatio(bytes32 marketId, int256 ratio) external { _imbalanceRatio[marketId] = ratio; }
    function setOI(bytes32 marketId, uint256 longOI, uint256 shortOI) external {
        _longOI[marketId] = longOI;
        _shortOI[marketId] = shortOI;
    }
    function setMarketOICap(bytes32 marketId, uint256 cap) external { _marketOICap[marketId] = cap; }

    function getImbalanceRatio(bytes32 marketId) external view returns (int256) { return _imbalanceRatio[marketId]; }
    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256) {
        return isLong ? _longOI[marketId] : _shortOI[marketId];
    }
    function getMarketOICap(bytes32 marketId) external view returns (uint256) { return _marketOICap[marketId]; }
    function getMarketOI(bytes32) external pure returns (uint256) { return 0; }
    function getGlobalOI() external pure returns (uint256) { return 0; }
    function getUserOI(bytes32, address) external pure returns (uint256) { return 0; }
    function increaseOI(bytes32, address, bool, uint256) external {}
    function decreaseOI(bytes32, address, bool, uint256) external {}
}

contract MockPositionManager_ANF {
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

    function closePosition(uint256 positionId) external { _positions[positionId].isOpen = false; }
    function updateCollateral(uint256 positionId, uint256 newCollateral) external { _positions[positionId].collateral = newCollateral; }
    function getPosition(uint256 positionId) external view returns (IPositionManager.Position memory) { return _positions[positionId]; }
    function isPositionOpen(uint256 positionId) external view returns (bool) { return _positions[positionId].isOpen; }
}

/// @notice Tracks calls and USDT balance (simulates USDT arriving via transfer)
contract MockAccountManager_ANF {
    mapping(address => uint256) public balances;
    mapping(address => uint256) public locked;

    // Track transferOut calls: to => amount
    address public lastTransferTo;
    uint256 public lastTransferAmount;
    uint256 public transferOutCallCount;

    function setBalance(address user, uint256 amount) external { balances[user] = amount; }

    function lockCollateral(address user, uint256 amount) external { locked[user] += amount; }
    function releaseCollateral(address user, uint256 amount) external { if (locked[user] >= amount) locked[user] -= amount; }
    function creditPnL(address user, uint256 amount) external { balances[user] += amount; }
    function debitPnL(address user, uint256 amount) external returns (uint256 badDebt) {
        if (amount > balances[user]) {
            badDebt = amount - balances[user];
            balances[user] = 0;
        } else {
            balances[user] -= amount;
        }
    }
    function transferOut(address to, uint256 amount) external {
        lastTransferTo = to;
        lastTransferAmount = amount;
        transferOutCallCount++;
    }
    function assignPosition(address, uint256) external {}
    function removePosition(address, uint256) external {}
    function getBalance(address user) external view returns (uint256) { return balances[user]; }
    function getFreeCollateral(address user) external view returns (uint256) { return balances[user] >= locked[user] ? balances[user] - locked[user] : 0; }
    function getLockedCollateral(address user) external view returns (uint256) { return locked[user]; }
    function getUserPositions(address) external pure returns (uint256[] memory) { return new uint256[](0); }
}

/// @notice Tracks receiveUnmatchedFunding calls and amounts received
contract MockRewardsDistributor_ANF {
    bytes32 public lastMarketId;
    uint256 public lastAmount;
    uint256 public receiveUnmatchedFundingCallCount;
    uint256 public depositRewardsCallCount;
    uint256 public usdtReceived; // Track USDT balance received

    function receiveUnmatchedFunding(bytes32 marketId, uint256 amount) external {
        lastMarketId = marketId;
        lastAmount = amount;
        receiveUnmatchedFundingCallCount++;
        usdtReceived += amount;
    }

    function depositRewards(uint256) external {
        depositRewardsCallCount++;
    }
}

contract MockFeeRouter_ANF {
    uint256 public constant TX_FEE_RATE = 1e15; // 0.10%
    uint256 public usdtReceived; // simulate USDT balance
    uint256 public routeFeesCallCount;
    bool public collectTransactionFeeCalled;

    function collectTransactionFee(uint256 notional) external returns (uint256) {
        collectTransactionFeeCalled = true;
        return (notional * TX_FEE_RATE) / 1e18;
    }

    function routeFees(IFeeRouter.FeeType, uint256 amount) external {
        routeFeesCallCount++;
        usdtReceived += amount;
    }
}

contract MockLeverVault_ANF {
    uint256 public totalAssets_;
    int256 private _netUnrealizedPnL;
    uint256 public fundCalls;
    uint256 public socializeLossCalls;

    function setTotalAssets(uint256 val) external { totalAssets_ = val; }
    function totalAssets() external view returns (uint256) { return totalAssets_; }
    function fundTraderPnL(address, uint256) external { fundCalls++; }
    function socializeLoss(uint256) external { socializeLossCalls++; }
    function updateUnrealizedPnL(int256 newPnL) external { _netUnrealizedPnL = newPnL; }
    function getNetUnrealizedPnL() external view returns (int256) { return _netUnrealizedPnL; }
}

contract MockInsuranceFund_ANF {
    function absorbBadDebt(bytes32, uint256 totalBadDebt, address) external pure returns (uint256, uint256) {
        return (totalBadDebt, 0);
    }
}

contract MockLeverageModel_ANF {
    uint256 private _maxLeverage = 30e18;
    function getEffectiveMaxLeverage(bytes32) external view returns (uint256) { return _maxLeverage; }
    function validateLeverage(bytes32, uint256 leverage) external view returns (bool) { return leverage <= _maxLeverage; }
}

contract MockMarginEngine_ANF {
    bool private _valid = true;
    uint8 private _failedCheck;

    function setValid(bool val, uint8 failedCheck_) external { _valid = val; _failedCheck = failedCheck_; }
    function validateMarginChecks(bytes32, address, bool, uint256, uint256) external view returns (bool, uint8) {
        return (_valid, _failedCheck);
    }
    function canRemoveCollateral(uint256, uint256) external pure returns (bool) { return true; }
}

contract MockOracleAdapter_ANF {
    mapping(bytes32 => uint256) private _pi;
    mapping(bytes32 => bool) private _frozen;

    function setPI(bytes32 marketId, uint256 pi) external { _pi[marketId] = pi; }
    function setFrozen(bytes32 marketId, bool frozen) external { _frozen[marketId] = frozen; }
    function getPI(bytes32 marketId) external view returns (uint256) { return _pi[marketId]; }
    function isFrozen(bytes32 marketId) external view returns (bool) { return _frozen[marketId]; }
}

contract MockBorrowFeeEngine_ANF {
    uint256 private _borrowIndex = 1e18;
    uint256 private _accruedFees;
    function setBorrowIndex(uint256 val) external { _borrowIndex = val; }
    function setAccruedFees(uint256 val) external { _accruedFees = val; }
    function getBorrowIndex(bytes32, bool) external view returns (uint256) { return _borrowIndex; }
    function getAccruedFees(uint256) external view returns (uint256) { return _accruedFees; }
}

contract MockFundingRateEngine_ANF {
    int256 private _fundingIndex;
    int256 private _accruedFunding;
    function setFundingIndex(int256 val) external { _fundingIndex = val; }
    function setAccruedFunding(int256 val) external { _accruedFunding = val; }
    function getFundingIndex(bytes32) external view returns (int256) { return _fundingIndex; }
    function getAccruedFunding(uint256) external view returns (int256) { return _accruedFunding; }
}

/// @notice Mock USDT with balance tracking
contract MockUSDT_ANF {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
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

// ──────────────────────────────────────────────────────────────────────────────
// Test Suite: LEVER-P01 through P06
// ──────────────────────────────────────────────────────────────────────────────

/// @title AuditNewFindingsTest
/// @notice Tests for audit fixes LEVER-P01 through LEVER-P06
contract AuditNewFindingsTest is Test {
    uint256 internal constant WAD = 1e18;

    // ── Shared contracts ──
    MockMarketRegistry_ANF registry;
    MockOILimits_ANF oiLimits;
    MockPositionManager_ANF positionManager;
    MockAccountManager_ANF accountManager;
    MockRewardsDistributor_ANF rewardsDistributor;
    MockUSDT_ANF usdt;
    MockLeverVault_ANF vault;

    address admin = address(this);
    bytes32 constant MARKET_A = keccak256("MARKET_A");

    function setUp() public {
        registry = new MockMarketRegistry_ANF();
        oiLimits = new MockOILimits_ANF();
        positionManager = new MockPositionManager_ANF();
        accountManager = new MockAccountManager_ANF();
        rewardsDistributor = new MockRewardsDistributor_ANF();
        usdt = new MockUSDT_ANF();
        vault = new MockLeverVault_ANF();
        vault.setTotalAssets(25_000_000e6);

        // Market A: 48h to resolution, not live
        registry.setMarket(MARKET_A, 48e18, false);
        registry.addActiveMarket(MARKET_A);
        oiLimits.setImbalanceRatio(MARKET_A, 0);
        oiLimits.setOI(MARKET_A, 500e18, 500e18);
        oiLimits.setMarketOICap(MARKET_A, 1_000_000e18);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P01: FundingRateEngine depthThreshold guard
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice When depthThreshold is 0 (not configured), accrueFunding must NOT revert
    /// and must compute with mMarket = WAD (no depth adjustment).
    function test_LEVER_P01_fundingEngineDepthThresholdGuard() public {
        FundingRateEngine engine = new FundingRateEngine(
            admin,
            address(registry),
            address(oiLimits),
            address(positionManager),
            address(accountManager),
            address(rewardsDistributor)
        );

        // Initialize market WITHOUT setting any depth risk params (depthThreshold stays 0)
        engine.initializeMarketIndex(MARKET_A);

        // No risk params set: depthThreshold[MARKET_A] == 0
        assertEq(engine.depthThreshold(MARKET_A), 0, "depthThreshold should be 0 by default");

        // Advance time so accrueFunding actually does work
        vm.warp(block.timestamp + 3600);

        // Must NOT revert (previously would revert with ZeroDepthThreshold)
        engine.accrueFunding(MARKET_A);

        // Verify funding index was updated (accrual happened)
        // With balanced OI (imbalanceRatio = 0), rate = 0, index stays 0
        assertEq(engine.getFundingIndex(MARKET_A), 0, "Index should remain 0 for balanced OI");

        // Verify multiplier is computed (indirectly: getFundingMultiplier must not revert)
        uint256 multiplier = engine.getFundingMultiplier(MARKET_A);
        // With mMarket = WAD (no adjustment), rAdj is purely from tau curve
        // multiplier = 1.0 + (4.0 - 1.0) × (1 - rAdj) > 0
        assertGt(multiplier, 0, "Multiplier must be computed without reverting");

        // Verify current funding rate is also safe to call
        int256 rate = engine.getCurrentFundingRate(MARKET_A);
        // Balanced OI -> rate should be 0
        assertEq(rate, 0, "Balanced OI should produce zero funding rate");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P02: BorrowFeeEngine depthThreshold guard
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice When depthThreshold is 0 (not configured), getCurrentBorrowRate must NOT revert
    function test_LEVER_P02_borrowEngineDepthThresholdGuard() public {
        BorrowFeeEngine engine = new BorrowFeeEngine(
            admin,
            address(registry),
            address(oiLimits),
            address(positionManager)
        );

        // Initialize market WITHOUT setting depth risk params (depthThreshold stays 0)
        engine.initializeMarketIndex(MARKET_A);
        assertEq(engine.depthThreshold(MARKET_A), 0, "depthThreshold should be 0 by default");

        // getCurrentBorrowRate must NOT revert
        uint256 longRate = engine.getCurrentBorrowRate(MARKET_A, true);
        uint256 shortRate = engine.getCurrentBorrowRate(MARKET_A, false);

        assertGt(longRate, 0, "Long borrow rate must be positive");
        assertGt(shortRate, 0, "Short borrow rate must be positive");

        // Advance time and call accrueIndex — must not revert
        vm.warp(block.timestamp + 3600);
        engine.accrueIndex(MARKET_A, true);
        engine.accrueIndex(MARKET_A, false);

        uint256 longIdx = engine.getBorrowIndex(MARKET_A, true);
        uint256 shortIdx = engine.getBorrowIndex(MARKET_A, false);

        // Index should have grown from WAD (accrual happened)
        assertGe(longIdx, WAD, "Long index must be at least WAD");
        assertGe(shortIdx, WAD, "Short index must be at least WAD");

        // Also verify accrueAll doesn't revert when depthThreshold is 0
        vm.warp(block.timestamp + 3600);
        engine.accrueAll();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P03: openPosition uses direct fee routing (not collectTransactionFee)
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Opening a position must:
    ///   1. Debit the tx fee from user's accounting (debitPnL)
    ///   2. Transfer USDT to FeeRouter via accountManager.transferOut
    ///   3. NOT call feeRouter.collectTransactionFee
    function test_LEVER_P03_openFeeUsesDirectRouting() public {
        MockFeeRouter_ANF feeRouter = new MockFeeRouter_ANF();
        MockMarginEngine_ANF marginEngine = new MockMarginEngine_ANF();
        MockOracleAdapter_ANF oracleAdapter = new MockOracleAdapter_ANF();
        MockLeverageModel_ANF leverageModel = new MockLeverageModel_ANF();
        MockBorrowFeeEngine_ANF borrowFeeEngine = new MockBorrowFeeEngine_ANF();
        MockFundingRateEngine_ANF fundingRateEngine = new MockFundingRateEngine_ANF();
        MockInsuranceFund_ANF insuranceFund = new MockInsuranceFund_ANF();

        ExecutionEngine execEngine = new ExecutionEngine(
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

        oracleAdapter.setPI(MARKET_A, 5e17); // PI = 0.50

        address trader = address(0xB1);
        uint256 collateral = 1_000e18; // $1,000 collateral
        uint256 leverage = 2e18;       // 2x
        // notional = 1000 * 2 = 2000e18
        // txFee = 2000e18 * 1e15 / 1e18 = 2e18

        accountManager.setBalance(trader, collateral);

        vm.prank(trader);
        uint256 positionId = execEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: MARKET_A,
                isLong: true,
                collateral: collateral,
                leverage: leverage
            })
        );

        assertGt(positionId, 0, "Position must be created");

        // Verify: collectTransactionFee was NEVER called on feeRouter
        bool collectCalled = feeRouter.collectTransactionFeeCalled();
        assertTrue(!collectCalled, "collectTransactionFee must NOT be called");

        // Verify: accountManager.transferOut was called (fee went to feeRouter)
        uint256 transferCount = accountManager.transferOutCallCount();
        assertTrue(transferCount > 0, "transferOut must be called to send fee to FeeRouter");
        assertEq(accountManager.lastTransferTo(), address(feeRouter), "Fee must be transferred to FeeRouter");

        // Verify: feeRouter.routeFees was called (the fee was actually routed)
        uint256 routeCount = feeRouter.routeFeesCallCount();
        assertTrue(routeCount > 0, "routeFees must be called");

        // Verify: fee amount is correct (2000e18 * 0.10% = 2e18)
        uint256 expectedFee = 2_000e18 * 1e15 / WAD;
        assertEq(accountManager.lastTransferAmount(), expectedFee, "Fee amount must match 0.10% of notional");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P04: InsuranceFund absorbBadDebt sends USDT to vault (not caller)
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice absorbBadDebt must transfer USDT to the specified recipient (vault),
    ///         not to msg.sender (ExecutionEngine/LiquidationEngine).
    function test_LEVER_P04_insuranceBadDebtGoesToVault() public {
        InsuranceFund fund = new InsuranceFund(admin, address(usdt), address(vault));

        // Grant roles
        vm.startPrank(admin);
        fund.grantRole(fund.EXECUTION_ENGINE_ROLE(), address(this));
        fund.grantRole(fund.FEE_ROUTER_ROLE(), address(this));
        vm.stopPrank();

        // BUG-4: Constructor no longer has phantom bootstrap. Explicitly fund.
        uint256 bootstrapAmount = 10_000e6;
        usdt.mint(address(fund), bootstrapAmount); // actual USDT tokens
        fund.deposit(bootstrapAmount);              // accounting update

        vault.setTotalAssets(50_000e6); // $50K TVL
        // IFR = 10_000e6 / 50_000e6 = 20% => tier 1 => 100% insurance coverage
        // daily cap = 25% of 10_000e6 = 2_500e6
        // floor = 5% of 50_000e6 = 2_500e6
        // maxSpend = 10_000e6 - 2_500e6 = 7_500e6

        uint256 badDebtAmountWAD = 1_000e18; // $1000 in WAD

        address mockVault = address(0xBEEF);
        uint256 vaultBalanceBefore = usdt.balanceOf(mockVault);

        (uint256 insurancePaidWAD, uint256 remainderWAD) = fund.absorbBadDebt(
            MARKET_A,
            badDebtAmountWAD,
            mockVault
        );

        uint256 vaultBalanceAfter = usdt.balanceOf(mockVault);

        assertGt(insurancePaidWAD, 0, "InsuranceFund must pay some amount (WAD)");
        assertEq(remainderWAD, badDebtAmountWAD - insurancePaidWAD, "Remainder must equal badDebt - paid");

        // USDT transferred = insurancePaidWAD / SCALE (1e12)
        uint256 insurancePaidUSDT = insurancePaidWAD / 1e12;

        // USDT must go to mockVault (recipient), NOT to address(this) (caller)
        assertEq(vaultBalanceAfter - vaultBalanceBefore, insurancePaidUSDT, "Vault must receive the USDT");

        // InsuranceFund accounting balance must decrease (USDT scale)
        uint256 fundBalanceAfter = fund.getBalance();
        assertEq(fundBalanceAfter, bootstrapAmount - insurancePaidUSDT, "Fund balance must decrease by amount paid");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P05: routeUnmatchedFunding calls receiveUnmatchedFunding, not depositRewards
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice routeUnmatchedFunding must call rewardsDistributor.receiveUnmatchedFunding,
    ///         NOT depositRewards. USDT must be transferred via accountManager.transferOut.
    function test_LEVER_P05_routeUnmatchedFundingCallsCorrectFunction() public {
        FundingRateEngine engine = new FundingRateEngine(
            admin,
            address(registry),
            address(oiLimits),
            address(positionManager),
            address(accountManager),
            address(rewardsDistributor)
        );

        // Initialize market with unmatched OI to generate pending funding
        engine.initializeMarketIndex(MARKET_A);

        // Set up significant OI imbalance: 800 long vs 200 short
        oiLimits.setOI(MARKET_A, 800e18, 200e18);
        oiLimits.setImbalanceRatio(MARKET_A, int256(6e17)); // 60% imbalance (long-heavy)

        // Advance time by 1 hour to accrue funding
        vm.warp(block.timestamp + 3600);
        engine.accrueFunding(MARKET_A);

        uint256 pendingBefore = engine.getPendingUnmatchedFunding(MARKET_A);
        assertGt(pendingBefore, 0, "Must have pending unmatched funding after accrual");

        // Route the unmatched funding
        engine.routeUnmatchedFunding(MARKET_A);

        // Verify: receiveUnmatchedFunding was called (NOT depositRewards)
        assertEq(
            rewardsDistributor.receiveUnmatchedFundingCallCount(),
            1,
            "receiveUnmatchedFunding must be called exactly once"
        );
        assertEq(
            rewardsDistributor.depositRewardsCallCount(),
            0,
            "depositRewards must NOT be called"
        );

        // Verify: correct market ID and amount were passed
        assertEq(rewardsDistributor.lastMarketId(), MARKET_A, "Market ID must match");
        assertEq(rewardsDistributor.lastAmount(), pendingBefore, "Amount must match pending funding");

        // Verify: USDT was transferred via accountManager.transferOut to RewardsDistributor
        assertTrue(accountManager.transferOutCallCount() > 0, "transferOut must be called");
        assertEq(
            accountManager.lastTransferTo(),
            address(rewardsDistributor),
            "USDT must be transferred to RewardsDistributor"
        );
        assertEq(
            accountManager.lastTransferAmount(),
            pendingBefore,
            "Transfer amount must equal pending funding"
        );

        // Verify: pending funding is now cleared
        assertEq(engine.getPendingUnmatchedFunding(MARKET_A), 0, "Pending funding must be zeroed after routing");

        // Verify: cannot route again (no pending funding)
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("FundingRateEngine__NoUnmatchedFunding(bytes32)")),
                MARKET_A
            )
        );
        engine.routeUnmatchedFunding(MARKET_A);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LEVER-P06: updateUnrealizedPnL is called on position close
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice When a position is closed with a profit, the vault's net unrealized PnL
    ///         must be updated to remove that position's contribution.
    function test_LEVER_P06_updateUnrealizedPnLCalledOnClose() public {
        MockFeeRouter_ANF feeRouter = new MockFeeRouter_ANF();
        MockMarginEngine_ANF marginEngine = new MockMarginEngine_ANF();
        MockOracleAdapter_ANF oracleAdapter = new MockOracleAdapter_ANF();
        MockLeverageModel_ANF leverageModel = new MockLeverageModel_ANF();
        MockBorrowFeeEngine_ANF borrowFeeEngine = new MockBorrowFeeEngine_ANF();
        MockFundingRateEngine_ANF fundingRateEngine = new MockFundingRateEngine_ANF();
        MockInsuranceFund_ANF insuranceFund = new MockInsuranceFund_ANF();

        ExecutionEngine execEngine = new ExecutionEngine(
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

        address trader = address(0xC1);
        uint256 entryPI = 5e17;   // PI = 0.50 at open
        uint256 exitPI  = 7e17;   // PI = 0.70 at close (trader profitable)

        oracleAdapter.setPI(MARKET_A, entryPI);

        uint256 collateral = 1_000e18;
        uint256 leverage = 2e18;
        // notional = 2_000e18
        // txFee = 2_000e18 * 0.10% = 2e18
        // collateralNet = 998e18

        accountManager.setBalance(trader, collateral);

        // Open position
        vm.prank(trader);
        uint256 positionId = execEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: MARKET_A,
                isLong: true,
                collateral: collateral,
                leverage: leverage
            })
        );

        // Simulate that the vault's unrealized PnL was set to +$400 before close
        // (this represents other positions' running PnL plus this position's)
        int256 simulatedUnrealizedPnL = 400e18;
        vault.updateUnrealizedPnL(simulatedUnrealizedPnL);
        assertEq(vault.getNetUnrealizedPnL(), simulatedUnrealizedPnL, "Setup: vault PnL should be 400");

        // Move PI to 0.70 for a profitable close
        oracleAdapter.setPI(MARKET_A, exitPI);

        // Get position details to compute expected PnL
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        // PnL = (exitPI - entryPI) * positionSize / WAD
        // = (0.70 - 0.50) * 2000e18 / 1e18 = 400e18
        int256 expectedPnL = (int256(exitPI) - int256(pos.entryPI)) * int256(pos.positionSize) / int256(WAD);

        // Close position
        vm.prank(trader);
        execEngine.closePosition(positionId);

        // Verify: vault's net unrealized PnL was updated
        // New PnL = old PnL - realized PnL of this position
        // = 400e18 - 400e18 = 0
        int256 expectedNewPnL = simulatedUnrealizedPnL - expectedPnL;
        int256 actualNewPnL = vault.getNetUnrealizedPnL();

        assertEq(
            actualNewPnL,
            expectedNewPnL,
            "Vault unrealized PnL must be reduced by closed position's PnL"
        );

        // Verify the position is actually closed
        assertFalse(
            positionManager.getPosition(positionId).isOpen,
            "Position must be closed"
        );
    }
}

