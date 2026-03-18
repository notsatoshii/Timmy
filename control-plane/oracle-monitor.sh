#!/bin/bash
# Oracle Price Staleness Monitor & Auto-Restart
# Enhanced monitoring for investor demo period
set -e

source /home/lever/lever-protocol/control-plane/deploy-env.sh

LOG_FILE="/home/lever/lever-protocol/control-plane/oracle-monitor.log"
PRICES_FILE="/home/lever/lever-protocol/frontend/user-app/public/prices.json"
ALERT_THRESHOLD=45   # Alert if prices are older than 45 seconds
STALE_THRESHOLD=120  # Critical alert if older than 2 minutes
CAST="/home/lever/.foundry/bin/cast"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ORACLE-MONITOR] $1" | tee -a "$LOG_FILE"
}

check_service() {
    if pgrep -f mock_keeper.py > /dev/null 2>&1; then
        local process_count=$(pgrep -f mock_keeper.py | wc -l)
        if (( process_count > 1 )); then
            log "WARNING: Multiple oracle keeper processes running (${process_count})"
            return 1
        else
            log "INFO: Oracle keeper service running (PID: $(pgrep -f mock_keeper.py))"
            return 0
        fi
    else
        log "CRITICAL: Oracle keeper service not running"
        return 2
    fi
}

check_transaction_errors() {
    local oracle_log="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
    if [[ ! -f "$oracle_log" ]]; then
        log "WARNING: Oracle log file not found"
        return 1
    fi

    # Count errors in last 50 lines (representing recent activity)
    local recent_errors=$(tail -50 "$oracle_log" | grep -c "ERROR" || echo 0)
    local success_count=$(tail -50 "$oracle_log" | grep -c "PUSHED:" || echo 0)
    local total_recent=$(tail -50 "$oracle_log" | grep -c "PUSHED:\|ERROR" || echo 1)

    local error_rate=$(( (recent_errors * 100) / total_recent ))

    if (( error_rate > 70 )); then
        log "CRITICAL: High error rate: ${recent_errors}/${total_recent} (${error_rate}%)"
        return 2
    elif (( error_rate > 40 )); then
        log "WARNING: Moderate error rate: ${recent_errors}/${total_recent} (${error_rate}%)"
        return 1
    else
        log "INFO: Low error rate: ${recent_errors}/${total_recent} (${error_rate}%)"
        return 0
    fi
}

check_price_freshness() {
    if [[ ! -f "$PRICES_FILE" ]]; then
        log "CRITICAL: prices.json file not found at $PRICES_FILE"
        return 2
    fi

    # Extract timestamp from JSON using jq
    local last_update=$(jq -r '.lastUpdate // empty' "$PRICES_FILE" 2>/dev/null)

    if [[ -z "$last_update" || "$last_update" == "null" ]]; then
        log "CRITICAL: Unable to read lastUpdate timestamp from prices.json"
        return 2
    fi

    local current_time=$(date +%s)
    local age=$((current_time - last_update))
    local price_count=$(jq -r '.prices | length' "$PRICES_FILE" 2>/dev/null || echo 0)

    if (( age > STALE_THRESHOLD )); then
        log "CRITICAL: Prices stale for ${age}s (threshold: ${STALE_THRESHOLD}s) - ${price_count} markets"
        return 2
    elif (( age > ALERT_THRESHOLD )); then
        log "WARNING: Prices aging for ${age}s (threshold: ${ALERT_THRESHOLD}s) - ${price_count} markets"
        return 1
    else
        log "INFO: Prices fresh (${age}s old) - ${price_count} markets active"
        return 0
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
    log "=== Oracle Health Check Start ==="

    local exit_code=0
    local restart_needed=false

    # Check service status
    local service_status=0
    check_service || service_status=$?

    # Check price freshness
    local price_status=0
    check_price_freshness || price_status=$?

    # Check transaction errors
    local error_status=0
    check_transaction_errors || error_status=$?

    # Determine overall health and actions
    if (( service_status == 2 )); then
        log "ACTION: Service not running - restart required"
        restart_needed=true
        exit_code=2
    elif (( price_status == 2 )); then
        log "ACTION: Prices critically stale - restart required"
        restart_needed=true
        exit_code=2
    elif (( error_status == 2 )); then
        log "ACTION: High error rate - restart required"
        restart_needed=true
        exit_code=2
    elif (( service_status == 1 || price_status == 1 || error_status == 1 )); then
        log "STATUS: Oracle has warnings but is functional"
        exit_code=1
    else
        log "STATUS: Oracle is healthy"
        exit_code=0
    fi

    # Perform restart if needed
    if [[ "$restart_needed" == "true" ]]; then
        restart_keeper
        # Re-check after restart
        sleep 10
        if check_service && check_price_freshness; then
            log "SUCCESS: Oracle restored to healthy state"
            exit_code=0
        else
            log "FAILURE: Oracle restart did not resolve issues"
            exit_code=2
        fi
    fi

    log "=== Oracle Health Check Complete (exit: $exit_code) ==="
    return $exit_code
}

# Allow running with specific modes
case "${1:-check}" in
    "check")
        main
        ;;
    "restart")
        log "Manual restart requested"
        restart_keeper
        ;;
    "status")
        check_service
        check_price_freshness
        check_transaction_errors
        ;;
    *)
        echo "Usage: $0 [check|restart|status]"
        exit 1
        ;;
esac