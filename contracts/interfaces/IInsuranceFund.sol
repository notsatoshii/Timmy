// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IInsuranceFund
/// @notice Bad debt absorption mechanism funded by 20% of fees.
///         Three constraints: daily cap (25%), tiered split, 5% IFR floor.
///         Bootstrapped at $10,000 at launch.
interface IInsuranceFund {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error InsuranceFund__DailyCapExceeded(uint256 requested, uint256 remaining);
    error InsuranceFund__FloorBreached(uint256 balance, uint256 floor);
    error InsuranceFund__InsufficientFunds(uint256 requested, uint256 available);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event FundsDeposited(uint256 amount, uint256 newBalance, uint256 timestamp);
    event BadDebtAbsorbed(bytes32 indexed marketId, uint256 amount, uint256 insurancePaid, uint256 adlAmount, uint256 timestamp);
    event DailyCapReset(uint256 newCap, uint256 timestamp);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Receive fee revenue (20% of protocol fees via FeeRouter)
    /// @param amount USDT amount (WAD)
    function deposit(uint256 amount) external;

    /// @notice Absorb bad debt from a liquidation or settlement
    /// @dev Applies three constraints: daily cap, tiered split, floor.
    ///      The `remainder` means different things for different callers:
    ///      - LiquidationEngine: remainder → LP socialization (NAV hit)
    ///      - SettlementEngine: remainder → ADL (winner haircuts), then LP socialization
    /// @param marketId Market where bad debt occurred
    /// @param totalBadDebt Total bad debt to absorb (WAD)
    /// @return insurancePaid Amount paid by insurance fund (WAD)
    /// @return remainder Amount NOT covered by insurance (WAD)
    function absorbBadDebt(bytes32 marketId, uint256 totalBadDebt)
        external returns (uint256 insurancePaid, uint256 remainder);

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get current insurance fund balance
    function getBalance() external view returns (uint256);

    /// @notice Get Insurance Fund Ratio: balance / TVL
    function getIFR() external view returns (uint256 ifr);

    /// @notice Get current ADL tier based on IFR
    /// @return tier 1-4. Determines insurance vs ADL split.
    /// @return insurancePct Insurance share of bad debt (WAD)
    /// @return adlPct ADL share of bad debt (WAD)
    function getCurrentTier() external view returns (uint8 tier, uint256 insurancePct, uint256 adlPct);

    /// @notice Get remaining daily absorption capacity
    /// @dev Daily cap = 25% of balance, rolling 24h window.
    function getRemainingDailyCapacity() external view returns (uint256);

    /// @notice Get the floor amount: 5% of TVL (fund never drops below this)
    function getFloor() external view returns (uint256 floor);

    /// @notice Get the target balance: IFR_target (20%) × TVL
    function getTarget() external view returns (uint256 target);

    /// @notice Check if the fund is fully funded (IFR ≥ 20%)
    function isFullyFunded() external view returns (bool);

    /// @notice Get total bad debt absorbed lifetime
    function totalAbsorbed() external view returns (uint256);
}

