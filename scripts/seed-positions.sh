#!/bin/bash
# ============================================
# LEVER Protocol — Position Seeder Bot
# Opens and closes positions continuously
# Min leverage: 4x, Min notional: $30K
# ============================================

set -e

source /home/lever/lever-protocol/control-plane/deploy-env.sh

DEMO_KEY="bf4b6a6e7c99d538edf38d0ac535a44729bb8c9907de5bb9494d852eb4e812ec"
DEMO_ADDR="0xB072263740D7c60f1Aa0BF46e737F83544C7b785"
WALLET_KEY="$DEMO_KEY"
WALLET_ADDR="$DEMO_ADDR"

LOG_FILE="/home/lever/lever-protocol/control-plane/dispatcher-logs/seeder.log"

# Market IDs (will be populated from on-chain)
MARKETS=(
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"  # SpaceX
)

# Collateral in USDT (6 decimals) — sized so notional >= $30K at 4x
# collateral * leverage = notional
# 7500 * 4 = 30K, 10000 * 5 = 50K, 15000 * 7 = 105K, etc.
COLLATERALS=(7500000000 10000000000 15000000000 25000000000 50000000000)  # 7.5K, 10K, 15K, 25K, 50K USDT

# Leverage in WAD (18 decimals) — minimum 4x, max ~10x (protocol caps at 7-12x)
LEVERAGES=(4000000000000000000 5000000000000000000 6000000000000000000 7000000000000000000 8000000000000000000 10000000000000000000)  # 4x, 5x, 6x, 7x, 8x, 10x

