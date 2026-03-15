"""
Polymarket API Client — Fetches binary markets and CLOB prices.

Polymarket exposes two relevant APIs:
1. Gamma API (markets/events): https://gamma-api.polymarket.com
2. CLOB API (orderbook/prices): https://clob.polymarket.com

This client fetches active binary markets and their current prices.
Used by the oracle keeper to push prices into OracleAdapter.
"""

import time
import json
import logging
from dataclasses import dataclass, field, asdict
from typing import Optional

import requests

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
GAMMA_API = "https://gamma-api.polymarket.com"
CLOB_API = "https://clob.polymarket.com"

# Rate limiting
REQUEST_TIMEOUT = 10  # seconds
MIN_REQUEST_INTERVAL = 0.25  # seconds between requests


@dataclass
class PolymarketMarket:
    """A binary prediction market from Polymarket."""
    condition_id: str          # Polymarket's unique market identifier
    question: str              # Human-readable question
    description: str           # Longer description
    outcomes: list[str]        # e.g., ["Yes", "No"]
    token_ids: list[str]       # CLOB token IDs for each outcome
    end_date: str              # ISO timestamp
    active: bool
    volume: float              # Total volume in USD
    liquidity: float           # Current liquidity
    category: str              # e.g., "politics", "sports", "crypto"
    image: str = ""
    # Price data (filled by fetch_price)
    yes_price: Optional[float] = None
    no_price: Optional[float] = None
    last_price_update: Optional[float] = None


