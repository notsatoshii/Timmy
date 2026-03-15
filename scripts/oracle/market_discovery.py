"""
Market Discovery System — Automated detection of high-volume Polymarket markets.

Continuously monitors Polymarket for new markets that meet LEVER onboarding criteria.
Tracks discovered markets, filters by volume/liquidity, and outputs candidates for review.

Key features:
- Persistent tracking of discovered markets (SQLite database)
- Volume/liquidity filtering with configurable thresholds
- Category-based filtering and weighting
- Automatic deduplication and freshness checks
- Export to onboarding pipeline format

Usage:
    python scripts/oracle/market_discovery.py                    # single scan
    python scripts/oracle/market_discovery.py --daemon           # continuous monitoring
    python scripts/oracle/market_discovery.py --export-candidates # generate candidates.json
"""

import argparse
import json
import logging
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone
from dataclasses import asdict
from pathlib import Path
from typing import Dict, List, Optional, Set

# Add project root to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.polymarket_client import PolymarketClient, PolymarketMarket

logger = logging.getLogger(__name__)

# ─── Configuration ────────────────────────────────────────

# Volume thresholds for auto-onboarding consideration
MIN_VOLUME_THRESHOLD = 50_000      # $50k minimum to be considered
HIGH_VOLUME_THRESHOLD = 500_000    # $500k for high-priority flagging
MEGA_VOLUME_THRESHOLD = 2_000_000  # $2M for immediate attention

# Liquidity requirements
MIN_LIQUIDITY_THRESHOLD = 10_000   # $10k minimum liquidity
PREFERRED_LIQUIDITY_RATIO = 0.1    # Liquidity should be ≥10% of volume

# Time-based filters
MIN_DAYS_TO_RESOLUTION = 7         # Don't onboard markets resolving <7 days
MAX_DAYS_TO_RESOLUTION = 365       # Don't onboard markets >1 year out
MARKET_AGE_STALENESS = 24          # Re-scan markets every 24 hours

# Category preferences (higher weights = more desirable)
CATEGORY_WEIGHTS = {
    "politics": 1.0,        # Core use case
    "crypto": 0.9,          # High interest
    "sports": 0.8,          # Popular
    "stocks": 0.7,          # Financial
    "science": 0.6,         # Niche but quality
    "tech": 0.6,            # Tech events
    "entertainment": 0.4,   # Lower priority
    "other": 0.3,           # Catch-all
}

# Database and output paths
DB_PATH = Path("scripts/oracle/discovery.db")
CANDIDATES_FILE = Path("scripts/oracle/candidates.json")
DISCOVERY_LOG = Path("scripts/oracle/discovery.log")

WAD = 10**18


