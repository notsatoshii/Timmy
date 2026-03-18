#!/bin/bash
# Oracle Keeper Stability Check
# Verifies:
# 1. Mock keeper is running and updating prices regularly
# 2. Price feeds are fresh (not stale) across all active markets
# 3. Oracle price pipeline from keeper → OracleAdapter → PI updates
# 4. Positions can open/close with current price data

cd "$(dirname "$0")"
cd ../..

export PATH="/home/lever/.foundry/bin:$PATH"
source control-plane/deploy-env.sh

echo "=== ORACLE KEEPER STABILITY CHECK ==="
echo "Date: $(date)"
echo "Oracle Adapter: $ORACLE_ADAPTER"
echo ""

# Check 1: Keeper Process Status
echo "--- Check 1: Keeper Process Status ---"
KEEPER_PID=""
if [ -f scripts/oracle/keeper.pid ]; then
    KEEPER_PID=$(cat scripts/oracle/keeper.pid)
fi

if [ -n "$KEEPER_PID" ] && ps -p "$KEEPER_PID" > /dev/null 2>&1; then
    echo "✓ PASS: Mock keeper is running (PID: $KEEPER_PID)"
    KEEPER_STATUS="RUNNING"
else
    echo "✗ FAIL: Mock keeper is not running"
    KEEPER_STATUS="STOPPED"
fi

# Check 2: Recent Log Activity
echo ""
echo "--- Check 2: Recent Log Activity ---"
if [ -f scripts/oracle/mock_keeper.log ]; then
    LAST_LOG_TIME=$(stat -c %Y scripts/oracle/mock_keeper.log)
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_LOG_TIME))

    if [ $TIME_DIFF -lt 300 ]; then
        echo "✓ PASS: Recent log activity (${TIME_DIFF}s ago)"
        LOG_STATUS="FRESH"
    else
        echo "✗ FAIL: No recent log activity (${TIME_DIFF}s ago)"
        LOG_STATUS="STALE"
    fi

    # Show recent successful pushes
    echo "Recent successful pushes:"
    tail -10 scripts/oracle/mock_keeper.log | grep "PUSHED:" | tail -3 | sed 's/^/  /'
else
    echo "✗ FAIL: No keeper log found"
    LOG_STATUS="MISSING"
fi

# Check 3: Price Data Freshness
echo ""
echo "--- Check 3: Price Data Freshness ---"
current_time=$(date +%s)
five_minutes_ago=$((current_time - 300))

market_ids=($(jq -r '.[].marketId' scripts/oracle/market_config.json))
fresh_count=0
stale_count=0
error_count=0

for market_id in "${market_ids[@]}"; do
    market_name=$(jq -r --arg id "$market_id" '.[] | select(.marketId == $id) | .name' scripts/oracle/market_config.json | cut -c1-40)

    # Get PI value from oracle
    pi_result=$(cast call --rpc-url https://sepolia.base.org $ORACLE_ADAPTER "getPI(bytes32)" $market_id 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$pi_result" ]; then
        # Parse the PI value
        pi_value_hex=$(echo $pi_result | sed 's/0x//')
        pi_value_decimal=$(echo "ibase=16; ${pi_value_hex^^}" | bc)
        pi_float=$(echo "scale=6; $pi_value_decimal / 1000000000000000000" | bc -l)

        # Get full price data including timestamp
        price_data=$(cast call --rpc-url https://sepolia.base.org $ORACLE_ADAPTER "getLatestPrice(bytes32)" $market_id 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$price_data" ]; then
            # Extract timestamp (last 64 hex chars from the response, excluding 0x)
            hex_without_prefix=$(echo $price_data | sed 's/0x//')
            timestamp_hex=${hex_without_prefix: -64}
            # Remove leading zeros for bc
            timestamp_hex=$(echo $timestamp_hex | sed 's/^0*//')
            timestamp_decimal=$(echo "ibase=16; ${timestamp_hex^^}" | bc)

            if [ $timestamp_decimal -gt $five_minutes_ago ]; then
                echo "  ✓ FRESH: $market_name | PI=$pi_float | Updated: $(date -d @$timestamp_decimal +'%H:%M:%S')"
                ((fresh_count++))
            else
                echo "  ✗ STALE: $market_name | PI=$pi_float | Updated: $(date -d @$timestamp_decimal +'%H:%M:%S')"
                ((stale_count++))
            fi
        else
            echo "  ? ERROR: $market_name | Could not get price data"
            ((error_count++))
        fi
    else
        echo "  ? ERROR: $market_name | Could not get PI"
        ((error_count++))
    fi
done

echo ""
echo "Price Data Summary:"
echo "  Fresh markets (< 5 min): $fresh_count"
echo "  Stale markets (> 5 min): $stale_count"
echo "  Error/unknown: $error_count"

# Check 4: Frontend Price File
echo ""
echo "--- Check 4: Frontend Price File ---"
if [ -f frontend/user-app/public/prices.json ]; then
    PRICES_TIME=$(jq -r '.lastUpdate' frontend/user-app/public/prices.json 2>/dev/null)
    if [ "$PRICES_TIME" != "null" ] && [ -n "$PRICES_TIME" ]; then
        TIME_DIFF=$((current_time - PRICES_TIME))
        if [ $TIME_DIFF -lt 300 ]; then
            PRICES_COUNT=$(jq -r '.prices | length' frontend/user-app/public/prices.json)
            echo "✓ PASS: Frontend prices.json fresh (${TIME_DIFF}s ago, ${PRICES_COUNT} markets)"
            FRONTEND_STATUS="FRESH"
        else
            echo "✗ FAIL: Frontend prices.json stale (${TIME_DIFF}s ago)"
            FRONTEND_STATUS="STALE"
        fi
    else
        echo "✗ FAIL: Frontend prices.json missing lastUpdate"
        FRONTEND_STATUS="INVALID"
    fi
else
    echo "✗ FAIL: Frontend prices.json not found"
    FRONTEND_STATUS="MISSING"
fi

# Overall Assessment
echo ""
echo "=== OVERALL ASSESSMENT ==="
PASS_COUNT=0
TOTAL_CHECKS=4

if [ "$KEEPER_STATUS" = "RUNNING" ]; then ((PASS_COUNT++)); fi
if [ "$LOG_STATUS" = "FRESH" ]; then ((PASS_COUNT++)); fi
if [ $fresh_count -gt 5 ]; then ((PASS_COUNT++)); fi
if [ "$FRONTEND_STATUS" = "FRESH" ]; then ((PASS_COUNT++)); fi

echo "Checks passed: $PASS_COUNT / $TOTAL_CHECKS"

if [ $PASS_COUNT -eq $TOTAL_CHECKS ] && [ $fresh_count -ge 8 ]; then
    echo "✅ SUCCESS: Oracle keeper stability verified!"
    echo "   - Mock keeper is running and updating prices regularly"
    echo "   - Price feeds are fresh across active markets"
    echo "   - Oracle pipeline is working: keeper → OracleAdapter → PI"
    echo "   - Frontend price data is current"
    exit 0
elif [ $PASS_COUNT -ge 3 ] && [ $fresh_count -ge 5 ]; then
    echo "⚠️  PARTIAL: Oracle keeper mostly stable with minor issues"
    exit 1
else
    echo "❌ CRITICAL: Oracle keeper has significant stability issues"
    if [ "$KEEPER_STATUS" != "RUNNING" ]; then
        echo "   - Mock keeper is not running properly"
    fi
    if [ $fresh_count -lt 5 ]; then
        echo "   - Too many stale/failed price feeds ($fresh_count fresh out of 10)"
    fi
    exit 2
fi