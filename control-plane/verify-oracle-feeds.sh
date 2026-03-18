#!/bin/bash
# Oracle Feed Staleness Verification Script
# Verifies that oracle feeds are updating within target timeframes

echo "=== Oracle Feed Staleness Check ==="
echo "Target: <30s (task requirement)"
echo ""

# Check prices.json file freshness
if [ -f "frontend/user-app/public/prices.json" ]; then
    CURRENT_TIME=$(date +%s)
    LAST_UPDATE=$(jq -r '.lastUpdate' frontend/user-app/public/prices.json)
    AGE=$((CURRENT_TIME - LAST_UPDATE))

    echo "Prices.json Status:"
    echo "  Current time: $CURRENT_TIME"
    echo "  Last update:  $LAST_UPDATE"
    echo "  Age: ${AGE} seconds"

    if [ $AGE -lt 30 ]; then
        echo "  Status: ✅ FRESH (under 30s)"
    elif [ $AGE -lt 120 ]; then
        echo "  Status: ⚠️  ACCEPTABLE (under 2min)"
    else
        echo "  Status: ❌ STALE (over 2min)"
    fi
else
    echo "❌ prices.json file not found"
fi

echo ""

# Check if oracle keeper is running
if pgrep -f "stable_mock_keeper.py" > /dev/null; then
    echo "Oracle Keeper: ✅ RUNNING (stable_mock_keeper.py)"

    # Check recent keeper activity
    if [ -f "scripts/oracle/stable_keeper.log" ]; then
        echo ""
        echo "Recent Activity (last 5 lines):"
        tail -5 scripts/oracle/stable_keeper.log | sed 's/^/  /'
    fi
else
    echo "Oracle Keeper: ❌ NOT RUNNING"
fi

echo ""
echo "=== Summary ==="
if [ $AGE -lt 30 ]; then
    echo "✅ Oracle feeds are FRESH (${AGE}s old, target <30s)"
    exit 0
else
    echo "⚠️  Oracle feeds are ${AGE}s old (target <30s)"
    echo "Consider restarting: bash scripts/oracle/start_stable_keeper.sh"
    exit 1
fi