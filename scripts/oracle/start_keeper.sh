#!/bin/bash
# Oracle Keeper Startup Script

cd "$(dirname "$0")"

# Environment variables
export RPC_URL="https://sepolia.base.org"
export KEEPER_KEY="$(cat ../../.env.deployer)"
export ORACLE_ADAPTER="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
export MARKET_CONFIG="market_config.json"
export PUSH_INTERVAL="30"
export DRY_RUN="false"

echo "Starting Oracle Keeper..."
echo "RPC_URL: $RPC_URL"
echo "Oracle Adapter: $ORACLE_ADAPTER"
echo "Markets: $(jq length market_config.json) markets configured"

# Activate venv and run keeper
source .venv/bin/activate
python keeper.py