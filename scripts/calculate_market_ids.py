#!/usr/bin/env python3
"""Calculate market IDs for demo markets."""

import hashlib

def market_id_from_name(name: str) -> str:
    """Generate deterministic market ID from name."""
    return "0x" + hashlib.sha256(name.encode()).hexdigest()

# Markets from demo_markets.json that are long-dated (>90 days)
markets = [
    "Largest IPO by Market Cap 2026: SpaceX?",  # 10x leverage
    "SpaceX IPO via Ackman SPAR?",  # 15x leverage
    "Nothing Ever Happens: 2026",  # 20x leverage
    "Fed Rate End of 2026: Below 4%?",  # 25x leverage
    "OpenSea Token Launch by 2026?",  # 30x leverage
]

print("Market IDs for position opening:")
for i, market in enumerate(markets):
    market_id = market_id_from_name(market)
    leverage = 10 + (i * 5)  # 10x, 15x, 20x, 25x, 30x
    print(f"Market {i+1}: {market}")
    print(f"  ID: {market_id}")
    print(f"  Leverage: {leverage}x")
    print()