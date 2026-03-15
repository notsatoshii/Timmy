"""
Oracle Keeper Bot — Pulls Polymarket prices, pushes to OracleAdapter on-chain.

Runs as a continuous loop:
1. Fetch current prices from Polymarket CLOB (midpoint)
2. Fetch orderbook spread and depth
3. Push prices to OracleAdapter.pushPrice() on-chain
4. Sleep and repeat

Environment variables:
    RPC_URL          — Base Sepolia RPC endpoint
    KEEPER_KEY       — Private key for the keeper wallet (ORACLE role)
    ORACLE_ADAPTER   — OracleAdapter contract address
    MARKET_CONFIG    — Path to market_config.json (default: scripts/oracle/market_config.json)
    PUSH_INTERVAL    — Seconds between price pushes (default: 30)
    DRY_RUN          — Set to "true" to skip on-chain calls (default: false)
"""

import json
import logging
import os
import sys
import time
from pathlib import Path

# Use oracle venv if available
VENV_PATH = Path(__file__).parent / ".venv" / "lib"
if VENV_PATH.exists():
    import site
    for p in VENV_PATH.glob("python*/site-packages"):
        site.addsitedir(str(p))

from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.polymarket_client import PolymarketClient

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
WAD = 10**18
DEFAULT_INTERVAL = 30  # seconds
DEFAULT_CONFIG = "scripts/oracle/market_config.json"

# OracleAdapter ABI (only what we need)
ORACLE_ABI = [
    {
        "type": "function",
        "name": "pushPrice",
        "inputs": [
            {"name": "marketId", "type": "bytes32"},
            {"name": "pYes", "type": "uint256"},
            {"name": "pNo", "type": "uint256"},
            {"name": "spread", "type": "uint256"},
            {"name": "depth", "type": "uint256"},
            {"name": "volume", "type": "uint256"},
        ],
        "outputs": [],
        "stateMutability": "nonpayable",
    }
]


def float_to_wad(value: float) -> int:
    """Convert a float (0.0–1.0) to WAD (1e18) format."""
    return int(value * WAD)


def load_market_config(path: str) -> list[dict]:
    """Load market config JSON."""
    with open(path) as f:
        return json.load(f)


