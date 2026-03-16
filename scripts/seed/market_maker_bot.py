#!/usr/bin/env python3
"""
Market Maker Bot — Provide liquidity by placing positions on both sides of markets.

This bot:
1. Places LONG and SHORT positions on the same markets (both sides)
2. Uses 5x-10x leverage range as specified for market makers
3. Maintains balanced exposure across top volume markets
4. Rebalances positions every 5-10 minutes to maintain liquidity
5. Generates consistent fee revenue and balanced OI

Environment variables:
    RPC_URL            — Base Sepolia RPC endpoint
    MM_BOT_KEY         — Private key for market maker bot wallet
    USDT_ADDRESS       — MockUSDT contract address
    EXECUTION_ENGINE   — ExecutionEngine contract address
    ACCOUNT_MANAGER    — AccountManager contract address
    MM_INTERVAL        — Seconds between rebalance checks (default: 300)
    MM_POSITION_SIZE   — Base position size in USDT (default: 20000)
    DRY_RUN            — Set to "true" to skip on-chain calls
"""

import json
import logging
import os
import random
import sys
import time
from pathlib import Path

from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
USDT_DECIMALS = 6
USDT_UNIT = 10**USDT_DECIMALS
WAD = 10**18
DEFAULT_INTERVAL = 300  # 5 minutes
DEFAULT_POSITION_SIZE = 20000  # $20k USDT per side
MIN_LEVERAGE = 5  # MM leverage range: 5x-10x
MAX_LEVERAGE = 10
FAUCET_AMOUNT = 10000  # MockUSDT faucet gives 10k

# Market making strategy
MM_MARKETS = [0, 1, 4, 6, 9]  # Top 5 markets: SpaceX, US-Iran, Fed Rate, AAPL, Argentina
REBALANCE_THRESHOLD = 0.2  # Rebalance if position sizes drift > 20%
MAX_POSITIONS_PER_MARKET = 2  # 1 long + 1 short per market

