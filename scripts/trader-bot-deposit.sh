#!/bin/bash
# Trader Bot Deposit & Position Opening (3-pass approach)
# Pass 1: Approve USDT for all bots
# Pass 2: Deposit to AccountManager for all bots
# Pass 3: Open positions for all bots
# Pauses between each tx to avoid nonce/state sync issues on L2

source /home/lever/lever-protocol/control-plane/deploy-env.sh

RPC="https://sepolia.base.org"
USDT="0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E"
ACCOUNT_MANAGER="0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684"
EXECUTION_ENGINE="0x081F77C848EaaCfBfCD06E159C6B8d437db6F386"
LEVERAGE_MODEL="0x63B98Ec1e559E3b24199eb2115F0a57222e9818c"

DEPOSIT_AMOUNT=50000000000       # 50K USDT (6 decimals)
POSITION_COLLATERAL=2000000000   # 2K USDT (6 decimals)

# 10 demo market IDs
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
MARKET_NAMES=("SpaceX" "US-Iran" "NothingHappens" "FIFA" "FedRate" "SpaceXAckman" "AAPL" "OpenSea" "FedCut" "ArgUSD")

TRADER_KEYS=(
  "46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449"
  "18cd0274afd31ceb3b376e5f417fae9be83711149f2b1f7c0f5f78b021346653"
  "e4706a7051c55c5dadcbbcde78c8c160448de1b379f09a51b21431d1cb22b565"
  "33e8b2f0ff44c4b17c333c433328d87db48ba324b59cb1a265f751dcfcbc22ac"
  "948ac7b707a744dbfa9551bf5ae83616a06b27e28605bdb0c8df0adf5a1a8408"
  "f2ef1d404d19052841a4a54df1e3a56854000ab0c48d04ee5bd4ab037fbeb6bd"
  "93ae27e4ed31d445a293794a1138ac9ccb16d18869a67eff0f2a2f2dfe89b92d"
  "f8d5d699495b1a53cb1eeefcbd36099de8bd768c327959779d53d2d54e643e49"
  "6fdd790aa6bc211ac5254da28dab3a83d1f1b6ad1bcfe1b5a253f186bab0530b"
  "73ab4b1cb5a93d556e4332a964a96c3a117ef8a9679090eb5b9b52e5c77af079"
  "efdcf0525c7904f69e4ed591ac1cbc3bcc083807a4722ffeb47c0eb2dbdf20ea"
  "a0c621225f66adb373d01b01c6b8c032defb4254688f831e721bba283cff97b5"
  "96e763522cbab91177b644db05328e811dda7d6579b0691785c2fe36d1ce0cd3"
  "b245f32e84d47ae3d90f8ed591acf304ae75926f960b7c7d78cf92f9ce901cd0"
  "958356aea8137e0d8387da958d7330db9d49d32058a9cfee25a3b2ffdb173519"
  "7104bc0cc1c24fce34301949c27733021ec711d02c60db319606164ea15b3295"
  "ab44e121d6f68364b9175e7112011dde97dca114ff0f6a466ecef575180543aa"
  "712ec8566caeafbffb77ef1b9e321f099bf6f05dedd7a5e09d4d14116f9b6303"
  "87edf75f45add029564417ba04adc9e8d7f566c0b9cc0f51bd4ae9484dd6d81d"
  "055c30c6467b330231d2fded7ea14ddc8ca5938f394d1471c9360e7540a5a1b6"
  "2506ae8e1f634d8cbdd46612a0161710f13be781886dcfc2ede3f9e260a2a6f5"
  "d6b988357f23dea099f6ddae496189e9a25aa0ca5c2866bc3843510d0ea2307b"
  "eb9620425aaada188adb4196718a35361e850a1f17a2ffec955716a5a0d26c0f"
  "50eea013153434a3d0f11382526bc41167d68a30f87c3cec3e7a95a18df6cc6d"
  "b9e19dbc64e31496483f78da23363b37ed93fb5412bb600ef74530912d15a138"
  "34ecc8d0756499aec22bd04390411bd74f210f5e555746fe774a9ce8f509aa5f"
  "455ef2d47dd597dabf1aca8aa447c883989f59e5ee23c6752d1d15f9e779561f"
  "87c9ac5bce370a33b40eda8fa91e11afa31b11c2e9cc28da36e76a326b3c2abc"
  "cb2a3dd5320e2d8dec6a9341849fbac68dab2214acf98b841a4734bb0449c06f"
  "a5de86024b27142d285e1c48c0297bebb0be5c9736f8d8465d2120f84b49ac84"
)

# How many bots to process (override with $1)
NUM_BOTS=${1:-30}

APPROVE_OK=0
DEPOSIT_OK=0
POSITION_OK=0
SKIP=0

