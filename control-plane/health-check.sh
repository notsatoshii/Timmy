#!/bin/bash
# LEVER Protocol Health Check
# Exit 0 = all good. Exit 1 = something broken.
# Outputs JSON so worker can parse results.

source /home/lever/lever-protocol/control-plane/deploy-env.sh

PASS=0
FAIL=0
RESULTS="{"

check() {
    local name="$1"
    local cmd="$2"
    local expect="$3"
    
    result=$(eval "$cmd" 2>&1)
    
    if echo "$result" | grep -qi "revert\|error\|Error"; then
        RESULTS="$RESULTS\"$name\":\"FAIL: reverted\","
        FAIL=$((FAIL+1))
        echo "FAIL: $name — reverted"
    elif [ -n "$expect" ] && ! echo "$result" | grep -q "$expect"; then
        RESULTS="$RESULTS\"$name\":\"FAIL: expected $expect got $result\","
        FAIL=$((FAIL+1))
        echo "FAIL: $name — expected $expect, got $result"
    else
        RESULTS="$RESULTS\"$name\":\"PASS: $result\","
        PASS=$((PASS+1))
        echo "PASS: $name"
    fi
}

echo "=== LEVER Health Check $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# 1. Contracts exist
check "usdt_exists" "cast call $USDT_ADDRESS 'totalSupply()(uint256)' --rpc-url $RPC_URL"
check "market_registry_exists" "cast call $MARKET_REGISTRY 'owner()(address)' --rpc-url $RPC_URL"
check "oracle_adapter_exists" "cast call $ORACLE_ADAPTER 'owner()(address)' --rpc-url $RPC_URL"
check "account_manager_exists" "cast call $ACCOUNT_MANAGER 'owner()(address)' --rpc-url $RPC_URL"
check "lever_vault_exists" "cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL"

# 2. TVL
check "vault_tvl" "cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL" "20000000000000"

# 3. Markets registered (try marketCount or similar)
check "markets_registered" "cast call $MARKET_REGISTRY 'marketCount()(uint256)' --rpc-url $RPC_URL"

# 4. Oracle prices (SpaceX market)
check "spacex_price" "cast call $ORACLE_ADAPTER 'getLatestPrice(bytes32)(uint256,uint256,uint256)' 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1 --rpc-url $RPC_URL"

# 5. Frontend serving
check "frontend_serving" "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000" "200"

# 6. Frontend has live data (not demo fallback)
check "frontend_live_data" "curl -s http://localhost:3000/deployments/core-deployment.json | grep -c marketRegistry" "1"

# 7. No stale addresses in scripts
STALE=$(grep -r "0x13e01E\|0xf846E3\|0x1acab9\|0x463697\|0x4F0224\|0xe0f420\|0x5D538d" script/ 2>/dev/null | wc -l)
if [ "$STALE" -gt 0 ]; then
    echo "FAIL: stale_addresses — $STALE stale addresses in scripts"
    FAIL=$((FAIL+1))
else
    echo "PASS: stale_addresses — none found"
    PASS=$((PASS+1))
fi

# 8. No DEPLOYER_KEY in scripts
OLDKEY=$(grep -r "DEPLOYER_KEY" script/ 2>/dev/null | wc -l)
if [ "$OLDKEY" -gt 0 ]; then
    echo "FAIL: deployer_key_refs — $OLDKEY references to DEPLOYER_KEY"
    FAIL=$((FAIL+1))
else
    echo "PASS: deployer_key_refs — all use PRIVATE_KEY"
    PASS=$((PASS+1))
fi

echo ""
echo "=== RESULT: $PASS passed, $FAIL failed ==="

# Write results to file
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pass\":$PASS,\"fail\":$FAIL}" > /home/lever/lever-protocol/control-plane/health-check-result.json

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
