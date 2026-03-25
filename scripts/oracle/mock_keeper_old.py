#!/usr/bin/env python3
"""
Mock Oracle Keeper - Pushes Simulated Price Data
Temporary solution while Polymarket API integration is being fixed
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

class MockOracleKeeper:
    def __init__(self):
        # Load environment
        self.rpc_url = os.getenv('RPC_URL', 'https://sepolia.base.org')
        self.private_key = os.getenv('KEEPER_KEY', '').strip()
        self.oracle_adapter = os.getenv('ORACLE_ADAPTER', '')
        self.push_interval = int(os.getenv('PUSH_INTERVAL', '15'))
        self.dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'

        # Initialize web3
        self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        if not self.w3.is_connected():
            raise Exception(f"Failed to connect to {self.rpc_url}")

        # Load account
        if not self.private_key:
            raise Exception("KEEPER_KEY environment variable required")

        self.account = self.w3.eth.account.from_key(self.private_key)
        logging.info(f"Keeper address: {self.account.address}")

        # Load markets and initialize prices
        self.markets = self.load_markets()
        self.current_prices = self.initialize_prices()

        # Oracle contract ABI (correct signature)
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
                "source": "oracle_keeper"
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
            # Use configured price or reasonable default
            initial_price = market.get('_polymarket', {}).get('currentPrice', 0.5)
            prices[market_id] = initial_price
            logging.info(f"Market {market['name'][:30]}... initialized at {initial_price:.3f}")
        return prices

    def simulate_price_movement(self, current_price: float, market_name: str) -> float:
        """Simulate realistic price movement based on market characteristics"""

        # Different volatility by market type
        if "SpaceX" in market_name or "IPO" in market_name:
            volatility = 0.02  # 2% max movement
        elif "Fed" in market_name or "Rate" in market_name:
            volatility = 0.015  # 1.5% max movement
        elif "Sports" in market_name or "FIFA" in market_name:
            volatility = 0.025  # 2.5% max movement
        else:
            volatility = 0.02  # Default 2%

        # Random walk with mean reversion
        random_change = random.uniform(-volatility, volatility)

        # Mean reversion (prices drift toward 0.5 slightly)
        mean_reversion = (0.5 - current_price) * 0.001

        # Apply changes
        new_price = current_price + random_change + mean_reversion

        # Clamp to valid range
        new_price = max(0.01, min(0.99, new_price))

        return new_price

    def update_prices(self):
        """Update all market prices"""
        for market in self.markets:
            market_id = market['marketId']
            market_name = market['name']

            # Simulate price movement
            old_price = self.current_prices[market_id]
            new_price = self.simulate_price_movement(old_price, market_name)
            self.current_prices[market_id] = new_price

            if self.dry_run:
                logging.info(f"DRY RUN: {market_name[:30]}... {old_price:.3f} -> {new_price:.3f}")
            else:
                try:
                    # Push to oracle
                    self.push_price_to_oracle(market_id, new_price)
                    logging.info(f"PUSHED: {market_name[:30]}... {old_price:.3f} -> {new_price:.3f}")
                except Exception as e:
                    logging.error(f"Failed to push {market_name[:20]}...: {e}")

    def push_price_to_oracle(self, market_id: str, price: float):
        """Push price to OracleAdapter contract with realistic market data"""

        # Convert market_id to bytes32
        market_id_bytes = bytes.fromhex(market_id[2:])

        # Convert price to pYes/pNo in WAD format
        p_yes_wad = int(price * 1e18)
        p_no_wad = int((1.0 - price) * 1e18)

        # Simulate realistic market data
        spread_wad = int(0.01 * 1e18)    # 1% spread
        depth_wad = int(1.0 * 1e18)      # 1.0 depth
        volume_wad = int(5.0 * 1e18)     # 5.0 volume

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
            'nonce': self.w3.eth.get_transaction_count(self.account.address),
            'gas': 150000,
            'gasPrice': self.w3.eth.gas_price,
        })

        # Sign and send
        signed_tx = self.account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)

        # Wait for confirmation (optional)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        if receipt.status != 1:
            raise Exception(f"Transaction failed: {tx_hash.hex()}")

    def run(self):
        """Main keeper loop"""
        logging.info(f"Starting Mock Oracle Keeper")
        logging.info(f"Markets: {len(self.markets)}")
        logging.info(f"Interval: {self.push_interval}s")
        logging.info(f"Dry run: {self.dry_run}")

        while True:
            try:
                start_time = time.time()
                self.update_prices()

                cycle_time = time.time() - start_time
                logging.info(f"Cycle complete in {cycle_time:.1f}s")

                self.write_prices_json()
                time.sleep(self.push_interval)

            except KeyboardInterrupt:
                logging.info("Shutting down...")
                break
            except Exception as e:
                logging.error(f"Keeper error: {e}")
                time.sleep(5)  # Brief pause before retry

if __name__ == "__main__":
    keeper = MockOracleKeeper()
    keeper.run()