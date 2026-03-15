// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountManager } from "../interfaces/IAccountManager.sol";

/// @title AccountManager
/// @notice User accounts, collateral deposits/withdrawals, position ownership tracking.
/// @dev No protocol dependencies. Holds trader USDT collateral.
contract AccountManager is IAccountManager, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Constants & Roles
    // ──────────────────────────────────────────────

    /// @notice Role for contracts that can lock/release collateral and credit/debit PnL
    bytes32 public constant ENGINE = keccak256("ENGINE");

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @notice The USDT token used as collateral
    IERC20 public immutable collateralToken;

    /// @dev user => total balance (free + locked)
    mapping(address => uint256) private _balances;

    /// @dev user => locked collateral in open positions
    mapping(address => uint256) private _lockedCollateral;

    /// @dev user => list of position IDs they own
    mapping(address => uint256[]) private _userPositions;

    /// @dev positionId => index+1 in user's position array (for O(1) removal)
    mapping(uint256 => uint256) private _positionIndex;

    /// @dev positionId => owner
    mapping(uint256 => address) private _positionOwner;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin Address granted DEFAULT_ADMIN_ROLE
    /// @param _collateralToken USDT token address
    constructor(address admin, address _collateralToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        collateralToken = IERC20(_collateralToken);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (User)
    // ──────────────────────────────────────────────

    /// @inheritdoc IAccountManager
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert AccountManager__ZeroAmount();

        _balances[msg.sender] += amount;
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, amount);
    }

    /// @inheritdoc IAccountManager
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert AccountManager__ZeroAmount();

        uint256 free = _balances[msg.sender] - _lockedCollateral[msg.sender];
        if (amount > free) {
            revert AccountManager__InsufficientBalance(msg.sender, amount, free);
        }

        _balances[msg.sender] -= amount;
        collateralToken.safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Engine-only)
    // ──────────────────────────────────────────────

    /// @inheritdoc IAccountManager
    function lockCollateral(address user, uint256 amount) external onlyRole(ENGINE) nonReentrant {
        uint256 free = _balances[user] - _lockedCollateral[user];
        if (amount > free) {
            revert AccountManager__InsufficientBalance(user, amount, free);
        }

        _lockedCollateral[user] += amount;
    }

    /// @inheritdoc IAccountManager
    function releaseCollateral(address user, uint256 amount) external onlyRole(ENGINE) nonReentrant {
        _lockedCollateral[user] -= amount;
    }

    /// @inheritdoc IAccountManager
    function creditPnL(address user, uint256 amount) external onlyRole(ENGINE) nonReentrant {
        _balances[user] += amount;
    }

    /// @inheritdoc IAccountManager
    function debitPnL(address user, uint256 amount) external onlyRole(ENGINE) nonReentrant returns (uint256 badDebt) {
        // Debit comes from locked collateral that is being released
        // The caller (ExecutionEngine) handles the ordering: release collateral first, then debit
        // If amount > balance, debit what's available — the remainder is bad debt
        uint256 balance = _balances[user];
        if (amount >= balance) {
            badDebt = amount - balance;
            _balances[user] = 0;
        } else {
            _balances[user] = balance - amount;
        }
    }

    /// @notice Assign a position to a user (called by ExecutionEngine on position open)
    /// @param user Position owner
    /// @param positionId Position identifier
    function assignPosition(address user, uint256 positionId) external onlyRole(ENGINE) {
        _userPositions[user].push(positionId);
        _positionIndex[positionId] = _userPositions[user].length; // 1-indexed
        _positionOwner[positionId] = user;

        emit PositionAssigned(user, positionId);
    }

    /// @notice Remove a position from a user (called on position close)
    /// @param user Position owner
    /// @param positionId Position identifier
    function removePosition(address user, uint256 positionId) external onlyRole(ENGINE) {
        if (_positionOwner[positionId] != user) {
            revert AccountManager__PositionNotOwned(user, positionId);
        }

        uint256 indexPlusOne = _positionIndex[positionId];
        uint256[] storage positions = _userPositions[user];
        uint256 lastIndex = positions.length - 1;
        uint256 removeIndex = indexPlusOne - 1;

        if (removeIndex != lastIndex) {
            uint256 lastPositionId = positions[lastIndex];
            positions[removeIndex] = lastPositionId;
            _positionIndex[lastPositionId] = indexPlusOne;
        }

        positions.pop();
        delete _positionIndex[positionId];
        delete _positionOwner[positionId];

        emit PositionRemoved(user, positionId);
    }

    /// @notice Pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IAccountManager
    function getBalance(address user) external view returns (uint256) {
        return _balances[user];
    }

    /// @inheritdoc IAccountManager
    function getFreeCollateral(address user) external view returns (uint256) {
        return _balances[user] - _lockedCollateral[user];
    }

    /// @inheritdoc IAccountManager
    function getLockedCollateral(address user) external view returns (uint256) {
        return _lockedCollateral[user];
    }

    /// @inheritdoc IAccountManager
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return _userPositions[user];
    }
}
