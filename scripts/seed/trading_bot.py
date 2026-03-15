#!/usr/bin/env python3
"""
Trading Seeding Bot — Simulate realistic trading activity on demo markets.

This bot:
1. Opens positions on demo markets with varying sizes and directions
2. Occasionally closes positions to simulate real trading behavior
3. Uses different leverage levels and timing patterns
4. Generates borrow fees, funding payments, and trading volume

Environment variables:
    RPC_URL            — Base Sepolia RPC endpoint
    TRADER_BOT_KEY     — Private key for trader bot wallet
    USDT_ADDRESS       — MockUSDT contract address
    EXECUTION_ENGINE   — ExecutionEngine contract address
    ACCOUNT_MANAGER    — AccountManager contract address
    TRADE_INTERVAL     — Seconds between trades (default: 60)
    POSITION_SIZE_MIN  — Min position size in USDT (default: 100)
    POSITION_SIZE_MAX  — Max position size in USDT (default: 2000)
    MAX_LEVERAGE       — Max leverage to use (default: 10)
    DRY_RUN            — Set to "true" to skip on-chain calls
"""

import json
import logging
import os
import random
import sys
import time
from pathlib import Path

# Use oracle venv if available
VENV_PATH = Path(__file__).parent.parent / "oracle" / ".venv" / "lib"
if VENV_PATH.exists():
    import site
    for p in VENV_PATH.glob("python*/site-packages"):
        site.addsitedir(str(p))

from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
USDT_DECIMALS = 6
USDT_UNIT = 10**USDT_DECIMALS
WAD = 10**18
DEFAULT_INTERVAL = 60  # 1 minute
DEFAULT_MIN_SIZE = 100  # $100 USDT
DEFAULT_MAX_SIZE = 2000  # $2k USDT
DEFAULT_MAX_LEVERAGE = 10
FAUCET_AMOUNT = 10000  # MockUSDT faucet gives 10k

# Trading patterns - realistic behavior
POSITION_HOLD_TIME_MIN = 300    # 5 minutes
POSITION_HOLD_TIME_MAX = 3600   # 1 hour
LONG_BIAS_MARKETS = ["tech", "crypto", "stocks"]  # Tend to go long
SHORT_BIAS_MARKETS = ["geopolitics"]  # Tend to go short

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
        "name": "getPositionCount",
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