# Contract ABIs
USDT_ABI = [
    {
        "type": "function",
        "name": "balanceOf",
        "inputs": [{"name": "account", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "faucet",
        "inputs": [],
        "outputs": [],
        "stateMutability": "nonpayable",
    }
]

ACCOUNT_ABI = [
    {
        "type": "function",
        "name": "deposit",
        "inputs": [{"name": "amount", "type": "uint256"}],
        "outputs": [],
        "stateMutability": "nonpayable",
    },
    {
        "type": "function",
        "name": "getBalance",
        "inputs": [{"name": "user", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "getUserPositions",
        "inputs": [{"name": "user", "type": "address"}],
        "outputs": [{"name": "", "type": "bytes32[]"}],
        "stateMutability": "view",
    }
]

EXECUTION_ABI = [
    {
        "type": "function",
        "name": "openPosition",
        "inputs": [
            {"name": "marketId", "type": "bytes32"},
            {"name": "direction", "type": "uint8"},
            {"name": "collateral", "type": "uint256"},
            {"name": "leverage", "type": "uint256"}
        ],
        "outputs": [{"name": "positionId", "type": "bytes32"}],
        "stateMutability": "nonpayable",
    },
    {
        "type": "function",
        "name": "closePosition",
        "inputs": [{"name": "positionId", "type": "bytes32"}],
        "outputs": [],
        "stateMutability": "nonpayable",
    }
]

def usdt_to_units(usdt_amount: float) -> int:
    """Convert USDT amount to contract units (6 decimals)."""
    return int(usdt_amount * USDT_UNIT)

def units_to_usdt(units: int) -> float:
    """Convert contract units to USDT amount."""
    return units / USDT_UNIT

def wad_to_float(wad: int) -> float:
    """Convert WAD to float."""
    return wad / WAD

def float_to_wad(value: float) -> int:
    """Convert float to WAD."""
    return int(value * WAD)

class MarketMakerBot:
    """Provides liquidity by maintaining positions on both sides of markets."""

    def __init__(
        self,
        rpc_url: str,
        private_key: str,
        usdt_address: str,
        execution_address: str,
        account_address: str,
        demo_markets: list,
        position_size: float = DEFAULT_POSITION_SIZE,
        dry_run: bool = False,
    ):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to RPC: {rpc_url}")

        self.account = self.w3.eth.account.from_key(private_key)
        self.demo_markets = demo_markets
        self.position_size = position_size
        self.dry_run = dry_run

        # Contract instances
        self.usdt = self.w3.eth.contract(
            address=Web3.to_checksum_address(usdt_address),
            abi=USDT_ABI,
        )
        self.execution = self.w3.eth.contract(
            address=Web3.to_checksum_address(execution_address),
            abi=EXECUTION_ABI,
        )
        self.account_mgr = self.w3.eth.contract(
            address=Web3.to_checksum_address(account_address),
            abi=ACCOUNT_ABI,
        )

        # Track MM positions: market_id -> {"long": position_data, "short": position_data}
        self.mm_positions = {}

        logger.info(f"Market Maker Bot initialized: {len(MM_MARKETS)} target markets, dry_run={dry_run}")
        logger.info(f"Bot address: {self.account.address}")
        logger.info(f"Position size: ${position_size:,.0f} per side, leverage: {MIN_LEVERAGE}x-{MAX_LEVERAGE}x")

    def ensure_usdt_balance(self, needed: float) -> bool:
        """Ensure bot has enough USDT balance."""
        try:
            balance = units_to_usdt(
                self.usdt.functions.balanceOf(self.account.address).call()
            )

            if balance >= needed:
                return True

            logger.info(f"Need ${needed:,.0f} USDT, have ${balance:,.2f} — calling faucet")

            if self.dry_run:
                logger.info("  [DRY RUN] Would call faucet")
                return True

            # Call faucet multiple times if needed
            faucets_needed = int((needed - balance) / FAUCET_AMOUNT) + 1
            for i in range(faucets_needed):
                tx = self.usdt.functions.faucet().build_transaction({
                    "from": self.account.address,
                    "nonce": self.w3.eth.get_transaction_count(self.account.address),
                    "gas": 100_000,
                    "maxFeePerGas": self.w3.eth.gas_price * 2,
                    "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
                })

                signed = self.account.sign_transaction(tx)
                tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
                receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

                if receipt.status != 1:
                    return False

                time.sleep(1)  # Avoid spam

            return True

        except Exception as e:
            logger.error(f"Failed to ensure USDT balance: {e}")
            return False

    def deposit_to_account(self, amount: float) -> bool:
        """Deposit USDT to AccountManager."""
        try:
            amount_units = usdt_to_units(amount)

            logger.info(f"Depositing ${amount:,.0f} to AccountManager")

            if self.dry_run:
                logger.info("  [DRY RUN] Would deposit to AccountManager")
                return True

            # Approve and deposit
            approve_tx = self.usdt.functions.approve(
                self.account_mgr.address,
                amount_units
            ).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 100_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(approve_tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

            deposit_tx = self.account_mgr.functions.deposit(amount_units).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 200_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(deposit_tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

            return receipt.status == 1

        except Exception as e:
            logger.error(f"Failed to deposit to account: {e}")
            return False

    def generate_mm_params(self, market_idx: int) -> tuple:
        """Generate market making parameters for a specific market."""
        market = self.demo_markets[market_idx]
        market_id = "0x" + market["name"].encode().hex()[:64].ljust(64, '0')

        # MM leverage: 5x-10x with preference for 7x-8x
        leverage_weights = [0.15, 0.2, 0.3, 0.25, 0.1]  # 5x, 6x, 7x, 8x, 9x, 10x
        leverage = random.choices(range(5, 11), weights=leverage_weights)[0]

        # Position size varies ±20% around base
        size_variance = random.uniform(-0.2, 0.2)
        adjusted_size = self.position_size * (1 + size_variance)

        return market_id, market["name"], leverage, adjusted_size

    def open_mm_position(self, market_id: str, market_name: str, is_long: bool,
                        collateral: float, leverage: float) -> str:
        """Open a market making position."""
        try:
            collateral_wad = float_to_wad(collateral)
            leverage_wad = float_to_wad(leverage)

            direction_str = "LONG" if is_long else "SHORT"
            notional = collateral * leverage

            logger.info(
                f"Opening MM {direction_str}: {market_name[:30]}... "
                f"${collateral:,.0f} @ {leverage:.1f}× (${notional:,.0f} notional)"
            )

            if self.dry_run:
                logger.info("  [DRY RUN] Would open MM position")
                position_id = f"mm_dry_{market_id}_{direction_str}_{int(time.time())}"
                return position_id

            # Ensure enough balance
            current_balance = units_to_usdt(
                self.account_mgr.functions.getBalance(self.account.address).call()
            )

            if current_balance < collateral:
                needed = collateral * 2  # Need for both sides
                if self.ensure_usdt_balance(needed):
                    if not self.deposit_to_account(needed):
                        return None

            # Open position
            tx = self.execution.functions.openPosition(
                bytes.fromhex(market_id[2:]),
                0 if is_long else 1,
                collateral_wad,
                leverage_wad
            ).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 500_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)

            if receipt.status == 1:
                position_id = f"mm_{market_id}_{direction_str}_{tx_hash.hex()}"
                logger.info(f"  MM position opened! tx={tx_hash.hex()[:18]}...")
                return position_id
            else:
                logger.error(f"  MM position reverted: {tx_hash.hex()}")
                return None

        except Exception as e:
            logger.error(f"Failed to open MM position: {e}")
            return None

    def create_mm_pair(self, market_idx: int) -> dict:
        """Create a matched long/short pair for market making."""
        try:
            market_id, market_name, leverage, base_size = self.generate_mm_params(market_idx)

            # Calculate collateral for each side
            collateral_per_side = base_size / leverage

            logger.info(f"Creating MM pair for {market_name}")
            logger.info(f"  Leverage: {leverage}x, Size: ${base_size:,.0f} per side")

            positions = {"long": None, "short": None}

            # Open LONG position
            long_position = self.open_mm_position(
                market_id, market_name, True, collateral_per_side, leverage
            )
            if long_position:
                positions["long"] = {
                    "position_id": long_position,
                    "collateral": collateral_per_side,
                    "leverage": leverage,
                    "open_time": time.time()
                }

            # Wait between sides
            time.sleep(2)

            # Open SHORT position
            short_position = self.open_mm_position(
                market_id, market_name, False, collateral_per_side, leverage
            )
            if short_position:
                positions["short"] = {
                    "position_id": short_position,
                    "collateral": collateral_per_side,
                    "leverage": leverage,
                    "open_time": time.time()
                }

            # Store MM pair
            if positions["long"] or positions["short"]:
                self.mm_positions[market_id] = positions
                logger.info(f"  MM pair created: long={positions['long'] is not None}, "
                          f"short={positions['short'] is not None}")

            return positions

        except Exception as e:
            logger.error(f"Failed to create MM pair: {e}")
            return {"long": None, "short": None}

    def rebalance_mm_positions(self) -> dict:
        """Rebalance existing MM positions if needed."""
        stats = {"created": 0, "rebalanced": 0, "errors": 0}

        try:
            # Create MM pairs for target markets if not existing
            for market_idx in MM_MARKETS:
                market = self.demo_markets[market_idx]
                market_id = "0x" + market["name"].encode().hex()[:64].ljust(64, '0')

                if market_id not in self.mm_positions:
                    logger.info(f"Creating new MM pair for market {market_idx}")
                    positions = self.create_mm_pair(market_idx)
                    if positions["long"] or positions["short"]:
                        stats["created"] += 1
                    else:
                        stats["errors"] += 1

            # Log current MM status
            total_pairs = len(self.mm_positions)
            active_longs = sum(1 for pos in self.mm_positions.values() if pos.get("long"))
            active_shorts = sum(1 for pos in self.mm_positions.values() if pos.get("short"))

            logger.info(f"MM Status: {total_pairs} pairs, {active_longs} longs, {active_shorts} shorts")

        except Exception as e:
            logger.error(f"MM rebalance error: {e}")
            stats["errors"] += 1

        return stats

    def run_mm_loop(self, interval: int = DEFAULT_INTERVAL):
        """Run market maker bot in continuous loop."""
        logger.info(f"Starting MM bot loop (interval={interval}s)")
        logger.info(f"Target markets: {len(MM_MARKETS)} ({MM_MARKETS})")

        while True:
            try:
                start = time.time()
                stats = self.rebalance_mm_positions()
                elapsed = time.time() - start

                total_positions = sum(
                    (1 if pos.get("long") else 0) + (1 if pos.get("short") else 0)
                    for pos in self.mm_positions.values()
                )

                logger.info(
                    f"MM cycle complete in {elapsed:.1f}s — "
                    f"pairs={len(self.mm_positions)} total_positions={total_positions} "
                    f"created={stats['created']} rebalanced={stats['rebalanced']} "
                    f"errors={stats['errors']}"
                )

            except KeyboardInterrupt:
                logger.info("Market Maker Bot stopped by user")
                break
            except Exception as e:
                logger.error(f"MM cycle error: {e}")

            # Sleep until next interval
            sleep_time = max(0, interval - (time.time() - start))
            if sleep_time > 0:
                time.sleep(sleep_time)

# ─── CLI ──────────────────────────────────────────────

def load_demo_markets(config_path: str) -> list:
    """Load demo markets from JSON file."""
    with open(config_path) as f:
        data = json.load(f)
    return data.get("markets", [])

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | MM-BOT | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    rpc_url = os.environ.get("RPC_URL")
    private_key = os.environ.get("MM_BOT_KEY")
    usdt_address = os.environ.get("USDT_ADDRESS")
    execution_address = os.environ.get("EXECUTION_ENGINE")
    account_address = os.environ.get("ACCOUNT_MANAGER")
    interval = int(os.environ.get("MM_INTERVAL", str(DEFAULT_INTERVAL)))
    position_size = float(os.environ.get("MM_POSITION_SIZE", str(DEFAULT_POSITION_SIZE)))
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    if not rpc_url:
        logger.error("RPC_URL not set")
        sys.exit(1)
    if not private_key:
        logger.error("MM_BOT_KEY not set")
        sys.exit(1)
    if not execution_address:
        logger.error("EXECUTION_ENGINE not set")
        sys.exit(1)

    # Load demo markets
    demo_config_path = "scripts/oracle/demo_markets.json"
    demo_markets = load_demo_markets(demo_config_path)
    if not demo_markets:
        logger.error(f"No demo markets found in {demo_config_path}")
        sys.exit(1)

    logger.info(f"Loaded {len(demo_markets)} demo markets")

    bot = MarketMakerBot(
        rpc_url=rpc_url,
        private_key=private_key,
        usdt_address=usdt_address,
        execution_address=execution_address,
        account_address=account_address,
        demo_markets=demo_markets,
        position_size=position_size,
        dry_run=dry_run,
    )

    bot.run_mm_loop(interval=interval)

if __name__ == "__main__":
    main()