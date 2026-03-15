"""
Price Feed Monitor — Heartbeat, staleness detection, and fallback for oracle feeds.

Wraps the PolymarketClient with reliability features:
- Heartbeat tracking per market (last successful price update)
- Staleness detection (alerts when price hasn't updated in N seconds)
- Automatic fallback: CLOB midpoint → Gamma embedded prices → last known price
- Health reporting for operator dashboards

Can run standalone for monitoring, or be imported by the keeper bot.
"""

import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.polymarket_client import PolymarketClient

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
STALE_THRESHOLD = 120      # seconds — price is stale after 2 minutes without update
CRITICAL_THRESHOLD = 300   # seconds — critical after 5 minutes
MAX_PRICE_DEVIATION = 0.15 # 15% — flag if CLOB and Gamma diverge more than this


@dataclass
class FeedHealth:
    """Health status for a single market's price feed."""
    market_id: str
    question: str
    token_id: str
    last_price: Optional[float] = None
    last_update: float = 0.0
    last_source: str = "none"  # "clob", "gamma", "cached"
    consecutive_failures: int = 0
    total_updates: int = 0
    total_failures: int = 0

    @property
    def age_seconds(self) -> float:
        if self.last_update == 0:
            return float("inf")
        return time.time() - self.last_update

    @property
    def is_stale(self) -> bool:
        return self.age_seconds > STALE_THRESHOLD

    @property
    def is_critical(self) -> bool:
        return self.age_seconds > CRITICAL_THRESHOLD

    @property
    def status(self) -> str:
        if self.last_price is None:
            return "NO_DATA"
        if self.is_critical:
            return "CRITICAL"
        if self.is_stale:
            return "STALE"
        return "HEALTHY"


