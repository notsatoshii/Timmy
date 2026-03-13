// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IPositionManager } from "../interfaces/IPositionManager.sol";

/// @title PositionManager
/// @notice Stores all position state. Single source of truth for position data.
///         Pure data store — no business logic, no formula computation.
/// @dev Multiple contracts read from this. Only authorized callers (ExecutionEngine,
///      LiquidationEngine, SettlementEngine) can write.
contract PositionManager is IPositionManager, AccessControl, ReentrancyGuard, Pausable {
    // ──────────────────────────────────────────────
    // Constants & Roles
    // ──────────────────────────────────────────────

    /// @notice Role for contracts that can create/close/update positions
    bytes32 public constant ENGINE = keccak256("ENGINE");

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @dev Next position ID to assign
    uint256 private _nextPositionId = 1;

    /// @dev Total count of currently open positions
    uint256 private _totalOpenPositions;

    /// @dev positionId => Position
    mapping(uint256 => Position) private _positions;

    /// @dev user => array of open position IDs
    mapping(address => uint256[]) private _userPositions;

    /// @dev positionId => index+1 in user's position array
    mapping(uint256 => uint256) private _userPositionIndex;

    /// @dev marketId => array of open position IDs
    mapping(bytes32 => uint256[]) private _marketPositions;

    /// @dev positionId => index+1 in market's position array
    mapping(uint256 => uint256) private _marketPositionIndex;

    /// @dev marketId => isLong => array of open position IDs
    mapping(bytes32 => mapping(bool => uint256[])) private _marketSidePositions;

    /// @dev positionId => index+1 in market side's position array
    mapping(uint256 => uint256) private _marketSidePositionIndex;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin Address granted DEFAULT_ADMIN_ROLE
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IPositionManager
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
    ) external onlyRole(ENGINE) whenNotPaused nonReentrant returns (uint256 positionId) {
        positionId = _nextPositionId++;

        _positions[positionId] = Position({
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

        _totalOpenPositions++;

        // Add to user tracking
        _userPositions[owner].push(positionId);
        _userPositionIndex[positionId] = _userPositions[owner].length;

        // Add to market tracking
        _marketPositions[marketId].push(positionId);
        _marketPositionIndex[positionId] = _marketPositions[marketId].length;

        // Add to market-side tracking
        _marketSidePositions[marketId][isLong].push(positionId);
        _marketSidePositionIndex[positionId] = _marketSidePositions[marketId][isLong].length;

        emit PositionCreated(
            positionId, marketId, owner, isLong, entryPI, entryPrice, positionSize, collateral, leverage,
            block.timestamp
        );
    }

    /// @inheritdoc IPositionManager
    function closePosition(uint256 positionId) external onlyRole(ENGINE) whenNotPaused nonReentrant {
        Position storage pos = _positions[positionId];
        if (pos.id == 0) revert PositionManager__PositionNotFound(positionId);
        if (!pos.isOpen) revert PositionManager__PositionNotOpen(positionId);

        pos.isOpen = false;
        _totalOpenPositions--;

        // Remove from user tracking
        _removeFromArray(_userPositions[pos.owner], _userPositionIndex, positionId);

        // Remove from market tracking
        _removeFromArray(_marketPositions[pos.marketId], _marketPositionIndex, positionId);

        // Remove from market-side tracking
        _removeFromArray(_marketSidePositions[pos.marketId][pos.isLong], _marketSidePositionIndex, positionId);

        emit PositionClosed(positionId, block.timestamp);
    }

    /// @inheritdoc IPositionManager
    function updateCollateral(
        uint256 positionId,
        uint256 newCollateral
    ) external onlyRole(ENGINE) whenNotPaused nonReentrant {
        Position storage pos = _positions[positionId];
        if (pos.id == 0) revert PositionManager__PositionNotFound(positionId);
        if (!pos.isOpen) revert PositionManager__PositionNotOpen(positionId);

        uint256 oldCollateral = pos.collateral;
        pos.collateral = newCollateral;

        emit PositionCollateralUpdated(positionId, oldCollateral, newCollateral);
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

    /// @inheritdoc IPositionManager
    function getPosition(uint256 positionId) external view returns (Position memory) {
        if (_positions[positionId].id == 0) revert PositionManager__PositionNotFound(positionId);
        return _positions[positionId];
    }

    /// @inheritdoc IPositionManager
    function isPositionOpen(uint256 positionId) external view returns (bool) {
        return _positions[positionId].isOpen;
    }

    /// @inheritdoc IPositionManager
    function getPositionOwner(uint256 positionId) external view returns (address) {
        if (_positions[positionId].id == 0) revert PositionManager__PositionNotFound(positionId);
        return _positions[positionId].owner;
    }

    /// @inheritdoc IPositionManager
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return _userPositions[user];
    }

    /// @inheritdoc IPositionManager
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return _marketPositions[marketId];
    }

    /// @inheritdoc IPositionManager
    function getMarketSidePositions(bytes32 marketId, bool isLong) external view returns (uint256[] memory) {
        return _marketSidePositions[marketId][isLong];
    }

    /// @inheritdoc IPositionManager
    function totalOpenPositions() external view returns (uint256) {
        return _totalOpenPositions;
    }

    /// @inheritdoc IPositionManager
    function nextPositionId() external view returns (uint256) {
        return _nextPositionId;
    }

    // ──────────────────────────────────────────────
    // Private Functions
    // ──────────────────────────────────────────────

    /// @dev Swap-and-pop removal from an array with index tracking
    function _removeFromArray(
        uint256[] storage arr,
        mapping(uint256 => uint256) storage indexMap,
        uint256 positionId
    ) private {
        uint256 indexPlusOne = indexMap[positionId];
        if (indexPlusOne == 0) return;

        uint256 lastIndex = arr.length - 1;
        uint256 removeIndex = indexPlusOne - 1;

        if (removeIndex != lastIndex) {
            uint256 lastId = arr[lastIndex];
            arr[removeIndex] = lastId;
            indexMap[lastId] = indexPlusOne;
        }

        arr.pop();
        delete indexMap[positionId];
    }
}
