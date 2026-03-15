#!/usr/bin/env python3
"""
Demo Seeding Orchestrator — Launch all seeding bots for demo markets.

This script:
1. Converts demo_markets.json to onboarding format
2. Deploys demo markets to the protocol
3. Launches oracle, LP, and trading bots
4. Monitors all processes

Usage:
    python scripts/seed/run_demo_seeding.py --setup     # Setup and deploy markets
    python scripts/seed/run_demo_seeding.py --bots      # Run bots only
    python scripts/seed/run_demo_seeding.py --all       # Setup + bots
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import signal
import time
from pathlib import Path
from threading import Thread

logger = logging.getLogger(__name__)

# Configuration
REQUIRED_ENV = [
    "RPC_URL",
    "DEPLOYER_KEY",    # For market deployment
    "ORACLE_KEY",      # For oracle keeper
    "LP_BOT_KEY",      # For LP bot
    "TRADER_BOT_KEY",  # For trading bot
]

DEFAULT_CONFIG = {
    "TARGET_TVL": "100000",          # $100k LP target
    "ORACLE_INTERVAL": "30",         # 30s oracle updates
    "LP_INTERVAL": "300",            # 5min LP checks
    "TRADE_INTERVAL": "60",          # 1min trading
    "DRY_RUN": "false",
}

# Contract addresses from deployment
CONTRACTS = {
    "USDT_ADDRESS": "0x92c9711101bBB0B742d6320D52521FAd1712A85e",
    "MARKET_REGISTRY": "0x463697f45a0dA6B247305bac56F68e37779ba6bF",
    "ORACLE_ADAPTER": "0x4F0224F2cC6ab7acC1A913D06F055Ae8FA484d78",
    "ACCOUNT_MANAGER": "0xe0f420dD416e6047fDA063d66292f7679160519B",
    "EXECUTION_ENGINE": "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
    "LEVER_VAULT": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
}

class SeedingOrchestrator:
    """Coordinates demo market seeding."""

    def __init__(self, dry_run=False):
        self.dry_run = dry_run
        self.processes = []

    def check_environment(self):
        """Verify required environment variables."""
        missing = []
        for var in REQUIRED_ENV:
            if not os.environ.get(var):
                missing.append(var)

        if missing:
            logger.error(f"Missing environment variables: {', '.join(missing)}")
            return False

        logger.info("Environment check: PASS")
        return True

    def setup_contracts(self):
        """Set contract addresses in environment."""
        for key, address in CONTRACTS.items():
            os.environ[key] = address
        logger.info("Contract addresses configured")

    def onboard_demo_markets(self):
        """Convert demo markets and deploy them."""
        logger.info("🏗️  Setting up demo markets...")

        try:
            # Generate config and Foundry script
            logger.info("Generating market configs...")
            result = subprocess.run(
                ["python3", "scripts/seed/demo_market_onboard.py"],
                capture_output=True,
                text=True,
                check=True
            )
            logger.info("Market configs generated")

            # Deploy markets via Foundry
            if not self.dry_run:
                logger.info("Deploying markets on-chain...")
                result = subprocess.run([
                    "forge", "script",
                    "script/OnboardDemoMarkets.s.sol:OnboardDemoMarkets",
                    "--rpc-url", os.environ["RPC_URL"],
                    "--private-key", os.environ["DEPLOYER_KEY"],
                    "--broadcast"
                ], capture_output=True, text=True, check=True)
                logger.info("Markets deployed successfully")
            else:
                logger.info("[DRY RUN] Would deploy markets")

            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"Market setup failed: {e}")
            logger.error(f"stdout: {e.stdout}")
            logger.error(f"stderr: {e.stderr}")
            return False

    def launch_oracle_bot(self):
        """Launch oracle keeper bot."""
        logger.info("🔮 Starting Oracle Bot...")

        env = os.environ.copy()
        env.update({
            "KEEPER_KEY": env["ORACLE_KEY"],
            "MARKET_CONFIG": "scripts/oracle/demo_market_config.json",
            "PUSH_INTERVAL": env.get("ORACLE_INTERVAL", "30"),
            "DRY_RUN": str(self.dry_run).lower()
        })

        try:
            process = subprocess.Popen([
                "python3", "scripts/oracle/keeper.py"
            ], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
               universal_newlines=True, preexec_fn=os.setsid)

            self.processes.append(("Oracle", process))
            logger.info(f"Oracle bot started (PID: {process.pid})")
            return True

        except Exception as e:
            logger.error(f"Failed to start oracle bot: {e}")
            return False

    def launch_lp_bot(self):
        """Launch LP seeding bot."""
        logger.info("🏦 Starting LP Bot...")

        env = os.environ.copy()
        env.update({
            "DEPOSIT_INTERVAL": env.get("LP_INTERVAL", "300"),
            "DRY_RUN": str(self.dry_run).lower()
        })

        try:
            process = subprocess.Popen([
                "python3", "scripts/seed/lp_bot.py"
            ], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
               universal_newlines=True, preexec_fn=os.setsid)

            self.processes.append(("LP", process))
            logger.info(f"LP bot started (PID: {process.pid})")
            return True

        except Exception as e:
            logger.error(f"Failed to start LP bot: {e}")
            return False

    def launch_trading_bot(self):
        """Launch trading seeding bot."""
        logger.info("📈 Starting Trading Bot...")

        env = os.environ.copy()
        env.update({
            "TRADE_INTERVAL": env.get("TRADE_INTERVAL", "60"),
            "DRY_RUN": str(self.dry_run).lower()
        })

        try:
            process = subprocess.Popen([
                "python3", "scripts/seed/trading_bot.py"
            ], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
               universal_newlines=True, preexec_fn=os.setsid)

            self.processes.append(("Trading", process))
            logger.info(f"Trading bot started (PID: {process.pid})")
            return True

        except Exception as e:
            logger.error(f"Failed to start trading bot: {e}")
            return False

    def monitor_processes(self):
        """Monitor all bot processes."""
        logger.info("👁️  Monitoring bot processes...")

        def log_output(name, process):
            """Log output from a process."""
            while True:
                line = process.stdout.readline()
                if not line:
                    break
                logger.info(f"[{name}] {line.strip()}")

        # Start output logging threads
        for name, process in self.processes:
            thread = Thread(target=log_output, args=(name, process), daemon=True)
            thread.start()

        try:
            while True:
                # Check if any processes died
                for name, process in self.processes[:]:  # Copy list
                    if process.poll() is not None:
                        logger.error(f"{name} bot died (exit code: {process.returncode})")
                        self.processes.remove((name, process))

                if not self.processes:
                    logger.warning("All processes died")
                    break

                time.sleep(5)

        except KeyboardInterrupt:
            logger.info("Shutdown requested...")
            self.cleanup()

    def cleanup(self):
        """Clean shutdown of all processes."""
        logger.info("Stopping all bots...")

        for name, process in self.processes:
            try:
                # Kill the process group (handles child processes)
                os.killpg(os.getpgid(process.pid), signal.SIGTERM)
                logger.info(f"Stopped {name} bot")
            except Exception as e:
                logger.error(f"Error stopping {name} bot: {e}")

        # Wait for graceful shutdown
        time.sleep(2)

        # Force kill if needed
        for name, process in self.processes:
            if process.poll() is None:
                try:
                    os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                    logger.info(f"Force killed {name} bot")
                except:
                    pass

        self.processes.clear()

    def run_setup(self):
        """Run market setup only."""
        if not self.check_environment():
            return False

        self.setup_contracts()
        return self.onboard_demo_markets()

    def run_bots_only(self):
        """Run bots only (assume markets already setup)."""
        if not self.check_environment():
            return False

        self.setup_contracts()

        # Start all bots
        success = True
        success &= self.launch_oracle_bot()
        success &= self.launch_lp_bot()
        success &= self.launch_trading_bot()

        if not success:
            logger.error("Failed to start some bots")
            self.cleanup()
            return False

        logger.info("🚀 All bots started successfully!")
        logger.info("Press Ctrl+C to stop all bots")

        # Monitor
        self.monitor_processes()
        return True

    def run_all(self):
        """Full setup and bot launch."""
        if not self.run_setup():
            return False

        # Short delay for deployment confirmation
        time.sleep(5)

        return self.run_bots_only()

def load_env_file(env_path):
    """Load environment variables from file."""
    if Path(env_path).exists():
        with open(env_path) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
        logger.info(f"Loaded environment from {env_path}")

def main():
    parser = argparse.ArgumentParser(description="Demo Market Seeding Orchestrator")
    parser.add_argument("--setup", action="store_true", help="Setup markets only")
    parser.add_argument("--bots", action="store_true", help="Run bots only")
    parser.add_argument("--all", action="store_true", help="Setup + bots")
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode")
    parser.add_argument("--env", default="scripts/seed/.env.demo", help="Environment file")

    args = parser.parse_args()

    if not any([args.setup, args.bots, args.all]):
        parser.print_help()
        sys.exit(1)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | SEED | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    # Load env file
    load_env_file(args.env)

    # Set defaults
    for key, value in DEFAULT_CONFIG.items():
        os.environ.setdefault(key, value)

    orchestrator = SeedingOrchestrator(dry_run=args.dry_run)

    try:
        if args.setup:
            success = orchestrator.run_setup()
        elif args.bots:
            success = orchestrator.run_bots_only()
        elif args.all:
            success = orchestrator.run_all()

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        orchestrator.cleanup()
        sys.exit(1)

if __name__ == "__main__":
    main()