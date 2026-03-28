#!/bin/bash
# Seed 150 positions across 20 markets using 20 wallets
set -e
cd /home/lever/lever-protocol
source control-plane/deploy-env.sh

USDT=0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E
DEPLOYER_KEY=$(cat .env.deployer | tr -d '[:space:]')
RPC=https://sepolia.base.org

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
  0x8215cf9d075f1ee6044f05d17fa1685d88da515f3ea119e10f50cb487f9e3774
  0x329ec977deb23dbc392959044918040f8a9252d502c6948eea33d2e72e787ddd
  0xc2a3fba66cdee6088484ae353b3c414390c591ac5cf485248f9b9cbb591a8cd4
  0x35f95cb4e4331813cbbcf8acd4efea29305a24ff890b4f22d163722095ebb706
  0x73b37115e0a747b8fec07143017b8359a53677baa466a4847c6af7c14c0ec5c7
  0x6ee69274ed792087cd80dc1db0f90456f4d2621287375a0e90032f61bbe32e9e
  0xdf341f72d47f0bbcb009aaa13d9d683a79ce8f77de068943c0316feade190c21
  0x0e6da084b18fb861b29203d611dc83df2bcfa3294281dd57ea735f3096023438
  0x5131ef671dbddffe63e34798f3cf92be05c95001b20f29255f97d87b2d6e1de2
  0x7155116cef46226d9a58e096c87fba03555313c85b9b9b649dca754090845136
)

# Extract 20 wallet keys
readarray -t WALLET_KEYS < <(python3 -c "
import json
with open('control-plane/bot-wallets.json') as f:
    data = json.load(f)
keys = list(data.keys())[:20]
for k in keys:
    print(data[k])
")

# Get addresses
WALLET_ADDRS=()
for pk in "${WALLET_KEYS[@]}"; do
  addr=$(cast wallet address "$pk" 2>/dev/null)
  WALLET_ADDRS+=("$addr")
done
echo "Loaded ${#WALLET_ADDRS[@]} wallets"

echo "=== Step 1: Fund InsuranceFund (20% TVL) ==="
TVL=$(cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC | head -1 | awk '{print $1}')
IF_AMOUNT=$(python3 -c "print(int('$TVL') * 20 // 100)")
echo "Sending $IF_AMOUNT USDT to InsuranceFund"
cast send --private-key $DEPLOYER_KEY --rpc-url $RPC $USDT "transfer(address,uint256)" $INSURANCE_FUND $IF_AMOUNT 2>&1 | grep "status"

echo ""
echo "=== Step 2: Fund wallets (ETH + USDT) ==="
for i in "${!WALLET_ADDRS[@]}"; do
  addr="${WALLET_ADDRS[$i]}"
  echo -n "W$i $addr: "
  # 0.002 ETH each (40 total = 0.04 ETH)
  cast send --private-key $DEPLOYER_KEY --rpc-url $RPC $addr --value 2000000000000000 2>&1 | grep -o "status.*" &
  # 500K USDT each
  cast send --private-key $DEPLOYER_KEY --rpc-url $RPC $USDT "transfer(address,uint256)" $addr 500000000000 2>&1 | grep -o "status.*" &
  wait
  echo ""
done

echo ""
echo "=== Step 3: Approve + Deposit for each wallet ==="
for i in "${!WALLET_ADDRS[@]}"; do
  pk="${WALLET_KEYS[$i]}"
  echo -n "W$i approve+deposit: "
  cast send --private-key "$pk" --rpc-url $RPC $USDT "approve(address,uint256)" $ACCOUNT_MANAGER 500000000000 2>&1 | grep -o "status.*"
  cast send --private-key "$pk" --rpc-url $RPC $ACCOUNT_MANAGER "deposit(uint256)" 500000000000 2>&1 | grep -o "status.*"
done

echo ""
echo "=== Step 4: Open 150 positions ==="
OPENED=0
for pos in $(seq 1 150); do
  wi=$((RANDOM % 20))
  mi=$((RANDOM % 20))
  long=$((RANDOM % 2))
  notional_k=$((70 + RANDOM % 111))
  lev=$((5 + RANDOM % 6))
  collateral=$(python3 -c "print(${notional_k} * 1000000 // ${lev})")
  lev_wad=$(python3 -c "print(${lev} * 10**18)")

  pk="${WALLET_KEYS[$wi]}"
  market="${MARKETS[$mi]}"
  dir=$([ $long -eq 1 ] && echo "true" || echo "false")

  echo -n "[$pos/150] W$wi M$mi ${notional_k}K ${lev}x $([ $long -eq 1 ] && echo L || echo S) "
  result=$(cast send --private-key "$pk" --rpc-url $RPC $EXECUTION_ENGINE \
    "openPosition(bytes32,bool,uint256,uint256)" "$market" $dir $collateral $lev_wad 2>&1)
  if echo "$result" | grep -q "status.*1"; then
    echo "OK"
    OPENED=$((OPENED + 1))
  else
    echo "FAIL: $(echo "$result" | grep -i "revert\|error" | head -1)"
  fi
done

echo ""
echo "=== DONE: $OPENED/150 positions opened ==="
echo "IF USDT: $(cast call $USDT 'balanceOf(address)(uint256)' $INSURANCE_FUND --rpc-url $RPC)"
echo "Global OI: $(cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC)"
