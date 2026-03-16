#!/bin/bash
# Mock Oracle Keeper Startup Script
# Temporary solution while Polymarket API integration is being fixed

cd "$(dirname "$0")"

# Stop any running keeper processes
pkill -f keeper.py
pkill -f mock_keeper.py

# Environment variables
export RPC_URL="https://sepolia.base.org"
export KEEPER_KEY="$(cat ../../.env.deployer | tr -d '[:space:]')"
export ORACLE_ADAPTER="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
export PUSH_INTERVAL="30"
export DRY_RUN="false"

echo "Starting Mock Oracle Keeper..."
echo "RPC_URL: $RPC_URL"
echo "Oracle Adapter: $ORACLE_ADAPTER"
echo "Markets: $(jq length market_config.json) markets configured"
echo "NOTE: Using simulated prices due to Polymarket API issues"

# Activate venv and run mock keeper
source .venv/bin/activate
nohup python3 mock_keeper.py > mock_keeper.log 2>&1 &

echo "Mock keeper started as PID $!"
echo "Monitor with: tail -f mock_keeper.log"