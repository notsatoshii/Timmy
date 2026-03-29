// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Custom Errors
// (defined in IInsuranceFund + additional below)

// 3. Events
// (defined in IInsuranceFund)

/// @title InsuranceFund
/// @notice Bad debt absorption mechanism funded by 20% of protocol fees (via FeeRouter).
///         Three simultaneous constraints protect the fund from depletion:
///         1. Daily cap: max 25% of balance per rolling 24h window
///         2. Tiered insurance/ADL split based on IFR level
///         3. Floor: fund never drops below 5% of TVL
///         Bootstrapped at $10,000 at launch.
contract InsuranceFund is IInsuranceFund, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    // FIX LEVER-003: Use USDT-denomination (6 decimals) instead of WAD
    uint256 public constant INSURANCE_BOOTSTRAP = 10_000e6;
    uint256 public constant DAILY_CAP_PCT = 25e16;          // 25% of balance
    uint256 public constant IFR_FLOOR = 5e16;               // 5% of TVL
    uint256 public constant IFR_TARGET = 2e17;              // 20% of TVL
    uint256 public constant TIER_1_THRESHOLD = 15e16;       // 15% IFR
    uint256 public constant TIER_2_THRESHOLD = 1e17;        // 10% IFR
    uint256 public constant TIER_3_THRESHOLD = 5e16;        // 5% IFR
    uint256 public constant WAD = 1e18;
    uint256 public constant DAILY_WINDOW = 24 hours;
    /// @notice Scale factor: WAD / USDT = 1e18 / 1e6. Converts between WAD and USDT scales.
    uint256 public constant SCALE = 1e12;

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant FEE_ROUTER_ROLE = keccak256("FEE_ROUTER_ROLE");
    bytes32 public constant EXECUTION_ENGINE_ROLE = keccak256("EXECUTION_ENGINE_ROLE");
    bytes32 public constant LIQUIDATION_ENGINE_ROLE = keccak256("LIQUIDATION_ENGINE_ROLE");
    bytes32 public constant SETTLEMENT_ENGINE_ROLE = keccak256("SETTLEMENT_ENGINE_ROLE");

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IERC20 public immutable usdt;
    ILeverVault public immutable leverVault;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    uint256 private _balance;
    uint256 private _dailySpent;
    uint256 private _dailyWindowStart;
    uint256 private _totalAbsorbed;

    // ──────────────────────────────────────────────
    // Custom Errors (beyond interface)
    // ──────────────────────────────────────────────

    error InsuranceFund__ZeroAddress();
    error InsuranceFund__ZeroAmount();

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin_ Admin address
    /// @param usdt_ USDT token address
    /// @param leverVault_ LeverVault contract (for TVL)
    constructor(address admin_, address usdt_, address leverVault_) {
        if (admin_ == address(0)) revert InsuranceFund__ZeroAddress();
        if (usdt_ == address(0)) revert InsuranceFund__ZeroAddress();
        if (leverVault_ == address(0)) revert InsuranceFund__ZeroAddress();

        usdt = IERC20(usdt_);
        leverVault = ILeverVault(leverVault_);

        _balance = 0; // FIX LEVER-BUG-4: No phantom bootstrap. Real USDT enters via FeeRouter.deposit().
        _dailyWindowStart = block.timestamp;

        _grantRole(ADMIN_ROLE, admin_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IInsuranceFund
    function deposit(uint256 amount) external override nonReentrant whenNotPaused {
        _checkRole(FEE_ROUTER_ROLE, msg.sender);
        if (amount == 0) revert InsuranceFund__ZeroAmount();

        _balance += amount;

        emit FundsDeposited(amount, _balance, block.timestamp);
    }

    /// @inheritdoc IInsuranceFund
    function absorbBadDebt(bytes32 marketId, uint256 totalBadDebt, address recipient)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 insurancePaid, uint256 remainder)
    {
        if (
            !hasRole(EXECUTION_ENGINE_ROLE, msg.sender)
                && !hasRole(LIQUIDATION_ENGINE_ROLE, msg.sender)
                && !hasRole(SETTLEMENT_ENGINE_ROLE, msg.sender)
        ) {
            revert AccessControlUnauthorizedAccount(msg.sender, LIQUIDATION_ENGINE_ROLE);
        }

        if (totalBadDebt == 0) return (0, 0);

        // FIX LEVER-BUG-5: Scale _balance (USDT, 6-decimal) to WAD for all comparison math.
        // totalBadDebt arrives in WAD from callers. All constraints must compare WAD vs WAD.
        uint256 balanceWAD = _balance * SCALE;

        // 1. Reset daily window if expired
        if (block.timestamp >= _dailyWindowStart + DAILY_WINDOW) {
            _dailySpent = 0;
            _dailyWindowStart = block.timestamp;
            emit DailyCapReset(balanceWAD.wadMul(DAILY_CAP_PCT), block.timestamp);
        }

        // 2. Determine tier (insurance vs ADL split)
        uint256 ifr = _getIFR();
        uint256 insurancePct;
        if (ifr > TIER_1_THRESHOLD) {
            insurancePct = WAD; // 100% insurance
        } else if (ifr > TIER_2_THRESHOLD) {
            insurancePct = 7e17; // 70% insurance
        } else if (ifr > TIER_3_THRESHOLD) {
            insurancePct = 4e17; // 40% insurance
        } else {
            insurancePct = 1e17; // 10% insurance
        }

        // 3. Insurance's share of this bad debt event (all WAD)
        uint256 insuranceTarget = totalBadDebt.wadMul(insurancePct);

        // 4. Apply daily cap constraint (all WAD)
        uint256 dailyCap = balanceWAD.wadMul(DAILY_CAP_PCT);
        uint256 dailySpentWAD = _dailySpent * SCALE;
        uint256 dailyRemaining = dailyCap > dailySpentWAD ? dailyCap - dailySpentWAD : 0;
        if (insuranceTarget > dailyRemaining) {
            insuranceTarget = dailyRemaining;
        }

        // 5. Apply floor constraint (fund cannot drop below 5% of TVL, all WAD)
        uint256 tvl = leverVault.totalAssets();
        uint256 tvlWAD = tvl * SCALE;
        uint256 floor = tvlWAD.wadMul(IFR_FLOOR);
        uint256 maxSpend = balanceWAD > floor ? balanceWAD - floor : 0;
        if (insuranceTarget > maxSpend) {
            insuranceTarget = maxSpend;
        }

        // 6. Cannot spend more than balance (WAD)
        if (insuranceTarget > balanceWAD) {
            insuranceTarget = balanceWAD;
        }

        // 7. Final amounts (all WAD, matches interface NatSpec)
        insurancePaid = insuranceTarget;
        remainder = totalBadDebt > insurancePaid ? totalBadDebt - insurancePaid : 0;

        // 8. Convert to USDT for actual token operations (single conversion point)
        uint256 transferUSDT = insurancePaid / SCALE;

        // 9. Update internal state (USDT scale)
        _balance -= transferUSDT;
        _dailySpent += transferUSDT;
        _totalAbsorbed += transferUSDT;

        // FIX LEVER-P04: Transfer USDT to the specified recipient (leverVault), not msg.sender.
        if (transferUSDT > 0) {
            usdt.safeTransfer(recipient, transferUSDT);
        }

        emit BadDebtAbsorbed(marketId, totalBadDebt, insurancePaid, remainder, block.timestamp);

        return (insurancePaid, remainder);
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    /// @notice Pause the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IInsuranceFund
    function getBalance() external view override returns (uint256) {
        return _balance;
    }

    /// @inheritdoc IInsuranceFund
    function getIFR() external view override returns (uint256 ifr) {
        return _getIFR();
    }

    /// @inheritdoc IInsuranceFund
    function getCurrentTier()
        external
        view
        override
        returns (uint8 tier, uint256 insurancePct, uint256 adlPct)
    {
        uint256 ifr = _getIFR();
        if (ifr > TIER_1_THRESHOLD) {
            return (1, WAD, 0);
        } else if (ifr > TIER_2_THRESHOLD) {
            return (2, 7e17, 3e17);
        } else if (ifr > TIER_3_THRESHOLD) {
            return (3, 4e17, 6e17);
        } else {
            return (4, 1e17, 9e17);
        }
    }

    /// @inheritdoc IInsuranceFund
    /// @dev Returns remaining daily capacity in USDT (6-decimal), consistent with getBalance().
    function getRemainingDailyCapacity() external view override returns (uint256) {
        uint256 balanceWAD = _balance * SCALE;
        uint256 dailyCap = balanceWAD.wadMul(DAILY_CAP_PCT);
        uint256 spent;

        if (block.timestamp >= _dailyWindowStart + DAILY_WINDOW) {
            spent = 0;
        } else {
            spent = _dailySpent * SCALE;
        }

        uint256 remainingWAD = dailyCap > spent ? dailyCap - spent : 0;
        return remainingWAD / SCALE; // return in USDT
    }

    /// @inheritdoc IInsuranceFund
    /// @dev Returns floor in USDT (6-decimal), consistent with getBalance().
    function getFloor() external view override returns (uint256 floor) {
        uint256 tvl = leverVault.totalAssets();
        return tvl * IFR_FLOOR / WAD; // simple percentage of USDT TVL
    }

    /// @inheritdoc IInsuranceFund
    /// @dev Returns target in USDT (6-decimal), consistent with getBalance().
    function getTarget() external view override returns (uint256 target) {
        uint256 tvl = leverVault.totalAssets();
        return tvl * IFR_TARGET / WAD; // simple percentage of USDT TVL
    }

    /// @inheritdoc IInsuranceFund
    function isFullyFunded() external view override returns (bool) {
        return _getIFR() >= IFR_TARGET;
    }

    /// @inheritdoc IInsuranceFund
    function totalAbsorbed() external view override returns (uint256) {
        return _totalAbsorbed;
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────

    /// @dev Compute IFR = balance / TVL. Returns WAD if TVL == 0.
    function _getIFR() internal view returns (uint256) {
        uint256 tvl = leverVault.totalAssets();
        if (tvl == 0) return WAD;
        return _balance.wadDiv(tvl);
    }
}
