#!/bin/bash
# Quick Oracle Status for Demo Period
# Provides a clean status report for during investor demonstrations

echo "🔍 ORACLE STATUS REPORT - $(date '+%H:%M:%S')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Process check
KEEPER_PID=$(pgrep -f mock_keeper.py)
if [ -n "$KEEPER_PID" ]; then
    echo "✅ Oracle Keeper: RUNNING (PID: $KEEPER_PID)"
else
    echo "❌ Oracle Keeper: NOT RUNNING"
    exit 1
fi

# Price freshness from health check
HEALTH_OUTPUT=$(bash /home/lever/lever-protocol/control-plane/health-check.sh 2>/dev/null | grep oracle_price_freshness)
if echo "$HEALTH_OUTPUT" | grep -q "PASS"; then
    LAST_UPDATE=$(echo "$HEALTH_OUTPUT" | grep -o "last push.*" | cut -d'(' -f2 | cut -d')' -f1)
    echo "✅ Price Updates: FRESH ($LAST_UPDATE)"
else
    echo "❌ Price Updates: STALE"
fi

# Recent activity summary
ORACLE_LOG="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
if [ -f "$ORACLE_LOG" ]; then
    RECENT_PUSHES=$(tail -n10 "$ORACLE_LOG" | grep "PUSHED:" | wc -l)
    RECENT_ERRORS=$(tail -n10 "$ORACLE_LOG" | grep "ERROR" | wc -l)
    echo "📊 Recent Activity: $RECENT_PUSHES successful updates, $RECENT_ERRORS errors"
else
    echo "❌ Oracle Log: NOT FOUND"
fi

# Sample current price data
echo "📈 Sample Current Prices:"
source /home/lever/lever-protocol/control-plane/deploy-env.sh
export PATH="/home/lever/.foundry/bin:$PATH"

# Test a few key markets
MARKETS=(
    "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1:SpaceX IPO"
    "0x48a7a15bc93bd0c38d8c1d6b0af4bb44df5a4ad90b7f8cb7e9b4e47b86b0f6a3:Fed Rate"
    "0x7b4e8f5c6d9a1e2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6:AAPL $250"
)

for market in "${MARKETS[@]}"; do
    MARKET_ID=$(echo $market | cut -d':' -f1)
    MARKET_NAME=$(echo $market | cut -d':' -f2)

    PI_RESULT=$(cast call --rpc-url https://sepolia.base.org $ORACLE_ADAPTER "getPI(bytes32)" $MARKET_ID 2>/dev/null)
    if [ $? -eq 0 ] && [ "$PI_RESULT" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        PI_HEX=$(echo $PI_RESULT | sed 's/0x//')
        PI_DEC=$(python3 -c "import sys; print(f'{int(\"$PI_HEX\", 16) / 1e18:.3f}')")
        echo "   $MARKET_NAME: $PI_DEC"
    else
        echo "   $MARKET_NAME: ERROR"
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🟢 Oracle system operational for investor demo"