class OracleKeeper:
    """Fetches Polymarket prices and pushes them to OracleAdapter."""

    def __init__(
        self,
        rpc_url: str,
        private_key: str,
        oracle_address: str,
        market_config: list[dict],
        dry_run: bool = False,
    ):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        # Base uses POA consensus
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to RPC: {rpc_url}")

        self.account = self.w3.eth.account.from_key(private_key)
        self.oracle = self.w3.eth.contract(
            address=Web3.to_checksum_address(oracle_address),
            abi=ORACLE_ABI,
        )
        self.market_config = market_config
        self.dry_run = dry_run
        self.poly_client = PolymarketClient()

        # Build market_id -> token_id mapping
        self._market_map = {}
        for mc in market_config:
            market_id = mc["marketId"]
            token_ids = mc.get("_polymarket", {}).get("tokenIds", [])
            if token_ids:
                self._market_map[market_id] = token_ids[0]  # YES token

        logger.info(f"Keeper initialized: {len(self._market_map)} markets, dry_run={dry_run}")
        logger.info(f"Keeper address: {self.account.address}")
        chain_id = self.w3.eth.chain_id
        logger.info(f"Chain ID: {chain_id}")

    def fetch_and_push(self) -> dict:
        """
        Fetch prices from Polymarket and push to OracleAdapter.

        Returns:
            Stats dict: {"pushed": N, "failed": N, "skipped": N}
        """
        stats = {"pushed": 0, "failed": 0, "skipped": 0}

        for market_id, token_id in self._market_map.items():
            try:
                # Fetch midpoint price
                yes_price = self.poly_client.fetch_price(token_id)
                if yes_price is None or yes_price <= 0:
                    logger.warning(f"No price for {market_id[:18]}... — skipping")
                    stats["skipped"] += 1
                    continue

                no_price = 1.0 - yes_price

                # Fetch orderbook for spread and depth
                spread = 0.02  # default 2% spread
                depth = 10000.0  # default $10k depth
                volume = 0.0

                try:
                    book = self.poly_client.fetch_orderbook(token_id)
                    bids = book.get("bids", [])
                    asks = book.get("asks", [])
                    if bids and asks:
                        best_bid = float(bids[0].get("price", 0))
                        best_ask = float(asks[0].get("price", 1))
                        spread = best_ask - best_bid
                        # Depth = sum of top 5 levels
                        bid_depth = sum(float(b.get("size", 0)) for b in bids[:5])
                        ask_depth = sum(float(a.get("size", 0)) for a in asks[:5])
                        depth = (bid_depth + ask_depth) / 2
                except Exception as e:
                    logger.debug(f"Orderbook fetch failed for {market_id[:18]}...: {e}")

                # Convert to WAD
                p_yes_wad = float_to_wad(yes_price)
                p_no_wad = float_to_wad(no_price)
                spread_wad = float_to_wad(max(spread, 0.001))  # min 0.1% spread
                depth_wad = float_to_wad(max(depth, 1.0))
                volume_wad = float_to_wad(volume)

                logger.info(
                    f"Market {market_id[:18]}... | YES={yes_price:.4f} NO={no_price:.4f} "
                    f"spread={spread:.4f} depth={depth:.0f}"
                )

                if self.dry_run:
                    logger.info(f"  [DRY RUN] Would push price for {market_id[:18]}...")
                    stats["pushed"] += 1
                    continue

                # Build and send transaction
                tx = self.oracle.functions.pushPrice(
                    bytes.fromhex(market_id[2:]),  # strip 0x prefix
                    p_yes_wad,
                    p_no_wad,
                    spread_wad,
                    depth_wad,
                    volume_wad,
                ).build_transaction({
                    "from": self.account.address,
                    "nonce": self.w3.eth.get_transaction_count(self.account.address),
                    "gas": 200_000,
                    "maxFeePerGas": self.w3.eth.gas_price * 2,
                    "maxPriorityFeePerGas": self.w3.to_wei(0.1, "gwei"),
                })

                signed = self.account.sign_transaction(tx)
                tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
                receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

                if receipt.status == 1:
                    logger.info(f"  Pushed! tx={tx_hash.hex()[:18]}... gas={receipt.gasUsed}")
                    stats["pushed"] += 1
                else:
                    logger.error(f"  TX reverted! tx={tx_hash.hex()}")
                    stats["failed"] += 1

            except Exception as e:
                logger.error(f"Error processing {market_id[:18]}...: {e}")
                stats["failed"] += 1

        return stats

    def run_loop(self, interval: int = DEFAULT_INTERVAL):
        """Run the keeper in a continuous loop."""
        logger.info(f"Starting keeper loop (interval={interval}s)")

        while True:
            try:
                start = time.time()
                stats = self.fetch_and_push()
                elapsed = time.time() - start

                logger.info(
                    f"Cycle complete in {elapsed:.1f}s — "
                    f"pushed={stats['pushed']} failed={stats['failed']} skipped={stats['skipped']}"
                )

            except KeyboardInterrupt:
                logger.info("Keeper stopped by user")
                break
            except Exception as e:
                logger.error(f"Cycle error: {e}")

            # Sleep until next interval
            sleep_time = max(0, interval - (time.time() - start))
            if sleep_time > 0:
                time.sleep(sleep_time)

    def close(self):
        """Clean up resources."""
        self.poly_client.close()


# ─── CLI ──────────────────────────────────────────────

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    rpc_url = os.environ.get("RPC_URL")
    private_key = os.environ.get("KEEPER_KEY")
    oracle_address = os.environ.get("ORACLE_ADAPTER")
    config_path = os.environ.get("MARKET_CONFIG", DEFAULT_CONFIG)
    interval = int(os.environ.get("PUSH_INTERVAL", str(DEFAULT_INTERVAL)))
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    if not rpc_url:
        logger.error("RPC_URL not set")
        sys.exit(1)
    if not private_key:
        logger.error("KEEPER_KEY not set")
        sys.exit(1)
    if not oracle_address:
        logger.error("ORACLE_ADAPTER not set")
        sys.exit(1)

    config = load_market_config(config_path)
    if not config:
        logger.error(f"No markets in config: {config_path}")
        sys.exit(1)

    keeper = OracleKeeper(
        rpc_url=rpc_url,
        private_key=private_key,
        oracle_address=oracle_address,
        market_config=config,
        dry_run=dry_run,
    )

    try:
        keeper.run_loop(interval=interval)
    finally:
        keeper.close()


if __name__ == "__main__":
    main()
