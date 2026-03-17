#!/usr/bin/env python3
"""Check existing positions for high leverage."""

import subprocess
import os

def run_cast_call(position_id):
    """Run cast call to get position data."""
    cmd = [
        "cast", "call", os.environ["POSITION_MANAGER"],
        "getPosition(uint256)", str(position_id),
        "--rpc-url", os.environ["RPC_URL"]
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def extract_leverage(position_data):
    """Extract leverage from position data."""
    if not position_data:
        return 0

    # Position data is multiple 64-char hex values (32 bytes each)
    # Leverage is the 8th field (index 7)
    lines = position_data.split('\n')
    full_data = ''.join(lines).replace('0x', '')

    # Each field is 64 hex chars (32 bytes)
    if len(full_data) >= 8 * 64:
        leverage_hex = full_data[7*64:8*64]
        leverage_dec = int(leverage_hex, 16)
        return leverage_dec / 1e18
    return 0

def main():
    print("Checking positions for leverage >=10x...")

    high_leverage_positions = []

    # Check positions 1-70
    for pos_id in range(1, 71):
        position_data = run_cast_call(pos_id)
        if position_data:
            leverage = extract_leverage(position_data)
            if leverage >= 10:
                print(f"Position {pos_id}: {leverage:.1f}x leverage")
                high_leverage_positions.append((pos_id, leverage))
            elif leverage > 1:
                print(f"Position {pos_id}: {leverage:.1f}x leverage (low)")

    print(f"\nHigh leverage positions (>=10x): {len(high_leverage_positions)}")
    if len(high_leverage_positions) >= 3:
        print("✅ DONE condition met: At least 3 positions with >=10x leverage")
    else:
        print("❌ DONE condition NOT met: Need at least 3 positions with >=10x leverage")
        print(f"Currently have: {len(high_leverage_positions)}")

if __name__ == "__main__":
    main()