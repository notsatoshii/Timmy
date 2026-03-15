"""
Market Onboarding Script — Generate LEVER market configs from Polymarket markets.

Takes Polymarket markets (via API or snapshot) and produces a JSON config
that the Foundry deployment script reads to call MarketRegistry.createMarket().

Usage:
    python scripts/oracle/onboard_markets.py                    # interactive, fetches live
    python scripts/oracle/onboard_markets.py --from-snapshot    # uses saved snapshot
    python scripts/oracle/onboard_markets.py --min-volume 100000
"""

import argparse
import hashlib
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.polymarket_client import PolymarketClient, PolymarketMarket

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────

# MarketCategory enum values from IMarketRegistry.sol
CATEGORY_MAP = {
    "HIGH_LIQUIDITY": 0,    # > $1M volume
    "MEDIUM_LIQUIDITY": 1,  # $100k–$1M
    "LOW_LIQUIDITY": 2,     # $10k–$100k
    "NEW_UNPROVEN": 3,      # < $10k or new
}

WAD = 10**18
OUTPUT_DIR = Path("scripts/oracle")
CONFIG_FILE = OUTPUT_DIR / "market_config.json"


def classify_category(volume: float) -> tuple[str, int]:
    """Map Polymarket volume to LEVER MarketCategory."""
    if volume >= 1_000_000:
        return "HIGH_LIQUIDITY", CATEGORY_MAP["HIGH_LIQUIDITY"]
    elif volume >= 100_000:
        return "MEDIUM_LIQUIDITY", CATEGORY_MAP["MEDIUM_LIQUIDITY"]
    elif volume >= 10_000:
        return "LOW_LIQUIDITY", CATEGORY_MAP["LOW_LIQUIDITY"]
    else:
        return "NEW_UNPROVEN", CATEGORY_MAP["NEW_UNPROVEN"]


def compute_market_id(condition_id: str) -> str:
    """
    Compute LEVER marketId from Polymarket conditionId.
    Uses keccak256 to match Solidity: keccak256(abi.encodePacked(conditionId))
    For script purposes we use the condition_id bytes directly as the marketId
    since it's already a bytes32 hex string.
    """
    # Polymarket condition_id is already a 0x-prefixed bytes32
    # We use it directly as the LEVER marketId for 1:1 mapping
    if condition_id.startswith("0x"):
        return condition_id
    return "0x" + condition_id


def parse_end_date(end_date: str) -> int:
    """Parse Polymarket end date to Unix timestamp."""
    # Handle ISO format: "2026-06-30T00:00:00Z"
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(end_date, fmt)
            return int(dt.timestamp())
        except ValueError:
            continue
    raise ValueError(f"Cannot parse date: {end_date}")


def compute_allocation_weight(volume: float, total_volume: float) -> int:
    """
    Compute allocation weight as fraction of total volume (WAD-scaled).
    Minimum 1% (0.01 WAD), capped at 30% (0.30 WAD).
    """
    if total_volume == 0:
        return WAD // 10  # default 10%

    raw = volume / total_volume
    # Clamp to [0.01, 0.30]
    clamped = max(0.01, min(0.30, raw))
    return int(clamped * WAD)


def generate_config(markets: list[PolymarketMarket]) -> list[dict]:
    """Generate LEVER market config entries from Polymarket markets."""
    total_volume = sum(m.volume for m in markets)
    configs = []

    for m in markets:
        category_name, category_id = classify_category(m.volume)
        market_id = compute_market_id(m.condition_id)
        resolution_time = parse_end_date(m.end_date)

        config = {
            "marketId": market_id,
            "name": m.question[:100],  # truncate long questions
            "externalMarketId": m.condition_id,
            "resolutionTime": resolution_time,
            "category": category_id,
            "categoryName": category_name,
            "allocationWeight": str(compute_allocation_weight(m.volume, total_volume)),
            # Metadata (not sent to contract, useful for operators)
            "_polymarket": {
                "conditionId": m.condition_id,
                "tokenIds": m.token_ids,
                "volume": m.volume,
                "liquidity": m.liquidity,
                "currentPrice": m.yes_price,
                "endDate": m.end_date,
                "polyCategory": m.category,
            },
        }
        configs.append(config)

    return configs


def main():
    parser = argparse.ArgumentParser(description="Generate LEVER market configs from Polymarket")
    parser.add_argument("--from-snapshot", action="store_true", help="Use saved snapshot instead of live API")
    parser.add_argument("--min-volume", type=float, default=10_000, help="Minimum volume filter (USD)")
    parser.add_argument("--limit", type=int, default=20, help="Max markets to fetch")
    parser.add_argument("--output", type=str, default=str(CONFIG_FILE), help="Output file path")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")

    if args.from_snapshot:
        snapshot_path = OUTPUT_DIR / "markets_snapshot.json"
        if not snapshot_path.exists():
            logger.error(f"Snapshot not found: {snapshot_path}. Run polymarket_client.py first.")
            sys.exit(1)
        with open(snapshot_path) as f:
            raw = json.load(f)
        markets = [PolymarketMarket(**item) for item in raw]
        logger.info(f"Loaded {len(markets)} markets from snapshot")
    else:
        client = PolymarketClient()
        try:
            markets = client.fetch_active_markets(limit=args.limit, min_volume=args.min_volume)
            client.fetch_prices_batch(markets)
        finally:
            client.close()

    if not markets:
        logger.warning("No markets found. Exiting.")
        sys.exit(0)

    configs = generate_config(markets)

    output_path = Path(args.output)
    with open(output_path, "w") as f:
        json.dump(configs, f, indent=2)

    print(f"\n=== Generated {len(configs)} Market Configs ===\n")
    for i, c in enumerate(configs, 1):
        price = c["_polymarket"]["currentPrice"]
        price_str = f"{price:.4f}" if price else "N/A"
        print(f"  {i}. {c['name'][:70]}")
        print(f"     ID: {c['marketId']}")
        print(f"     Category: {c['categoryName']} | Price: {price_str}")
        print(f"     Resolution: {datetime.fromtimestamp(c['resolutionTime']).isoformat()}")
        print()

    print(f"Config saved to: {output_path}")
    print(f"\nNext: Use this config with the Foundry deployment script to create markets on-chain.")


if __name__ == "__main__":
    main()
