#!/usr/bin/env python3
"""
LP Seeding Bot — Provide initial liquidity to LeverVault for demo markets.

This bot:
1. Mints USDT from the MockUSDT faucet
2. Deposits USDT into LeverVault to get lvUSDT shares
3. Maintains target TVL for healthy market operations

Environment variables:
    RPC_URL          — Base Sepolia RPC endpoint
    LP_BOT_KEY       — Private key for LP bot wallet
    USDT_ADDRESS     — MockUSDT contract address
    LEVER_VAULT      — LeverVault contract address
    TARGET_TVL       — Target TVL in USDT (default: 100000 = $100k)
    DEPOSIT_INTERVAL — Seconds between deposits (default: 300 = 5min)
    DRY_RUN          — Set to "true" to skip on-chain calls
"""

import json
import logging
import os
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
DEFAULT_TARGET_TVL = 100_000  # $100k USDT
DEFAULT_INTERVAL = 300  # 5 minutes
FAUCET_COOLDOWN = 3600  # 1 hour MockUSDT faucet cooldown

# Contract ABIs (only what we need)
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
    },
    {
        "type": "function",
        "name": "approve",
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"}
        ],
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
    },
    {
        "type": "function",
        "name": "decimals",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint8"}],
        "stateMutability": "view",
    }
]

