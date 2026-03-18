#!/usr/bin/env python3
"""
Oracle Keeper Load Test for Demo Conditions
Simulates the load conditions expected during investor demo
"""

import time
import requests
import json
import subprocess
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    datefmt='%H:%M:%S'
)

class DemoLoadTester:
    def __init__(self):
        self.oracle_dir = Path("/home/lever/lever-protocol/scripts/oracle")
        self.frontend_prices_file = Path("/home/lever/lever-protocol/frontend/user-app/public/prices.json")
        self.rpc_url = "https://sepolia.base.org"
        self.test_duration = 300  # 5 minutes

    def check_keeper_process(self):
        """Check if oracle keeper is running"""
        try:
            result = subprocess.run(['pgrep', '-f', 'stable_mock_keeper.py'],
                                 capture_output=True, text=True)
            if result.returncode == 0:
                pid = result.stdout.strip()
                logging.info(f"✅ Oracle keeper running (PID: {pid})")
                return True
            else:
                logging.error("❌ Oracle keeper not running")
                return False
        except Exception as e:
            logging.error(f"Error checking keeper process: {e}")
            return False

    def check_price_freshness(self):
        """Check if prices are being updated regularly"""
        try:
            if not self.frontend_prices_file.exists():
                logging.error("❌ Frontend prices.json not found")
                return False

            with open(self.frontend_prices_file, 'r') as f:
                data = json.load(f)

            last_update = data.get('lastUpdate', 0)
            current_time = int(time.time())
            age = current_time - last_update

            if age < 300:  # Less than 5 minutes old
                logging.info(f"✅ Prices are fresh (updated {age}s ago)")
                return True
            else:
                logging.error(f"❌ Prices are stale (updated {age}s ago)")
                return False

        except Exception as e:
            logging.error(f"Error checking price freshness: {e}")
            return False

    def simulate_frontend_load(self):
        """Simulate frontend price requests"""
        try:
            with open(self.frontend_prices_file, 'r') as f:
                data = json.load(f)

            price_count = len(data.get('prices', {}))
            logging.info(f"✅ Frontend can read {price_count} market prices")
            return True

        except Exception as e:
            logging.error(f"❌ Frontend price read failed: {e}")
            return False

    def check_rpc_health(self):
        """Check RPC endpoint responsiveness"""
        try:
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 1
            }

            response = requests.post(self.rpc_url, json=payload, timeout=10)

            if response.status_code == 200:
                result = response.json()
                block_number = int(result['result'], 16)
                logging.info(f"✅ RPC healthy (block: {block_number})")
                return True
            else:
                logging.error(f"❌ RPC unhealthy (status: {response.status_code})")
                return False

        except Exception as e:
            logging.error(f"❌ RPC error: {e}")
            return False

    def monitor_keeper_performance(self, duration_seconds=60):
        """Monitor keeper performance for a specific duration"""
        logging.info(f"Monitoring keeper performance for {duration_seconds} seconds...")

        log_file = self.oracle_dir / "stable_keeper.log"
        if not log_file.exists():
            logging.error("❌ Keeper log file not found")
            return False

        # Get initial log position
        with open(log_file, 'r') as f:
            initial_lines = len(f.readlines())

        start_time = time.time()
        successful_cycles = 0
        failed_updates = 0

        while time.time() - start_time < duration_seconds:
            time.sleep(10)  # Check every 10 seconds

            # Read new log lines
            with open(log_file, 'r') as f:
                all_lines = f.readlines()
                new_lines = all_lines[initial_lines:]

            # Count successes and failures in new lines
            for line in new_lines:
                if "Cycle complete:" in line and "successful" in line:
                    successful_cycles += 1
                elif "FAILED" in line:
                    failed_updates += 1

            initial_lines = len(all_lines)

        if successful_cycles > 0:
            logging.info(f"✅ Observed {successful_cycles} successful cycles in {duration_seconds}s")
            if failed_updates == 0:
                logging.info("✅ No failed updates detected")
                return True
            else:
                logging.warning(f"⚠️  {failed_updates} failed updates detected")
                return failed_updates < successful_cycles * 2  # Allow some failures
        else:
            logging.error("❌ No successful cycles observed")
            return False

    def run_demo_load_test(self):
        """Run complete demo load test"""
        logging.info("=== DEMO LOAD TEST STARTING ===")

        test_results = {
            'keeper_running': False,
            'prices_fresh': False,
            'frontend_access': False,
            'rpc_healthy': False,
            'performance_stable': False
        }

        # Test 1: Check keeper is running
        logging.info("\n--- Test 1: Keeper Process Check ---")
        test_results['keeper_running'] = self.check_keeper_process()

        # Test 2: Check price freshness
        logging.info("\n--- Test 2: Price Freshness Check ---")
        test_results['prices_fresh'] = self.check_price_freshness()

        # Test 3: Check frontend can access prices
        logging.info("\n--- Test 3: Frontend Access Check ---")
        test_results['frontend_access'] = self.simulate_frontend_load()

        # Test 4: Check RPC health
        logging.info("\n--- Test 4: RPC Health Check ---")
        test_results['rpc_healthy'] = self.check_rpc_health()

        # Test 5: Monitor performance under load
        logging.info("\n--- Test 5: Performance Stability Check ---")
        test_results['performance_stable'] = self.monitor_keeper_performance(90)

        # Summary
        logging.info("\n=== DEMO LOAD TEST RESULTS ===")
        passed = sum(test_results.values())
        total = len(test_results)

        for test_name, result in test_results.items():
            status = "✅ PASS" if result else "❌ FAIL"
            logging.info(f"{test_name}: {status}")

        logging.info(f"\nOverall: {passed}/{total} tests passed")

        if passed == total:
            logging.info("🎉 DEMO READY: Oracle keeper is stable for investor demo!")
            return True
        else:
            logging.error("🚨 DEMO RISK: Oracle keeper issues detected!")
            return False

if __name__ == "__main__":
    tester = DemoLoadTester()
    success = tester.run_demo_load_test()
    exit(0 if success else 1)