class FeedMonitor:
    """
    Monitors price feed health with fallback chain:
    1. CLOB /midpoint (primary — most accurate, real-time)
    2. Gamma API outcomePrices (fallback — slightly delayed)
    3. Last known price (emergency — cached from previous successful fetch)
    """

    def __init__(self, market_config: list[dict]):
        self.client = PolymarketClient()
        self.feeds: dict[str, FeedHealth] = {}

        # Initialize feed tracking
        for mc in market_config:
            market_id = mc["marketId"]
            poly = mc.get("_polymarket", {})
            token_ids = poly.get("tokenIds", [])
            self.feeds[market_id] = FeedHealth(
                market_id=market_id,
                question=mc.get("name", "")[:60],
                token_id=token_ids[0] if token_ids else "",
            )

        logger.info(f"Feed monitor initialized: {len(self.feeds)} markets")

    def fetch_price_with_fallback(self, market_id: str) -> Optional[float]:
        """
        Fetch price using fallback chain. Returns YES price (0-1) or None.

        Fallback order:
        1. CLOB /midpoint (primary)
        2. Gamma API outcomePrices (secondary)
        3. Last known price (emergency cache)
        """
        feed = self.feeds.get(market_id)
        if not feed or not feed.token_id:
            return None

        # Source 1: CLOB midpoint (primary)
        try:
            price = self.client.fetch_price(feed.token_id)
            if price is not None and 0 < price < 1:
                self._record_success(feed, price, "clob")
                return price
        except Exception as e:
            logger.debug(f"CLOB failed for {market_id[:18]}...: {e}")

        # Source 2: Gamma API embedded prices
        try:
            from scripts.oracle.polymarket_client import GAMMA_API
            import requests
            resp = requests.get(
                f"{GAMMA_API}/markets",
                params={"id": feed.token_id},
                timeout=10,
            )
            if resp.ok:
                data = resp.json()
                if data and len(data) > 0:
                    outcome_prices = data[0].get("outcomePrices", "")
                    if isinstance(outcome_prices, str):
                        import json as _json
                        outcome_prices = _json.loads(outcome_prices)
                    if isinstance(outcome_prices, list) and len(outcome_prices) >= 1:
                        price = float(outcome_prices[0])
                        if 0 < price < 1:
                            self._record_success(feed, price, "gamma")
                            logger.warning(
                                f"Using Gamma fallback for {market_id[:18]}... "
                                f"(CLOB unavailable)"
                            )
                            return price
        except Exception as e:
            logger.debug(f"Gamma fallback failed for {market_id[:18]}...: {e}")

        # Source 3: Cached price (last resort)
        if feed.last_price is not None:
            feed.consecutive_failures += 1
            feed.total_failures += 1
            logger.warning(
                f"Using cached price for {market_id[:18]}... "
                f"(age={feed.age_seconds:.0f}s, failures={feed.consecutive_failures})"
            )
            return feed.last_price

        # Complete failure
        feed.consecutive_failures += 1
        feed.total_failures += 1
        logger.error(f"All price sources failed for {market_id[:18]}...")
        return None

    def _record_success(self, feed: FeedHealth, price: float, source: str):
        """Record a successful price fetch."""
        feed.last_price = price
        feed.last_update = time.time()
        feed.last_source = source
        feed.consecutive_failures = 0
        feed.total_updates += 1

    def get_health_report(self) -> dict:
        """Generate a health report for all feeds."""
        report = {
            "timestamp": time.time(),
            "total_feeds": len(self.feeds),
            "healthy": 0,
            "stale": 0,
            "critical": 0,
            "no_data": 0,
            "feeds": [],
        }

        for feed in self.feeds.values():
            status = feed.status
            report[status.lower()] = report.get(status.lower(), 0) + 1

            report["feeds"].append({
                "market_id": feed.market_id[:18] + "...",
                "question": feed.question,
                "status": status,
                "price": feed.last_price,
                "source": feed.last_source,
                "age_seconds": round(feed.age_seconds, 1) if feed.last_update > 0 else None,
                "consecutive_failures": feed.consecutive_failures,
                "total_updates": feed.total_updates,
                "total_failures": feed.total_failures,
            })

        return report

    def check_heartbeat(self) -> list[str]:
        """
        Check all feeds for staleness. Returns list of alert messages.
        Intended to be called periodically by the keeper or a monitor cron.
        """
        alerts = []
        for feed in self.feeds.values():
            if feed.is_critical:
                alerts.append(
                    f"CRITICAL: {feed.question} — no update for {feed.age_seconds:.0f}s "
                    f"(failures={feed.consecutive_failures})"
                )
            elif feed.is_stale:
                alerts.append(
                    f"STALE: {feed.question} — no update for {feed.age_seconds:.0f}s"
                )
        return alerts

    def close(self):
        self.client.close()


# ─── CLI ──────────────────────────────────────────────

def main():
    """Run a single monitoring check and print health report."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")

    config_path = Path("scripts/oracle/market_config.json")
    if not config_path.exists():
        logger.error("No market_config.json found. Run onboard_markets.py first.")
        sys.exit(1)

    with open(config_path) as f:
        config = json.load(f)

    monitor = FeedMonitor(config)

    print("\n=== Price Feed Health Check ===\n")

    # Fetch prices with fallback for each market
    for market_id in monitor.feeds:
        price = monitor.fetch_price_with_fallback(market_id)
        feed = monitor.feeds[market_id]
        status_icon = {"HEALTHY": "OK", "STALE": "!!", "CRITICAL": "XX", "NO_DATA": "--"}
        icon = status_icon.get(feed.status, "??")
        price_str = f"{price:.4f}" if price else "N/A"
        print(f"  [{icon}] {feed.question:60} | {price_str} via {feed.last_source}")

    # Print summary
    report = monitor.get_health_report()
    print(f"\n  Summary: {report['healthy']} healthy, {report['stale']} stale, "
          f"{report['critical']} critical, {report['no_data']} no_data")

    # Check alerts
    alerts = monitor.check_heartbeat()
    if alerts:
        print("\n  Alerts:")
        for alert in alerts:
            print(f"    {alert}")

    monitor.close()


if __name__ == "__main__":
    main()
