#!/usr/bin/env python3
"""
Fund only the remaining unfunded bot wallets.
Targeted approach for efficiency.
"""

import json
import subprocess
import time

# Load environment
def get_env():
    env = {}
    with open("/home/lever/lever-protocol/control-plane/deploy-env.sh") as f:
        for line in f:
            line = line.strip()
            if line.startswith("export ") and "=" in line and "$(" not in line:
                parts = line.replace("export ", "").split("=", 1)
                value = parts[1].strip('"')
                env[parts[0]] = value
    return env

def run_cast(args, check=True):
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

    with open("/home/lever/lever-protocol/.env.deployer") as f:
        DEPLOYER_KEY = f.read().strip()

    addresses = json.load(open("/home/lever/lever-protocol/control-plane/bot-addresses.json"))

    # Identify unfunded bots
    print("Identifying unfunded bots...")
    unfunded_bots = []

    for name, addr in addresses.items():
        balance = run_cast(["balance", addr, "--rpc-url", RPC])
        if balance and int(balance) == 0:
            unfunded_bots.append((name, addr))

    print(f"Found {len(unfunded_bots)} unfunded bots")

    # ETH amounts by role
    ETH_AMOUNTS = {
        "lp": "0.0004ether",
        "trader": "0.0005ether",
        "market": "0.001ether",
        "oracle": "0.003ether",
        "liquidator": "0.002ether",
        "orchestrator": "0.0005ether"
    }

    USDT_AMOUNTS = {
        "lp": 500000_000000,
        "trader": 133333_000000,
        "market": 1000000_000000,
        "oracle": 0,
        "liquidator": 100000_000000,
        "orchestrator": 0
    }

    # Fund each unfunded bot
    funded = 0
    errors = 0

    for name, addr in unfunded_bots:
        role = name.split("_")[0]
        eth_amount = ETH_AMOUNTS.get(role, "0.0005ether")
        usdt_amount = USDT_AMOUNTS.get(role, 0)

        print(f"Funding {name} ({addr})...")

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

        time.sleep(0.5)

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

            time.sleep(0.5)

        funded += 1
        print(f"  ✓ {name} funded successfully")

    print(f"\n=== FUNDING COMPLETE ===")
    print(f"Funded: {funded}")
    print(f"Errors: {errors}")
    print(f"Total unfunded found: {len(unfunded_bots)}")

    # Verify sample
    print("\nVerifying sample...")
    for i, (name, addr) in enumerate(unfunded_bots[:3]):
        eth = run_cast(["balance", addr, "--rpc-url", RPC])
        print(f"  {name}: ETH={eth}")

if __name__ == "__main__":
    main()