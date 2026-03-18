#!/bin/bash
# Oracle Keeper Monitoring Script
# Ensures oracle keeper stays healthy during demo
# Usage: Run this periodically to monitor and restart if needed

echo "=== ORACLE KEEPER MONITOR - $(date) ==="

# Check if keeper process is running
KEEPER_PID=$(pgrep -f mock_keeper.py)
if [ -z "$KEEPER_PID" ]; then
    echo "❌ ALERT: Oracle keeper process not running!"
    echo "Attempting to restart..."

    cd /home/lever/lever-protocol/scripts/oracle
    nohup bash start_mock_keeper.sh > /dev/null 2>&1 &
    sleep 5

    NEW_PID=$(pgrep -f mock_keeper.py)
    if [ -n "$NEW_PID" ]; then
        echo "✅ Oracle keeper restarted successfully (PID: $NEW_PID)"
    else
        echo "❌ FAILED to restart oracle keeper!"
        exit 1
    fi
else
    echo "✅ Oracle keeper running (PID: $KEEPER_PID)"
fi

# Check for price staleness
ORACLE_LOG="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
if [ -f "$ORACLE_LOG" ]; then
    LAST_PUSH=$(grep "PUSHED:" "$ORACLE_LOG" | tail -n1 | cut -d'|' -f1 | tr -d ' ')
    if [ -n "$LAST_PUSH" ]; then
        echo "✅ Recent price updates detected"
        echo "   Last push: $LAST_PUSH"

        # Check for excessive errors in recent logs
        RECENT_ERRORS=$(tail -n20 "$ORACLE_LOG" | grep "ERROR" | wc -l)
        if [ "$RECENT_ERRORS" -gt 10 ]; then
            echo "⚠️  WARNING: High error rate detected ($RECENT_ERRORS errors in last 20 lines)"
            echo "   Recent errors:"
            tail -n20 "$ORACLE_LOG" | grep "ERROR" | tail -n3
        else
            echo "✅ Error rate acceptable ($RECENT_ERRORS errors in last 20 lines)"
        fi
    else
        echo "❌ No recent price pushes found in log!"
    fi
else
    echo "❌ Oracle log file not found!"
fi

# Quick health check
HEALTH_RESULT=$(bash /home/lever/lever-protocol/control-plane/health-check.sh 2>/dev/null | grep oracle_price_freshness)
if echo "$HEALTH_RESULT" | grep -q "PASS"; then
    echo "✅ Health check: Oracle prices are fresh"
else
    echo "❌ Health check: Oracle prices may be stale"
    echo "   $HEALTH_RESULT"
fi

# Check for duplicate processes
KEEPER_COUNT=$(pgrep -f mock_keeper.py | wc -l)
if [ "$KEEPER_COUNT" -gt 1 ]; then
    echo "⚠️  WARNING: Multiple keeper processes detected ($KEEPER_COUNT)"
    echo "   PIDs: $(pgrep -f mock_keeper.py | tr '\n' ' ')"
    echo "   This may cause nonce conflicts!"
fi

echo "=== MONITOR COMPLETE ==="