log() {
  local msg="[$(date '+%H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

preflight() {
  log "=== PREFLIGHT CHECKS ==="

  # Check ETH balance for gas
  local eth_balance
  eth_balance=$(cast balance "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
  log "ETH balance: $eth_balance wei"
  if [ -z "$eth_balance" ] || [ "$eth_balance" = "0" ]; then
    log "ERROR: No ETH for gas. Fund $WALLET_ADDR on Base Sepolia."
    return 1
  fi

  # Check USDT balance
  local usdt_balance
  usdt_balance=$(cast call "$USDT" "balanceOf(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
  log "USDT wallet balance: $usdt_balance (6 decimals)"
  if [ -z "$usdt_balance" ] || [ "$usdt_balance" = "0" ]; then
    log "No USDT. Calling faucet..."
    cast send "$USDT" "faucet()" --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 5
    usdt_balance=$(cast call "$USDT" "balanceOf(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
    log "USDT after faucet: $usdt_balance"
  fi

  # Approve USDT for AccountManager (max approval)
  local allowance
  allowance=$(cast call "$USDT" "allowance(address,address)(uint256)" "$WALLET_ADDR" "$ACCOUNT_MANAGER" --rpc-url "$RPC_URL" 2>/dev/null)
  log "USDT allowance for AccountManager: $allowance"
  if [ -z "$allowance" ] || [ "$allowance" = "0" ]; then
    log "Approving USDT for AccountManager (max)..."
    cast send "$USDT" "approve(address,uint256)" "$ACCOUNT_MANAGER" "115792089237316195423570985008687907853269984665640564039457584007913129639935" \
      --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 3
    log "USDT approved"
  fi

  # Deposit to AccountManager if needed
  local acct_balance
  acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
  log "AccountManager balance: $acct_balance"
  if [ -z "$acct_balance" ] || [ "$acct_balance" = "0" ] || [ "$acct_balance" -lt 100000000000 ]; then
    log "Depositing 500,000 USDT to AccountManager..."
    cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "500000000000" \
      --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 3
    acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
    log "AccountManager balance after deposit: $acct_balance"
  fi

  # Try to discover additional markets
  log "Checking registered markets..."
  local market_ids
  market_ids=$(cast call "$MARKET_REGISTRY" "getActiveMarketIds()(bytes32[])" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
  if [ -n "$market_ids" ] && [ "$market_ids" != "[]" ]; then
    log "Found markets: $market_ids"
  fi

  log "=== PREFLIGHT COMPLETE ==="
  return 0
}

open_position() {
  local market_id="$1"
  local is_long="$2"
  local collateral="$3"
  local leverage="$4"

  # Calculate notional for logging
  local coll_usd=$((collateral / 1000000))
  local lev_x=$((leverage / 1000000000000000000))
  local notional=$((coll_usd * lev_x))

  log "OPEN: market=${market_id:0:10}... ${is_long^^} collateral=\$${coll_usd} leverage=${lev_x}x notional=\$${notional}K"

  local result
  result=$(cast send "$EXECUTION_ENGINE" \
    "openPosition((bytes32,bool,uint256,uint256))" \
    "($market_id,$is_long,$collateral,$leverage)" \
    --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>&1)

  if echo "$result" | grep -qi "transactionhash\|0x[0-9a-f]\{64\}"; then
    local tx_hash
    tx_hash=$(echo "$result" | grep -oP '0x[0-9a-f]{64}' | head -1)
    log "  ✅ Opened: $tx_hash (notional \$${notional}K)"
    return 0
  else
    log "  ❌ Failed: $(echo "$result" | head -3)"
    return 1
  fi
}

close_position() {
  local position_id="$1"

  log "CLOSE: position #$position_id"

  local result
  result=$(cast send "$EXECUTION_ENGINE" \
    "closePosition(uint256)" \
    "$position_id" \
    --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>&1)

  if echo "$result" | grep -qi "transactionhash\|0x[0-9a-f]\{64\}"; then
    local tx_hash
    tx_hash=$(echo "$result" | grep -oP '0x[0-9a-f]{64}' | head -1)
    log "  ✅ Closed #$position_id: $tx_hash"
    return 0
  else
    log "  ❌ Close failed: $(echo "$result" | head -3)"
    return 1
  fi
}

get_next_position_id() {
  cast call "$POSITION_MANAGER" "nextPositionId()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null
}

main() {
  log "=========================================="
  log "LEVER Position Seeder Bot"
  log "Min leverage: 4x | Min notional: \$30K"
  log "=========================================="
  log "Wallet: $WALLET_ADDR"

  if ! preflight; then
    log "Preflight failed. Exiting."
    exit 1
  fi

  # Track positions we opened so we can close them
  declare -a OUR_POSITIONS=()
  local cycle=0

  while true; do
    cycle=$((cycle + 1))
    log ""
    log "--- Cycle $cycle ---"

    # Pick random parameters
    local market_idx=$((RANDOM % ${#MARKETS[@]}))
    local market="${MARKETS[$market_idx]}"

    local coll_idx=$((RANDOM % ${#COLLATERALS[@]}))
    local collateral="${COLLATERALS[$coll_idx]}"

    local lev_idx=$((RANDOM % ${#LEVERAGES[@]}))
    local leverage="${LEVERAGES[$lev_idx]}"

    # Cap leverage at protocol max to avoid reverts
    # SpaceX max is ~7x, others ~12x. Use 7x as safe cap.
    if [ "$leverage" -gt 7000000000000000000 ]; then
      leverage=7000000000000000000
    fi

    local is_long="true"
    if [ $((RANDOM % 2)) -eq 0 ]; then
      is_long="false"
    fi

    # Record position ID before opening
    local before_id
    before_id=$(get_next_position_id)

    # Open position
    if open_position "$market" "$is_long" "$collateral" "$leverage"; then
      if [ -n "$before_id" ]; then
        OUR_POSITIONS+=("$before_id")
        log "  Tracked as position #$before_id (${#OUR_POSITIONS[@]} total)"
      fi
    fi

    # Wait 45-120 seconds between actions
    local wait_time=$((45 + RANDOM % 75))
    log "Next action in ${wait_time}s..."
    sleep "$wait_time"

    # Every 4th cycle, close a random position we opened
    if [ $((cycle % 4)) -eq 0 ] && [ ${#OUR_POSITIONS[@]} -gt 2 ]; then
      # Pick a random position from our list (keep at least 2 open)
      local close_idx=$((RANDOM % (${#OUR_POSITIONS[@]} - 2)))
      local close_id="${OUR_POSITIONS[$close_idx]}"

      if close_position "$close_id"; then
        # Remove from tracking array
        unset 'OUR_POSITIONS[$close_idx]'
        OUR_POSITIONS=("${OUR_POSITIONS[@]}")  # Re-index
        log "  ${#OUR_POSITIONS[@]} positions still tracked"
      fi

      wait_time=$((30 + RANDOM % 60))
      log "Next action in ${wait_time}s..."
      sleep "$wait_time"
    fi

    # Re-check and top up balance every 10 cycles
    if [ $((cycle % 10)) -eq 0 ]; then
      log "Balance check..."
      local acct_balance
      acct_balance=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null)
      log "AccountManager balance: $acct_balance"

      if [ -n "$acct_balance" ] && [ "$acct_balance" -lt 100000000000 ]; then
        log "Balance low (<$100K), depositing more..."
        cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "500000000000" \
          --private-key "$WALLET_KEY" --rpc-url "$RPC_URL" 2>/dev/null
        sleep 3
      fi
    fi

  done
}

main "$@"
