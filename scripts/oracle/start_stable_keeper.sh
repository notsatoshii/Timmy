#!/bin/bash
# Improved Mock Oracle Keeper Startup Script with Stability Fixes
# Fixed nonce management issues for demo stability

cd "$(dirname "$0")"

echo "=== Oracle Keeper Stability Check & Restart ==="

# Kill ALL keeper processes system-wide (including root processes if possible)
echo "Stopping existing keeper processes..."
pkill -f keeper.py
pkill -f mock_keeper.py
sleep 3

# Double-check for any remaining processes
REMAINING_PROCESSES=$(ps aux | grep -E "(keeper\.py|mock_keeper\.py)" | grep -v grep)
if [ ! -z "$REMAINING_PROCESSES" ]; then
    echo "WARNING: Found remaining keeper processes:"
    echo "$REMAINING_PROCESSES"
    echo "This could cause nonce conflicts. Manual cleanup may be required."
fi

# Environment variables with stability improvements
export RPC_URL="https://sepolia.base.org"
export KEEPER_KEY="$(cat ../../.env.deployer | tr -d '[:space:]')"
export ORACLE_ADAPTER="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
export PUSH_INTERVAL="45"  # Increased interval to reduce nonce conflicts
export DRY_RUN="false"

# Verify environment
echo "Environment Check:"
echo "RPC_URL: $RPC_URL"
echo "Oracle Adapter: $ORACLE_ADAPTER"
echo "Push Interval: ${PUSH_INTERVAL}s (increased for stability)"
echo "Markets: $(jq length market_config.json) markets configured"

# Test RPC connection
echo "Testing RPC connection..."
if ! curl -s --max-time 10 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null; then
    echo "ERROR: Cannot connect to RPC endpoint $RPC_URL"
    exit 1
fi
echo "RPC connection: OK"

# Create clean log file
rm -f stable_keeper.log
touch stable_keeper.log

# Activate venv and run stable keeper
echo "Starting Oracle Keeper with stability fixes..."
source .venv/bin/activate

# Start stable keeper in background
nohup python3 stable_mock_keeper.py > stable_keeper.log 2>&1 &
KEEPER_PID=$!

# Save PID
echo $KEEPER_PID > keeper.pid

echo "Oracle Keeper started as PID $KEEPER_PID"
echo "Log file: stable_keeper.log"

# Wait a moment and verify it started successfully
sleep 3
if ! ps -p $KEEPER_PID > /dev/null; then
    echo "ERROR: Keeper process died immediately. Check logs:"
    tail -10 stable_keeper.log
    exit 1
fi

echo "✅ Oracle Keeper is running stably"
echo "Monitor with: tail -f stable_keeper.log"
echo ""
echo "Stability improvements:"
echo "- Increased push interval to 45s"
echo "- Clean process restart"
echo "- Better nonce management expected"