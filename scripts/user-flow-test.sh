#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    if echo "$result" | grep -qi "revert\|error"; then
        echo "FAIL: $name — $result"
        FAIL=$((FAIL+1))
    else
        echo "PASS: $name — $(echo $result | head -c 120)"
        PASS=$((PASS+1))
    fi
}

echo "=== USER FLOW TEST $(date -u) ==="

# Use test wallet if available, otherwise deployer
if [ -n "$TEST_WALLET_KEY" ]; then
    TEST_KEY=$TEST_WALLET_KEY
    TEST_ADDR=$(cast wallet address --private-key $TEST_KEY)
    echo "Using test wallet: $TEST_ADDR"
else
    TEST_KEY=$PRIVATE_KEY
    TEST_ADDR=$DEPLOYER
    echo "WARNING: No test wallet, using deployer: $TEST_ADDR"
fi

echo ""
echo "--- Step 1: Contracts respond ---"
check "usdt_decimals" "$(cast call $USDT_ADDRESS 'decimals()(uint8)' --rpc-url $RPC_URL 2>&1)"
check "vault_total_assets" "$(cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>&1)"
check "registry_owner" "$(cast call $MARKET_REGISTRY 'owner()(address)' --rpc-url $RPC_URL 2>&1)"

echo ""
echo "--- Step 2: Check balances ---"
check "test_eth_balance" "$(cast balance $TEST_ADDR --rpc-url $RPC_URL 2>&1)"
check "test_usdt_balance" "$(cast call $USDT_ADDRESS 'balanceOf(address)(uint256)' $TEST_ADDR --rpc-url $RPC_URL 2>&1)"

echo ""
echo "--- Step 3: Mint and deposit to vault ---"
MINT_AMT=1000000000  # 1000 USDT

# Mint (only deployer can mint MockUSDT)
check "mint_usdt" "$(cast send $USDT_ADDRESS 'mint(address,uint256)' $TEST_ADDR $MINT_AMT --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1)"
sleep 1

# Approve vault (test wallet signs)
check "approve_vault" "$(cast send $USDT_ADDRESS 'approve(address,uint256)' $LEVER_VAULT $MINT_AMT --rpc-url $RPC_URL --private-key $TEST_KEY 2>&1)"
sleep 1

# Deposit (test wallet signs)
check "vault_deposit" "$(cast send $LEVER_VAULT 'deposit(uint256,address)' $MINT_AMT $TEST_ADDR --rpc-url $RPC_URL --private-key $TEST_KEY 2>&1)"
sleep 1

# Verify shares
check "vault_shares" "$(cast call $LEVER_VAULT 'balanceOf(address)(uint256)' $TEST_ADDR --rpc-url $RPC_URL 2>&1)"

echo ""
echo "=== USER FLOW RESULT: $PASS passed, $FAIL failed ==="
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pass\":$PASS,\"fail\":$FAIL}" > /home/lever/lever-protocol/control-plane/user-flow-result.json
exit $FAIL
