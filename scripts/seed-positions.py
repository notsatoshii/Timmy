#!/usr/bin/env python3
"""
Seed 20 wallets with positions on Lever Protocol.
- Fund each with ETH for gas
- Mint USDT, deposit to AccountManager
- Open 5 positions each (random markets, $50K+ notional, 6x+ leverage)
- Close half, open new ones
"""

import json
import subprocess
import random
import time
import sys
import os

# Load config
RPC_URL = "https://sepolia.base.org"
DEPLOYER_KEY = open("/home/lever/lever-protocol/.env.deployer").read().strip()
DEPLOYER = "0x0e4D636c6D79c380A137f28EF73E054364cd5434"

# Contract addresses (from deploy-env.sh)
USDT = "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E"
ACCOUNT_MANAGER = "0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684"
EXECUTION_ENGINE = "0x31078bfe85d3f586edce8f5579d32448cb0586d6"
POSITION_MANAGER = "0x25ba54a7b2fBac753B601Da05e3661F2E959510b"

MARKETS = [
    "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1",  # SpaceX IPO
    "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a",  # US-Iran
    "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d",  # Nothing Happens
    "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2",  # FIFA
    "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7",  # Fed Rate EOY
    "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2",  # SpaceX Ackman
    "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554",  # AAPL $250
    "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc",  # OpenSea
    "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f",  # Fed April Cut
    "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea",  # Argentina USD
]

MARKET_NAMES = ["SpaceX", "US-Iran", "Nothing", "FIFA", "FedEOY", "Ackman", "AAPL", "OpenSea", "FedApril", "Argentina"]

def cast_send(to, sig, args_str, key, gas=200000, value=None):
    """Execute a cast send and return success"""
    cmd = ["cast", "send", to, sig]
    if args_str:
        cmd.extend(args_str.split(" "))
    cmd.extend(["--private-key", key, "--rpc-url", RPC_URL, "--gas-limit", str(gas)])
    if value:
        cmd.extend(["--value", value])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False

def cast_send_deployer(to, sig, args_str, gas=200000, value=None):
    return cast_send(to, sig, args_str, DEPLOYER_KEY, gas, value)

def get_nonce(addr):
    result = subprocess.run(
        ["cast", "nonce", addr, "--rpc-url", RPC_URL],
        capture_output=True, text=True
    )
    return int(result.stdout.strip())

