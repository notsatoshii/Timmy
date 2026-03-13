// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Custom Errors
error RewardsDistributor__ZeroAddress();
error RewardsDistributor__ZeroAmount();
error RewardsDistributor__InsufficientBalance(uint256 requested, uint256 available);

/// @title RewardsDistributor
/// @notice Separate from LeverVault. Receives LP's 50% fee share (via FeeRouter) +
///         unmatched funding (via FundingRateEngine). Maintains a cumulative reward-per-share
///         index. LPs claim yield via LeverVault without burning shares.
/// @dev The vault computes yield from tranche snapshots and calls releaseRewards() to transfer USDT.
///      depositRewards() and receiveUnmatchedFunding() increase the cumulative index.
contract RewardsDistributor is IRewardsDistributor, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant FEE_ROUTER_ROLE = keccak256("FEE_ROUTER_ROLE");
    bytes32 public constant FUNDING_RATE_ENGINE_ROLE = keccak256("FUNDING_RATE_ENGINE_ROLE");
    bytes32 public constant LEVER_VAULT_ROLE = keccak256("LEVER_VAULT_ROLE");

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IERC20 public immutable usdt;
    ILeverVault public immutable leverVault;

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    /// @dev Cumulative reward-per-share index (WAD). Increases monotonically.
    uint256 private _rewardPerShareCumulative;

    /// @dev Lifetime total rewards distributed (fee + funding)
    uint256 private _totalDistributed;

    /// @dev Lifetime total from unmatched funding
    uint256 private _totalUnmatchedFunding;

    /// @dev Lifetime total from fee revenue
    uint256 private _totalFeeRewards;

    // ──────────────────────────────────────────────
    // Events (beyond interface)
    // ──────────────────────────────────────────────

    event RewardsReleased(address indexed to, uint256 amount, uint256 timestamp);

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin_ Admin address
    /// @param usdt_ USDT token address
    /// @param leverVault_ LeverVault contract (for reading totalSupply and tranches)
    constructor(
        address admin_,
        address usdt_,
        address leverVault_
    ) {
        if (admin_ == address(0)) revert RewardsDistributor__ZeroAddress();
        if (usdt_ == address(0)) revert RewardsDistributor__ZeroAddress();
        if (leverVault_ == address(0)) revert RewardsDistributor__ZeroAddress();

        usdt = IERC20(usdt_);
        leverVault = ILeverVault(leverVault_);

        _grantRole(ADMIN_ROLE, admin_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IRewardsDistributor
    function depositRewards(uint256 amount) external override onlyRole(FEE_ROUTER_ROLE) nonReentrant whenNotPaused {
        if (amount == 0) revert RewardsDistributor__ZeroAmount();

        uint256 shares = leverVault.totalSupply();
        if (shares > 0) {
            uint256 indexDelta = (amount * 1e18) / shares;
            _rewardPerShareCumulative += indexDelta;
        }
        // If no shares exist, rewards accumulate in balance but index doesn't increase.
        // Next depositor won't capture them via index — they remain as surplus.

        _totalDistributed += amount;
        _totalFeeRewards += amount;

        emit RewardsDeposited(amount, _rewardPerShareCumulative, block.timestamp);
    }

    /// @inheritdoc IRewardsDistributor
    function receiveUnmatchedFunding(bytes32 marketId, uint256 amount)
        external
        override
        onlyRole(FUNDING_RATE_ENGINE_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert RewardsDistributor__ZeroAmount();

        uint256 shares = leverVault.totalSupply();
        if (shares > 0) {
            uint256 indexDelta = (amount * 1e18) / shares;
            _rewardPerShareCumulative += indexDelta;
        }

        _totalDistributed += amount;
        _totalUnmatchedFunding += amount;

        emit UnmatchedFundingReceived(marketId, amount, block.timestamp);
    }

    /// @inheritdoc IRewardsDistributor
    /// @dev Claims are handled through LeverVault.claim() which computes yield from
    ///      tranche snapshots and calls releaseRewards(). This function exists for
    ///      interface compliance but reverts — use LeverVault.claim() instead.
    function claim() external pure override returns (uint256) {
        revert RewardsDistributor__NothingToClaim(address(0));
    }

    /// @inheritdoc IRewardsDistributor
    /// @dev Called by LeverVault after computing yield and resetting tranche snapshots.
    function releaseRewards(address to, uint256 amount)
        external
        override
        onlyRole(LEVER_VAULT_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (to == address(0)) revert RewardsDistributor__ZeroAddress();
        if (amount == 0) revert RewardsDistributor__ZeroAmount();

        uint256 balance = usdt.balanceOf(address(this));
        if (amount > balance) {
            revert RewardsDistributor__InsufficientBalance(amount, balance);
        }

        usdt.safeTransfer(to, amount);

        emit RewardsReleased(to, amount, block.timestamp);
        emit RewardsClaimed(to, amount, block.timestamp);
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

    /// @inheritdoc IRewardsDistributor
    function rewardPerShareCumulative() external view override returns (uint256) {
        return _rewardPerShareCumulative;
    }

    /// @inheritdoc IRewardsDistributor
    function pendingRewards(address holder) external view override returns (uint256 pending) {
        uint256 currentIndex = _rewardPerShareCumulative;
        ILeverVault.Tranche[] memory tranches = leverVault.getTranches(holder);
        for (uint256 i; i < tranches.length; ++i) {
            if (currentIndex > tranches[i].rewardSnapshot) {
                pending += uint256(tranches[i].shares).wadMul(
                    uint256(currentIndex - tranches[i].rewardSnapshot)
                );
            }
        }
    }

    /// @inheritdoc IRewardsDistributor
    function totalDistributed() external view override returns (uint256) {
        return _totalDistributed;
    }

    /// @inheritdoc IRewardsDistributor
    function totalUnmatchedFunding() external view override returns (uint256) {
        return _totalUnmatchedFunding;
    }

    /// @inheritdoc IRewardsDistributor
    function totalFeeRewards() external view override returns (uint256) {
        return _totalFeeRewards;
    }
}
