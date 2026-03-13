// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRewardsDistributor
/// @notice Separate from vault. Receives LP's 50% fee share + unmatched funding.
///         LPs claim yield without burning shares. Tranche-aware yield tracking.
interface IRewardsDistributor {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error RewardsDistributor__NothingToClaim(address user);
    error RewardsDistributor__UnauthorizedDepositor(address caller);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event RewardsDeposited(uint256 amount, uint256 newIndex, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event UnmatchedFundingReceived(bytes32 indexed marketId, uint256 amount, uint256 timestamp);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Deposit fee revenue for distribution to LP holders
    /// @dev Called by FeeRouter. Increases the cumulative reward index.
    /// @param amount USDT amount to distribute (WAD)
    function depositRewards(uint256 amount) external;

    /// @notice Receive unmatched funding from FundingRateEngine
    /// @dev Separate entry point for tracking. Also increases reward index.
    /// @param marketId Source market
    /// @param amount USDT amount (WAD)
    function receiveUnmatchedFunding(bytes32 marketId, uint256 amount) external;

    /// @notice Claim all pending rewards for the caller
    /// @dev Iterates caller's tranches in LeverVault, computes yield per tranche,
    ///      resets snapshots. Callable anytime, no cooldown, no utilization gate.
    /// @return amount USDT claimed
    function claim() external returns (uint256 amount);

    /// @notice Release USDT rewards to a recipient (vault-only)
    /// @dev Called by LeverVault after computing yield and resetting tranche snapshots.
    /// @param to Recipient address
    /// @param amount USDT amount to release (WAD)
    function releaseRewards(address to, uint256 amount) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get the current cumulative reward-per-share index (WAD)
    function rewardPerShareCumulative() external view returns (uint256);

    /// @notice Get pending (claimable) rewards for an address
    /// @dev Computed from the address's tranches in LeverVault
    function pendingRewards(address holder) external view returns (uint256);

    /// @notice Get total rewards distributed lifetime
    function totalDistributed() external view returns (uint256);

    /// @notice Get total rewards from unmatched funding lifetime
    function totalUnmatchedFunding() external view returns (uint256);

    /// @notice Get total rewards from fee split lifetime
    function totalFeeRewards() external view returns (uint256);
}
