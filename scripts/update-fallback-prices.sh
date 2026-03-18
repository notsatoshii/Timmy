#!/bin/bash
# Auto-update frontend fallback prices from on-chain oracle
# Runs via cron to keep fallback values close to reality

source /home/lever/lever-protocol/control-plane/deploy-env.sh
ORACLE="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
HOOK_FILE="/home/lever/lever-protocol/frontend/user-app/src/hooks/useMarketProbabilities.ts"
LOG="/home/lever/lever-protocol/control-plane/dispatcher-logs/fallback-update.log"

MARKETS=(
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a"
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d"
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2"
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7"
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2"
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554"
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc"
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f"
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea"
)

echo "[$(date)] Starting fallback price update..." >> $LOG

PRICES=()
SUCCESS=0
for MKT in "${MARKETS[@]}"; do
  RAW=$(cast call $ORACLE "getPI(bytes32)(uint256)" $MKT --rpc-url $RPC_URL 2>/dev/null | head -1 | awk '{print $1}')
  if [ -n "$RAW" ] && [ "$RAW" != "0" ]; then
    PROB=$(python3 -c "print(round(int('$RAW') / 1e18, 4))")
    PRICES+=("$PROB")
    SUCCESS=$((SUCCESS + 1))
  else
    PRICES+=("")
  fi
done

echo "[$(date)] Read $SUCCESS/${#MARKETS[@]} prices from oracle" >> $LOG

# Only update if we got all 10
if [ $SUCCESS -lt 10 ]; then
  echo "[$(date)] Skipping update — only $SUCCESS/10 prices read" >> $LOG
  exit 0
fi

# Read current fallback values and replace in order
CURRENT=($(grep "initial_probability:" $HOOK_FILE | head -10 | grep -oP '[\d.]+'))

CHANGED=0
for i in "${!PRICES[@]}"; do
  if [ -n "${PRICES[$i]}" ] && [ -n "${CURRENT[$i]}" ]; then
    if [ "${PRICES[$i]}" != "${CURRENT[$i]}" ]; then
      sed -i "0,/initial_probability: ${CURRENT[$i]}/s/initial_probability: ${CURRENT[$i]}/initial_probability: ${PRICES[$i]}/" $HOOK_FILE
      CHANGED=$((CHANGED + 1))
    fi
  fi
done

if [ $CHANGED -gt 0 ]; then
  echo "[$(date)] Updated $CHANGED fallback prices. Rebuilding..." >> $LOG
  cd /home/lever/lever-protocol/frontend/user-app && npm run build >> $LOG 2>&1
  systemctl restart lever-frontend
  echo "[$(date)] Frontend rebuilt and restarted" >> $LOG
else
  echo "[$(date)] No price changes needed" >> $LOG
fi
