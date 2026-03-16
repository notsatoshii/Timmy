#!/usr/bin/env python3
"""
Fund all bot wallets with ETH (for gas) and MockUSDT.
Uses deployer wallet to mint USDT and send ETH.
Batches transactions to avoid nonce issues.

Run: python3 scripts/fund-all-bots.py
"""

import json
import subprocess
import time
import os
import sys

REPO = "/home/lever/lever-protocol"
WALLETS_FILE = f"{REPO}/control-plane/bot-wallets.json"
ADDRESSES_FILE = f"{REPO}/control-plane/bot-addresses.json"

# Load deploy env
def get_env():
    """Parse deploy-env.sh for variables"""
    env = {}
    with open(f"{REPO}/control-plane/deploy-env.sh") as f:
        for line in f:
            line = line.strip()
            if line.startswith("export ") and "=" in line and "$(" not in line:
                parts = line.replace("export ", "").split("=", 1)
                env[parts[0]] = parts[1]
    return env

def run_cast(args, check=True):
    """Run a cast command and return output"""
    cmd = ["cast"] + args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if check and result.returncode != 0:
        print(f"  ERROR: {' '.join(cmd[:4])}... -> {result.stderr[:200]}")
        return None
    return result.stdout.strip()

def main():
    env = get_env()
    RPC = env.get("RPC_URL", "https://sepolia.base.org")
    USDT = env.get("USDT_ADDRESS")
    DEPLOYER = env.get("DEPLOYER")

    # Read deployer key
    with open(f"{REPO}/.env.deployer") as f:
        DEPLOYER_KEY = f.read().strip()

    # Load wallets
    wallets = json.load(open(WALLETS_FILE))

    # Generate addresses
    print("Generating bot addresses...")
    addresses = {}
    for name, key in wallets.items():
        addr = run_cast(["wallet", "address", "--private-key", key])
        if addr:
            addresses[name] = addr
    json.dump(addresses, open(ADDRESSES_FILE, "w"), indent=2)
    print(f"  {len(addresses)} addresses generated")

    # Funding amounts per role
    ETH_AMOUNTS = {
        "lp": "0.005ether",        # LPs mostly deposit, few txs
        "trader": "0.01ether",      # Traders open/close positions
        "market_maker": "0.02ether", # MMs trade frequently
        "oracle": "0.05ether",      # Oracle pushes prices constantly
        "liquidator": "0.03ether",  # Liquidator needs gas for liq txs
        "orchestrator": "0.01ether", # Orchestrator coordinates
    }

    USDT_AMOUNTS = {
        "lp": 500000_000000,          # 500K USDT each (40 * 500K = 20M)
        "trader": 133333_000000,       # ~133K USDT each (30 * 133K = 4M)
        "market_maker": 1000000_000000, # 1M each
        "oracle": 0,                    # Oracle doesn't need USDT
        "liquidator": 100000_000000,    # 100K for liquidation bot
        "orchestrator": 0,              # Orchestrator doesn't need USDT
    }

    # Check deployer balance first
    print("\nChecking deployer balance...")
    deployer_eth = run_cast(["balance", DEPLOYER, "--rpc-url", RPC])
    print(f"  Deployer ETH: {deployer_eth}")

    total_eth_needed = 0
    total_usdt_needed = 0
    for name in wallets:
        role = name.rsplit("_", 1)[0] if "_" in name else name
        eth_str = ETH_AMOUNTS.get(role, "0.005ether")
        eth_val = float(eth_str.replace("ether", ""))
        total_eth_needed += eth_val
        total_usdt_needed += USDT_AMOUNTS.get(role, 0)

    print(f"  Total ETH needed: ~{total_eth_needed:.2f} ETH")
    print(f"  Total USDT to mint: {total_usdt_needed / 1e6:.0f} USDT")

    # Fund each bot
    print(f"\nFunding {len(wallets)} bots...")
    funded = 0
    errors = 0

    for name, addr in addresses.items():
        role = name.rsplit("_", 1)[0] if "_" in name else name
        eth_amount = ETH_AMOUNTS.get(role, "0.005ether")
        usdt_amount = USDT_AMOUNTS.get(role, 0)

        # Send ETH
        result = run_cast([
            "send", addr,
            "--value", eth_amount,
            "--rpc-url", RPC,
            "--private-key", DEPLOYER_KEY
        ], check=False)

        if result is None:
            errors += 1
            continue

        time.sleep(0.3)  # Avoid nonce issues

        # Mint USDT if needed
        if usdt_amount > 0:
            result = run_cast([
                "send", USDT,
                "mint(address,uint256)", addr, str(usdt_amount),
                "--rpc-url", RPC,
                "--private-key", DEPLOYER_KEY
            ], check=False)

            if result is None:
                errors += 1
                continue

            time.sleep(0.3)

        funded += 1
        if funded % 10 == 0:
            print(f"  Funded {funded}/{len(wallets)}...")

    print(f"\n=== FUNDING COMPLETE: {funded} funded, {errors} errors ===")

    # Verify a sample
    print("\nVerifying sample wallets...")
    samples = list(addresses.items())[:5]
    for name, addr in samples:
        eth = run_cast(["balance", addr, "--rpc-url", RPC])
        usdt = run_cast(["call", USDT, "balanceOf(address)(uint256)", addr, "--rpc-url", RPC])
        print(f"  {name}: ETH={eth}, USDT={usdt}")

    # Save funding report
    report = {
        "funded": funded,
        "errors": errors,
        "total_bots": len(wallets),
        "total_eth_sent": total_eth_needed,
        "total_usdt_minted": total_usdt_needed / 1e6,
    }
    json.dump(report, open(f"{REPO}/control-plane/bot-funding-report.json", "w"), indent=2)
    print(f"\nReport saved to control-plane/bot-funding-report.json")

if __name__ == "__main__":
    main()
