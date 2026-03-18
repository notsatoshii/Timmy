#!/bin/bash
# Multi-wallet position seeder — uses 20 wallets to bypass per-user OI caps
source /home/lever/lever-protocol/control-plane/deploy-env.sh

LOG="/home/lever/lever-protocol/control-plane/dispatcher-logs/seeder.log"
WALLETS_FILE="/home/lever/lever-protocol/scripts/seeder-wallets.json"

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

COLLATERALS=(10000000000 25000000000 50000000000 75000000000)
LEVERAGES=(3000000000000000000 4000000000000000000 5000000000000000000)

TARGET_UTIL=45
TVL=60500000

log() {
  local msg="[$(date +%H:%M:%S)] $1"
  echo "$msg"
  echo "$msg" >> "$LOG"
}

# Load wallet keys into array
mapfile -t KEYS < <(python3 -c "import json; data=json.load(open('$WALLETS_FILE')); [print(k) for k in data['wallets']]")
NUM_WALLETS=${#KEYS[@]}
log "Loaded $NUM_WALLETS seeder wallets"

get_current_oi() {
  local oi_raw
  oi_raw=$(cast call 0x5B9820B789785f62349bAE7e2B8a17a8e4A3E7cd "getGlobalOI()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
  if [ -n "$oi_raw" ] && [ "$oi_raw" != "0" ]; then
    echo $((oi_raw / 1000000))
  else
    echo 0
  fi
}

open_position() {
  local key="0x$1"
  local market="$2"
  local is_long="$3"
  local collateral="$4"
  local leverage="$5"

  local coll_usd=$((collateral / 1000000))
  local lev_x=$((leverage / 1000000000000000000))
  local notional=$((coll_usd * lev_x))
  local addr=$(cast wallet address --private-key "$key" 2>/dev/null)

  log "OPEN: ${addr:0:10}... ${is_long^^} \$${coll_usd} @ ${lev_x}x = \$${notional} notional"

  local result
  result=$(cast send 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D     "openPosition((bytes32,bool,uint256,uint256))"     "($market,$is_long,$collateral,$leverage)"     --private-key "$key" --rpc-url "$RPC_URL" 2>&1)

  if echo "$result" | grep -q "status.*1"; then
    log "  ✅ Opened (\$${notional} notional)"
    return 0
  else
    local err=$(echo "$result" | grep -oP 'error.*|Error.*|revert.*' | head -1)
    log "  ❌ Failed: ${err:0:100}"
    return 1
  fi
}

main() {
  log "=========================================="
  log "Multi-Wallet Seeder (${NUM_WALLETS} wallets)"
  log "TARGET: ${TARGET_UTIL}% utilization"
  log "=========================================="

  local cycle=0
  local wallet_idx=0

  while true; do
    cycle=$((cycle + 1))

    local current_oi=$(get_current_oi)
    local target_oi=$((TVL * TARGET_UTIL / 100))
    local current_util=0
    [ "$TVL" -gt 0 ] && current_util=$((current_oi * 100 / TVL))

    log ""
    log "--- Cycle $cycle | OI: \$${current_oi} | Target: \$${target_oi} | Util: ${current_util}% / ${TARGET_UTIL}% ---"

    if [ "$current_oi" -ge "$target_oi" ]; then
      log "TARGET REACHED! Maintenance mode."
      sleep $((120 + RANDOM % 180))
      continue
    fi

    # Rotate through wallets
    local key="${KEYS[$wallet_idx]}"
    wallet_idx=$(( (wallet_idx + 1) % NUM_WALLETS ))

    # Random market, collateral, leverage, direction
    local market="${MARKETS[$((RANDOM % ${#MARKETS[@]}))]}"
    local collateral="${COLLATERALS[$((RANDOM % ${#COLLATERALS[@]}))]}"
    local leverage="${LEVERAGES[$((RANDOM % ${#LEVERAGES[@]}))]}"
    local is_long="true"
    [ $((RANDOM % 2)) -eq 0 ] && is_long="false"

    open_position "$key" "$market" "$is_long" "$collateral" "$leverage"

    local wait=$((8 + RANDOM % 15))
    log "Next in ${wait}s (wallet ${wallet_idx}/${NUM_WALLETS})..."
    sleep "$wait"
  done
}

main "$@"
