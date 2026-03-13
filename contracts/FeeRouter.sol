// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IFeeRouter } from "./interfaces/IFeeRouter.sol";
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title FeeRouter
/// @notice Deterministic fee split. Routes all protocol fees (borrow, TX, liquidation,
///         settlement) through 50/30/20 (LP/Protocol/Insurance). Tier 2 when IFR >= 20%: 50/50/0.
///         Funding payments do NOT go through this — they route directly between traders and LP.
contract FeeRouter is IFeeRouter, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 public constant LP_SHARE = 5e17;               // 50% — always
    uint256 public constant PROTOCOL_SHARE_T1 = 3e17;      // 30% (IFR < 20%)
    uint256 public constant INSURANCE_SHARE_T1 = 2e17;     // 20% (IFR < 20%)
    uint256 public constant PROTOCOL_SHARE_T2 = 5e17;      // 50% (IFR >= 20%)
    uint256 public constant INSURANCE_SHARE_T2 = 0;        // 0%  (IFR >= 20%)
    uint256 public constant TX_FEE_RATE = 1e15;            // 0.10% (10 bps)

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant BORROW_FEE_ENGINE_ROLE = keccak256("BORROW_FEE_ENGINE_ROLE");
    bytes32 public constant EXECUTION_ENGINE_ROLE = keccak256("EXECUTION_ENGINE_ROLE");
    bytes32 public constant LIQUIDATION_ENGINE_ROLE = keccak256("LIQUIDATION_ENGINE_ROLE");
    bytes32 public constant SETTLEMENT_ENGINE_ROLE = keccak256("SETTLEMENT_ENGINE_ROLE");

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IERC20 public immutable usdt;
    IInsuranceFund public immutable insuranceFund;
    IRewardsDistributor public immutable rewardsDistributor;
    address public immutable override protocolTreasury;

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    /// @dev Total fees routed per FeeType
    mapping(FeeType => uint256) private _totalFeesRouted;

    /// @dev Last observed tier (for TierChanged events)
    uint8 private _lastTier;

    // ──────────────────────────────────────────────
    // Custom Errors (beyond interface)
    // ──────────────────────────────────────────────

    error FeeRouter__ZeroAddress();

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin_ Admin address
    /// @param usdt_ USDT token address
    /// @param insuranceFund_ InsuranceFund contract
    /// @param rewardsDistributor_ RewardsDistributor contract
    /// @param protocolTreasury_ Protocol treasury address (immutable)
    constructor(
        address admin_,
        address usdt_,
        address insuranceFund_,
        address rewardsDistributor_,
        address protocolTreasury_
    ) {
        if (admin_ == address(0)) revert FeeRouter__ZeroAddress();
        if (usdt_ == address(0)) revert FeeRouter__ZeroAddress();
        if (insuranceFund_ == address(0)) revert FeeRouter__ZeroAddress();
        if (rewardsDistributor_ == address(0)) revert FeeRouter__ZeroAddress();
        if (protocolTreasury_ == address(0)) revert FeeRouter__ZeroAddress();

        usdt = IERC20(usdt_);
        insuranceFund = IInsuranceFund(insuranceFund_);
        rewardsDistributor = IRewardsDistributor(rewardsDistributor_);
        protocolTreasury = protocolTreasury_;

        _grantRole(ADMIN_ROLE, admin_);
        _lastTier = 1;
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IFeeRouter
    function routeFees(FeeType feeType, uint256 amount) external override nonReentrant whenNotPaused {
        _checkFeeRouterRole(msg.sender);
        if (amount == 0) revert FeeRouter__ZeroAmount();

        (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare, uint8 tier) = _computeSplit(amount);

        _totalFeesRouted[feeType] += amount;

        // Emit tier change if applicable
        if (tier != _lastTier) {
            emit TierChanged(_lastTier, tier, insuranceFund.getIFR());
            _lastTier = tier;
        }

        // Transfer to RewardsDistributor (LP share)
        usdt.safeTransfer(address(rewardsDistributor), lpShare);
        rewardsDistributor.depositRewards(lpShare);

        // Transfer to protocol treasury
        usdt.safeTransfer(protocolTreasury, protocolShare);

        // Transfer to insurance fund (Tier 1 only)
        if (insuranceShare > 0) {
            usdt.safeTransfer(address(insuranceFund), insuranceShare);
            insuranceFund.deposit(insuranceShare);
        }

        emit FeesRouted(uint8(feeType), amount, lpShare, protocolShare, insuranceShare, tier);
    }

    /// @inheritdoc IFeeRouter
    function collectTransactionFee(uint256 notional) external override nonReentrant whenNotPaused returns (uint256 fee) {
        _checkRole(EXECUTION_ENGINE_ROLE, msg.sender);

        fee = notional.wadMul(TX_FEE_RATE);
        if (fee == 0) return 0;

        (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare, uint8 tier) = _computeSplit(fee);

        _totalFeesRouted[FeeType.TRANSACTION] += fee;

        // Emit tier change if applicable
        if (tier != _lastTier) {
            emit TierChanged(_lastTier, tier, insuranceFund.getIFR());
            _lastTier = tier;
        }

        // Transfer to RewardsDistributor (LP share)
        usdt.safeTransfer(address(rewardsDistributor), lpShare);
        rewardsDistributor.depositRewards(lpShare);

        // Transfer to protocol treasury
        usdt.safeTransfer(protocolTreasury, protocolShare);

        // Transfer to insurance fund (Tier 1 only)
        if (insuranceShare > 0) {
            usdt.safeTransfer(address(insuranceFund), insuranceShare);
            insuranceFund.deposit(insuranceShare);
        }

        emit FeesRouted(uint8(FeeType.TRANSACTION), fee, lpShare, protocolShare, insuranceShare, tier);
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

    /// @inheritdoc IFeeRouter
    function getCurrentTier() external view override returns (uint8 tier) {
        tier = insuranceFund.isFullyFunded() ? 2 : 1;
    }

    /// @inheritdoc IFeeRouter
    function getCurrentSplit()
        external
        view
        override
        returns (uint256 lpPct, uint256 protocolPct, uint256 insurancePct)
    {
        lpPct = LP_SHARE;
        if (insuranceFund.isFullyFunded()) {
            protocolPct = PROTOCOL_SHARE_T2;
            insurancePct = INSURANCE_SHARE_T2;
        } else {
            protocolPct = PROTOCOL_SHARE_T1;
            insurancePct = INSURANCE_SHARE_T1;
        }
    }

    /// @inheritdoc IFeeRouter
    function previewSplit(uint256 amount)
        external
        view
        override
        returns (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare)
    {
        (lpShare, protocolShare, insuranceShare,) = _computeSplit(amount);
    }

    /// @inheritdoc IFeeRouter
    function getTotalFeesRouted(FeeType feeType) external view override returns (uint256) {
        return _totalFeesRouted[feeType];
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────

    /// @dev Compute fee split based on current tier. Uses remainder for last share to prevent rounding loss.
    function _computeSplit(uint256 amount)
        internal
        view
        returns (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare, uint8 tier)
    {
        tier = insuranceFund.isFullyFunded() ? 2 : 1;

        lpShare = amount.wadMul(LP_SHARE);

        if (tier == 1) {
            protocolShare = amount.wadMul(PROTOCOL_SHARE_T1);
            insuranceShare = amount - lpShare - protocolShare; // remainder avoids rounding loss
        } else {
            protocolShare = amount - lpShare; // 50% remainder
            insuranceShare = 0;
        }
    }

    /// @dev Check that caller has one of the authorized fee-routing roles
    function _checkFeeRouterRole(address caller) internal view {
        if (
            !hasRole(BORROW_FEE_ENGINE_ROLE, caller)
                && !hasRole(EXECUTION_ENGINE_ROLE, caller)
                && !hasRole(LIQUIDATION_ENGINE_ROLE, caller)
                && !hasRole(SETTLEMENT_ENGINE_ROLE, caller)
        ) {
            revert FeeRouter__UnauthorizedCaller(caller);
        }
    }
}
