#!/bin/bash
# Rotate oracle logs to prevent disk space issues

LOG_FILE="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
MONITOR_LOG="/home/lever/lever-protocol/control-plane/oracle-monitor.log"
MAX_SIZE=10485760  # 10MB

# Rotate mock keeper log
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_SIZE ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# Rotate monitor log
if [ -f "$MONITOR_LOG" ] && [ $(stat -f%z "$MONITOR_LOG" 2>/dev/null || stat -c%s "$MONITOR_LOG" 2>/dev/null || echo 0) -gt $MAX_SIZE ]; then
    tail -n 1000 "$MONITOR_LOG" > "${MONITOR_LOG}.tmp"
    mv "${MONITOR_LOG}.tmp" "$MONITOR_LOG"
fi