def main():
    # Load wallets
    with open("/home/lever/lever-protocol/control-plane/demo-wallets.json") as f:
        wallets = json.load(f)

    print(f"=== SEEDING {len(wallets)} WALLETS ===")
    print()

    # ============================
    # PHASE 1: Fund wallets with ETH
    # ============================
    print("--- PHASE 1: Fund ETH for gas ---")
    # Each wallet needs ~5 TXs at ~500K gas each, at ~0.1 gwei base fee on Base Sepolia
    # ~0.001 ETH per wallet should be plenty
    ETH_PER_WALLET = "1000000000000000"  # 0.001 ETH

    for i, w in enumerate(wallets):
        ok = cast_send_deployer(w['address'], "", None, gas=21000, value=ETH_PER_WALLET)
        status = "✓" if ok else "✗"
        print(f"  [{i+1}/20] ETH → {w['address'][:10]}... {status}")
        time.sleep(4)

    print()

    # ============================
    # PHASE 2: Mint USDT + Approve AM + Deposit
    # ============================
    print("--- PHASE 2: Mint USDT + Deposit to AM ---")
    # Each wallet needs: 5 positions × $50K+ collateral at 6x+ = ~$10K collateral each = $50K per wallet
    USDT_PER_WALLET = "100000000000"  # $100K USDT (100000 * 1e6)

    for i, w in enumerate(wallets):
        # Mint USDT (deployer can mint)
        ok = cast_send_deployer(USDT, "mint(address,uint256)", f"{w['address']} {USDT_PER_WALLET}", gas=200000)
        print(f"  [{i+1}/20] Mint $100K USDT {'✓' if ok else '✗'}")
        time.sleep(4)

        # Approve AM
        ok = cast_send(USDT, "approve(address,uint256)", f"{ACCOUNT_MANAGER} {USDT_PER_WALLET}", w['key'], gas=100000)
        print(f"  [{i+1}/20] Approve AM {'✓' if ok else '✗'}")
        time.sleep(4)

        # Deposit to AM
        ok = cast_send(ACCOUNT_MANAGER, "deposit(uint256)", USDT_PER_WALLET, w['key'], gas=300000)
        print(f"  [{i+1}/20] Deposit $100K to AM {'✓' if ok else '✗'}")
        time.sleep(4)

    print()

    # ============================
    # PHASE 3: Open 5 positions each
    # ============================
    print("--- PHASE 3: Open 5 positions per wallet (100 total) ---")

    all_positions = []  # Track (wallet_index, position_id) for closing

    for i, w in enumerate(wallets):
        for j in range(5):
            market_idx = random.randint(0, 9)
            market_id = MARKETS[market_idx]
            is_long = random.choice([True, False])
            direction = "true" if is_long else "false"
            dir_label = "LONG" if is_long else "SHORT"

            # Collateral: $8K-$12K USDT (6 decimals) → notional at 6-8x = $48K-$96K
            collateral = random.randint(8000, 12000) * 1000000  # 8000-12000 USDT in 6 dec
            leverage_x = random.uniform(6.0, 8.5)  # 6x to 8.5x (max is ~8.5x)
            leverage_wad = int(leverage_x * 1e18)

            notional = collateral * leverage_x / 1e6

            # openPosition((bytes32,bool,uint256,uint256))
            tuple_arg = f"({market_id},{direction},{collateral},{leverage_wad})"

            ok = cast_send(
                EXECUTION_ENGINE,
                "openPosition((bytes32,bool,uint256,uint256))",
                tuple_arg,
                w['key'],
                gas=2000000
            )

            mkt_name = MARKET_NAMES[market_idx]
            status = "✓" if ok else "✗"
            print(f"  W{i+1} P{j+1}: {dir_label} {mkt_name} ${notional/1000:.0f}K @{leverage_x:.1f}x {status}")

            if ok:
                all_positions.append((i, w))

            time.sleep(5)

    print(f"\nTotal positions opened: {len(all_positions)}")
    print()

    # ============================
    # PHASE 4: Close half randomly
    # ============================
    print("--- PHASE 4: Close ~50 positions randomly ---")

    # Get all open position IDs
    time.sleep(10)  # Wait for chain to settle

    # Find position IDs by scanning
    result = subprocess.run(
        ["cast", "call", POSITION_MANAGER, "totalPositions()(uint256)", "--rpc-url", RPC_URL],
        capture_output=True, text=True
    )
    total_pos = int(result.stdout.strip().split()[0]) if result.returncode == 0 else 0
    print(f"  Total positions on-chain: {total_pos}")

    # Find open positions
    open_positions = []
    for pid in range(1, total_pos + 1):
        result = subprocess.run(
            ["cast", "call", POSITION_MANAGER, "isPositionOpen(uint256)(bool)", str(pid), "--rpc-url", RPC_URL],
            capture_output=True, text=True
        )
        if result.stdout.strip() == "true":
            # Get position owner
            result2 = subprocess.run(
                ["cast", "call", POSITION_MANAGER, "getPosition(uint256)", str(pid), "--rpc-url", RPC_URL],
                capture_output=True, text=True
            )
            open_positions.append(pid)

    print(f"  Open positions found: {len(open_positions)}")

    # Close half randomly
    to_close = random.sample(open_positions, len(open_positions) // 2) if len(open_positions) > 1 else []
    print(f"  Closing {len(to_close)} positions...")

    # Find which wallet owns each position and close
    wallet_keys = {w['address'].lower(): w['key'] for w in wallets}

    for pid in to_close:
        # Get position owner from the tuple returned by getPosition
        # We need to find the trader address - it's embedded in the position struct
        # Simplest: try closing with each wallet's EE call
        # Actually, the owner calls closePosition on EE

        # Get the trader from position
        result = subprocess.run(
            ["cast", "call", EXECUTION_ENGINE, "getPositionTrader(uint256)(address)", str(pid), "--rpc-url", RPC_URL],
            capture_output=True, text=True
        )

        if result.returncode != 0:
            # Try reading from PM
            result = subprocess.run(
                ["cast", "call", POSITION_MANAGER, "getPosition(uint256)", str(pid), "--rpc-url", RPC_URL],
                capture_output=True, text=True
            )
            # Skip if we can't determine owner
            print(f"  Position {pid}: can't determine owner, skipping")
            continue

        trader = result.stdout.strip().lower()
        if trader in wallet_keys:
            ok = cast_send(EXECUTION_ENGINE, "closePosition(uint256)", str(pid), wallet_keys[trader], gas=2000000)
            print(f"  Close #{pid}: {'✓' if ok else '✗'}")
            time.sleep(5)

    print()

    # ============================
    # PHASE 5: Open new positions to replace closed ones
    # ============================
    print(f"--- PHASE 5: Open {len(to_close)} replacement positions ---")

    for k in range(len(to_close)):
        w = wallets[k % 20]
        market_idx = random.randint(0, 9)
        market_id = MARKETS[market_idx]
        is_long = random.choice([True, False])
        direction = "true" if is_long else "false"
        dir_label = "LONG" if is_long else "SHORT"

        collateral = random.randint(8000, 12000) * 1000000
        leverage_x = random.uniform(6.0, 8.5)
        leverage_wad = int(leverage_x * 1e18)
        notional = collateral * leverage_x / 1e6

        tuple_arg = f"({market_id},{direction},{collateral},{leverage_wad})"

        ok = cast_send(EXECUTION_ENGINE, "openPosition((bytes32,bool,uint256,uint256))", tuple_arg, w['key'], gas=2000000)
        mkt_name = MARKET_NAMES[market_idx]
        print(f"  New {k+1}/{len(to_close)}: {dir_label} {mkt_name} ${notional/1000:.0f}K @{leverage_x:.1f}x {'✓' if ok else '✗'}")
        time.sleep(5)

    print()
    print("=== SEEDING COMPLETE ===")

    # Final count
    result = subprocess.run(
        ["cast", "call", POSITION_MANAGER, "totalPositions()(uint256)", "--rpc-url", RPC_URL],
        capture_output=True, text=True
    )
    print(f"Total positions on-chain: {result.stdout.strip()}")

if __name__ == "__main__":
    main()
