// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

// Real contracts
import { MarketRegistry } from "../../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../../contracts/core/OracleAdapter.sol";
import { PositionManager } from "../../contracts/core/PositionManager.sol";
import { AccountManager } from "../../contracts/core/AccountManager.sol";
import { ExecutionEngine } from "../../contracts/ExecutionEngine.sol";
import { MarginEngine } from "../../contracts/MarginEngine.sol";
import { BorrowFeeEngine } from "../../contracts/BorrowFeeEngine.sol";
import { FundingRateEngine } from "../../contracts/FundingRateEngine.sol";
import { LeverageModel } from "../../contracts/LeverageModel.sol";
import { OILimits } from "../../contracts/OILimits.sol";

// Interfaces
import { IMarketRegistry } from "../../contracts/interfaces/IMarketRegistry.sol";
import { IOracleAdapter } from "../../contracts/interfaces/IOracleAdapter.sol";
import { IPositionManager } from "../../contracts/interfaces/IPositionManager.sol";
import { IExecutionEngine } from "../../contracts/interfaces/IExecutionEngine.sol";
import { IMarginEngine } from "../../contracts/interfaces/IMarginEngine.sol";
import { ILeverVault } from "../../contracts/interfaces/ILeverVault.sol";
import { IInsuranceFund } from "../../contracts/interfaces/IInsuranceFund.sol";
import { IFeeRouter } from "../../contracts/interfaces/IFeeRouter.sol";
import { IRewardsDistributor } from "../../contracts/interfaces/IRewardsDistributor.sol";

import { FixedPointMath } from "../../contracts/libraries/FixedPointMath.sol";

// ─────────────────────────────────────────────────
// Lightweight mocks for leaf dependencies
// ─────────────────────────────────────────────────

