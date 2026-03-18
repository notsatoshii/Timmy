#!/usr/bin/env python3
"""
Improved Oracle Keeper - Enhanced transaction handling and reliability
Addresses nonce conflicts and gas price issues for demo stability
"""

import json
import time
import random
import logging
from web3 import Web3
from decimal import Decimal
import os
from typing import Dict, List

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    datefmt='%H:%M:%S'
)

class ImprovedOracleKeeper:
    def __init__(self):
        # Load environment
        self.rpc_url = os.getenv('RPC_URL', 'https://sepolia.base.org')
        self.private_key = os.getenv('KEEPER_KEY', '').strip()
        self.oracle_adapter = os.getenv('ORACLE_ADAPTER', '')
        self.push_interval = int(os.getenv('PUSH_INTERVAL', '15'))
        self.dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'

        # Initialize web3 with retry logic
        self.w3 = self._connect_with_retry()

        # Load account
        if not self.private_key:
            raise Exception("KEEPER_KEY environment variable required")

        self.account = self.w3.eth.account.from_key(self.private_key)
        logging.info(f"Keeper address: {self.account.address}")

        # Nonce management
        self.current_nonce = None
        self.last_nonce_update = 0

        # Load markets and initialize prices
        self.markets = self.load_markets()
        self.current_prices = self.initialize_prices()

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
            }
        ]

        # Initialize oracle contract
        self.oracle_contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(self.oracle_adapter),
            abi=self.oracle_abi
        )

    def _connect_with_retry(self, max_retries=3):
        """Connect to RPC with retry logic"""
        for attempt in range(max_retries):
            try:
                w3 = Web3(Web3.HTTPProvider(self.rpc_url, request_kwargs={'timeout': 30}))
                if w3.is_connected():
                    logging.info(f"Connected to {self.rpc_url}")
                    return w3
                else:
                    raise Exception("Connection failed")
            except Exception as e:
                if attempt == max_retries - 1:
                    raise Exception(f"Failed to connect after {max_retries} attempts: {e}")
                logging.warning(f"Connection attempt {attempt + 1} failed, retrying...")
                time.sleep(2 ** attempt)

    def _get_nonce(self):
        """Get current nonce with caching to avoid conflicts"""
        current_time = time.time()

        # Refresh nonce every 30 seconds or if not set
        if self.current_nonce is None or (current_time - self.last_nonce_update) > 30:
            try:
                self.current_nonce = self.w3.eth.get_transaction_count(self.account.address, 'pending')
                self.last_nonce_update = current_time
                logging.debug(f"Updated nonce to {self.current_nonce}")
            except Exception as e:
                logging.warning(f"Failed to get nonce: {e}")
                if self.current_nonce is None:
                    self.current_nonce = 0

        nonce = self.current_nonce
        self.current_nonce += 1
        return nonce

    def _get_gas_price(self):
        """Get current gas price with a buffer for reliability"""
        try:
            base_gas_price = self.w3.eth.gas_price
            # Add 20% buffer to ensure transactions are picked up
            buffered_price = int(base_gas_price * 1.2)
            return buffered_price
        except Exception as e:
            logging.warning(f"Failed to get gas price: {e}")
            # Fallback to reasonable default for Base Sepolia
            return int(1e9)  # 1 gwei

    def write_prices_json(self):
        """Write current prices to static JSON file for frontend consumption"""
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
                "source": "improved_oracle_keeper"
            }
            json_path = "/home/lever/lever-protocol/frontend/user-app/public/prices.json"
            with open(json_path, 'w') as f:
                json.dump(output, f)
        except Exception as e:
            logging.warning(f"Failed to write prices.json: {e}")

    def load_markets(self) -> List[Dict]:
        """Load market configuration"""
        try:
            with open('market_config.json', 'r') as f:
                markets = json.load(f)
            logging.info(f"Loaded {len(markets)} markets")
            return markets
        except Exception as e:
            logging.error(f"Failed to load markets: {e}")
            return []

    def initialize_prices(self) -> Dict[str, float]:
        """Initialize current prices for all markets"""
        prices = {}
        for market in self.markets:
            market_id = market['marketId']
            initial_price = market.get('_polymarket', {}).get('currentPrice', 0.5)
            prices[market_id] = initial_price
            logging.info(f"Market {market['name'][:30]}... initialized at {initial_price:.3f}")
        return prices

    def simulate_price_movement(self, current_price: float, market_name: str) -> float:
        """Simulate realistic price movement"""
        volatility = 0.015  # 1.5% max movement for demo stability
        random_change = random.uniform(-volatility, volatility)
        mean_reversion = (0.5 - current_price) * 0.0005  # Gentler mean reversion
        new_price = current_price + random_change + mean_reversion
        return max(0.01, min(0.99, new_price))

    def push_price_to_oracle(self, market_id: str, price: float, max_retries=3):
        """Push price to oracle with improved error handling"""

        for attempt in range(max_retries):
            try:
                # Convert market_id to bytes32
                market_id_bytes = bytes.fromhex(market_id[2:])

                # Convert price to pYes/pNo in WAD format
                p_yes_wad = int(price * 1e18)
                p_no_wad = int((1.0 - price) * 1e18)

                # Realistic market data
                spread_wad = int(0.01 * 1e18)
                depth_wad = int(1.0 * 1e18)
                volume_wad = int(5.0 * 1e18)

                # Get fresh nonce and gas price for each transaction
                nonce = self._get_nonce()
                gas_price = self._get_gas_price()

                # Build transaction
                tx = self.oracle_contract.functions.pushPrice(
                    market_id_bytes,
                    p_yes_wad,
                    p_no_wad,
                    spread_wad,
                    depth_wad,
                    volume_wad
                ).build_transaction({
                    'from': self.account.address,
                    'nonce': nonce,
                    'gas': 200000,  # Increased gas limit for safety
                    'gasPrice': gas_price,
                })

                # Sign and send
                signed_tx = self.account.sign_transaction(tx)
                tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)

                # Wait for confirmation with timeout
                receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
                if receipt.status == 1:
                    return  # Success
                else:
                    raise Exception(f"Transaction failed with status {receipt.status}")

            except Exception as e:
                error_msg = str(e)

                # Handle specific error types
                if "nonce too low" in error_msg:
                    logging.warning(f"Nonce conflict (attempt {attempt + 1}), refreshing nonce...")
                    self.current_nonce = None  # Force nonce refresh
                    time.sleep(1)
                    continue
                elif "replacement transaction underpriced" in error_msg:
                    logging.warning(f"Gas price too low (attempt {attempt + 1}), will retry...")
                    time.sleep(2)
                    continue
                elif attempt == max_retries - 1:
                    raise Exception(f"Failed after {max_retries} attempts: {error_msg}")
                else:
                    logging.warning(f"Transaction failed (attempt {attempt + 1}): {error_msg}")
                    time.sleep(1)

    def update_prices(self):
        """Update all market prices with improved error handling"""
        successful_updates = 0
        failed_updates = 0

        for market in self.markets:
            market_id = market['marketId']
            market_name = market['name']

            try:
                # Simulate price movement
                old_price = self.current_prices[market_id]
                new_price = self.simulate_price_movement(old_price, market_name)
                self.current_prices[market_id] = new_price

                if self.dry_run:
                    logging.info(f"DRY RUN: {market_name[:30]}... {old_price:.3f} -> {new_price:.3f}")
                    successful_updates += 1
                else:
                    # Push to oracle with retry logic
                    self.push_price_to_oracle(market_id, new_price)
                    logging.info(f"✅ PUSHED: {market_name[:30]}... {old_price:.3f} -> {new_price:.3f}")
                    successful_updates += 1

            except Exception as e:
                logging.error(f"❌ FAILED: {market_name[:30]}... {e}")
                failed_updates += 1

        success_rate = (successful_updates * 100) // (successful_updates + failed_updates) if (successful_updates + failed_updates) > 0 else 0
        logging.info(f"Update cycle complete: {successful_updates} success, {failed_updates} failed ({success_rate}% success)")

    def run(self):
        """Main keeper loop with enhanced stability"""
        logging.info("Starting Improved Oracle Keeper")
        logging.info(f"Markets: {len(self.markets)}")
        logging.info(f"Interval: {self.push_interval}s")
        logging.info(f"Dry run: {self.dry_run}")

        consecutive_failures = 0

        while True:
            try:
                start_time = time.time()

                # Check RPC connection health
                if not self.w3.is_connected():
                    logging.warning("RPC connection lost, attempting reconnect...")
                    self.w3 = self._connect_with_retry()

                self.update_prices()

                cycle_time = time.time() - start_time
                logging.info(f"Cycle complete in {cycle_time:.1f}s")

                # Update prices.json for frontend
                self.write_prices_json()

                consecutive_failures = 0
                time.sleep(self.push_interval)

            except KeyboardInterrupt:
                logging.info("Shutting down gracefully...")
                break
            except Exception as e:
                consecutive_failures += 1
                logging.error(f"Keeper error #{consecutive_failures}: {e}")

                # Progressive backoff for consecutive failures
                if consecutive_failures >= 5:
                    logging.error("Too many consecutive failures, longer pause...")
                    time.sleep(30)
                else:
                    time.sleep(min(consecutive_failures * 2, 10))

if __name__ == "__main__":
    keeper = ImprovedOracleKeeper()
    keeper.run()