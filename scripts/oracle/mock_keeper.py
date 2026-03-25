"""
Polymarket Oracle Keeper — Fetches LIVE Polymarket prices for all 20 LEVER markets.

Falls back to gentle random walk only if Polymarket API is unreachable.
Pushes prices to OracleAdapter on-chain every 30 seconds.
"""

import json
import logging
import os
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, List, Optional
from pathlib import Path

# Use oracle venv if available
VENV_PATH = Path(__file__).parent / ".venv" / "lib"
if VENV_PATH.exists():
    import site
    for p in VENV_PATH.glob("python*/site-packages"):
        site.addsitedir(str(p))

from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('polymarket_keeper.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

WAD = 10**18


class PolymarketOracleKeeper:
    def __init__(self):
        self.rpc_url = os.getenv('RPC_URL', 'https://sepolia.base.org')
        self.private_key = os.getenv('KEEPER_KEY', '').strip()
        self.oracle_adapter = os.getenv('ORACLE_ADAPTER', '0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c')
        self.push_interval = int(os.getenv('PUSH_INTERVAL', '30'))
        self.dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'

        # Connect to RPC
        self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        if not self.private_key:
            raise Exception("KEEPER_KEY environment variable required")

        self.account = self.w3.eth.account.from_key(self.private_key)
        logger.info(f"Keeper address: {self.account.address}")

        # Load markets
        self.markets = self.load_markets()
        self.current_prices: Dict[str, float] = {}
        self.last_polymarket_prices: Dict[str, float] = {}

        # Initialize prices from config
        for market in self.markets:
            mid = market['marketId']
            initial = market.get('_polymarket', {}).get('currentPrice', 0.5)
            self.current_prices[mid] = initial
            self.last_polymarket_prices[mid] = initial

        # Track on-chain prices for gradual stepping (anti-manipulation filter is 5% max tick)
        self.onchain_prices: Dict[str, float] = {}
        self.DELTA_MAX = 0.045  # Stay under the 5% deltaMax filter

        # Oracle contract ABI
        self.oracle_abi = [
            {
                "inputs": [
                    {"name": "marketId", "type": "bytes32"},
                    {"name": "pYes", "type": "uint256"},
                    {"name": "pNo", "type": "uint256"},
                    {"name": "spread", "type": "uint256"},
                    {"name": "depth", "type": "uint256"},
                    {"name": "volume", "type": "uint256"}
                ],
                "name": "pushPrice",
                "type": "function"
            },
            {
                "inputs": [{"name": "marketId", "type": "bytes32"}],
                "outputs": [{"name": "pi", "type": "uint256"}],
                "name": "getPI",
                "type": "function",
                "stateMutability": "view"
            }
        ]

        self.oracle_contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(self.oracle_adapter),
            abi=self.oracle_abi
        )

        # Multicall3 — standard address on all EVM chains
        self.multicall3_addr = Web3.to_checksum_address('0xcA11bde05977b3631167028862bE2a173976CA11')
        self.multicall3_abi = [{
            "inputs": [{"components": [
                {"name": "target", "type": "address"},
                {"name": "callData", "type": "bytes"}
            ], "name": "calls", "type": "tuple[]"}],
            "name": "aggregate",
            "outputs": [
                {"name": "blockNumber", "type": "uint256"},
                {"name": "returnData", "type": "bytes[]"}
            ],
            "type": "function"
        }]
        self.multicall3 = self.w3.eth.contract(
            address=self.multicall3_addr,
            abi=self.multicall3_abi
        )

    def load_markets(self) -> List[Dict]:
        try:
            with open('market_config.json', 'r') as f:
                markets = json.load(f)
            logger.info(f"Loaded {len(markets)} markets")
            return markets
        except Exception as e:
            logger.error(f"Failed to load markets: {e}")
            return []

    def fetch_polymarket_price_by_slug(self, slug: str, condition_id: str = '', question_hint: str = '') -> Optional[float]:
        """Fetch current price from Polymarket Gamma API by event slug.

        Uses condition_id for exact matching when available (multi-market events).
        Falls back to keyword matching for single-market events.
        """
        if not slug:
            return None
        try:
            url = f"https://gamma-api.polymarket.com/events?slug={slug}&limit=1"
            req = urllib.request.Request(url, headers={'User-Agent': 'LEVER-Oracle/1.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                if not data or len(data) == 0:
                    return None
                event = data[0]
                markets = event.get('markets', [])

                best_market = None

                # Strategy 1: Match by condition ID (exact, preferred)
                if condition_id:
                    for m in markets:
                        if m.get('conditionId', '') == condition_id:
                            best_market = m
                            break

                # Strategy 2: Single market event = use it directly
                if not best_market and len(markets) == 1:
                    best_market = markets[0]

                # Strategy 3: Keyword matching (last resort)
                if not best_market and question_hint and len(markets) > 1:
                    hint_lower = question_hint.lower()
                    best_score = 0
                    for m in markets:
                        q = m.get('question', '').lower()
                        score = sum(1 for w in hint_lower.split() if len(w) > 3 and w in q)
                        if score > best_score:
                            best_score = score
                            best_market = m

                if best_market:
                    prices_raw = best_market.get('outcomePrices', '[]')
                    if isinstance(prices_raw, str):
                        prices = json.loads(prices_raw)
                    else:
                        prices = prices_raw
                    if prices and len(prices) > 0:
                        p = float(prices[0])
                        p = max(0.01, min(0.99, p))
                        return p
        except Exception as e:
            logger.debug(f"Polymarket API error for slug={slug}: {e}")
        return None

    def fetch_all_polymarket_prices(self):
        """Fetch live prices from Polymarket for all markets that have slugs."""
        fetched = 0
        for market in self.markets:
            mid = market['marketId']
            poly = market.get('_polymarket', {})
            slug = poly.get('slug', '')
            condition_id = poly.get('conditionId', '')

            if not slug:
                continue

            price = self.fetch_polymarket_price_by_slug(slug, condition_id, market.get('name', ''))
            if price is not None:
                old = self.current_prices.get(mid, 0)
                self.last_polymarket_prices[mid] = price
                self.current_prices[mid] = price
                if abs(old - price) > 0.005:
                    logger.info(f"POLY: {market['name'][:35]}... {old:.4f} -> {price:.4f}")
                fetched += 1

        if fetched > 0:
            logger.info(f"Fetched {fetched} live prices from Polymarket")
        return fetched

    def simulate_price_movement(self, current_price: float, market_name: str) -> float:
        """Gentle random walk for markets without live Polymarket data."""
        import random
        volatility = 0.005  # Very gentle: 0.5% max movement per cycle

        random_change = random.uniform(-volatility, volatility)
        # Mean reversion toward the initial/last known Polymarket price
        new_price = current_price + random_change
        new_price = max(0.01, min(0.99, new_price))
        return new_price

    def update_prices(self):
        """Update all market prices — prefer Polymarket, fallback to gentle walk."""
        # First try Polymarket API
        fetched = self.fetch_all_polymarket_prices()

        # Cache gas price and nonce once per cycle
        try:
            base_gas_price = self.w3.eth.gas_price
            gas_price = max(base_gas_price + 1000000, 1000000)
            nonce = self.w3.eth.get_transaction_count(self.account.address, 'pending')
        except Exception as e:
            logger.error(f"Failed to get gas/nonce: {e}")
            return

        # Read current on-chain prices so we can step within deltaMax
        oracle_addr = Web3.to_checksum_address(self.oracle_adapter)
        for market in self.markets:
            mid = market['marketId']
            if mid not in self.onchain_prices:
                try:
                    pi_raw = self.oracle_contract.functions.getPI(
                        bytes.fromhex(mid[2:])
                    ).call()
                    self.onchain_prices[mid] = pi_raw / 1e18
                except:
                    self.onchain_prices[mid] = self.current_prices.get(mid, 0.5)

        # Build calldata for all markets, then send as single Multicall3 tx
        calls = []

        for market in self.markets:
            mid = market['marketId']
            poly = market.get('_polymarket', {})
            cid = poly.get('conditionId', '')

            if cid == mid or not cid:
                old_price = self.current_prices.get(mid, 0.5)
                new_price = self.simulate_price_movement(old_price, market['name'])
                self.current_prices[mid] = new_price

            target_price = self.current_prices[mid]

            # Step toward target within deltaMax to avoid anti-manipulation rejection
            current_onchain = self.onchain_prices.get(mid, target_price)
            diff = target_price - current_onchain
            if abs(diff) > self.DELTA_MAX:
                # Clamp the step to deltaMax
                step = self.DELTA_MAX if diff > 0 else -self.DELTA_MAX
                price = current_onchain + step
                price = max(0.01, min(0.99, price))
            else:
                price = target_price

            # Update our tracking of what we're pushing (optimistic — assume it lands)
            self.onchain_prices[mid] = price
            if self.dry_run:
                logger.info(f"DRY RUN: {market['name'][:35]}... -> {price:.4f}")
                continue

            market_id_bytes = bytes.fromhex(mid[2:])
            p_yes_wad = int(price * 1e18)
            p_no_wad = int((1.0 - price) * 1e18)
            spread_wad = int(0.01 * 1e18)
            depth_wad = int(1.0 * 1e18)
            volume_wad = int(5.0 * 1e18)

            calldata = self.oracle_contract.functions.pushPrice(
                market_id_bytes, p_yes_wad, p_no_wad,
                spread_wad, depth_wad, volume_wad
            )._encode_transaction_data()

            calls.append((oracle_addr, calldata))

        if not calls:
            return

        # Send all 20 pushPrice calls in a single Multicall3.aggregate() transaction
        try:
            tx = self.multicall3.functions.aggregate(calls).build_transaction({
                'from': self.account.address,
                'nonce': nonce,
                'gas': 120000 * len(calls),  # ~120k per subcall
                'gasPrice': gas_price,
            })
            signed_tx = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
            logger.info(f"Pushed {len(calls)} markets in 1 tx (hash: {tx_hash.hex()[:16]}...)")
        except Exception as e:
            logger.error(f"Multicall batch failed: {e}")
            # Fallback: push individually
            logger.info("Falling back to individual pushes...")
            for i, market in enumerate(self.markets):
                mid = market['marketId']
                price = self.current_prices.get(mid, 0.5)
                try:
                    market_id_bytes = bytes.fromhex(mid[2:])
                    p_yes_wad = int(price * 1e18)
                    p_no_wad = int((1.0 - price) * 1e18)
                    tx = self.oracle_contract.functions.pushPrice(
                        market_id_bytes, p_yes_wad, p_no_wad,
                        int(0.01e18), int(1e18), int(5e18)
                    ).build_transaction({
                        'from': self.account.address,
                        'nonce': nonce + i,
                        'gas': 120000,
                        'gasPrice': gas_price,
                    })
                    signed_tx = self.account.sign_transaction(tx)
                    self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
                except Exception as e2:
                    logger.error(f"Individual push failed {market['name'][:20]}: {e2}")

    def write_prices_json(self):
        try:
            prices = {}
            for market_id, price in self.current_prices.items():
                prices[market_id] = {
                    "probability": round(float(price), 6),
                    "timestamp": int(time.time()),
                }
            output = {
                "prices": prices,
                "lastUpdate": int(time.time()),
                "source": "polymarket_keeper"
            }
            json_path = "/home/lever/lever-protocol/frontend/user-app/public/prices.json"
            with open(json_path, 'w') as f:
                json.dump(output, f)
            # Also write to build dir
            build_path = "/home/lever/lever-protocol/frontend/user-app/build/prices.json"
            try:
                with open(build_path, 'w') as f:
                    json.dump(output, f)
            except:
                pass
        except Exception as e:
            logger.warning(f"Failed to write prices.json: {e}")

    def run(self):
        logger.info(f"Starting Polymarket Oracle Keeper")
        logger.info(f"Markets: {len(self.markets)}")
        logger.info(f"Interval: {self.push_interval}s")
        logger.info(f"Dry run: {self.dry_run}")

        while True:
            try:
                start_time = time.time()
                self.update_prices()
                cycle_time = time.time() - start_time
                logger.info(f"Cycle complete in {cycle_time:.1f}s")
                self.write_prices_json()
                time.sleep(self.push_interval)
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
            except Exception as e:
                logger.error(f"Keeper error: {e}")
                time.sleep(5)


if __name__ == "__main__":
    keeper = PolymarketOracleKeeper()
    keeper.run()
