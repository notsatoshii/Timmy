#!/bin/bash
# ============================================
# LEVER Protocol — Position Seeder Bot v2
# TARGET: 20% utilization ($12.1M OI)
# ============================================

# set -e  # Removed: let script continue on individual failures

source /home/lever/lever-protocol/control-plane/deploy-env.sh

DEMO_KEY="bf4b6a6e7c99d538edf38d0ac535a44729bb8c9907de5bb9494d852eb4e812ec"
DEMO_ADDR="0xB072263740D7c60f1Aa0BF46e737F83544C7b785"
WALLET_KEY="$DEMO_KEY"
WALLET_ADDR="$DEMO_ADDR"

LOG_FILE="/home/lever/lever-protocol/control-plane/dispatcher-logs/seeder.log"

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

# Much larger collateral for faster OI buildup
# At 5x leverage: 200K*5=1M, 500K*5=2.5M, 1M*5=5M notional per position
COLLATERALS=(200000000000 500000000000 1000000000000 250000000000 750000000000)  # 200K, 500K, 1M, 250K, 750K USDT

LEVERAGES=(4000000000000000000 5000000000000000000 6000000000000000000 7000000000000000000)  # 4x, 5x, 6x, 7x

TARGET_UTIL=20  # percent
TVL=60500000    # $60.5M in whole dollars

