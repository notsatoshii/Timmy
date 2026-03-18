#!/bin/bash
# Demo Monitoring Script for Oracle Keeper
# Run this during the investor demo to monitor oracle health

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/stable_keeper.log"

echo "=== LEVER ORACLE KEEPER - DEMO MONITOR ==="
echo "Started at: $(date)"
echo ""

# Function to check keeper health
check_keeper_health() {
    local timestamp=$(date '+%H:%M:%S')

    # Check if process is running
    if pgrep -f "stable_mock_keeper.py" > /dev/null; then
        echo "[$timestamp] ✅ Keeper process: RUNNING"
    else
        echo "[$timestamp] ❌ Keeper process: STOPPED"
        return 1
    fi

    # Check price freshness
    local prices_file="/home/lever/lever-protocol/frontend/user-app/public/prices.json"
    if [ -f "$prices_file" ]; then
        local last_update=$(jq -r '.lastUpdate' "$prices_file" 2>/dev/null)
        local current_time=$(date +%s)
        local age=$((current_time - last_update))

        if [ $age -lt 120 ]; then  # Less than 2 minutes
            echo "[$timestamp] ✅ Price freshness: ${age}s ago"
        else
            echo "[$timestamp] ⚠️  Price freshness: ${age}s ago (stale)"
        fi
    else
        echo "[$timestamp] ❌ Price file: NOT FOUND"
        return 1
    fi

    # Check for recent errors in log
    if [ -f "$LOG_FILE" ]; then
        local recent_errors=$(tail -20 "$LOG_FILE" | grep -c "ERROR")
        local recent_failures=$(tail -20 "$LOG_FILE" | grep -c "FAILED")

        if [ $recent_errors -eq 0 ] && [ $recent_failures -eq 0 ]; then
            echo "[$timestamp] ✅ Recent errors: NONE"
        else
            echo "[$timestamp] ⚠️  Recent errors: ${recent_errors} errors, ${recent_failures} failures"
        fi
    fi

    echo ""
    return 0
}

# Function to show keeper statistics
show_keeper_stats() {
    local timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] === KEEPER STATISTICS ==="

    if [ -f "$LOG_FILE" ]; then
        # Get success rate from recent cycles
        local recent_cycles=$(tail -100 "$LOG_FILE" | grep "Cycle complete:" | wc -l)
        local total_successful=$(tail -100 "$LOG_FILE" | grep -o "successful (100.0%)" | wc -l)

        if [ $recent_cycles -gt 0 ]; then
            local success_rate=$((total_successful * 100 / recent_cycles))
            echo "Recent cycles: $recent_cycles"
            echo "Success rate: ${success_rate}% (last 100 entries)"
        else
            echo "No recent cycle data available"
        fi

        # Show last successful update
        local last_success=$(tail -20 "$LOG_FILE" | grep "SUCCESS" | tail -1)
        if [ ! -z "$last_success" ]; then
            echo "Last success: $last_success"
        fi
    fi
    echo ""
}

# Main monitoring loop
if [ "$1" = "--continuous" ]; then
    echo "Starting continuous monitoring (Ctrl+C to stop)..."
    echo ""

    while true; do
        check_keeper_health
        sleep 30
    done
elif [ "$1" = "--stats" ]; then
    show_keeper_stats
else
    # Single check mode
    check_keeper_health

    if [ $? -eq 0 ]; then
        echo "🎉 Oracle keeper is healthy and ready for demo!"
        echo ""
        echo "Commands:"
        echo "  ./demo_monitor.sh --continuous  # Monitor during demo"
        echo "  ./demo_monitor.sh --stats       # Show detailed stats"
        echo "  tail -f stable_keeper.log       # View live log"
        exit 0
    else
        echo "🚨 Oracle keeper issues detected!"
        echo "Run: ./start_stable_keeper.sh to restart"
        exit 1
    fi
fi