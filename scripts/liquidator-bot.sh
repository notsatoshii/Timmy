#!/bin/bash
# Liquidator bot — scans all markets for liquidatable positions and executes them.
# Uses a DEDICATED wallet to avoid nonce contention with oracle keeper.
# Re-sources deploy-env.sh each cycle for contract address updates.

DEPLOY_ENV=/home/lever/lever-protocol/control-plane/deploy-env.sh

# Dedicated liquidator wallet — separate from deployer to avoid nonce races
LIQ_KEY=23d48ac0ec79d91097f03f8edc4f108844ec2fd6d10866c241dfb8f0160f0f10

MARKETS=(
  0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1
  0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a
  0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d
  0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2
  0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7
  0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2
  0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554
  0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc
  0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f
  0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea
)

echo "[$(date)] Liquidator bot started"
LIQ_ADDR=$(cast wallet address --private-key $LIQ_KEY)
echo "[$(date)] Using dedicated wallet: $LIQ_ADDR"

while true; do
  source "$DEPLOY_ENV"

  LIQUIDATED=0
  for MKT in "${MARKETS[@]}"; do
    POSITIONS=$(cast call $POSITION_MANAGER "getMarketPositions(bytes32)(uint256[])" $MKT --rpc-url $RPC_URL 2>/dev/null)
    if [ -z "$POSITIONS" ] || [ "$POSITIONS" = "[]" ]; then continue; fi

    CLEAN=$(echo "$POSITIONS" | tr -d '[]' | tr ',' '\n' | tr -d ' ')
    for PID in $CLEAN; do
      [ -z "$PID" ] && continue
      LIQ=$(cast call $MARGIN_ENGINE "isLiquidatable(uint256)(bool)" $PID --rpc-url $RPC_URL 2>/dev/null)
      if [ "$LIQ" = "true" ]; then
        echo "[$(date)] Position $PID is liquidatable — executing"
        RESULT=$(cast send $LIQUIDATION_ENGINE "liquidate(uint256)" $PID \
          --private-key $LIQ_KEY --rpc-url $RPC_URL 2>&1)
        if echo "$RESULT" | grep -q "status.*1"; then
          echo "[$(date)] Liquidated position $PID successfully"
          LIQUIDATED=$((LIQUIDATED + 1))
        else
          echo "[$(date)] Failed to liquidate $PID: $(echo "$RESULT" | grep -E 'Error|error' | head -1)"
        fi
      fi
    done
  done

  if [ $LIQUIDATED -gt 0 ]; then
    echo "[$(date)] Liquidated $LIQUIDATED positions this cycle"
  fi
  sleep 30
done
