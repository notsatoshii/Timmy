#!/usr/bin/env python3
"""
Demo Market Onboarding — Convert demo_markets.json to deployable format and create markets.

This script:
1. Reads scripts/oracle/demo_markets.json
2. Converts to market_config.json format for keeper
3. Creates Foundry script to call MarketRegistry.createMarket() for each demo market
"""

import json
import hashlib
from datetime import datetime
from pathlib import Path

# Constants from LEVER protocol
WAD = 10**18
CATEGORY_MAP = {
    "tech": 0,         # HIGH_LIQUIDITY
    "geopolitics": 1,  # MEDIUM_LIQUIDITY
    "sports": 0,       # HIGH_LIQUIDITY
    "macro": 1,        # MEDIUM_LIQUIDITY
    "speculative": 2,  # LOW_LIQUIDITY
    "stocks": 0,       # HIGH_LIQUIDITY
    "crypto": 0,       # HIGH_LIQUIDITY
    "forex": 1,        # MEDIUM_LIQUIDITY
}

def market_id_from_name(name: str) -> str:
    """Generate deterministic market ID from name."""
    return "0x" + hashlib.sha256(name.encode()).hexdigest()

def parse_expiry(expiry_str: str) -> int:
    """Convert ISO datetime to Unix timestamp."""
    dt = datetime.fromisoformat(expiry_str.replace('Z', '+00:00'))
    return int(dt.timestamp())

def generate_market_config(demo_markets: list) -> list:
    """Convert demo markets to keeper-compatible format."""
    config = []

    for market in demo_markets:
        market_id = market_id_from_name(market["name"])
        category = CATEGORY_MAP.get(market["category"], 2)

        # Allocation weight based on category (higher for premium categories)
        if category == 0:  # HIGH_LIQUIDITY
            weight = 0.4 * WAD // 10  # 40% allocation
        elif category == 1:  # MEDIUM_LIQUIDITY
            weight = 0.25 * WAD // 10  # 25% allocation
        else:  # LOW_LIQUIDITY
            weight = 0.15 * WAD // 10  # 15% allocation

        config.append({
            "marketId": market_id,
            "name": market["name"],
            "externalMarketId": market_id,
            "resolutionTime": parse_expiry(market["expiry"]),
            "category": category,
            "categoryName": ["HIGH_LIQUIDITY", "MEDIUM_LIQUIDITY", "LOW_LIQUIDITY"][category],
            "allocationWeight": str(weight),
            "_polymarket": {
                "conditionId": market_id,
                "tokenIds": [
                    f"{hash(market['polymarket_ref'] + '_yes') % (2**256)}",
                    f"{hash(market['polymarket_ref'] + '_no') % (2**256)}"
                ],
                "volume": 50000.0 if category <= 1 else 15000.0,  # Simulated volume
                "liquidity": 10000.0 if category <= 1 else 5000.0,  # Simulated liquidity
                "currentPrice": market["initial_probability"],
                "endDate": market["expiry"],
                "polyCategory": market["category"]
            }
        })

    return config

def generate_foundry_script(demo_markets: list) -> str:
    """Generate Foundry deployment script for demo markets."""

    solidity_code = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../../contracts/core/MarketRegistry.sol";

/// @title Demo Market Onboarding Script
/// @notice Creates demo markets from demo_markets.json for seeding bots
contract OnboardDemoMarkets is Script {
    MarketRegistry public marketRegistry;

    struct MarketParams {
        string name;
        uint256 resolutionTime;
        IMarketRegistry.MarketCategory category;
        uint256 allocationWeight;
        bytes32 externalId;
    }

    function run() external {
        marketRegistry = MarketRegistry(vm.envAddress("MARKET_REGISTRY"));

        vm.startBroadcast();

        // Create demo markets'''

    for i, market in enumerate(demo_markets):
        market_id = market_id_from_name(market["name"])
        category = CATEGORY_MAP.get(market["category"], 2)

        if category == 0:
            weight = 0.4 * WAD // 10
        elif category == 1:
            weight = 0.25 * WAD // 10
        else:
            weight = 0.15 * WAD // 10

        solidity_code += f'''

        // {market["name"]}
        marketRegistry.createMarket(
            "{market["name"]}",
            {parse_expiry(market["expiry"])},
            IMarketRegistry.MarketCategory({category}),
            {weight},
            {market_id}
        );'''

    solidity_code += '''

        vm.stopBroadcast();

        console2.log("Demo markets created successfully");
        console2.log("Total markets:", vm.envUint("DEMO_MARKET_COUNT"));
    }
}'''

    return solidity_code

def main():
    # Read demo markets
    demo_path = Path("scripts/oracle/demo_markets.json")
    with open(demo_path) as f:
        data = json.load(f)

    demo_markets = data["markets"]

    # Generate keeper config
    market_config = generate_market_config(demo_markets)

    # Write market config for keeper
    config_path = Path("scripts/oracle/demo_market_config.json")
    with open(config_path, 'w') as f:
        json.dump(market_config, f, indent=2)

    print(f"✅ Generated keeper config: {config_path}")
    print(f"   - {len(market_config)} markets configured")

    # Generate Foundry script
    foundry_script = generate_foundry_script(demo_markets)

    script_path = Path("script/OnboardDemoMarkets.s.sol")
    with open(script_path, 'w') as f:
        f.write(foundry_script)

    print(f"✅ Generated Foundry script: {script_path}")
    print(f"   - Ready for: forge script {script_path}:OnboardDemoMarkets --broadcast")

    # Generate env template
    env_template = f"""# Demo Market Onboarding Environment
MARKET_REGISTRY=0x463697f45a0dA6B247305bac56F68e37779ba6bF
DEMO_MARKET_COUNT={len(demo_markets)}

# For bots
ORACLE_ADAPTER=0x4F0224F2cC6ab7acC1A913D06F055Ae8FA484d78
USDT_ADDRESS=0x92c9711101bBB0B742d6320D52521FAd1712A85e
LEVER_VAULT=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
EXECUTION_ENGINE=0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
ACCOUNT_MANAGER=0xe0f420dD416e6047fDA063d66292f7679160519B
"""

    env_path = Path("scripts/seed/.env.demo")
    with open(env_path, 'w') as f:
        f.write(env_template)

    print(f"✅ Generated env template: {env_path}")
    print(f"\n🚀 Next steps:")
    print(f"   1. Set up environment: export $(cat {env_path} | xargs)")
    print(f"   2. Deploy markets: forge script script/OnboardDemoMarkets.s.sol:OnboardDemoMarkets --broadcast")
    print(f"   3. Run bots: see scripts/seed/")

if __name__ == "__main__":
    main()