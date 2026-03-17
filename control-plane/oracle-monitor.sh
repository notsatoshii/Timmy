#!/bin/bash
# Oracle Keeper Monitor - Auto-restart if service fails or prices become stale
set -e

source /home/lever/lever-protocol/control-plane/deploy-env.sh

LOG_FILE="/home/lever/lever-protocol/control-plane/oracle-monitor.log"
MARKET_ID="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"
CAST="/home/lever/.foundry/bin/cast"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ORACLE-MONITOR] $1" | tee -a "$LOG_FILE"
}

check_service() {
    if pgrep -f mock_keeper.py > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_price_freshness() {
    local log_file="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
    if [ ! -f "$log_file" ]; then
        log "ERROR: Oracle log file not found"
        return 1
    fi

    local recent_pushes
    recent_pushes=$(grep "PUSHED:" "$log_file" | tail -n1 | grep -E "$(date '+%H:%M'|cut -c1-4)" || true)

    if [ -n "$recent_pushes" ]; then
        log "INFO: Oracle prices fresh (recent push detected)"
        return 0
    else
        local last_push=$(grep "PUSHED:" "$log_file" | tail -n1 | cut -d'|' -f1 | tr -d ' ' || echo "never")
        log "WARNING: Oracle prices stale (last push: $last_push)"
        return 1
    fi
}

restart_keeper() {
    log "INFO: Restarting oracle keeper process..."

    # Stop any running keeper processes
    pkill -f mock_keeper.py || true
    sleep 2

    # Start the keeper using existing script
    cd /home/lever/lever-protocol/scripts/oracle
    ./start_mock_keeper.sh > /dev/null 2>&1
    sleep 5

    if pgrep -f mock_keeper.py > /dev/null 2>&1; then
        log "SUCCESS: Oracle keeper restarted successfully"
        return 0
    else
        log "ERROR: Failed to restart oracle keeper"
        return 1
    fi
}

# Main monitoring logic
main() {
    log "INFO: Starting oracle keeper health check"

    # Check if service is running
    if ! check_service; then
        log "WARNING: Oracle keeper service not running"
        restart_keeper
        return
    fi

    # Check if prices are fresh
    if ! check_price_freshness; then
        log "WARNING: Oracle prices stale, restarting service"
        restart_keeper
        return
    fi

    log "INFO: Oracle keeper healthy"
}

# Run the monitor
main