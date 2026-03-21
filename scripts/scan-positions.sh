#!/bin/bash
# Scan all positions, find open ones, check liquidatability, identify owners
source /home/lever/lever-protocol/control-plane/deploy-env.sh

DEMO_WALLET="0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da"
DEPLOYER="0x0e4D636c6D79c380A137f28EF73E054364cd5434"

MAX_ID=$(cast call $POSITION_MANAGER "nextPositionId()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
echo "Scanning positions 1 to $((MAX_ID - 1))..."
echo ""

OPEN_IDS=""
LIQUIDATABLE_IDS=""
DEMO_IDS=""
DEPLOYER_IDS=""
OTHER_IDS=""
OPEN_COUNT=0

for pid in $(seq 1 $((MAX_ID - 1))); do
    RAW=$(cast call $POSITION_MANAGER "getPosition(uint256)" $pid --rpc-url $RPC_URL 2>/dev/null)
    if [ -z "$RAW" ]; then continue; fi

    # Check if open: last 64-char word is 01 (true)
    LAST=$(echo "$RAW" | tr -d '\n' | tail -c 64)
    if [ "$LAST" == "0000000000000000000000000000000000000000000000000000000000000001" ]; then
        OPEN_COUNT=$((OPEN_COUNT + 1))
        # Extract owner: bytes 66-130 of the hex (second 32-byte word)
        # Remove 0x prefix, get chars for the owner field
        CLEAN=$(echo "$RAW" | tr -d '\n' | sed 's/^0x//')
        # Owner is at offset 32 bytes (64 hex chars), 20 bytes long (40 hex chars), right-padded in 32 bytes
        OWNER_RAW=$(echo "$CLEAN" | cut -c65-128)
        OWNER="0x$(echo "$OWNER_RAW" | tail -c 41 | head -c 40)"
        OWNER_LOWER=$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')
        DEMO_LOWER=$(echo "$DEMO_WALLET" | tr '[:upper:]' '[:lower:]')
        DEPLOYER_LOWER=$(echo "$DEPLOYER" | tr '[:upper:]' '[:lower:]')

        # Check liquidatability
        LIQ=$(cast call $MARGIN_ENGINE "isLiquidatable(uint256)(bool)" $pid --rpc-url $RPC_URL 2>/dev/null | head -1)

        if [ "$LIQ" == "true" ]; then
            echo "  PID $pid: OPEN | Owner: $OWNER | LIQUIDATABLE"
            LIQUIDATABLE_IDS="$LIQUIDATABLE_IDS $pid"
        elif [ "$OWNER_LOWER" == "$DEMO_LOWER" ]; then
            echo "  PID $pid: OPEN | Owner: DEMO | Not liquidatable"
            DEMO_IDS="$DEMO_IDS $pid"
        elif [ "$OWNER_LOWER" == "$DEPLOYER_LOWER" ]; then
            echo "  PID $pid: OPEN | Owner: DEPLOYER | Not liquidatable"
            DEPLOYER_IDS="$DEPLOYER_IDS $pid"
        else
            echo "  PID $pid: OPEN | Owner: $OWNER | Not liquidatable | NO KEY"
            OTHER_IDS="$OTHER_IDS $pid"
        fi
    fi
done

echo ""
echo "=== SCAN COMPLETE ==="
echo "Total open: $OPEN_COUNT"
echo "Liquidatable:$LIQUIDATABLE_IDS"
echo "Demo wallet:$DEMO_IDS"
echo "Deployer:$DEPLOYER_IDS"
echo "Other (no key):$OTHER_IDS"
