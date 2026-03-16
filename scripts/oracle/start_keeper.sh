#!/bin/bash
# Oracle Keeper Startup Script

cd "$(dirname "$0")"

# Environment variables
export RPC_URL="https://sepolia.base.org"
export KEEPER_KEY="$(cat ../../.env.deployer)"
export ORACLE_ADAPTER="0x13e01E7E58196cff03068FDf0bB29382ec60b676"
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