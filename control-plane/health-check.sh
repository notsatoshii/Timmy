#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh

# Ensure foundry tools are available
CAST="/home/lever/.foundry/bin/cast"
if [ ! -f "$CAST" ]; then
    echo "ERROR: foundry cast not found at $CAST"
    exit 1
fi

echo "=== LEVER HEALTH CHECK $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    local expect="$3"

    if echo "$result" | grep -qi "revert\|error\|Error"; then
        echo "FAIL: $name — reverted or error"
        FAIL=$((FAIL+1))
    elif [ -n "$expect" ] && ! echo "$result" | grep -q "$expect"; then
        echo "FAIL: $name — expected $expect, got: $result"
        FAIL=$((FAIL+1))
    else
        echo "PASS: $name — $result"
        PASS=$((PASS+1))
    fi
}

# Contracts exist
check "usdt" "$($CAST call $USDT_ADDRESS 'decimals()(uint8)' --rpc-url $RPC_URL 2>&1)"
check "market_registry" "$($CAST call $MARKET_REGISTRY 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"
check "oracle_adapter" "$($CAST call $ORACLE_ADAPTER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"
check "account_manager" "$($CAST call $ACCOUNT_MANAGER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"
check "position_manager" "$($CAST call $POSITION_MANAGER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"
check "lever_vault" "$($CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>&1)"
check "fee_router" "$($CAST call $FEE_ROUTER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"

# TVL
TVL=$($CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$TVL" | grep -q "^0$"; then
    echo "FAIL: vault_tvl — TVL is 0"
    FAIL=$((FAIL+1))
else
    echo "PASS: vault_tvl — $TVL"
    PASS=$((PASS+1))
fi

# Deployer ETH
DEPLOYER_WEI=$($CAST balance $DEPLOYER --rpc-url $RPC_URL --raw 2>/dev/null)
if [ -n "$DEPLOYER_WEI" ] && [ "$DEPLOYER_WEI" -lt 10000000000000000 ] 2>/dev/null; then
    echo "WARN: deployer_eth — low balance ($DEPLOYER_WEI wei)"
else
    echo "PASS: deployer_eth — sufficient"
    PASS=$((PASS+1))
fi

# Frontend
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
check "frontend" "$HTTP" "200"

# Deployment JSONs accessible
HTTP2=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/deployments/core-deployment.json 2>/dev/null)
check "deployment_jsons" "$HTTP2" "200"

# Stale addresses
STALE=$(grep -r "0x13e01E\|0xf846E3\|0x1acab9\|0x463697\|0x4F0224\|0xe0f420\|0x5D538d" /home/lever/lever-protocol/script/ 2>/dev/null | wc -l)
if [ "$STALE" -gt 0 ]; then
    echo "FAIL: stale_addresses — $STALE found in scripts"
    FAIL=$((FAIL+1))
else
    echo "PASS: stale_addresses — clean"
    PASS=$((PASS+1))
fi

# DEPLOYER_KEY refs
OLDKEY=$(grep -r "DEPLOYER_KEY" /home/lever/lever-protocol/script/ 2>/dev/null | wc -l)
if [ "$OLDKEY" -gt 0 ]; then
    echo "FAIL: deployer_key_refs — $OLDKEY found"
    FAIL=$((FAIL+1))
else
    echo "PASS: deployer_key_refs — clean"
    PASS=$((PASS+1))
fi

# Dashboard critical data points
MARKET_ID="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"
check "global_oi" "$($CAST call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>&1)"
check "insurance_fund" "$($CAST call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>&1)"
check "platform_ceiling" "$($CAST call $LEVERAGE_MODEL 'getPlatformCeiling()(uint256)' --rpc-url $RPC_URL 2>&1)"
check "market_max_leverage" "$($CAST call $LEVERAGE_MODEL 'getEffectiveMaxLeverage(bytes32)(uint256)' $MARKET_ID --rpc-url $RPC_URL 2>&1)"
check "global_utilization" "$($CAST call $OI_LIMITS 'getGlobalUtilization()(uint256)' --rpc-url $RPC_URL 2>&1)"

echo ""
echo "=== RESULT: $PASS passed, $FAIL failed ==="

echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pass\":$PASS,\"fail\":$FAIL}" > /home/lever/lever-protocol/control-plane/health-check-result.json

if [ "$FAIL" -gt 0 ]; then exit 1; else exit 0; fi