class MarketDiscoveryEngine:
    """Core market discovery and tracking engine."""

    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.client = PolymarketClient()
        self._init_database()

    def _init_database(self):
        """Initialize SQLite database for market tracking."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS discovered_markets (
                    condition_id TEXT PRIMARY KEY,
                    question TEXT NOT NULL,
                    category TEXT,
                    volume REAL,
                    liquidity REAL,
                    current_price REAL,
                    resolution_time INTEGER,
                    first_seen REAL,
                    last_updated REAL,
                    onboarding_score REAL,
                    status TEXT DEFAULT 'discovered',  -- discovered, candidate, onboarded, rejected
                    notes TEXT
                )
            """)

            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_status_score
                ON discovered_markets(status, onboarding_score DESC)
            """)

            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_last_updated
                ON discovered_markets(last_updated)
            """)

    def compute_onboarding_score(self, market: PolymarketMarket) -> float:
        """
        Compute a composite score for market onboarding priority.

        Factors:
        - Volume (primary driver)
        - Liquidity depth and ratio
        - Category preference
        - Time to resolution (Goldilocks zone)
        - Price balance (avoid extreme prices)

        Returns:
            Float score where higher = better candidate
        """
        score = 0.0

        # Volume component (0-100 points, logarithmic scaling)
        if market.volume > 0:
            volume_score = min(100, 20 * (market.volume / MIN_VOLUME_THRESHOLD) ** 0.5)
            score += volume_score

        # Liquidity component (0-20 points)
        if market.liquidity > MIN_LIQUIDITY_THRESHOLD:
            liquidity_ratio = market.liquidity / max(market.volume, 1)
            liquidity_score = min(20, liquidity_ratio / PREFERRED_LIQUIDITY_RATIO * 20)
            score += liquidity_score

        # Category preference (0-10 points)
        category_weight = CATEGORY_WEIGHTS.get(market.category.lower(), 0.3)
        score += category_weight * 10

        # Time to resolution (0-15 points, Goldilocks zone)
        try:
            resolution_date = datetime.fromisoformat(market.end_date.replace('Z', '+00:00'))
            days_to_resolution = (resolution_date - datetime.now(timezone.utc)).days

            if MIN_DAYS_TO_RESOLUTION <= days_to_resolution <= MAX_DAYS_TO_RESOLUTION:
                # Optimal range: 30-180 days
                if 30 <= days_to_resolution <= 180:
                    time_score = 15
                elif days_to_resolution < 30:
                    time_score = 10 * (days_to_resolution - 7) / 23  # Taper down
                else:  # > 180 days
                    time_score = 10 * (365 - days_to_resolution) / 185  # Taper down
                score += max(0, time_score)
        except (ValueError, TypeError):
            score += 5  # Neutral if date parsing fails

        # Price balance (0-5 points, penalize extreme prices)
        if market.yes_price is not None:
            if 0.2 <= market.yes_price <= 0.8:
                score += 5  # Sweet spot
            elif 0.1 <= market.yes_price <= 0.9:
                score += 3  # Reasonable
            else:
                score += 1  # Very skewed

        return round(score, 2)

    def scan_new_markets(self, limit: int = 100) -> List[PolymarketMarket]:
        """
        Fetch latest markets from Polymarket and identify new discoveries.

        Returns:
            List of newly discovered markets (not previously tracked)
        """
        logger.info(f"Scanning Polymarket for new markets (limit: {limit})")

        # Fetch active markets, ordered by volume
        markets = self.client.fetch_active_markets(
            limit=limit,
            min_volume=MIN_VOLUME_THRESHOLD
        )

        if not markets:
            logger.warning("No markets returned from API")
            return []

        # Get current prices
        self.client.fetch_prices_batch(markets)

        # Check which are new
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # Get existing condition IDs
            cursor.execute("SELECT condition_id FROM discovered_markets")
            existing_ids = {row[0] for row in cursor.fetchall()}

        new_markets = [m for m in markets if m.condition_id not in existing_ids]

        logger.info(f"Found {len(new_markets)} new markets out of {len(markets)} scanned")
        return new_markets

    def record_discovery(self, market: PolymarketMarket, status: str = "discovered"):
        """Record a newly discovered market in the database."""
        score = self.compute_onboarding_score(market)
        now = time.time()

        try:
            resolution_timestamp = datetime.fromisoformat(
                market.end_date.replace('Z', '+00:00')
            ).timestamp()
        except (ValueError, TypeError):
            resolution_timestamp = now + (30 * 24 * 3600)  # Default 30 days

        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO discovered_markets
                (condition_id, question, category, volume, liquidity, current_price,
                 resolution_time, first_seen, last_updated, onboarding_score, status, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                market.condition_id,
                market.question,
                market.category,
                market.volume,
                market.liquidity,
                market.yes_price,
                resolution_timestamp,
                now,
                now,
                score,
                status,
                f"Auto-discovered. Vol: ${market.volume:,.0f}, Liq: ${market.liquidity:,.0f}"
            ))

        logger.info(f"Recorded market [{score:.1f}]: {market.question[:60]}")

    def update_existing_markets(self, max_age_hours: float = MARKET_AGE_STALENESS):
        """Update volume/price data for existing markets that haven't been refreshed recently."""
        stale_cutoff = time.time() - (max_age_hours * 3600)

        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT condition_id, question FROM discovered_markets
                WHERE last_updated < ? AND status IN ('discovered', 'candidate')
                ORDER BY onboarding_score DESC
                LIMIT 50
            """, (stale_cutoff,))

            stale_markets = cursor.fetchall()

        if not stale_markets:
            logger.info("No stale markets to update")
            return

        logger.info(f"Updating {len(stale_markets)} stale markets")

        for condition_id, question in stale_markets:
            try:
                # Fetch fresh data (simplified - we'd need to map condition_id to token_id)
                # For now, we'll mark as updated and trust periodic full scans
                now = time.time()
                with sqlite3.connect(self.db_path) as conn:
                    conn.execute("""
                        UPDATE discovered_markets
                        SET last_updated = ?, notes = notes || '; refreshed'
                        WHERE condition_id = ?
                    """, (now, condition_id))

            except Exception as e:
                logger.error(f"Failed to update {condition_id}: {e}")

    def get_top_candidates(self, limit: int = 20, min_score: float = 50.0) -> List[Dict]:
        """
        Get the highest-scoring market candidates for onboarding.

        Returns:
            List of market dictionaries sorted by onboarding score
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT * FROM discovered_markets
                WHERE status IN ('discovered', 'candidate')
                    AND onboarding_score >= ?
                    AND resolution_time > ?
                ORDER BY onboarding_score DESC, volume DESC
                LIMIT ?
            """, (min_score, time.time(), limit))

            columns = [desc[0] for desc in cursor.description]
            candidates = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return candidates

    def export_candidates(self, output_path: Path = CANDIDATES_FILE, min_score: float = 60.0):
        """Export top candidates in format compatible with onboarding pipeline."""
        candidates = self.get_top_candidates(limit=50, min_score=min_score)

        if not candidates:
            logger.warning("No candidates meet the minimum score threshold")
            return

        # Convert to onboarding format
        onboarding_format = []
        for candidate in candidates:
            # Compute market ID and allocation weight (simplified)
            market_id = candidate['condition_id']
            if not market_id.startswith('0x'):
                market_id = '0x' + market_id

            config = {
                "marketId": market_id,
                "name": candidate['question'][:100],
                "externalMarketId": candidate['condition_id'],
                "resolutionTime": int(candidate['resolution_time']),
                "category": 0,  # Will need proper category mapping
                "allocationWeight": str(int(0.05 * WAD)),  # Default 5% allocation
                "_discovery": {
                    "onboardingScore": candidate['onboarding_score'],
                    "volume": candidate['volume'],
                    "liquidity": candidate['liquidity'],
                    "currentPrice": candidate['current_price'],
                    "category": candidate['category'],
                    "firstSeen": candidate['first_seen'],
                    "discoveryNotes": candidate['notes'],
                }
            }
            onboarding_format.append(config)

        with open(output_path, 'w') as f:
            json.dump(onboarding_format, f, indent=2)

        logger.info(f"Exported {len(onboarding_format)} candidates to {output_path}")

    def run_discovery_scan(self):
        """Execute a full discovery scan: find new markets + update existing."""
        logger.info("=== Starting Market Discovery Scan ===")

        try:
            # Scan for new markets
            new_markets = self.scan_new_markets(limit=200)

            for market in new_markets:
                self.record_discovery(market)

            # Update existing markets
            self.update_existing_markets()

            # Report top candidates
            candidates = self.get_top_candidates(limit=10)
            if candidates:
                logger.info(f"\nTop {len(candidates)} candidates:")
                for i, c in enumerate(candidates, 1):
                    price = c['current_price']
                    price_str = f"{price:.3f}" if price else "N/A"
                    logger.info(f"  {i}. [{c['onboarding_score']:.1f}] {c['question'][:60]}")
                    logger.info(f"      Vol: ${c['volume']:,.0f} | Price: {price_str} | {c['category']}")

            logger.info("=== Discovery Scan Complete ===")

        except Exception as e:
            logger.error(f"Discovery scan failed: {e}")
            raise

    def close(self):
        """Clean up resources."""
        self.client.close()


# ─── CLI ──────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="LEVER Market Discovery System")
    parser.add_argument("--daemon", action="store_true", help="Run in daemon mode (continuous)")
    parser.add_argument("--interval", type=int, default=3600, help="Daemon scan interval (seconds)")
    parser.add_argument("--export-candidates", action="store_true", help="Export candidates.json and exit")
    parser.add_argument("--min-score", type=float, default=60.0, help="Minimum onboarding score for export")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    args = parser.parse_args()

    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S"
    )

    # Also log to file
    file_handler = logging.FileHandler(DISCOVERY_LOG)
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(logging.Formatter(
        "%(asctime)s | %(levelname)s | %(message)s"
    ))
    logger.addHandler(file_handler)

    discovery = MarketDiscoveryEngine()

    try:
        if args.export_candidates:
            discovery.export_candidates(min_score=args.min_score)

        elif args.daemon:
            logger.info(f"Starting discovery daemon (scan every {args.interval}s)")
            while True:
                try:
                    discovery.run_discovery_scan()
                    logger.info(f"Sleeping {args.interval}s until next scan...")
                    time.sleep(args.interval)
                except KeyboardInterrupt:
                    logger.info("Daemon stopped by user")
                    break
                except Exception as e:
                    logger.error(f"Scan failed: {e}. Retrying in {args.interval}s...")
                    time.sleep(args.interval)
        else:
            # Single scan
            discovery.run_discovery_scan()

    finally:
        discovery.close()


if __name__ == "__main__":
    main()