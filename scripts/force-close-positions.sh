#!/bin/bash
# Force-close orphaned positions
source /home/lever/lever-protocol/control-plane/deploy-env.sh

DEPLOYER_ADDR=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null)
MAX_ID=$(cast call $POSITION_MANAGER "nextPositionId()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
GAS_PRICE=$(cast gas-price --rpc-url $RPC_URL 2>/dev/null)
DOUBLE_GAS=$((GAS_PRICE * 2))

CLOSED=0
FAILED=0

echo "=== Force-closing orphaned positions ==="
echo "Scanning $((MAX_ID - 1)) positions..."

for pid in $(seq 1 $((MAX_ID - 1))); do
    RAW=$(cast call $POSITION_MANAGER "getPosition(uint256)" $pid --rpc-url $RPC_URL 2>/dev/null)
    [ -z "$RAW" ] && continue

    DECODED=$(cast abi-decode "f()(uint256,address,bytes32,bool,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool)" "$RAW" 2>/dev/null)
    [ -z "$DECODED" ] && continue

    IS_OPEN=$(echo "$DECODED" | sed -n '13p')
    [ "$IS_OPEN" != "true" ] && continue

    OWNER=$(echo "$DECODED" | sed -n '2p')
    MARKET_ID=$(echo "$DECODED" | sed -n '3p')
    IS_LONG=$(echo "$DECODED" | sed -n '4p')
    POS_SIZE_RAW=$(echo "$DECODED" | sed -n '8p' | sed 's/ \[.*\]//')

    echo -n "PID $pid (${OWNER:0:8}... $IS_LONG $POS_SIZE_RAW): "

    # Step 1: decreaseOI
    OI_OUT=$(cast send $OI_LIMITS "decreaseOI(bytes32,address,bool,uint256)" \
        "$MARKET_ID" "$OWNER" "$IS_LONG" "$POS_SIZE_RAW" \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL \
        --gas-limit 200000 --gas-price $DOUBLE_GAS 2>&1)

    # Step 2: closePosition (try regardless of OI result)
    PM_OUT=$(cast send $POSITION_MANAGER "closePosition(uint256)" "$pid" \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL \
        --gas-limit 300000 --gas-price $DOUBLE_GAS 2>&1)

    if echo "$PM_OUT" | grep -q "status.*1"; then
        echo "CLOSED"
        CLOSED=$((CLOSED + 1))
    else
        echo "FAIL"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== DONE ==="
echo "Closed: $CLOSED | Failed: $FAILED"
echo "Open: $(cast call $POSITION_MANAGER 'totalOpenPositions()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
echo "OI: $(cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