log() {
  local msg="[$(date '+%H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

preflight() {
  log "=== PREFLIGHT CHECKS ==="

  local eth_balance
  eth_balance=$(cast balance "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
  log "ETH balance: $eth_balance wei"
  if [ -z "$eth_balance" ] || [ "$eth_balance" = "0" ]; then
    log "ERROR: No ETH for gas."
    return 1
  fi

  local usdt_balance
  usdt_balance=$(cast call "$USDT" "balanceOf(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
  log "USDT wallet balance: $usdt_balance"
  if [ -z "$usdt_balance" ] || [ "$usdt_balance" = "0" ]; then
    log "No USDT. Calling faucet..."
    cast send "$USDT" "faucet()" --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 5
  fi

  local allowance
  allowance=$(cast call "$USDT" "allowance(address,address)(uint256)" "$WALLET_ADDR" "$ACCOUNT_MANAGER" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
  if [ -z "$allowance" ] || [ "$allowance" = "0" ]; then
    log "Approving USDT for AccountManager (max)..."
    cast send "$USDT" "approve(address,uint256)" "$ACCOUNT_MANAGER" "115792089237316195423570985008687907853269984665640564039457584007913129639935" \
      --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 3
  fi

  local acct_balance
  acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
  log "AccountManager balance: $acct_balance"
  # Deposit 5M USDT for large positions
  if [ -z "$acct_balance" ] || [ "$acct_balance" -lt 2000000000000 ]; then
    log "Depositing 5,000,000 USDT to AccountManager..."
    cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "5000000000000" \
      --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 3
    acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
    log "AccountManager balance after deposit: $acct_balance"
  fi

  log "=== PREFLIGHT COMPLETE ==="
  return 0
}

get_current_oi() {
  local oi_raw
  oi_raw=$(cast call "$OI_LIMITS" "getGlobalOI()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}')
  # Strip any non-numeric characters
  oi_raw=$(echo "$oi_raw" | tr -dc '0-9')
  # Convert from raw (6 decimals) to whole dollars
  if [ -n "$oi_raw" ] && [ "$oi_raw" != "0" ]; then
    echo $((oi_raw / 1000000))
  else
    echo 0
  fi
}

open_position() {
  local market_id="$1"
  local is_long="$2"
  local collateral="$3"
  local leverage="$4"

  local coll_usd=$((collateral / 1000000))
  local lev_x=$((leverage / 1000000000000000000))
  local notional=$((coll_usd * lev_x))

  log "OPEN: ${is_long^^} collateral=\$${coll_usd} leverage=${lev_x}x notional=\$${notional}"

  local result
  result=$(cast send "$EXECUTION_ENGINE" \
    "openPosition((bytes32,bool,uint256,uint256))" \
    "($market_id,$is_long,$collateral,$leverage)" \
    --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>&1)

  if echo "$result" | grep -q "status.*1"; then
    log "  ✅ Position opened (notional \$${notional})"
    return 0
  else
    log "  ❌ Failed: $(echo "$result" | grep -i "error\|revert" | head -1)"
    return 1
  fi
}

close_position() {
  local position_id="$1"
  log "CLOSE: position #$position_id"
  local result
  result=$(cast send "$EXECUTION_ENGINE" \
    "closePosition(uint256)" "$position_id" \
    --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>&1)
  if echo "$result" | grep -q "status.*1"; then
    log "  ✅ Closed #$position_id"
    return 0
  else
    log "  ❌ Close failed"
    return 1
  fi
}

main() {
  log "=========================================="
  log "LEVER Position Seeder Bot v2"
  log "TARGET: ${TARGET_UTIL}% utilization"
  log "=========================================="

  if ! preflight; then
    log "Preflight failed."
    exit 1
  fi

  local cycle=0

  while true; do
    cycle=$((cycle + 1))

    # Check current utilization
    local current_oi
    current_oi=$(get_current_oi)
    local target_oi=$((TVL * TARGET_UTIL / 100))
    local current_util=0
    if [ "$TVL" -gt 0 ]; then
      current_util=$((current_oi * 100 / TVL))
    fi

    log ""
    log "--- Cycle $cycle | OI: \$${current_oi} | Target: \$${target_oi} | Util: ${current_util}% / ${TARGET_UTIL}% ---"

    # If we hit target, slow down to maintenance mode
    if [ "$current_oi" -ge "$target_oi" ]; then
      log "TARGET REACHED! Utilization at ${current_util}%. Entering maintenance mode."
      log "Opening small positions and closing old ones to maintain activity."

      # Maintenance: open small, close some, wait longer
      local market="${MARKETS[$((RANDOM % ${#MARKETS[@]}))]}"
      local is_long="true"
      [ $((RANDOM % 2)) -eq 0 ] && is_long="false"

      # Small maintenance position
      open_position "$market" "$is_long" "50000000000" "5000000000000000000"  # 50K at 5x = 250K

      # Close a recent one to show activity
      local next_id
      next_id=$(cast call "$POSITION_MANAGER" "nextPositionId()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null)
      if [ -n "$next_id" ] && [ "$next_id" -gt 80 ]; then
        local close_id=$((next_id - 2 - RANDOM % 3))
        close_position "$close_id" 2>/dev/null || true
      fi

      sleep $((120 + RANDOM % 180))
      continue
    fi

    # Aggressive mode: open large positions quickly
    local market="${MARKETS[$((RANDOM % ${#MARKETS[@]}))]}"
    local coll_idx=$((RANDOM % ${#COLLATERALS[@]}))
    local collateral="${COLLATERALS[$coll_idx]}"
    local lev_idx=$((RANDOM % ${#LEVERAGES[@]}))
    local leverage="${LEVERAGES[$lev_idx]}"

    local is_long="true"
    [ $((RANDOM % 2)) -eq 0 ] && is_long="false"

    open_position "$market" "$is_long" "$collateral" "$leverage"

    # Short wait in aggressive mode
    local wait_time=$((10 + RANDOM % 20))
    log "Next in ${wait_time}s (aggressive mode)..."
    sleep "$wait_time"

    # Top up balance every 5 cycles
    if [ $((cycle % 5)) -eq 0 ]; then
      local acct_balance
      acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
      if [ -n "$acct_balance" ] && [ "$acct_balance" -lt 2000000000000 ]; then
        log "Topping up AccountManager..."
        cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "5000000000000" \
          --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
        sleep 3
      fi
    fi
  done
}

main "$@"
