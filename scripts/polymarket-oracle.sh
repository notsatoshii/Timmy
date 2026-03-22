#!/bin/bash
# Polymarket Oracle Updater for LEVER Protocol
# Fetches live prices from Polymarket and pushes to OracleAdapter
# Runs every 60 seconds for all 20 markets

export PATH="/home/lever/.foundry/bin:$PATH"
source /home/lever/lever-protocol/control-plane/deploy-env.sh

WALLET=$(cast wallet address --private-key $PRIVATE_KEY)
CONFIG="/home/lever/lever-protocol/scripts/oracle-markets.json"
LOG="/tmp/oracle-updater.log"
PRICES_JSON="/home/lever/lever-protocol/frontend/user-app/build/prices.json"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

log "=== Polymarket Oracle Updater Started ==="
log "Wallet: $WALLET"
log "Oracle Adapter: $ORACLE_ADAPTER"
log "Config: $CONFIG"

# Parse market config
MARKETS=$(python3 -c "
import json
with open('$CONFIG') as f:
    markets = json.load(f)
for m in markets:
    print(f\"{m['marketId']}|{m['conditionId']}|{m['slug']}|{m['fallbackPrice']}|{m['name']}\")
")

while true; do
  log "--- Update cycle ---"
  PRICES_DATA="{\"lastUpdate\": $(date +%s), \"prices\": {"
  FIRST=true
  UPDATED=0
  FAILED=0

  while IFS='|' read -r MARKET_ID CONDITION_ID SLUG FALLBACK NAME; do
    # Try to fetch from Polymarket Gamma API using the slug
    PRICE=""

    # Method 1: Try by slug
    if [ -n "$SLUG" ]; then
      API_RESULT=$(curl -s --max-time 10 "https://gamma-api.polymarket.com/markets?slug=$SLUG&limit=1" 2>/dev/null || echo "")
      if [ -n "$API_RESULT" ] && echo "$API_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if len(d)>0 else 1)" 2>/dev/null; then
        PRICE=$(echo "$API_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data and len(data) > 0:
    m = data[0]
    prices = m.get('outcomePrices', '[]')
    if isinstance(prices, str):
        import json as j
        prices = j.loads(prices)
    if prices and len(prices) > 0:
        print(f'{float(prices[0]):.6f}')
" 2>/dev/null)
      fi
    fi

    # Method 2: Try by condition ID for new markets
    if [ -z "$PRICE" ] && [ -n "$CONDITION_ID" ] && [ "$CONDITION_ID" != "$MARKET_ID" ]; then
      API_RESULT=$(curl -s --max-time 10 "https://gamma-api.polymarket.com/markets?condition_id=$CONDITION_ID&limit=1" 2>/dev/null || echo "")
      if [ -n "$API_RESULT" ] && echo "$API_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if len(d)>0 else 1)" 2>/dev/null; then
        PRICE=$(echo "$API_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data and len(data) > 0:
    m = data[0]
    prices = m.get('outcomePrices', '[]')
    if isinstance(prices, str):
        import json as j
        prices = j.loads(prices)
    if prices and len(prices) > 0:
        print(f'{float(prices[0]):.6f}')
" 2>/dev/null)
      fi
    fi

    # Fallback to configured price
    if [ -z "$PRICE" ] || [ "$PRICE" = "0.000000" ]; then
      PRICE="$FALLBACK"
      log "  $NAME: using fallback $PRICE"
    fi

    # Convert to WAD
    PYES=$(python3 -c "p=float('$PRICE'); print(int(p * 1e18))")
    PNO=$(python3 -c "p=float('$PRICE'); print(int((1-p) * 1e18))")

    # Push to OracleAdapter
    for tx_attempt in 1 2; do
      NONCE=$(cast nonce $WALLET --rpc-url $RPC_URL 2>/dev/null)
      if [ -z "$NONCE" ]; then
        sleep 2
        continue
      fi

      RESULT=$(cast send $ORACLE_ADAPTER \
        "pushPrice(bytes32,uint256,uint256,uint256,uint256,uint256)" \
        "$MARKET_ID" "$PYES" "$PNO" \
        "10000000000000000" "50000000000000000000000" "1000000000000000000000" \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL \
        --nonce $NONCE --gas-limit 300000 --confirmations 1 2>&1)

      if echo "$RESULT" | grep -q "transactionHash\|status.*0x1"; then
        log "  $NAME: $PRICE ✓"
        UPDATED=$((UPDATED + 1))
        break
      elif echo "$RESULT" | grep -q "nonce"; then
        sleep 2
        continue
      else
        log "  $NAME: FAILED - $(echo $RESULT | head -c 100)"
        FAILED=$((FAILED + 1))
        break
      fi
    done

    # Build prices.json entry
    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      PRICES_DATA="$PRICES_DATA,"
    fi
    PRICES_DATA="$PRICES_DATA \"$MARKET_ID\": {\"probability\": $PRICE, \"name\": \"$NAME\"}"

    sleep 1  # Small delay between markets to avoid nonce races
  done <<< "$MARKETS"

  PRICES_DATA="$PRICES_DATA }}"

  # Write prices.json for frontend
  echo "$PRICES_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d,indent=2))" > "$PRICES_JSON" 2>/dev/null || true

  log "Cycle complete: $UPDATED updated, $FAILED failed"
  log "Sleeping 60s..."
  sleep 60
done
