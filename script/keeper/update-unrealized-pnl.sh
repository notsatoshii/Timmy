#!/bin/bash
# LEVER-BUG-9: Keeper script to refresh vault's net unrealized PnL.
# Calls ExecutionEngine.refreshUnrealizedPnL() which reads aggregate PnL
# from MarginEngine and writes it to LeverVault.
#
# Run every 5-10 minutes via cron or systemd timer.
# Costs ~50K gas on Base L2 (one storage write + event).
#
# Prerequisites:
# - KEEPER_KEY must have KEEPER_ROLE on ExecutionEngine
# - source deploy-env.sh for contract addresses

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../deploy-env.sh" 2>/dev/null || {
    echo "ERROR: deploy-env.sh not found. Set EXECUTION_ENGINE and RPC_URL manually."
    exit 1
}

# Sanity check
if [ -z "${EXECUTION_ENGINE:-}" ] || [ -z "${RPC_URL:-}" ] || [ -z "${KEEPER_KEY:-}" ]; then
    echo "ERROR: EXECUTION_ENGINE, RPC_URL, and KEEPER_KEY must be set"
    exit 1
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Refreshing unrealized PnL..."

cast send "$EXECUTION_ENGINE" "refreshUnrealizedPnL()" \
    --rpc-url "$RPC_URL" \
    --private-key "$KEEPER_KEY" \
    --gas-limit 500000 2>&1

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Done."
