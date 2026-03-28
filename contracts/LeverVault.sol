// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title LeverVault
/// @notice ERC-4626 vault with tranche ledger for yield-carrying LP shares.
///         Deposits USDT → mints lvUSDT. NAV includes unrealized trader PnL.
///         Withdrawal via two-step queue (request → 48h → execute at current NAV).
///         Transfers use proportional tranche splitting (not FIFO/LIFO).
contract LeverVault is ILeverVault, ERC4626, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint8 public constant MAX_TRANCHES_LIMIT = 10;
    uint256 public constant WITHDRAWAL_COOLDOWN = 172_800; // 48 hours
    uint256 public constant CANCEL_COOLDOWN = 86_400;      // 24 hours
    uint256 public constant MAX_UTIL_FOR_WITHDRAWAL = 8e17; // 80%
    uint256 internal constant WAD = 1e18;

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant EXECUTION_ENGINE_ROLE = keccak256("EXECUTION_ENGINE_ROLE");
    bytes32 public constant LIQUIDATION_ENGINE_ROLE = keccak256("LIQUIDATION_ENGINE_ROLE");

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IRewardsDistributor public immutable rewardsDistributor;
    IERC20 public immutable usdt;

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    /// @dev Tranche ledger per address
    mapping(address => Tranche[]) private _tranches;

    /// @dev Shares currently locked in withdrawal queue per user
    mapping(address => uint256) private _queuedShares;

    /// @dev Withdrawal receipts by ID
    mapping(uint256 => WithdrawalReceipt) private _receipts;

    /// @dev User → list of receipt IDs
    mapping(address => uint256[]) private _userReceiptIds;

    /// @dev Cancel cooldown end timestamp per user
    mapping(address => uint256) private _cancelCooldownEnd;

    /// @dev Next receipt ID counter
    uint256 private _nextReceiptId;

    /// @dev Total shares across all queued withdrawal requests
    uint256 private _totalQueuedShares;

    /// @dev Net unrealized trader PnL (positive = traders profitable = vault owes them)
    int256 private _netUnrealizedPnL;

    /// @dev Socialized loss accumulator (reduces NAV)
    uint256 private _socializedLosses;

    // ──────────────────────────────────────────────
    // Custom Errors (beyond interface)
    // ──────────────────────────────────────────────

    error LeverVault__ZeroAddress();
    error LeverVault__ZeroAmount();

    // ──────────────────────────────────────────────
    // Events (beyond interface)
    // ──────────────────────────────────────────────

    event UnrealizedPnLUpdated(int256 oldPnL, int256 newPnL);
    event LossSocialized(uint256 amount, uint256 totalSocialized);

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin_ Admin address
    /// @param usdt_ USDT token address (deposit asset)
    /// @param rewardsDistributor_ RewardsDistributor contract for yield tracking
    constructor(
        address admin_,
        address usdt_,
        address rewardsDistributor_
    )
        ERC20("Lever Vault USDT", "lvUSDT")
        ERC4626(IERC20(usdt_))
    {
        if (admin_ == address(0)) revert LeverVault__ZeroAddress();
        if (usdt_ == address(0)) revert LeverVault__ZeroAddress();
        if (rewardsDistributor_ == address(0)) revert LeverVault__ZeroAddress();

        usdt = IERC20(usdt_);
        rewardsDistributor = IRewardsDistributor(rewardsDistributor_);

        _grantRole(ADMIN_ROLE, admin_);
        _nextReceiptId = 1;
    }

    // ──────────────────────────────────────────────
    // ERC-4626 Overrides
    // ──────────────────────────────────────────────

    /// @notice Total assets = USDT balance adjusted for unrealized PnL and socialized losses
    /// @dev NAV = USDT_balance - netUnrealizedPnL - socializedLosses
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        uint256 balance = usdt.balanceOf(address(this));
        int256 nav = int256(balance) - _netUnrealizedPnL - int256(_socializedLosses);
        return nav > 0 ? uint256(nav) : 0;
    }

    /// @dev Disable direct ERC-4626 withdraw (must use withdrawal queue)
    function maxWithdraw(address) public pure override(ERC4626, IERC4626) returns (uint256) {
        return 0;
    }

    /// @dev Disable direct ERC-4626 redeem (must use withdrawal queue)
    function maxRedeem(address) public pure override(ERC4626, IERC4626) returns (uint256) {
        return 0;
    }

    /// @dev Override deposit to add tranche tracking
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 shares = super.deposit(assets, receiver);
        _addTranche(receiver, uint128(shares));
        return shares;
    }

    /// @dev Override mint to add tranche tracking
    function mint(uint256 shares, address receiver)
        public
        override(ERC4626, IERC4626)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 assets = super.mint(shares, receiver);
        _addTranche(receiver, uint128(shares));
        return assets;
    }

    /// @dev Override _update to handle tranche splitting on transfers
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        // Mint case: handled by deposit/mint which call _addTranche
        // Burn case: handled by executeWithdrawal which manages tranches
        if (from != address(0) && to != address(0)) {
            // Transfer case: proportional tranche split
            uint256 senderBalance = balanceOf(from);
            uint256 freeShares = senderBalance - _queuedShares[from];
            if (value > freeShares) revert LeverVault__SharesInQueue(value);

            _splitTranches(from, to, value, senderBalance);
        }

        super._update(from, to, value);
    }

    /// @dev Override decimals to resolve multiple inheritance
    function decimals() public view override(ERC4626, IERC20Metadata) returns (uint8) {
        return super.decimals();
    }

    // ──────────────────────────────────────────────
    // External — Withdrawal Queue
    // ──────────────────────────────────────────────

    /// @inheritdoc ILeverVault
    function requestWithdrawal(uint256 shares)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 receiptId)
    {
        if (shares == 0) revert LeverVault__ZeroShares();
        if (isInCooldown(msg.sender)) {
            revert LeverVault__CooldownActive(msg.sender, _cancelCooldownEnd[msg.sender]);
        }

        uint256 freeShares = balanceOf(msg.sender) - _queuedShares[msg.sender];
        if (shares > freeShares) revert LeverVault__SharesInQueue(shares);

        receiptId = _nextReceiptId++;
        _receipts[receiptId] = WithdrawalReceipt({
            id: receiptId,
            owner: msg.sender,
            shares: shares,
            requestTimestamp: block.timestamp,
            executed: false,
            cancelled: false
        });
        _userReceiptIds[msg.sender].push(receiptId);
        _queuedShares[msg.sender] += shares;
        _totalQueuedShares += shares;

        emit WithdrawalRequested(receiptId, msg.sender, shares, block.timestamp);
    }

    /// @inheritdoc ILeverVault
    function executeWithdrawal(uint256 receiptId)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        WithdrawalReceipt storage receipt = _receipts[receiptId];
        if (receipt.owner == address(0)) revert LeverVault__NoWithdrawalRequest(receiptId);
        if (receipt.owner != msg.sender) revert LeverVault__NotReceiptOwner(receiptId, msg.sender);
        if (receipt.executed || receipt.cancelled) revert LeverVault__NoWithdrawalRequest(receiptId);

        uint256 readyAt = receipt.requestTimestamp + WITHDRAWAL_COOLDOWN;
        if (block.timestamp < readyAt) {
            revert LeverVault__WithdrawalNotReady(receiptId, readyAt);
        }

        // Compute assets at current NAV
        uint256 supply = totalSupply();
        uint256 nav = totalAssets();
        uint256 shares = receipt.shares;
        assets = supply > 0 ? (shares * nav) / supply : 0;

        // Update state
        _queuedShares[msg.sender] -= shares;
        _totalQueuedShares -= shares;
        receipt.executed = true;

        // Remove tranches proportionally for the burned shares
        _removeTranches(msg.sender, shares);

        // Burn shares and transfer assets
        _burn(msg.sender, shares);
        if (assets > 0) {
            usdt.safeTransfer(msg.sender, assets);
        }

        emit WithdrawalExecuted(receiptId, msg.sender, shares, assets, block.timestamp);
    }

    /// @inheritdoc ILeverVault
    function cancelWithdrawal(uint256 receiptId) external nonReentrant {
        WithdrawalReceipt storage receipt = _receipts[receiptId];
        if (receipt.owner == address(0)) revert LeverVault__NoWithdrawalRequest(receiptId);
        if (receipt.owner != msg.sender) revert LeverVault__NotReceiptOwner(receiptId, msg.sender);
        if (receipt.executed || receipt.cancelled) revert LeverVault__NoWithdrawalRequest(receiptId);

        receipt.cancelled = true;
        _queuedShares[msg.sender] -= receipt.shares;
        _totalQueuedShares -= receipt.shares;
        _cancelCooldownEnd[msg.sender] = block.timestamp + CANCEL_COOLDOWN;

        emit WithdrawalCancelled(receiptId, msg.sender, receipt.shares, block.timestamp);
    }

    // ──────────────────────────────────────────────
    // External — Yield (vault computes, distributor releases)
    // ──────────────────────────────────────────────

    /// @inheritdoc ILeverVault
    function claim() external nonReentrant returns (uint256 amount) {
        amount = _computeAndResetYield(msg.sender);
        if (amount == 0) revert LeverVault__ZeroAmount();
        rewardsDistributor.releaseRewards(msg.sender, amount);
    }

    /// @inheritdoc ILeverVault
    function compound() external nonReentrant whenNotPaused returns (uint256 newShares) {
        uint256 amount = _computeAndResetYield(msg.sender);
        if (amount == 0) return 0;

        // Release yield to vault, then mint shares
        rewardsDistributor.releaseRewards(address(this), amount);
        newShares = previewDeposit(amount);
        _mint(msg.sender, newShares);
        _addTranche(msg.sender, uint128(newShares));

        emit Deposit(msg.sender, msg.sender, amount, newShares);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (NAV management)
    // ──────────────────────────────────────────────

    /// @notice Update the net unrealized trader PnL for NAV calculation
    /// @param newPnL New net unrealized PnL (positive = traders profitable)
    function updateUnrealizedPnL(int256 newPnL) external onlyRole(EXECUTION_ENGINE_ROLE) {
        int256 oldPnL = _netUnrealizedPnL;
        _netUnrealizedPnL = newPnL;
        emit UnrealizedPnLUpdated(oldPnL, newPnL);
    }

    /// @inheritdoc ILeverVault
    function fundTraderPnL(address recipient, uint256 amount) external onlyRole(EXECUTION_ENGINE_ROLE) {
        if (recipient == address(0)) revert LeverVault__ZeroAddress();
        if (amount == 0) revert LeverVault__ZeroAmount();
        usdt.safeTransfer(recipient, amount);
    }

    /// @inheritdoc ILeverVault
    /// @dev Callable by both LiquidationEngine and ExecutionEngine for bad debt socialization
    function socializeLoss(uint256 amount) external {
        if (!hasRole(LIQUIDATION_ENGINE_ROLE, msg.sender) && !hasRole(EXECUTION_ENGINE_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, LIQUIDATION_ENGINE_ROLE);
        }
        if (amount == 0) revert LeverVault__ZeroAmount();
        _socializedLosses += amount;
        emit LossSocialized(amount, _socializedLosses);
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
    // External — View (Tranche System)
    // ──────────────────────────────────────────────

    /// @inheritdoc ILeverVault
    function getTranches(address holder) external view returns (Tranche[] memory) {
        return _tranches[holder];
    }

    /// @inheritdoc ILeverVault
    function pendingYield(address holder) external view returns (uint256 yield_) {
        uint256 currentIndex = rewardsDistributor.rewardPerShareCumulative();
        Tranche[] storage tranches = _tranches[holder];
        for (uint256 i; i < tranches.length; ++i) {
            if (currentIndex > tranches[i].rewardSnapshot) {
                yield_ += uint256(tranches[i].shares).wadMul(
                    uint256(currentIndex - tranches[i].rewardSnapshot)
                );
            }
        }
    }

    /// @inheritdoc ILeverVault
    function weightedAge(address holder) external view returns (uint256 ageSeconds) {
        Tranche[] storage tranches = _tranches[holder];
        if (tranches.length == 0) return 0;
        return tranches.length;
    }

    /// @inheritdoc ILeverVault
    function totalValue(address holder) external view returns (uint256 value) {
        uint256 shares = balanceOf(holder);
        uint256 supply = totalSupply();
        uint256 nav = totalAssets();

        if (supply > 0 && shares > 0) {
            value = (shares * nav) / supply;
        }

        uint256 currentIndex = rewardsDistributor.rewardPerShareCumulative();
        Tranche[] storage tranches = _tranches[holder];
        for (uint256 i; i < tranches.length; ++i) {
            if (currentIndex > tranches[i].rewardSnapshot) {
                value += uint256(tranches[i].shares).wadMul(
                    uint256(currentIndex - tranches[i].rewardSnapshot)
                );
            }
        }
    }

    /// @inheritdoc ILeverVault
    function maxTranches() external pure returns (uint8) {
        return MAX_TRANCHES_LIMIT;
    }

    // ──────────────────────────────────────────────
    // External — View (Vault Health)
    // ──────────────────────────────────────────────

    /// @inheritdoc ILeverVault
    function getNAV() external view returns (uint256 nav) {
        return totalAssets();
    }

    /// @inheritdoc ILeverVault
    function getUtilization() external view returns (uint256) {
        return 0;
    }

    /// @inheritdoc ILeverVault
    function withdrawalsEnabled() external view returns (bool) {
        return true;
    }

    /// @inheritdoc ILeverVault
    function totalQueuedShares() external view returns (uint256) {
        return _totalQueuedShares;
    }

    /// @inheritdoc ILeverVault
    function getReceipt(uint256 receiptId) external view returns (WithdrawalReceipt memory) {
        return _receipts[receiptId];
    }

    /// @inheritdoc ILeverVault
    function getUserReceipts(address user) external view returns (WithdrawalReceipt[] memory) {
        uint256[] storage ids = _userReceiptIds[user];
        WithdrawalReceipt[] memory receipts = new WithdrawalReceipt[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            receipts[i] = _receipts[ids[i]];
        }
        return receipts;
    }

    /// @inheritdoc ILeverVault
    function isInCooldown(address user) public view returns (bool) {
        return block.timestamp < _cancelCooldownEnd[user];
    }

    // ──────────────────────────────────────────────
    // Internal — Yield Computation
    // ──────────────────────────────────────────────

    /// @dev Compute pending yield for a user and reset all tranche snapshots to current index
    function _computeAndResetYield(address user) internal returns (uint256 totalYield) {
        uint256 currentIndex = rewardsDistributor.rewardPerShareCumulative();
        Tranche[] storage tranches = _tranches[user];
        for (uint256 i; i < tranches.length; ++i) {
            if (currentIndex > tranches[i].rewardSnapshot) {
                totalYield += uint256(tranches[i].shares).wadMul(
                    uint256(currentIndex - tranches[i].rewardSnapshot)
                );
                tranches[i].rewardSnapshot = uint128(currentIndex);
            }
        }
    }

    // ──────────────────────────────────────────────
    // Internal — Tranche Management
    // ──────────────────────────────────────────────

    /// @dev Add a new tranche for a receiver. Consolidate if exceeding MAX_TRANCHES.
    function _addTranche(address receiver, uint128 shares) internal {
        if (shares == 0) return;

        uint128 snapshot = uint128(rewardsDistributor.rewardPerShareCumulative());
        _tranches[receiver].push(Tranche(shares, snapshot));

        if (_tranches[receiver].length > MAX_TRANCHES_LIMIT) {
            _consolidateOldest(receiver);
        }
    }

    /// @dev Proportional tranche split from sender to receiver
    function _splitTranches(address from, address to, uint256 amount, uint256 senderBalance) internal {
        Tranche[] storage senderTranches = _tranches[from];
        uint256 len = senderTranches.length;
        if (len == 0) return;

        uint256 fraction = (amount * WAD) / senderBalance;

        uint256 totalMoved;
        for (uint256 i; i < len; ++i) {
            uint128 sharesToMove = uint128((uint256(senderTranches[i].shares) * fraction) / WAD);
            if (sharesToMove > 0) {
                senderTranches[i].shares -= sharesToMove;
                _tranches[to].push(Tranche(sharesToMove, senderTranches[i].rewardSnapshot));
                totalMoved += sharesToMove;
            }
        }

        // Handle dust: if totalMoved < amount due to rounding, take from largest tranche
        if (totalMoved < amount) {
            uint256 dust = amount - totalMoved;
            for (uint256 i = len; i > 0; --i) {
                if (senderTranches[i - 1].shares >= dust) {
                    senderTranches[i - 1].shares -= uint128(dust);
                    Tranche[] storage receiverTranches = _tranches[to];
                    if (receiverTranches.length > 0) {
                        receiverTranches[receiverTranches.length - 1].shares += uint128(dust);
                    } else {
                        receiverTranches.push(Tranche(uint128(dust), senderTranches[i - 1].rewardSnapshot));
                    }
                    break;
                }
            }
        }

        _cleanZeroTranches(from);

        while (_tranches[to].length > MAX_TRANCHES_LIMIT) {
            _consolidateOldest(to);
        }
    }

    /// @dev Remove tranches proportionally when burning shares (withdrawal execution)
    function _removeTranches(address holder, uint256 sharesToRemove) internal {
        Tranche[] storage tranches = _tranches[holder];
        uint256 len = tranches.length;
        if (len == 0) return;

        uint256 totalShares = balanceOf(holder);
        if (totalShares == 0) return;

        uint256 fraction = (sharesToRemove * WAD) / totalShares;
        uint256 totalRemoved;

        for (uint256 i; i < len; ++i) {
            uint128 toRemove = uint128((uint256(tranches[i].shares) * fraction) / WAD);
            if (toRemove > tranches[i].shares) toRemove = tranches[i].shares;
            tranches[i].shares -= toRemove;
            totalRemoved += toRemove;
        }

        if (totalRemoved < sharesToRemove) {
            uint256 dust = sharesToRemove - totalRemoved;
            for (uint256 i = len; i > 0; --i) {
                if (tranches[i - 1].shares >= dust) {
                    tranches[i - 1].shares -= uint128(dust);
                    break;
                }
            }
        }

        _cleanZeroTranches(holder);
    }

    /// @dev Merge two oldest tranches (index 0 and 1)
    function _consolidateOldest(address holder) internal {
        Tranche[] storage tranches = _tranches[holder];
        uint256 len = tranches.length;
        if (len < 2) return;

        uint256 oldCount = len;
        uint128 sharesA = tranches[0].shares;
        uint128 sharesB = tranches[1].shares;
        uint128 mergedShares = sharesA + sharesB;

        uint128 mergedSnapshot;
        if (mergedShares > 0) {
            mergedSnapshot = uint128(
                (uint256(sharesA) * uint256(tranches[0].rewardSnapshot)
                    + uint256(sharesB) * uint256(tranches[1].rewardSnapshot))
                    / uint256(mergedShares)
            );
        }

        tranches[0] = Tranche(mergedShares, mergedSnapshot);
        for (uint256 i = 1; i < len - 1; ++i) {
            tranches[i] = tranches[i + 1];
        }
        tranches.pop();

        emit TrancheConsolidated(holder, oldCount, tranches.length);
    }

    /// @dev Remove zero-share tranches from an address
    function _cleanZeroTranches(address holder) internal {
        Tranche[] storage tranches = _tranches[holder];
        uint256 i;
        while (i < tranches.length) {
            if (tranches[i].shares == 0) {
                tranches[i] = tranches[tranches.length - 1];
                tranches.pop();
            } else {
                ++i;
            }
        }
    }

    /// @notice Required override for AccessControl + ERC20
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