/// @dev Mock ERC20 for USDT
contract MockUSDT {
    string public name = "Mock USDT";
    string public symbol = "USDT";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
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

/// @dev Mock LeverVault — provides TVL (totalAssets) and utilization for LeverageModel and OILimits
contract MockLeverVault {
    uint256 private _totalAssets;
    uint256 private _utilization;
    uint256 private _nav;

    function setTotalAssets(uint256 val) external { _totalAssets = val; }
    function setUtilization(uint256 val) external { _utilization = val; }
    function setNAV(uint256 val) external { _nav = val; }

    function totalAssets() external view returns (uint256) { return _totalAssets; }
    function getNAV() external view returns (uint256) { return _nav > 0 ? _nav : _totalAssets; }
    function getUtilization() external view returns (uint256) { return _utilization; }
    function withdrawalsEnabled() external pure returns (bool) { return true; }
    function socializeLoss(uint256) external {}
    function fundTraderPnL(address, uint256) external {}

    // ERC4626 stubs needed by some contracts
    function asset() external pure returns (address) { return address(0); }
    function totalSupply() external view returns (uint256) { return _totalAssets; }
}

/// @dev Mock InsuranceFund — provides balance and IFR for LeverageModel
contract MockInsuranceFund {
    uint256 private _balance;
    uint256 private _tvl;

    constructor() {
        _balance = 10_000e18; // INSURANCE_BOOTSTRAP
    }

    function setBalance(uint256 val) external { _balance = val; }
    function setTVL(uint256 val) external { _tvl = val; }

    function getBalance() external view returns (uint256) { return _balance; }
    function getIFR() external view returns (uint256) {
        if (_tvl == 0) return 0;
        return (_balance * 1e18) / _tvl;
    }
    function deposit(uint256 amount) external { _balance += amount; }
    function absorbBadDebt(bytes32, uint256 totalBadDebt)
        external returns (uint256 insurancePaid, uint256 remainder)
    {
        if (totalBadDebt <= _balance) {
            _balance -= totalBadDebt;
            return (totalBadDebt, 0);
        } else {
            uint256 paid = _balance;
            _balance = 0;
            return (paid, totalBadDebt - paid);
        }
    }
    function getCurrentTier() external pure returns (uint8, uint256, uint256) {
        return (1, 1e18, 0);
    }
    function getRemainingDailyCapacity() external view returns (uint256) { return _balance / 4; }
    function getFloor() external pure returns (uint256) { return 0; }
    function getTarget() external pure returns (uint256) { return 0; }
    function isFullyFunded() external pure returns (bool) { return false; }
    function totalAbsorbed() external pure returns (uint256) { return 0; }
}

/// @dev Mock FeeRouter — collectTransactionFee returns 10bps of notional without token transfers
contract MockFeeRouter {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;
    uint256 constant TX_FEE_RATE = 1e15; // 0.10% = 10 bps

    uint256 public totalFeesCollected;

    function collectTransactionFee(uint256 notional) external returns (uint256 fee) {
        fee = notional.wadMul(TX_FEE_RATE);
        totalFeesCollected += fee;
    }

    function routeFees(uint8, uint256 amount) external {
        totalFeesCollected += amount;
    }

    function getCurrentTier() external pure returns (uint8) { return 1; }
    function getCurrentSplit() external pure returns (uint256, uint256, uint256) {
        return (5e17, 3e17, 2e17);
    }
    function previewSplit(uint256 amount) external pure returns (uint256, uint256, uint256) {
        return (amount * 50 / 100, amount * 30 / 100, amount * 20 / 100);
    }
    function getTotalFeesRouted(uint8) external pure returns (uint256) { return 0; }
    function protocolTreasury() external pure returns (address) { return address(0xDEAD); }
}

// ─────────────────────────────────────────────────
// Integration Test Base
// ─────────────────────────────────────────────────

/// @title IntegrationBase
/// @notice Shared base for integration tests. Deploys real core contracts + lightweight mocks.
abstract contract IntegrationBase is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    // ── Addresses ──
    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xA2);
    address keeper = address(0xBE);
    address oracle = address(0x0AC);

    // ── Test market ──
    bytes32 marketId = keccak256("ELECTION_2028");
    uint256 marketResolutionTime;

    // ── Real contracts ──
    MarketRegistry public registry;
    OracleAdapter public oracleAdapter;
    PositionManager public positionManager;
    AccountManager public accountManager;
    ExecutionEngine public executionEngine;
    MarginEngine public marginEngine;
    BorrowFeeEngine public borrowFeeEngine;
    FundingRateEngine public fundingRateEngine;
    LeverageModel public leverageModel;
    OILimits public oiLimits;

    // ── Mock contracts ──
    MockUSDT public usdt;
    MockLeverVault public vault;
    MockInsuranceFund public insuranceFund;
    MockFeeRouter public feeRouter;

    function setUp() public virtual {
        vm.startPrank(admin);

        // ── 1. Deploy token + mocks ──
        usdt = new MockUSDT();
        vault = new MockLeverVault();
        insuranceFund = new MockInsuranceFund();
        feeRouter = new MockFeeRouter();

        // Set realistic TVL for leverage/OI calculations
        vault.setTotalAssets(10_000_000e18); // $10M TVL
        insuranceFund.setTVL(10_000_000e18);
        insuranceFund.setBalance(2_000_000e18); // 20% IFR

        // ── 2. Deploy core contracts (dependency order) ──
        registry = new MarketRegistry(admin);
        oracleAdapter = new OracleAdapter(admin, address(registry));
        positionManager = new PositionManager(admin);
        accountManager = new AccountManager(admin, address(usdt));

        // ── 3. Deploy OILimits first (needed by fee engines) ──
        oiLimits = new OILimits(address(registry), address(vault), admin);

        // ── 4. Deploy fee engines ──
        borrowFeeEngine = new BorrowFeeEngine(admin, address(registry), address(oiLimits), address(positionManager));
        fundingRateEngine = new FundingRateEngine(admin, address(registry), address(oiLimits), address(positionManager));

        // ── 5. Deploy MarginEngine ──
        marginEngine = new MarginEngine(
            admin,
            address(positionManager),
            address(oracleAdapter),
            address(registry),
            address(borrowFeeEngine),
            address(fundingRateEngine)
        );

        // ── 6. Deploy LeverageModel ──
        leverageModel = new LeverageModel(
            address(vault),
            address(insuranceFund),
            address(oiLimits),
            address(registry),
            address(oracleAdapter),
            admin
        );

        // ── 7. Deploy ExecutionEngine ──
        executionEngine = new ExecutionEngine(
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
            admin
        );

        // ── 8. Grant roles ──
        _grantAllRoles();

        // ── 9. Set up test market ──
        _setupTestMarket();

        vm.stopPrank();
    }

    function _grantAllRoles() internal {
        // PositionManager: ENGINE role to ExecutionEngine
        positionManager.grantRole(positionManager.ENGINE(), address(executionEngine));

        // AccountManager: ENGINE role to ExecutionEngine
        accountManager.grantRole(accountManager.ENGINE(), address(executionEngine));

        // OILimits: engine roles
        oiLimits.grantRole(oiLimits.EXECUTION_ENGINE_ROLE(), address(executionEngine));

        // FeeRouter: EXECUTION_ENGINE_ROLE (mock doesn't use roles, but keep for real FeeRouter tests)

        // OracleAdapter roles
        oracleAdapter.grantRole(oracleAdapter.ORACLE(), oracle);
        oracleAdapter.grantRole(oracleAdapter.KEEPER(), keeper);

        // Register oracle as an active source (required by pushPrice)
        oracleAdapter.registerSource(oracle, 1e18);
    }

    function _setupTestMarket() internal {
        // Create market: resolution in 48 hours
        marketResolutionTime = block.timestamp + 48 hours;

        registry.createMarket(
            marketId,
            "US Election 2028",
            "polymarket_election_2028",
            marketResolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            2e17 // 20% allocation weight
        );

        // Activate market
        registry.activateMarket(marketId);

        // Initialize fee engine indices for this market
        borrowFeeEngine.initializeMarketIndex(marketId);
        fundingRateEngine.initializeMarketIndex(marketId);

        // Set market risk params (depthThreshold must be > 0 to avoid RiskCurves__ZeroDepthThreshold)
        // Using baseline volatility values: sigmaCurrent=sigmaBaseline=0.1, depth=$100k, depthThreshold=$50k
        borrowFeeEngine.updateMarketRiskParams(
            marketId,
            1e17,       // sigmaCurrent = 0.1
            1e17,       // sigmaBaseline = 0.1
            100_000e18, // externalDepth = $100k
            100_000e18, // depthThreshold = $100k (= externalDepth, so depth_factor = 1.0)
            0,          // marketOI = 0 (no positions yet)
            0           // globalOI = 0
        );
        fundingRateEngine.updateMarketRiskParams(
            marketId,
            1e17,       // sigmaCurrent = 0.1
            1e17,       // sigmaBaseline = 0.1
            100_000e18, // externalDepth = $100k
            100_000e18, // depthThreshold = $100k (= externalDepth, so depth_factor = 1.0)
            0,          // marketOI = 0
            0           // globalOI = 0
        );
        marginEngine.updateMarketRiskParams(
            marketId,
            1e17,       // sigmaCurrent = 0.1
            1e17,       // sigmaBaseline = 0.1
            100_000e18, // externalDepth = $100k
            100_000e18, // depthThreshold = $100k (= externalDepth, so depth_factor = 1.0)
            0,          // marketOI = 0
            0,          // globalOI = 0
            0           // marketUtilization = 0
        );
        leverageModel.setMarketRiskParams(
            marketId,
            1e17,       // sigmaBaseline = 0.1
            100_000e18  // depthThreshold = $100k (= externalDepth, so depth_factor = 1.0)
        );

        // Set up smoothing params for the oracle
        oracleAdapter.updateSmoothingParams(marketId, IOracleAdapter.SmoothingParams({
            alpha: 3e17,       // 0.3 base smoothing
            deltaMax: 1e17,    // 10% max tick
            epsilon: 5e16,     // 5% max change per update
            spreadLimit: 5e16, // 5% max spread
            depthMin: 1e18     // $1 min depth
        }));

        // Push initial price (PI = 0.50)
        vm.stopPrank();
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId,
            5e17,       // pYes = 0.50
            5e17,       // pNo = 0.50
            1e16,       // spread = 1%
            100_000e18, // depth = $100k
            50_000e18   // volume = $50k
        );
        vm.startPrank(admin);
    }

    // ─── Helper: Push a new PI ───
    function _pushPI(uint256 newPI) internal {
        vm.prank(oracle);
        oracleAdapter.pushPrice(
            marketId,
            newPI,
            WAD - newPI,
            1e16,       // 1% spread
            100_000e18, // $100k depth
            50_000e18   // $50k volume
        );
    }

    // ─── Helper: Fund a user's AccountManager balance with USDT ───
    function _fundUser(address user, uint256 amount) internal {
        usdt.mint(user, amount);
        vm.startPrank(user);
        usdt.approve(address(accountManager), amount);
        accountManager.deposit(amount);
        vm.stopPrank();
    }

    // ─── Helper: Open a position as a specific user ───
    /// @dev Automatically funds the user's AccountManager if needed
    function _openPosition(
        address user,
        bool isLong,
        uint256 collateral,
        uint256 leverage
    ) internal returns (uint256 positionId) {
        // Ensure user has enough balance in AccountManager
        uint256 currentFree = accountManager.getFreeCollateral(user);
        if (currentFree < collateral) {
            _fundUser(user, collateral - currentFree);
        }

        vm.prank(user);
        positionId = executionEngine.openPosition(
            IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: collateral,
                leverage: leverage
            })
        );
    }

    // ─── Helper: Close a position as the owner ───
    function _closePosition(address user, uint256 positionId) internal {
        vm.prank(user);
        executionEngine.closePosition(positionId);
    }
}
