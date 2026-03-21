#!/bin/bash
# Rebalance market allocation weights equally across all active markets.
# Run after adding/removing markets: ./scripts/rebalance-weights.sh
# Can also be called automatically from market creation scripts.

set -e
source /home/lever/lever-protocol/control-plane/deploy-env.sh

echo "=== Market Weight Rebalancer ==="

# Get all active markets
ACTIVE_MARKETS=$(cast call $MARKET_REGISTRY "getActiveMarkets()(bytes32[])" --rpc-url $RPC_URL 2>/dev/null)

# Parse the array — cast returns a formatted list
NUM_MARKETS=$(echo "$ACTIVE_MARKETS" | grep -c "0x" || echo 0)

if [ "$NUM_MARKETS" -eq 0 ]; then
    echo "No active markets found."
    exit 1
fi

echo "Active markets: $NUM_MARKETS"

# Equal weight = 1.0 / numMarkets in WAD
WEIGHT=$(python3 -c "print(int(1e18 / $NUM_MARKETS))")
WEIGHT_PCT=$(python3 -c "print(f'{int(\"$WEIGHT\")/1e18*100:.1f}%')")
echo "Target weight per market: $WEIGHT_PCT ($WEIGHT WAD)"
echo ""

# Extract market IDs from the cast output
MARKET_IDS=()
while IFS= read -r line; do
    MID=$(echo "$line" | grep -oP '0x[0-9a-fA-F]{64}' | head -1)
    if [ -n "$MID" ]; then
        MARKET_IDS+=("$MID")
    fi
done <<< "$ACTIVE_MARKETS"

if [ ${#MARKET_IDS[@]} -eq 0 ]; then
    # Fallback: try parsing differently
    echo "Parsing markets from registry..."
    for i in $(seq 0 $((NUM_MARKETS-1))); do
        MID=$(cast call $MARKET_REGISTRY "getMarketIdByIndex(uint256)(bytes32)" $i --rpc-url $RPC_URL 2>/dev/null | awk '{print $1}')
        if [ -n "$MID" ] && [ "$MID" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
            MARKET_IDS+=("$MID")
        fi
    done
fi

echo "Found ${#MARKET_IDS[@]} markets to rebalance"

# Stop keepers to avoid nonce conflicts
echo "Stopping keepers..."
systemctl stop lever-oracle 2>/dev/null
sleep 3

UPDATED=0
FAILED=0
for MID in "${MARKET_IDS[@]}"; do
    CURRENT=$(cast call $MARKET_REGISTRY "getAllocationWeight(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    if [ "$CURRENT" == "$WEIGHT" ]; then
        echo "  ${MID:0:10}...: already $WEIGHT_PCT, skip"
        UPDATED=$((UPDATED+1))
        continue
    fi

    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    RESULT=$(cast send $MARKET_REGISTRY "updateAllocationWeight(bytes32,uint256)" $MID $WEIGHT \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000 --json 2>&1)
    STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','0x0'))" 2>/dev/null)

    if [ "$STATUS" == "0x1" ]; then
        echo "  ${MID:0:10}...: → $WEIGHT_PCT ✓"
        UPDATED=$((UPDATED+1))
    else
        echo "  ${MID:0:10}...: FAILED"
        FAILED=$((FAILED+1))
    fi
    sleep 5
done

# Restart keepers
echo ""
echo "Restarting keepers..."
systemctl start lever-oracle 2>/dev/null

echo ""
echo "=== DONE ==="
echo "Updated: $UPDATED / Failed: $FAILED / Total: ${#MARKET_IDS[@]}"
echo "Each market now has $WEIGHT_PCT of the global OI cap"
