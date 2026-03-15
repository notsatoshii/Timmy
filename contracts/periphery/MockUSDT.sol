// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDT — Testnet USDT with faucet
/// @notice 6-decimal ERC-20 mimicking real Tether. Anyone can mint via faucet (capped per call).
///         Owner can mint unlimited for seeding contracts.
/// @dev For Base Sepolia testnet use ONLY. Not for production.
contract MockUSDT is ERC20, Ownable {
    // ─── Constants ───────────────────────────────────
    uint256 public constant FAUCET_AMOUNT = 10_000e6; // 10,000 USDT per faucet call
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    // ─── Errors ──────────────────────────────────────
    error MockUSDT__FaucetCooldown(uint256 nextAvailable);

    // ─── Events ──────────────────────────────────────
    event FaucetDrip(address indexed recipient, uint256 amount);

    // ─── State ───────────────────────────────────────
    mapping(address => uint256) public lastFaucetTime;

    // ─── Constructor ─────────────────────────────────
    constructor() ERC20("Mock USDT", "USDT") Ownable(msg.sender) {}

    // ─── Overrides ───────────────────────────────────
    /// @notice Returns 6 decimals to match real USDT
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // ─── External Functions ──────────────────────────

    /// @notice Public faucet — anyone can request testnet USDT (rate-limited)
    function faucet() external {
        uint256 nextAvailable = lastFaucetTime[msg.sender] + FAUCET_COOLDOWN;
        if (block.timestamp < nextAvailable) {
            revert MockUSDT__FaucetCooldown(nextAvailable);
        }

        lastFaucetTime[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);

        emit FaucetDrip(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Faucet to a specific address (anyone can call, rate-limited per recipient)
    function faucetTo(address recipient) external {
        uint256 nextAvailable = lastFaucetTime[recipient] + FAUCET_COOLDOWN;
        if (block.timestamp < nextAvailable) {
            revert MockUSDT__FaucetCooldown(nextAvailable);
        }

        lastFaucetTime[recipient] = block.timestamp;
        _mint(recipient, FAUCET_AMOUNT);

        emit FaucetDrip(recipient, FAUCET_AMOUNT);
    }

    /// @notice Owner-only unlimited mint for seeding contracts and LPs
    /// @param to Recipient address
    /// @param amount Amount in 6-decimal format (e.g., 1_000_000e6 = 1M USDT)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
