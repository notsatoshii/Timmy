#!/bin/bash
# Oracle Continuous Watchdog - Ensures oracle stability during investor demo
# Runs every 60 seconds and maintains comprehensive monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/home/lever/lever-protocol/control-plane/oracle-watchdog.log"
ALERT_FILE="/home/lever/lever-protocol/control-plane/oracle-alerts.log"
PIDFILE="/tmp/oracle-watchdog.pid"

# Alert thresholds
PRICE_STALE_WARNING=60   # Warn if prices older than 1 minute
PRICE_STALE_CRITICAL=180 # Critical if older than 3 minutes
ERROR_RATE_WARNING=30    # Warn if error rate > 30%
ERROR_RATE_CRITICAL=70   # Critical if error rate > 70%

# Source environment
source /home/lever/lever-protocol/control-plane/deploy-env.sh 2>/dev/null || true

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"

    # Also log alerts to separate file
    if [[ "$level" == "ALERT" || "$level" == "CRITICAL" ]]; then
        echo "[$timestamp] $message" >> "$ALERT_FILE"
    fi
}

check_single_instance() {
    if [[ -f "$PIDFILE" ]]; then
        local old_pid=$(cat "$PIDFILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "INFO" "Watchdog already running (PID: $old_pid), exiting"
            exit 0
        else
            log "INFO" "Removing stale PID file"
            rm -f "$PIDFILE"
        fi
    fi
    echo $$ > "$PIDFILE"
}

cleanup() {
    rm -f "$PIDFILE"
}
trap cleanup EXIT

check_oracle_process() {
    local process_count=$(pgrep -f "(mock_keeper.py|improved_keeper.py)" | wc -l)
    local status_code=0

    if (( process_count == 0 )); then
        log "CRITICAL" "No oracle keeper process running!"
        return 2
    elif (( process_count > 1 )); then
        log "ALERT" "Multiple oracle processes detected: $process_count"
        # Kill extra processes
        local pids=($(pgrep -f "(mock_keeper.py|improved_keeper.py)"))
        local main_pid=${pids[0]}
        log "INFO" "Keeping main process PID: $main_pid"
        for ((i=1; i<${#pids[@]}; i++)); do
            log "INFO" "Killing duplicate process: ${pids[i]}"
            kill "${pids[i]}" 2>/dev/null || true
        done
        return 1
    else
        log "INFO" "Oracle process healthy (PID: $(pgrep -f '(mock_keeper.py|improved_keeper.py)'))"
        return 0
    fi
}

check_price_freshness() {
    local prices_file="/home/lever/lever-protocol/frontend/user-app/public/prices.json"

    if [[ ! -f "$prices_file" ]]; then
        log "CRITICAL" "prices.json not found at $prices_file"
        return 2
    fi

    local last_update=$(jq -r '.lastUpdate // empty' "$prices_file" 2>/dev/null)

    if [[ -z "$last_update" || "$last_update" == "null" ]]; then
        log "CRITICAL" "Unable to read timestamp from prices.json"
        return 2
    fi

    local current_time=$(date +%s)
    local age=$((current_time - last_update))
    local price_count=$(jq -r '.prices | length' "$prices_file" 2>/dev/null || echo 0)

    if (( age > PRICE_STALE_CRITICAL )); then
        log "CRITICAL" "Prices critically stale: ${age}s old (${price_count} markets)"
        return 2
    elif (( age > PRICE_STALE_WARNING )); then
        log "ALERT" "Prices getting stale: ${age}s old (${price_count} markets)"
        return 1
    else
        log "INFO" "Prices fresh: ${age}s old (${price_count} markets)"
        return 0
    fi
}

check_error_rate() {
    # Check both oracle log files
    local oracle_logs=("/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
                      "/home/lever/lever-protocol/scripts/oracle/improved_keeper.log")

    local total_errors=0
    local total_ops=0

    for log_file in "${oracle_logs[@]}"; do
        if [[ -f "$log_file" ]]; then
            # Count recent operations (last 100 lines)
            local errors=$(tail -100 "$log_file" | grep -c "ERROR\|❌" || echo 0)
            local successes=$(tail -100 "$log_file" | grep -c "PUSHED:\|✅" || echo 0)

            total_errors=$((total_errors + errors))
            total_ops=$((total_ops + errors + successes))
        fi
    done

    if (( total_ops == 0 )); then
        log "ALERT" "No oracle activity detected in log files"
        return 1
    fi

    local error_rate=$(( (total_errors * 100) / total_ops ))

    if (( error_rate > ERROR_RATE_CRITICAL )); then
        log "CRITICAL" "High error rate: ${total_errors}/${total_ops} (${error_rate}%)"
        return 2
    elif (( error_rate > ERROR_RATE_WARNING )); then
        log "ALERT" "Elevated error rate: ${total_errors}/${total_ops} (${error_rate}%)"
        return 1
    else
        log "INFO" "Error rate acceptable: ${total_errors}/${total_ops} (${error_rate}%)"
        return 0
    fi
}

check_rpc_connectivity() {
    local rpc_url="${RPC_URL:-https://sepolia.base.org}"

    # Simple RPC health check
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        -H "Content-Type: application/json" \
        "$rpc_url" | grep -q "200"; then
        log "INFO" "RPC endpoint responsive"
        return 0
    else
        log "ALERT" "RPC endpoint not responding: $rpc_url"
        return 1
    fi
}

restart_oracle() {
    log "INFO" "Attempting oracle restart..."

    # Kill all oracle processes
    pkill -f "(mock_keeper.py|improved_keeper.py)" || true
    sleep 3

    # Start the improved keeper if available, fallback to original
    cd /home/lever/lever-protocol/scripts/oracle

    if [[ -f "improved_keeper.py" ]]; then
        log "INFO" "Starting improved oracle keeper..."
        export KEEPER_KEY="$PRIVATE_KEY"
        export DRY_RUN="false"
        nohup .venv/bin/python3 improved_keeper.py > improved_keeper.log 2>&1 &
        sleep 5

        if pgrep -f "improved_keeper.py" >/dev/null; then
            log "INFO" "Successfully started improved oracle keeper"
            return 0
        else
            log "ALERT" "Failed to start improved keeper, trying original..."
        fi
    fi

    # Fallback to original keeper
    if [[ -f "start_mock_keeper.sh" ]]; then
        ./start_mock_keeper.sh > /dev/null 2>&1 &
        sleep 5

        if pgrep -f "mock_keeper.py" >/dev/null; then
            log "INFO" "Successfully started original oracle keeper"
            return 0
        else
            log "CRITICAL" "Failed to start any oracle keeper"
            return 1
        fi
    else
        log "CRITICAL" "No oracle keeper scripts found"
        return 1
    fi
}

generate_status_report() {
    local status_file="/home/lever/lever-protocol/control-plane/oracle-status.json"

    # Gather current metrics
    local process_status="unknown"
    local price_age="unknown"
    local error_rate="unknown"
    local rpc_status="unknown"

    # Check process
    if pgrep -f "(mock_keeper.py|improved_keeper.py)" >/dev/null; then
        process_status="running"
    else
        process_status="stopped"
    fi

    # Check price age
    local prices_file="/home/lever/lever-protocol/frontend/user-app/public/prices.json"
    if [[ -f "$prices_file" ]]; then
        local last_update=$(jq -r '.lastUpdate // empty' "$prices_file" 2>/dev/null)
        if [[ -n "$last_update" && "$last_update" != "null" ]]; then
            local current_time=$(date +%s)
            price_age=$((current_time - last_update))
        fi
    fi

    # Create status JSON
    cat > "$status_file" << EOF
{
    "timestamp": $(date +%s),
    "process_status": "$process_status",
    "price_age_seconds": $price_age,
    "rpc_endpoint": "$RPC_URL",
    "last_check": "$(date '+%Y-%m-%d %H:%M:%S')",
    "watchdog_status": "active"
}
EOF
}

main_check() {
    log "INFO" "=== Oracle Watchdog Check ==="

    local overall_status=0
    local restart_needed=false

    # Run all checks
    local process_status=0
    check_oracle_process || process_status=$?

    local price_status=0
    check_price_freshness || price_status=$?

    local error_status=0
    check_error_rate || error_status=$?

    local rpc_status=0
    check_rpc_connectivity || rpc_status=$?

    # Determine if restart is needed
    if (( process_status == 2 || price_status == 2 )); then
        restart_needed=true
        overall_status=2
    elif (( error_status == 2 )); then
        restart_needed=true
        overall_status=2
    elif (( process_status == 1 || price_status == 1 || error_status == 1 || rpc_status == 1 )); then
        overall_status=1
    fi

    # Perform restart if needed
    if [[ "$restart_needed" == "true" ]]; then
        log "ALERT" "Critical issues detected, restarting oracle..."
        if restart_oracle; then
            log "INFO" "Oracle restart successful"
            # Wait and re-check
            sleep 30
            if check_oracle_process && check_price_freshness; then
                log "INFO" "Post-restart verification passed"
                overall_status=0
            else
                log "CRITICAL" "Oracle still unhealthy after restart"
                overall_status=2
            fi
        else
            log "CRITICAL" "Oracle restart failed"
            overall_status=2
        fi
    fi

    # Generate status report
    generate_status_report

    case $overall_status in
        0) log "INFO" "Oracle watchdog: ALL SYSTEMS HEALTHY" ;;
        1) log "ALERT" "Oracle watchdog: WARNINGS DETECTED" ;;
        2) log "CRITICAL" "Oracle watchdog: CRITICAL ISSUES" ;;
    esac

    return $overall_status
}

# Script modes
case "${1:-daemon}" in
    "daemon")
        check_single_instance
        log "INFO" "Oracle watchdog daemon starting..."

        while true; do
            main_check || true  # Don't exit on check failures
            sleep 60
        done
        ;;
    "check")
        main_check
        ;;
    "restart")
        restart_oracle
        ;;
    "status")
        if [[ -f "/home/lever/lever-protocol/control-plane/oracle-status.json" ]]; then
            jq . /home/lever/lever-protocol/control-plane/oracle-status.json
        else
            echo "No status file found"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [daemon|check|restart|status]"
        echo "  daemon  - Run continuous monitoring (default)"
        echo "  check   - Run single health check"
        echo "  restart - Force restart oracle"
        echo "  status  - Show current status"
        exit 1
        ;;
esac