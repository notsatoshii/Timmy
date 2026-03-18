#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh
source /home/lever/lever-protocol/control-plane/rpc-config.env 2>/dev/null || true

# Ensure foundry tools are available
CAST="/home/lever/.foundry/bin/cast"
if [ ! -f "$CAST" ]; then
    echo "ERROR: foundry cast not found at $CAST"
    exit 1
fi

echo "=== LEVER HEALTH CHECK $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
PASS=0
FAIL=0


# Enhanced RPC call with fallback handling
rpc_call_with_fallback() {
    local cmd="$1"
    local fallback_rpcs=("$RPC_FALLBACK_1" "$RPC_FALLBACK_2" "$RPC_FALLBACK_3")

    # Try primary RPC first
    result=$(eval "$cmd" 2>&1)
    if ! echo "$result" | grep -qi "413\|rate limit\|timeout\|network"; then
        echo "$result"
        return 0
    fi

    echo "WARN: Primary RPC failed with rate limit/network error, trying fallbacks..." >&2

    # Try fallback RPCs
    for fallback_rpc in "${fallback_rpcs[@]}"; do
        if [ -n "$fallback_rpc" ]; then
            fallback_cmd=$(echo "$cmd" | sed "s|--rpc-url \$RPC_URL|--rpc-url $fallback_rpc|g")
            result=$(eval "$fallback_cmd" 2>&1)
            if ! echo "$result" | grep -qi "413\|rate limit\|timeout\|network"; then
                echo "INFO: Fallback RPC $fallback_rpc succeeded" >&2
                echo "$result"
                return 0
            fi
            sleep 1
        fi
    done

    echo "$result"
    return 1
}

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
check "lever_vault" "$(rpc_call_with_fallback "$CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL" 2>&1)"
check "fee_router" "$($CAST call $FEE_ROUTER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)"

# TVL
TVL=$(rpc_call_with_fallback "$CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL" 2>&1)
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

# Frontend (React SPA Testing)
FRONTEND_RESULT=$(node /home/lever/lever-protocol/scripts/react-spa-verification.js --quick 2>/dev/null)
FRONTEND_EXIT_CODE=$?
if [ $FRONTEND_EXIT_CODE -eq 0 ]; then
    check "frontend_react_spa" "PASS - React SPA verified via browser testing" ""
else
    # Fallback to basic HTTP check if browser testing fails
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
    if [ "$HTTP" = "200" ]; then
        check "frontend_basic_http" "PASS - HTTP 200 (browser testing failed, using fallback)" ""
    else
        check "frontend" "FAIL - HTTP $HTTP and browser testing failed" ""
    fi
fi

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
check "global_oi" "$(rpc_call_with_fallback "$CAST call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL" 2>&1)"
check "insurance_fund" "$(rpc_call_with_fallback "$CAST call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL" 2>&1)"
check "platform_ceiling" "$(rpc_call_with_fallback "$CAST call $LEVERAGE_MODEL 'getPlatformCeiling()(uint256)' --rpc-url $RPC_URL" 2>&1)"
check "market_max_leverage" "$($CAST call $LEVERAGE_MODEL 'getEffectiveMaxLeverage(bytes32)(uint256)' $MARKET_ID --rpc-url $RPC_URL 2>&1)"
check "global_utilization" "$($CAST call $OI_LIMITS 'getGlobalUtilization()(uint256)' --rpc-url $RPC_URL 2>&1)"

# Oracle keeper process status
if pgrep -f mock_keeper.py > /dev/null 2>&1; then
    echo "PASS: oracle_keeper_process — running"
    PASS=$((PASS+1))
else
    echo "FAIL: oracle_keeper_process — not running"
    FAIL=$((FAIL+1))
fi

# Oracle price updates (check for stale prices >5 minutes old)
ORACLE_LOG="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
if [ -f "$ORACLE_LOG" ]; then
    # Get the timestamp of the last successful PUSHED entry
    LAST_PUSH_LINE=$(grep "PUSHED:" "$ORACLE_LOG" | tail -n1)

    if [ -n "$LAST_PUSH_LINE" ]; then
        LAST_PUSH_TIME=$(echo "$LAST_PUSH_LINE" | cut -d'|' -f1 | tr -d ' ')

        # Convert HH:MM:SS to seconds since midnight for comparison
        CURRENT_SECONDS=$(date '+%s')

        # Extract time components and convert to seconds since midnight today
        PUSH_HOUR=$(echo "$LAST_PUSH_TIME" | cut -d':' -f1)
        PUSH_MIN=$(echo "$LAST_PUSH_TIME" | cut -d':' -f2)
        PUSH_SEC=$(echo "$LAST_PUSH_TIME" | cut -d':' -f3)

        # Force decimal interpretation (remove leading zeros to avoid octal interpretation)
        PUSH_HOUR=$((10#$PUSH_HOUR))
        PUSH_MIN=$((10#$PUSH_MIN))
        PUSH_SEC=$((10#$PUSH_SEC))

        TODAY_MIDNIGHT=$(date -d 'today 00:00:00' '+%s')
        PUSH_TIMESTAMP=$((TODAY_MIDNIGHT + PUSH_HOUR*3600 + PUSH_MIN*60 + PUSH_SEC))

        # Check if last push was more than 5 minutes (300 seconds) ago
        TIME_DIFF=$((CURRENT_SECONDS - PUSH_TIMESTAMP))

        if [ $TIME_DIFF -le 300 ]; then
            echo "PASS: oracle_price_freshness — last push ${TIME_DIFF}s ago (${LAST_PUSH_TIME})"
            PASS=$((PASS+1))
        else
            echo "FAIL: oracle_price_freshness — STALE: last push ${TIME_DIFF}s ago (${LAST_PUSH_TIME})"
            FAIL=$((FAIL+1))
        fi
    else
        echo "FAIL: oracle_price_freshness — no successful pushes found"
        FAIL=$((FAIL+1))
    fi
else
    echo "FAIL: oracle_price_freshness — no log file found"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== RESULT: $PASS passed, $FAIL failed ==="

echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pass\":$PASS,\"fail\":$FAIL}" > /home/lever/lever-protocol/control-plane/health-check-result.json

if [ "$FAIL" -gt 0 ]; then exit 1; else exit 0; fi