class PolymarketClient:
    """Client for Polymarket Gamma and CLOB APIs."""

    def __init__(self):
        self._session = requests.Session()
        self._session.headers.update({
            "Accept": "application/json",
            "User-Agent": "LEVER-Protocol-Oracle/1.0",
        })
        self._last_request_time = 0.0

    def _rate_limit(self):
        """Enforce minimum interval between requests."""
        elapsed = time.time() - self._last_request_time
        if elapsed < MIN_REQUEST_INTERVAL:
            time.sleep(MIN_REQUEST_INTERVAL - elapsed)
        self._last_request_time = time.time()

    def _get(self, url: str, params: Optional[dict] = None) -> dict:
        """Make a rate-limited GET request."""
        self._rate_limit()
        try:
            resp = self._session.get(url, params=params, timeout=REQUEST_TIMEOUT)
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"API request failed: {url} — {e}")
            raise

    # ─── Market Discovery ─────────────────────────────

    def fetch_active_markets(
        self,
        limit: int = 50,
        min_volume: float = 10_000,
        category: Optional[str] = None,
    ) -> list[PolymarketMarket]:
        """
        Fetch active binary markets from Polymarket Gamma API.

        Args:
            limit: Max markets to return
            min_volume: Minimum volume filter (USD)
            category: Optional category filter (e.g., "politics", "sports")

        Returns:
            List of PolymarketMarket objects
        """
        params = {
            "limit": limit,
            "active": "true",
            "closed": "false",
            "order": "volume",
            "ascending": "false",
        }

        data = self._get(f"{GAMMA_API}/markets", params=params)

        markets = []
        for item in data:
            # Skip non-binary markets
            outcomes = item.get("outcomes", "")
            if isinstance(outcomes, str):
                try:
                    outcomes = json.loads(outcomes)
                except (json.JSONDecodeError, TypeError):
                    continue
            if len(outcomes) != 2:
                continue

            volume = float(item.get("volume", 0) or 0)
            if volume < min_volume:
                continue

            cat = (item.get("category") or "other").lower()
            if category and cat != category.lower():
                continue

            # Parse token IDs from clobTokenIds
            token_ids_raw = item.get("clobTokenIds", "")
            if isinstance(token_ids_raw, str):
                try:
                    token_ids = json.loads(token_ids_raw)
                except (json.JSONDecodeError, TypeError):
                    token_ids = []
            else:
                token_ids = token_ids_raw or []

            # Extract embedded prices from Gamma API (fast, no extra request)
            outcome_prices = item.get("outcomePrices", "")
            yes_price = None
            no_price = None
            if isinstance(outcome_prices, str):
                try:
                    outcome_prices = json.loads(outcome_prices)
                except (json.JSONDecodeError, TypeError):
                    outcome_prices = []
            if isinstance(outcome_prices, list) and len(outcome_prices) >= 2:
                yes_price = float(outcome_prices[0])
                no_price = float(outcome_prices[1])

            market = PolymarketMarket(
                condition_id=item.get("conditionId", ""),
                question=item.get("question", ""),
                description=item.get("description", ""),
                outcomes=outcomes,
                token_ids=token_ids,
                end_date=item.get("endDate", ""),
                active=item.get("active", False),
                volume=volume,
                liquidity=float(item.get("liquidity", 0) or 0),
                category=cat,
                image=item.get("image", ""),
                yes_price=yes_price,
                no_price=no_price,
                last_price_update=time.time() if yes_price else None,
            )
            markets.append(market)

        logger.info(f"Fetched {len(markets)} active binary markets (min vol: ${min_volume:,.0f})")
        return markets

    # ─── Price Fetching ───────────────────────────────

    def fetch_price(self, token_id: str) -> float:
        """
        Fetch the current mid-price for a token from the CLOB.

        Args:
            token_id: The CLOB token ID (for YES outcome)

        Returns:
            Price as a float between 0 and 1
        """
        data = self._get(f"{CLOB_API}/midpoint", params={"token_id": token_id})
        price = float(data.get("mid", 0))
        return price

    def fetch_prices_batch(self, markets: list[PolymarketMarket]) -> list[PolymarketMarket]:
        """
        Fetch current prices for a list of markets (YES token).

        Updates each market's yes_price, no_price, and last_price_update in place.
        """
        for market in markets:
            if not market.token_ids or len(market.token_ids) < 1:
                logger.warning(f"No token IDs for market: {market.question[:60]}")
                continue

            try:
                yes_price = self.fetch_price(market.token_ids[0])
                market.yes_price = yes_price
                market.no_price = round(1.0 - yes_price, 6) if yes_price else None
                market.last_price_update = time.time()
            except Exception as e:
                logger.error(f"Price fetch failed for {market.condition_id}: {e}")

        priced = sum(1 for m in markets if m.yes_price is not None)
        logger.info(f"Priced {priced}/{len(markets)} markets")
        return markets

    # ─── Utilities ────────────────────────────────────

    def fetch_orderbook(self, token_id: str) -> dict:
        """Fetch full orderbook for a token. Useful for depth analysis."""
        return self._get(f"{CLOB_API}/book", params={"token_id": token_id})

    def close(self):
        """Close the HTTP session."""
        self._session.close()


# ─── CLI ──────────────────────────────────────────────

def main():
    """Quick test: fetch top markets and their prices."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")

    client = PolymarketClient()
    try:
        print("\n=== Fetching Active Binary Markets from Polymarket ===\n")
        markets = client.fetch_active_markets(limit=10, min_volume=50_000)

        if not markets:
            print("No markets found. API may be down or rate-limited.")
            return

        # Fetch prices
        client.fetch_prices_batch(markets)

        for i, m in enumerate(markets, 1):
            price_str = f"YES: {m.yes_price:.4f}" if m.yes_price else "NO PRICE"
            print(f"  {i}. [{m.category}] {m.question[:80]}")
            print(f"     Volume: ${m.volume:,.0f} | {price_str}")
            print(f"     Condition ID: {m.condition_id}")
            print(f"     Ends: {m.end_date}")
            print()

        # Export for reference
        output = [asdict(m) for m in markets]
        with open("scripts/oracle/markets_snapshot.json", "w") as f:
            json.dump(output, f, indent=2)
        print(f"Snapshot saved to scripts/oracle/markets_snapshot.json")

    finally:
        client.close()


if __name__ == "__main__":
    main()