class TradingBot:
    """Simulates realistic trading activity on demo markets."""

    def __init__(
        self,
        rpc_url: str,
        private_key: str,
        usdt_address: str,
        execution_address: str,
        account_address: str,
        demo_markets: list,
        min_size: float = DEFAULT_MIN_SIZE,
        max_size: float = DEFAULT_MAX_SIZE,
        max_leverage: float = DEFAULT_MAX_LEVERAGE,
        dry_run: bool = False,
    ):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to RPC: {rpc_url}")

        self.account = self.w3.eth.account.from_key(private_key)
        self.demo_markets = demo_markets
        self.min_size = min_size
        self.max_size = max_size
        self.max_leverage = max_leverage
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

        # Track open positions
        self.open_positions = []  # [(position_id, market_id, open_time, direction, size)]

        logger.info(f"Trading Bot initialized: {len(demo_markets)} markets, dry_run={dry_run}")
        logger.info(f"Bot address: {self.account.address}")
        logger.info(f"Position size: ${min_size:,.0f} - ${max_size:,.0f}, max leverage: {max_leverage}×")

    def ensure_usdt_balance(self, needed: float) -> bool:
        """Ensure bot has enough USDT balance."""
        try:
            # Check current balance
            balance = units_to_usdt(
                self.usdt.functions.balanceOf(self.account.address).call()
            )

            if balance >= needed:
                return True

            logger.info(f"Need ${needed:,.0f} USDT, have ${balance:,.2f} — calling faucet")

            if self.dry_run:
                logger.info("  [DRY RUN] Would call faucet")
                return True

            # Call faucet
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

            return receipt.status == 1

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

            # First approve
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

            # Then deposit
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

    def select_trade_params(self) -> tuple:
        """Select random trade parameters based on market behavior patterns."""
        # Pick random market
        market = random.choice(self.demo_markets)
        market_id = "0x" + market["name"].encode().hex()[:64].ljust(64, '0')

        # Position size (slightly favor smaller sizes)
        size = random.uniform(self.min_size, self.max_size)
        if random.random() < 0.7:  # 70% chance of smaller position
            size = random.uniform(self.min_size, (self.min_size + self.max_size) / 2)

        # Leverage (favor moderate leverage)
        leverage_weights = [0.4, 0.3, 0.2, 0.1]  # Favor 1-2×, then 3-5×, then higher
        leverage_ranges = [(1, 2), (3, 5), (6, 8), (9, self.max_leverage)]
        leverage_range = random.choices(leverage_ranges, weights=leverage_weights)[0]
        leverage = random.uniform(*leverage_range)

        # Direction based on market bias
        category = market["category"]
        if category in LONG_BIAS_MARKETS:
            direction = 0 if random.random() < 0.7 else 1  # 70% long bias
        elif category in SHORT_BIAS_MARKETS:
            direction = 1 if random.random() < 0.6 else 0  # 60% short bias
        else:
            direction = random.randint(0, 1)  # 50/50

        return market_id, market["name"], direction, size, leverage

    def open_position(self, market_id: str, direction: int, size: float, leverage: float) -> str:
        """Open a position on the specified market."""
        try:
            collateral = size / leverage
            collateral_wad = float_to_wad(collateral)
            leverage_wad = float_to_wad(leverage)

            direction_str = "LONG" if direction == 0 else "SHORT"
            logger.info(
                f"Opening {direction_str} position: ${size:,.0f} @ {leverage:.1f}× "
                f"(collateral: ${collateral:,.0f})"
            )

            if self.dry_run:
                logger.info("  [DRY RUN] Would open position")
                position_id = f"dry_run_{int(time.time())}"
                self.open_positions.append((
                    position_id, market_id, time.time(), direction, size
                ))
                return position_id

            # Ensure enough balance in AccountManager
            current_balance = units_to_usdt(
                self.account_mgr.functions.getBalance(self.account.address).call()
            )

            if current_balance < collateral:
                needed = collateral * 1.5  # Extra buffer
                if self.ensure_usdt_balance(needed):
                    if not self.deposit_to_account(needed):
                        return None

            # Open position
            tx = self.execution.functions.openPosition(
                bytes.fromhex(market_id[2:]),
                direction,
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
                # Extract position ID from logs (simplified)
                position_id = f"0x{tx_hash.hex()}"  # Use tx hash as proxy
                self.open_positions.append((
                    position_id, market_id, time.time(), direction, size
                ))
                logger.info(f"  Position opened! tx={tx_hash.hex()[:18]}...")
                return position_id
            else:
                logger.error(f"  Position open reverted: {tx_hash.hex()}")
                return None

        except Exception as e:
            logger.error(f"Failed to open position: {e}")
            return None

    def close_random_position(self) -> bool:
        """Close a random old position."""
        if not self.open_positions:
            return True

        # Find positions older than minimum hold time
        now = time.time()
        old_positions = [
            pos for pos in self.open_positions
            if now - pos[2] >= POSITION_HOLD_TIME_MIN
        ]

        if not old_positions:
            return True

        # Pick random old position
        position = random.choice(old_positions)
        position_id, market_id, open_time, direction, size = position

        age_minutes = (now - open_time) / 60
        direction_str = "LONG" if direction == 0 else "SHORT"

        logger.info(
            f"Closing {direction_str} position (age: {age_minutes:.1f}m, size: ${size:,.0f})"
        )

        if self.dry_run:
            logger.info("  [DRY RUN] Would close position")
            self.open_positions.remove(position)
            return True

        try:
            # Close position
            tx = self.execution.functions.closePosition(
                bytes.fromhex(position_id[2:])
            ).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 400_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)

            if receipt.status == 1:
                self.open_positions.remove(position)
                logger.info(f"  Position closed! tx={tx_hash.hex()[:18]}...")
                return True
            else:
                logger.error(f"  Position close reverted: {tx_hash.hex()}")
                return False

        except Exception as e:
            logger.error(f"Failed to close position: {e}")
            return False

    def trading_cycle(self) -> dict:
        """Execute one trading cycle."""
        stats = {"opens": 0, "closes": 0, "errors": 0}

        try:
            # 60% chance to open a new position
            if random.random() < 0.6:
                market_id, market_name, direction, size, leverage = self.select_trade_params()
                logger.info(f"Selected market: {market_name[:50]}...")

                if self.open_position(market_id, direction, size, leverage):
                    stats["opens"] += 1
                else:
                    stats["errors"] += 1

            # 30% chance to close an old position (if any exist)
            if random.random() < 0.3 and self.open_positions:
                if self.close_random_position():
                    stats["closes"] += 1
                else:
                    stats["errors"] += 1

            # Cleanup very old positions (force close after max hold time)
            now = time.time()
            very_old = [
                pos for pos in self.open_positions
                if now - pos[2] >= POSITION_HOLD_TIME_MAX
            ]

            for position in very_old[:2]:  # Close max 2 per cycle
                if self.close_random_position():
                    stats["closes"] += 1

        except Exception as e:
            logger.error(f"Trading cycle error: {e}")
            stats["errors"] += 1

        return stats

    def run_loop(self, interval: int = DEFAULT_INTERVAL):
        """Run trading bot in continuous loop."""
        logger.info(f"Starting trading bot loop (interval={interval}s)")

        while True:
            try:
                start = time.time()
                stats = self.trading_cycle()
                elapsed = time.time() - start

                logger.info(
                    f"Trading cycle complete in {elapsed:.1f}s — "
                    f"opens={stats['opens']} closes={stats['closes']} "
                    f"open_positions={len(self.open_positions)} errors={stats['errors']}"
                )

            except KeyboardInterrupt:
                logger.info("Trading Bot stopped by user")
                break
            except Exception as e:
                logger.error(f"Trading cycle error: {e}")

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
        format="%(asctime)s | TRADER | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    rpc_url = os.environ.get("RPC_URL")
    private_key = os.environ.get("TRADER_BOT_KEY")
    usdt_address = os.environ.get("USDT_ADDRESS")
    execution_address = os.environ.get("EXECUTION_ENGINE")
    account_address = os.environ.get("ACCOUNT_MANAGER")
    interval = int(os.environ.get("TRADE_INTERVAL", str(DEFAULT_INTERVAL)))
    min_size = float(os.environ.get("POSITION_SIZE_MIN", str(DEFAULT_MIN_SIZE)))
    max_size = float(os.environ.get("POSITION_SIZE_MAX", str(DEFAULT_MAX_SIZE)))
    max_leverage = float(os.environ.get("MAX_LEVERAGE", str(DEFAULT_MAX_LEVERAGE)))
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    if not rpc_url:
        logger.error("RPC_URL not set")
        sys.exit(1)
    if not private_key:
        logger.error("TRADER_BOT_KEY not set")
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

    bot = TradingBot(
        rpc_url=rpc_url,
        private_key=private_key,
        usdt_address=usdt_address,
        execution_address=execution_address,
        account_address=account_address,
        demo_markets=demo_markets,
        min_size=min_size,
        max_size=max_size,
        max_leverage=max_leverage,
        dry_run=dry_run,
    )

    bot.run_loop(interval=interval)

if __name__ == "__main__":
    main()