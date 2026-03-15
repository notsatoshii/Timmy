#!/bin/bash
# Demo Market Seeding Launcher
# Runs oracle, LP, and trading bots for 10 curated demo markets

set -e

echo "🎯 LEVER Protocol Demo Market Seeding"
echo "======================================"
echo

# Check if we're in the right directory
if [[ ! -f "scripts/oracle/demo_markets.json" ]]; then
    echo "❌ Error: Run this from the lever-protocol root directory"
    exit 1
fi

echo "📋 Demo Markets Configuration:"
echo "   - 10 curated markets across tech, geopolitics, sports, macro, crypto, forex"
echo "   - Markets span from April 2026 to December 2026"
echo "   - Price ranges: 0.22 to 0.88 (realistic prediction market odds)"
echo

# Show demo markets summary
if command -v jq >/dev/null 2>&1; then
    echo "📊 Markets Summary:"
    jq -r '.markets[] | "   • \(.category | ascii_upcase): \(.name[0:50])..."' scripts/oracle/demo_markets.json
else
    echo "   • See scripts/oracle/demo_markets.json for full market list"
fi
echo

echo "🔧 Generated Artifacts:"
echo "   ✓ scripts/oracle/demo_market_config.json - Oracle keeper configuration"
echo "   ✓ script/OnboardDemoMarkets.s.sol - Foundry deployment script"
echo "   ✓ scripts/seed/.env.demo - Environment template"
echo "   ✓ scripts/seed/lp_bot.py - LP liquidity seeding bot"
echo "   ✓ scripts/seed/trading_bot.py - Trading activity simulation bot"
echo "   ✓ scripts/oracle/keeper.py - Oracle price feed bot (existing)"
echo

echo "🚀 Bot Capabilities:"
echo "   📡 Oracle Bot: Fetches Polymarket prices every 30s, pushes to OracleAdapter"
echo "   🏦 LP Bot: Deposits USDT to reach $100k TVL target, manages vault liquidity"
echo "   📈 Trading Bot: Opens/closes positions with 1-10x leverage, realistic patterns"
echo

# Check environment setup
echo "🔍 Environment Check:"
missing_vars=()

required_vars=(
    "RPC_URL"
    "DEPLOYER_KEY"
    "ORACLE_KEY"
    "LP_BOT_KEY"
    "TRADER_BOT_KEY"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "   ❌ Missing environment variables: ${missing_vars[*]}"
    echo "   💡 Set these variables or source scripts/seed/.env.demo with real keys"
    echo
    echo "🧪 Running DRY-RUN demonstration instead..."
    DRY_RUN="true"
else
    echo "   ✅ All required environment variables set"
    DRY_RUN="${DRY_RUN:-false}"
fi

echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo "🧪 DRY RUN MODE - Demonstration Only"
    echo "   - No actual on-chain transactions"
    echo "   - Shows bot logic and market processing"
    echo "   - Safe to run without gas or real keys"
    echo

    # Set dummy environment for dry run
    export RPC_URL="${RPC_URL:-https://sepolia.base.org}"
    export DEPLOYER_KEY="${DEPLOYER_KEY:-0x0000000000000000000000000000000000000000000000000000000000000001}"
    export ORACLE_KEY="${ORACLE_KEY:-0x0000000000000000000000000000000000000000000000000000000000000002}"
    export LP_BOT_KEY="${LP_BOT_KEY:-0x0000000000000000000000000000000000000000000000000000000000000003}"
    export TRADER_BOT_KEY="${TRADER_BOT_KEY:-0x0000000000000000000000000000000000000000000000000000000000000004}"

    export DRY_RUN="true"
else
    echo "🔥 LIVE MODE - Real Base Sepolia Deployment"
    echo "   - Will create actual markets and transactions"
    echo "   - Requires gas and funded wallets"
    echo
fi

# Load contract addresses
source scripts/seed/.env.demo

echo "📍 Target Contracts (Base Sepolia):"
echo "   USDT (Mock):        $USDT_ADDRESS"
echo "   MarketRegistry:     $MARKET_REGISTRY"
echo "   OracleAdapter:      $ORACLE_ADAPTER"
echo "   LeverVault:         $LEVER_VAULT"
echo "   ExecutionEngine:    $EXECUTION_ENGINE"
echo "   AccountManager:     $ACCOUNT_MANAGER"
echo

echo "⚙️  Bot Configuration:"
echo "   Oracle interval:    ${ORACLE_INTERVAL:-30}s"
echo "   LP check interval:  ${LP_INTERVAL:-300}s (5min)"
echo "   Trading interval:   ${TRADE_INTERVAL:-60}s"
echo "   Target TVL:         \$${TARGET_TVL:-100000}"
echo "   Position size:      \$${POSITION_SIZE_MIN:-100} - \$${POSITION_SIZE_MAX:-2000}"
echo "   Max leverage:       ${MAX_LEVERAGE:-10}x"
echo

# Ask for confirmation unless in CI
if [[ -z "$CI" ]] && [[ "$DRY_RUN" != "true" ]]; then
    echo -n "🤔 Proceed with seeding? [y/N] "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled by user"
        exit 1
    fi
fi

echo "🚀 Launching Demo Seeding..."
echo

# Run the orchestrator
if [[ "$1" == "--setup-only" ]]; then
    echo "🏗️  Setting up markets only..."
    python3 scripts/seed/run_demo_seeding.py --setup ${DRY_RUN:+--dry-run}
elif [[ "$1" == "--bots-only" ]]; then
    echo "🤖 Starting bots only (assumes markets exist)..."
    python3 scripts/seed/run_demo_seeding.py --bots ${DRY_RUN:+--dry-run}
else
    echo "🎬 Full setup + bots..."
    python3 scripts/seed/run_demo_seeding.py --all ${DRY_RUN:+--dry-run}
fi

echo
echo "✅ Demo seeding complete!"
echo "📊 Check the logs above for bot activity and market interactions"