echo "=== PASS 1: Approve USDT for $NUM_BOTS trader bots ==="
for i in $(seq 0 $((NUM_BOTS - 1))); do
  KEY="0x${TRADER_KEYS[$i]}"
  ADDR=$(cast wallet address "$KEY" 2>/dev/null)
  BAL=$(cast call "$USDT" "balanceOf(address)(uint256)" "$ADDR" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')

  if [ "$BAL" -lt "$DEPOSIT_AMOUNT" ] 2>/dev/null; then
    echo "  Trader $i ($ADDR): SKIP (balance $BAL < $DEPOSIT_AMOUNT)"
    continue
  fi

  # Check if already approved
  ALLOWANCE=$(cast call "$USDT" "allowance(address,address)(uint256)" "$ADDR" "$ACCOUNT_MANAGER" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')
  if [ "$ALLOWANCE" -ge "$DEPOSIT_AMOUNT" ] 2>/dev/null; then
    echo "  Trader $i: Already approved ($ALLOWANCE)"
    APPROVE_OK=$((APPROVE_OK + 1))
    continue
  fi

  RESULT=$(cast send "$USDT" "approve(address,uint256)" "$ACCOUNT_MANAGER" "$DEPOSIT_AMOUNT" --private-key "$KEY" --rpc-url "$RPC" 2>&1 || true)
  STATUS=$(echo "$RESULT" | grep "^status" | awk '{print $2}')
  if [ "$STATUS" = "1" ]; then
    echo "  Trader $i: Approved"
    APPROVE_OK=$((APPROVE_OK + 1))
  else
    echo "  Trader $i: Approve FAILED"
  fi
  sleep 1
done

echo ""
echo "Approvals complete: $APPROVE_OK"
echo "Waiting 5s for state sync..."
sleep 5

echo ""
echo "=== PASS 2: Deposit 50K USDT for $NUM_BOTS trader bots ==="
for i in $(seq 0 $((NUM_BOTS - 1))); do
  KEY="0x${TRADER_KEYS[$i]}"
  ADDR=$(cast wallet address "$KEY" 2>/dev/null)
  BAL=$(cast call "$USDT" "balanceOf(address)(uint256)" "$ADDR" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')

  if [ "$BAL" -lt "$DEPOSIT_AMOUNT" ] 2>/dev/null; then
    echo "  Trader $i: SKIP (insufficient USDT)"
    continue
  fi

  # Check if already has AM balance (skip re-deposit)
  AM_BAL=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$ADDR" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')
  if [ "$AM_BAL" -ge "$POSITION_COLLATERAL" ] 2>/dev/null; then
    echo "  Trader $i: Already has AM balance ($AM_BAL)"
    DEPOSIT_OK=$((DEPOSIT_OK + 1))
    continue
  fi

  RESULT=$(cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "$DEPOSIT_AMOUNT" --private-key "$KEY" --rpc-url "$RPC" 2>&1 || true)
  STATUS=$(echo "$RESULT" | grep "^status" | awk '{print $2}')
  if [ "$STATUS" = "1" ]; then
    echo "  Trader $i: Deposited 50K USDT"
    DEPOSIT_OK=$((DEPOSIT_OK + 1))
  else
    ERROR=$(echo "$RESULT" | grep -i "error\|revert" | head -1)
    echo "  Trader $i: Deposit FAILED — $ERROR"
  fi
  sleep 1
done

echo ""
echo "Deposits complete: $DEPOSIT_OK"
echo "Waiting 5s for state sync..."
sleep 5

echo ""
echo "=== PASS 3: Open positions for $NUM_BOTS trader bots ==="
for i in $(seq 0 $((NUM_BOTS - 1))); do
  KEY="0x${TRADER_KEYS[$i]}"
  ADDR=$(cast wallet address "$KEY" 2>/dev/null)

  # Check AM balance
  AM_BAL=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$ADDR" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')
  if [ "$AM_BAL" -lt "$POSITION_COLLATERAL" ] 2>/dev/null; then
    echo "  Trader $i: SKIP (AM balance $AM_BAL < $POSITION_COLLATERAL)"
    SKIP=$((SKIP + 1))
    continue
  fi

  MARKET_IDX=$((i % 10))
  MARKET_ID="${MARKETS[$MARKET_IDX]}"
  MARKET_NAME="${MARKET_NAMES[$MARKET_IDX]}"
  IS_LONG=$([ $((i % 2)) -eq 0 ] && echo "true" || echo "false")
  DIR_STR=$([ "$IS_LONG" = "true" ] && echo "LONG" || echo "SHORT")

  # Query max leverage
  MAX_LEV=$(cast call "$LEVERAGE_MODEL" "getEffectiveMaxLeverage(bytes32)(uint256)" "$MARKET_ID" --rpc-url "$RPC" 2>/dev/null | head -1 | awk '{print $1}')

  # Cap at 2x, floor at 1x
  LEV="2000000000000000000"
  if [ "$MAX_LEV" -lt "$LEV" ] 2>/dev/null; then LEV="$MAX_LEV"; fi
  if [ "$LEV" -lt "1000000000000000000" ] 2>/dev/null; then LEV="1000000000000000000"; fi

  echo -n "  Trader $i: $MARKET_NAME $DIR_STR (lev=$(echo "scale=1; $LEV / 1000000000000000000" | bc)x)... "

  RESULT=$(cast send "$EXECUTION_ENGINE" \
    "openPosition((bytes32,bool,uint256,uint256))" \
    "($MARKET_ID,$IS_LONG,$POSITION_COLLATERAL,$LEV)" \
    --private-key "$KEY" --rpc-url "$RPC" 2>&1 || true)
  STATUS=$(echo "$RESULT" | grep "^status" | awk '{print $2}')

  if [ "$STATUS" = "1" ]; then
    echo "OK"
    POSITION_OK=$((POSITION_OK + 1))
  else
    ERROR=$(echo "$RESULT" | grep -i "revert\|error\|Error" | head -1)
    echo "FAILED: $ERROR"
  fi
  sleep 1
done

echo ""
echo "========================================="
echo "=== FINAL RESULTS ==="
echo "Deposits successful: $DEPOSIT_OK / $NUM_BOTS"
echo "Positions opened: $POSITION_OK / $NUM_BOTS"
echo "Skipped (insufficient funds): $SKIP"
echo "========================================="
