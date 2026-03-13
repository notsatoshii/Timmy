// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title OILimits
/// @notice Four-tier OI cap system: global, per-market (dynamic), per-side, per-user.
///         Every cap is dynamic — scales with TVL, compresses with R(τ).
///         Enforces hard capacity constraints. When a cap is reached, no new positions open.
/// @dev Tier 1 (global) does NOT compress with R(τ). Tiers 2-4 compress via oiCapMultiplier.
///      Existing OI that exceeds caps after TVL drops is grandfathered — no forced closes.
contract OILimits is IOILimits, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;
    uint256 public constant GLOBAL_OI_RATIO = 6e17;   // 0.60 — 60% of TVL
    uint256 public constant OI_CAP_FLOOR = 2e17;       // 0.20 — per-market floor
    uint256 public constant SIDE_OI_RATIO = 7e17;      // 0.70 — per-side
    uint256 public constant USER_OI_RATIO = 2e17;      // 0.20 — per-user

    // ──────────────────────────────────────────────
    // Custom Errors
    // ──────────────────────────────────────────────

    error OILimits__ZeroAddress();
    error OILimits__ZeroNotional();

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTION_ENGINE_ROLE = keccak256("EXECUTION_ENGINE_ROLE");
    bytes32 public constant LIQUIDATION_ENGINE_ROLE = keccak256("LIQUIDATION_ENGINE_ROLE");
    bytes32 public constant SETTLEMENT_ENGINE_ROLE = keccak256("SETTLEMENT_ENGINE_ROLE");

    // ──────────────────────────────────────────────
    // State variables
    // ──────────────────────────────────────────────

    IMarketRegistry public immutable marketRegistry;
    ILeverVault public immutable vault;

    uint256 private _globalOI;
    mapping(bytes32 => uint256) private _marketOI;
    mapping(bytes32 => uint256) private _longOI;
    mapping(bytes32 => uint256) private _shortOI;
    mapping(bytes32 => mapping(address => uint256)) private _userOI;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param _marketRegistry MarketRegistry address (for τ, is_live, allocation weights)
    /// @param _vault LeverVault address (for TVL)
    /// @param _admin Initial admin address
    constructor(address _marketRegistry, address _vault, address _admin) {
        if (_marketRegistry == address(0) || _vault == address(0) || _admin == address(0)) {
            revert OILimits__ZeroAddress();
        }

        marketRegistry = IMarketRegistry(_marketRegistry);
        vault = ILeverVault(_vault);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ──────────────────────────────────────────────
    // External functions (state-changing)
    // ──────────────────────────────────────────────

    /// @inheritdoc IOILimits
    function increaseOI(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 notional
    ) external override onlyRole(EXECUTION_ENGINE_ROLE) nonReentrant whenNotPaused {
        if (notional == 0) revert OILimits__ZeroNotional();

        // Validate all four tier caps (extracted to avoid stack-too-deep)
        _validateCaps(marketId, user, isLong, notional);

        // Update state
        _globalOI += notional;
        uint256 newMarketOI = _marketOI[marketId] + notional;
        _marketOI[marketId] = newMarketOI;
        if (isLong) {
            _longOI[marketId] += notional;
        } else {
            _shortOI[marketId] += notional;
        }
        _userOI[marketId][user] += notional;

        emit OIIncreased(marketId, isLong, notional, newMarketOI);
    }

    /// @inheritdoc IOILimits
    function decreaseOI(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 notional
    ) external override nonReentrant whenNotPaused {
        _requireDecreaseRole();
        if (notional == 0) revert OILimits__ZeroNotional();

        // Floor at 0 for all decreases (spec: don't underflow)
        _globalOI = notional > _globalOI ? 0 : _globalOI - notional;
        _marketOI[marketId] = notional > _marketOI[marketId] ? 0 : _marketOI[marketId] - notional;

        if (isLong) {
            _longOI[marketId] = notional > _longOI[marketId] ? 0 : _longOI[marketId] - notional;
        } else {
            _shortOI[marketId] = notional > _shortOI[marketId] ? 0 : _shortOI[marketId] - notional;
        }

        _userOI[marketId][user] = notional > _userOI[marketId][user]
            ? 0
            : _userOI[marketId][user] - notional;

        emit OIDecreased(marketId, isLong, notional, _marketOI[marketId]);
    }

    /// @notice Pause the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // External functions (view)
    // ──────────────────────────────────────────────

    /// @inheritdoc IOILimits
    function getGlobalOICap() external view override returns (uint256) {
        return _computeGlobalOICap();
    }

    /// @inheritdoc IOILimits
    function getGlobalOI() external view override returns (uint256) {
        return _globalOI;
    }

    /// @inheritdoc IOILimits
    function getMarketOICap(bytes32 marketId) external view override returns (uint256) {
        return _computeMarketOICap(marketId, _computeGlobalOICap());
    }

    /// @inheritdoc IOILimits
    function getMarketOI(bytes32 marketId) external view override returns (uint256) {
        return _marketOI[marketId];
    }

    /// @inheritdoc IOILimits
    function getSideOICap(bytes32 marketId) external view override returns (uint256) {
        uint256 marketCap = _computeMarketOICap(marketId, _computeGlobalOICap());
        return marketCap.wadMul(SIDE_OI_RATIO);
    }

    /// @inheritdoc IOILimits
    function getSideOI(bytes32 marketId, bool isLong) external view override returns (uint256) {
        return isLong ? _longOI[marketId] : _shortOI[marketId];
    }

    /// @inheritdoc IOILimits
    function getUserOICap(bytes32 marketId) external view override returns (uint256) {
        uint256 marketCap = _computeMarketOICap(marketId, _computeGlobalOICap());
        return marketCap.wadMul(USER_OI_RATIO);
    }

    /// @inheritdoc IOILimits
    function getUserOI(bytes32 marketId, address user) external view override returns (uint256) {
        return _userOI[marketId][user];
    }

    /// @inheritdoc IOILimits
    function canIncreaseOI(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 notional
    ) external view override returns (bool) {
        uint256 globalCap = _computeGlobalOICap();
        if (_globalOI + notional > globalCap) return false;

        uint256 marketCap = _computeMarketOICap(marketId, globalCap);
        if (_marketOI[marketId] + notional > marketCap) return false;

        uint256 sideCap = marketCap.wadMul(SIDE_OI_RATIO);
        uint256 currentSideOI = isLong ? _longOI[marketId] : _shortOI[marketId];
        if (currentSideOI + notional > sideCap) return false;

        uint256 userCap = marketCap.wadMul(USER_OI_RATIO);
        if (_userOI[marketId][user] + notional > userCap) return false;

        return true;
    }

    /// @inheritdoc IOILimits
    function getImbalanceRatio(bytes32 marketId) external view override returns (int256 ratio) {
        uint256 longOI = _longOI[marketId];
        uint256 shortOI = _shortOI[marketId];
        uint256 totalOI = longOI + shortOI;

        if (totalOI == 0) return 0;

        // (longOI - shortOI) × WAD / totalOI
        int256 numerator = int256(longOI) - int256(shortOI);
        ratio = numerator * int256(WAD) / int256(totalOI);
    }

    /// @inheritdoc IOILimits
    function getMarketUtilization(bytes32 marketId) external view override returns (uint256) {
        uint256 marketCap = _computeMarketOICap(marketId, _computeGlobalOICap());
        if (marketCap == 0) return 0;
        uint256 marketOI = _marketOI[marketId];
        if (marketOI == 0) return 0;
        return marketOI.wadDiv(marketCap);
    }

    /// @inheritdoc IOILimits
    function getGlobalUtilization() external view override returns (uint256) {
        uint256 globalCap = _computeGlobalOICap();
        if (globalCap == 0) return 0;
        if (_globalOI == 0) return 0;
        return _globalOI.wadDiv(globalCap);
    }

    // ──────────────────────────────────────────────
    // Internal / Private functions
    // ──────────────────────────────────────────────

    /// @dev Compute Global_OI_Cap = TVL × GLOBAL_OI_RATIO / WAD
    function _computeGlobalOICap() internal view returns (uint256) {
        uint256 tvl = vault.totalAssets();
        return tvl.wadMul(GLOBAL_OI_RATIO);
    }

    /// @dev Compute per-market OI cap with R(τ) compression
    /// @param marketId Market identifier
    /// @param globalCap Pre-computed global OI cap
    function _computeMarketOICap(bytes32 marketId, uint256 globalCap) internal view returns (uint256) {
        uint256 weight = marketRegistry.getAllocationWeight(marketId);
        uint256 baseMarketCap = globalCap.wadMul(weight);

        uint256 rAdjusted = _computeRAdjusted(marketId);
        uint256 oiMult = RiskCurves.oiCapMultiplier(rAdjusted);

        return baseMarketCap.wadMul(oiMult);
    }

    /// @dev Compute R_adjusted = R(τ_effective). M_market = 1.0 for OILimits
    ///      (avoids circular dependency since concentration needs globalOI from us).
    function _computeRAdjusted(bytes32 marketId) internal view returns (uint256) {
        uint256 tau = marketRegistry.getTau(marketId);
        bool isLive = marketRegistry.isLive(marketId);

        uint256 tauEff = RiskCurves.computeTauEffective(tau, isLive);
        return RiskCurves.computeR(tauEff);
    }

    /// @dev Validate all four OI cap tiers. Reverts with specific error if any is breached.
    function _validateCaps(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 notional
    ) private view {
        uint256 globalCap = _computeGlobalOICap();
        uint256 newGlobalOI = _globalOI + notional;
        if (newGlobalOI > globalCap) {
            revert OILimits__GlobalCapExceeded(newGlobalOI, globalCap);
        }

        uint256 marketCap = _computeMarketOICap(marketId, globalCap);
        uint256 newMarketOI = _marketOI[marketId] + notional;
        if (newMarketOI > marketCap) {
            revert OILimits__MarketCapExceeded(marketId, newMarketOI, marketCap);
        }

        _validateSideAndUserCaps(marketId, user, isLong, notional, marketCap);
    }

    /// @dev Validate side and user caps (second half of cap validation, split for stack depth)
    function _validateSideAndUserCaps(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 notional,
        uint256 marketCap
    ) private view {
        uint256 sideCap = marketCap.wadMul(SIDE_OI_RATIO);
        uint256 currentSideOI = isLong ? _longOI[marketId] : _shortOI[marketId];
        uint256 newSideOI = currentSideOI + notional;
        if (newSideOI > sideCap) {
            revert OILimits__SideCapExceeded(marketId, isLong, newSideOI, sideCap);
        }

        uint256 userCap = marketCap.wadMul(USER_OI_RATIO);
        uint256 newUserOI = _userOI[marketId][user] + notional;
        if (newUserOI > userCap) {
            revert OILimits__UserCapExceeded(marketId, user, newUserOI, userCap);
        }
    }

    /// @dev Require caller has one of the decrease roles
    function _requireDecreaseRole() internal view {
        if (
            !hasRole(EXECUTION_ENGINE_ROLE, msg.sender)
                && !hasRole(LIQUIDATION_ENGINE_ROLE, msg.sender)
                && !hasRole(SETTLEMENT_ENGINE_ROLE, msg.sender)
        ) {
            revert AccessControlUnauthorizedAccount(msg.sender, EXECUTION_ENGINE_ROLE);
        }
    }
}
