#!/bin/bash
# 48-Hour Monitoring Orchestrator

set -euo pipefail

ORACLE_DIR="/home/lever/lever-protocol/scripts/oracle"
cd "$ORACLE_DIR"

echo "[$(date)] Starting 48-hour testnet monitoring..."

# Check if services are already running
check_service() {
    pgrep -f "$1" > /dev/null
}

# Start oracle keeper if not running
if ! check_service "keeper.py"; then
    echo "[$(date)] Starting oracle keeper..."
    nohup python3 keeper.py --dry-run=false > keeper.log 2>&1 &
    echo "Oracle keeper started (PID: $!)"
else
    echo "[$(date)] Oracle keeper already running"
fi

# Start feed monitor if not running
if ! check_service "feed_monitor.py"; then
    echo "[$(date)] Starting feed monitor..."
    nohup python3 feed_monitor.py > monitor.log 2>&1 &
    echo "Feed monitor started (PID: $!)"
else
    echo "[$(date)] Feed monitor already running"
fi

# Start market discovery daemon
if ! check_service "market_discovery.py"; then
    echo "[$(date)] Starting market discovery daemon..."
    nohup python3 market_discovery.py --daemon > discovery.log 2>&1 &
    echo "Market discovery started (PID: $!)"
else
    echo "[$(date)] Market discovery already running"
fi

# Health check
sleep 5
echo "[$(date)] Health check:"
ps aux | grep -E "(keeper|monitor|discovery)" | grep python3 | grep -v grep | awk '{print "  PID "$2": "$0}'

# Monitor dashboard status
if curl -s http://localhost:8081 > /dev/null; then
    echo "  Dashboard: ONLINE at http://localhost:8081"
else
    echo "  Dashboard: OFFLINE"
fi

echo "[$(date)] 48-hour monitoring initiated successfully"
echo "Monitor status: tail -f *.log"
echo "Dashboard: http://localhost:8081"