VAULT_ABI = [
    {
        "type": "function",
        "name": "totalAssets",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "deposit",
        "inputs": [
            {"name": "assets", "type": "uint256"},
            {"name": "receiver", "type": "address"}
        ],
        "outputs": [{"name": "shares", "type": "uint256"}],
        "stateMutability": "nonpayable",
    },
    {
        "type": "function",
        "name": "balanceOf",
        "inputs": [{"name": "account", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "convertToShares",
        "inputs": [{"name": "assets", "type": "uint256"}],
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
    }
]

def usdt_to_units(usdt_amount: float) -> int:
    """Convert USDT amount to contract units (6 decimals)."""
    return int(usdt_amount * USDT_UNIT)

def units_to_usdt(units: int) -> float:
    """Convert contract units to USDT amount."""
    return units / USDT_UNIT

class LPBot:
    """Provides liquidity to LeverVault by depositing USDT."""

    def __init__(
        self,
        rpc_url: str,
        private_key: str,
        usdt_address: str,
        vault_address: str,
        target_tvl: float = DEFAULT_TARGET_TVL,
        dry_run: bool = False,
    ):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to RPC: {rpc_url}")

        self.account = self.w3.eth.account.from_key(private_key)
        self.target_tvl = target_tvl
        self.dry_run = dry_run

        # Contract instances
        self.usdt = self.w3.eth.contract(
            address=Web3.to_checksum_address(usdt_address),
            abi=USDT_ABI,
        )
        self.vault = self.w3.eth.contract(
            address=Web3.to_checksum_address(vault_address),
            abi=VAULT_ABI,
        )

        logger.info(f"LP Bot initialized: target_TVL=${target_tvl:,.0f}, dry_run={dry_run}")
        logger.info(f"LP Bot address: {self.account.address}")
        logger.info(f"Chain ID: {self.w3.eth.chain_id}")

    def check_balances(self) -> dict:
        """Check current balances and vault TVL."""
        try:
            # Bot USDT balance
            usdt_balance = self.usdt.functions.balanceOf(self.account.address).call()
            usdt_amount = units_to_usdt(usdt_balance)

            # Bot vault shares
            shares_balance = self.vault.functions.balanceOf(self.account.address).call()

            # Current vault TVL
            total_assets = self.vault.functions.totalAssets().call()
            current_tvl = units_to_usdt(total_assets)

            return {
                "usdt_balance": usdt_amount,
                "vault_shares": shares_balance,
                "current_tvl": current_tvl,
                "target_tvl": self.target_tvl,
                "tvl_gap": max(0, self.target_tvl - current_tvl)
            }

        except Exception as e:
            logger.error(f"Failed to check balances: {e}")
            return None

    def mint_usdt(self, amount_needed: float) -> bool:
        """Mint USDT from MockUSDT faucet if needed."""
        try:
            current_balance = units_to_usdt(
                self.usdt.functions.balanceOf(self.account.address).call()
            )

            if current_balance >= amount_needed:
                logger.info(f"Sufficient USDT balance: ${current_balance:,.2f}")
                return True

            logger.info(f"Minting USDT from faucet (need ${amount_needed:,.2f})")

            if self.dry_run:
                logger.info("  [DRY RUN] Would call usdt.faucet()")
                return True

            # Call faucet (MockUSDT gives 10k USDT per hour)
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

            if receipt.status == 1:
                new_balance = units_to_usdt(
                    self.usdt.functions.balanceOf(self.account.address).call()
                )
                logger.info(f"  Faucet success! New balance: ${new_balance:,.2f}")
                return True
            else:
                logger.error(f"  Faucet TX reverted: {tx_hash.hex()}")
                return False

        except Exception as e:
            logger.error(f"Failed to mint USDT: {e}")
            return False

    def approve_vault(self, amount: float) -> bool:
        """Approve vault to spend USDT."""
        try:
            amount_units = usdt_to_units(amount)

            logger.info(f"Approving vault to spend ${amount:,.2f} USDT")

            if self.dry_run:
                logger.info("  [DRY RUN] Would approve vault")
                return True

            tx = self.usdt.functions.approve(
                self.vault.address,
                amount_units
            ).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 100_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

            if receipt.status == 1:
                logger.info(f"  Approved! tx={tx_hash.hex()[:18]}...")
                return True
            else:
                logger.error(f"  Approval reverted: {tx_hash.hex()}")
                return False

        except Exception as e:
            logger.error(f"Failed to approve: {e}")
            return False

    def deposit_to_vault(self, amount: float) -> bool:
        """Deposit USDT to vault."""
        try:
            amount_units = usdt_to_units(amount)

            logger.info(f"Depositing ${amount:,.2f} USDT to vault")

            if self.dry_run:
                logger.info("  [DRY RUN] Would deposit to vault")
                return True

            # Estimate shares
            expected_shares = self.vault.functions.convertToShares(amount_units).call()

            tx = self.vault.functions.deposit(
                amount_units,
                self.account.address
            ).build_transaction({
                "from": self.account.address,
                "nonce": self.w3.eth.get_transaction_count(self.account.address),
                "gas": 300_000,
                "maxFeePerGas": self.w3.eth.gas_price * 2,
                "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
            })

            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

            if receipt.status == 1:
                logger.info(f"  Deposited! tx={tx_hash.hex()[:18]}... gas={receipt.gasUsed}")
                logger.info(f"  Expected shares: {expected_shares}")
                return True
            else:
                logger.error(f"  Deposit reverted: {tx_hash.hex()}")
                return False

        except Exception as e:
            logger.error(f"Failed to deposit: {e}")
            return False

    def seed_liquidity(self) -> dict:
        """Main seeding logic - ensure vault has target TVL."""
        stats = {"deposits": 0, "usdt_deposited": 0, "faucet_calls": 0, "errors": 0}

        try:
            balances = self.check_balances()
            if not balances:
                stats["errors"] += 1
                return stats

            tvl_gap = balances["tvl_gap"]

            if tvl_gap <= 0:
                logger.info(
                    f"TVL target met: ${balances['current_tvl']:,.2f} >= ${self.target_tvl:,.2f}"
                )
                return stats

            # How much to deposit this round (max 25% of gap to spread over time)
            deposit_amount = min(tvl_gap * 0.25, 10_000)  # Max $10k per deposit

            logger.info(
                f"TVL gap: ${tvl_gap:,.2f} — depositing ${deposit_amount:,.2f} this round"
            )

            # Ensure we have enough USDT
            if not self.mint_usdt(deposit_amount):
                stats["errors"] += 1
                return stats

            stats["faucet_calls"] += 1

            # Approve and deposit
            if self.approve_vault(deposit_amount):
                if self.deposit_to_vault(deposit_amount):
                    stats["deposits"] += 1
                    stats["usdt_deposited"] += deposit_amount
                else:
                    stats["errors"] += 1
            else:
                stats["errors"] += 1

        except Exception as e:
            logger.error(f"Seed liquidity error: {e}")
            stats["errors"] += 1

        return stats

    def run_loop(self, interval: int = DEFAULT_INTERVAL):
        """Run LP bot in continuous loop."""
        logger.info(f"Starting LP bot loop (interval={interval}s)")

        while True:
            try:
                start = time.time()
                stats = self.seed_liquidity()
                elapsed = time.time() - start

                logger.info(
                    f"LP cycle complete in {elapsed:.1f}s — "
                    f"deposits={stats['deposits']} "
                    f"usdt=${stats['usdt_deposited']:,.0f} "
                    f"errors={stats['errors']}"
                )

                # Show current state
                balances = self.check_balances()
                if balances:
                    logger.info(
                        f"  Current: TVL=${balances['current_tvl']:,.2f} "
                        f"Bot_USDT=${balances['usdt_balance']:,.2f} "
                        f"Shares={balances['vault_shares']}"
                    )

            except KeyboardInterrupt:
                logger.info("LP Bot stopped by user")
                break
            except Exception as e:
                logger.error(f"LP cycle error: {e}")

            # Sleep until next interval
            sleep_time = max(0, interval - (time.time() - start))
            if sleep_time > 0:
                time.sleep(sleep_time)

# ─── CLI ──────────────────────────────────────────────

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | LP | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    rpc_url = os.environ.get("RPC_URL")
    private_key = os.environ.get("LP_BOT_KEY")
    usdt_address = os.environ.get("USDT_ADDRESS")
    vault_address = os.environ.get("LEVER_VAULT")
    target_tvl = float(os.environ.get("TARGET_TVL", str(DEFAULT_TARGET_TVL)))
    interval = int(os.environ.get("DEPOSIT_INTERVAL", str(DEFAULT_INTERVAL)))
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    if not rpc_url:
        logger.error("RPC_URL not set")
        sys.exit(1)
    if not private_key:
        logger.error("LP_BOT_KEY not set")
        sys.exit(1)
    if not usdt_address:
        logger.error("USDT_ADDRESS not set")
        sys.exit(1)
    if not vault_address:
        logger.error("LEVER_VAULT not set")
        sys.exit(1)

    bot = LPBot(
        rpc_url=rpc_url,
        private_key=private_key,
        usdt_address=usdt_address,
        vault_address=vault_address,
        target_tvl=target_tvl,
        dry_run=dry_run,
    )

    bot.run_loop(interval=interval)

if __name__ == "__main__":
    main()