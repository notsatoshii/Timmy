#!/bin/bash
# Test script for validating all critical contract data fetching
source /home/lever/lever-protocol/control-plane/deploy-env.sh

CAST="/home/lever/.foundry/bin/cast"
if [ ! -f "$CAST" ]; then
    echo "ERROR: foundry cast not found at $CAST"
    exit 1
fi

echo "=== LEVER CONTRACT DATA TEST $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# Test market (SpaceX IPO from scripts)
MARKET_ID="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"

echo ""
echo "=== CORE FINANCIAL DATA ==="

# TVL from LeverVault
echo -n "TVL: "
TVL=$($CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$TVL" | grep -qi "error\|revert"; then
    echo "FAIL - $TVL"
else
    TVL_USDT=$(echo "scale=2; $TVL / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $TVL wei (~$TVL_USDT USDT)"
fi

# Global OI from OILimits
echo -n "Global OI: "
GLOBAL_OI=$($CAST call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$GLOBAL_OI" | grep -qi "error\|revert"; then
    echo "FAIL - $GLOBAL_OI"
else
    OI_USDT=$(echo "scale=2; $GLOBAL_OI / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $GLOBAL_OI wei (~$OI_USDT USDT notional)"
fi

# Insurance Fund Balance
echo -n "Insurance Fund: "
INS_BALANCE=$($CAST call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$INS_BALANCE" | grep -qi "error\|revert"; then
    echo "FAIL - $INS_BALANCE"
else
    INS_USDT=$(echo "scale=2; $INS_BALANCE / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $INS_BALANCE wei (~$INS_USDT USDT)"
fi

echo ""
echo "=== LEVERAGE DATA ==="

# Platform Ceiling
echo -n "Platform Ceiling: "
PLATFORM_CEILING=$($CAST call $LEVERAGE_MODEL 'getPlatformCeiling()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$PLATFORM_CEILING" | grep -qi "error\|revert"; then
    echo "FAIL - $PLATFORM_CEILING"
else
    CEILING_X=$(echo "scale=2; $PLATFORM_CEILING / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $PLATFORM_CEILING wei (~${CEILING_X}x)"
fi

# Market-specific max leverage
echo -n "Max Leverage (SpaceX): "
MAX_LEV=$($CAST call $LEVERAGE_MODEL 'getEffectiveMaxLeverage(bytes32)(uint256)' $MARKET_ID --rpc-url $RPC_URL 2>&1)
if echo "$MAX_LEV" | grep -qi "error\|revert"; then
    echo "FAIL - $MAX_LEV"
else
    LEV_X=$(echo "scale=2; $MAX_LEV / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $MAX_LEV wei (~${LEV_X}x)"
fi

echo ""
echo "=== UTILIZATION & CAPS ==="

# Global OI Cap
echo -n "Global OI Cap: "
GLOBAL_CAP=$($CAST call $OI_LIMITS 'getGlobalOICap()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$GLOBAL_CAP" | grep -qi "error\|revert"; then
    echo "FAIL - $GLOBAL_CAP"
else
    CAP_USDT=$(echo "scale=2; $GLOBAL_CAP / 1000000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $GLOBAL_CAP wei (~$CAP_USDT USDT)"
fi

# Global Utilization
echo -n "Global Utilization: "
GLOBAL_UTIL=$($CAST call $OI_LIMITS 'getGlobalUtilization()(uint256)' --rpc-url $RPC_URL 2>&1)
if echo "$GLOBAL_UTIL" | grep -qi "error\|revert"; then
    echo "FAIL - $GLOBAL_UTIL"
else
    UTIL_PCT=$(echo "scale=2; $GLOBAL_UTIL / 10000000000000000" | bc -l 2>/dev/null || echo "calc error")
    echo "✅ $GLOBAL_UTIL wei (~${UTIL_PCT}%)"
fi

echo ""
echo "=== CONTRACT ACCESSIBILITY ==="

# Test role-based access on key contracts
echo -n "Market Registry access: "
MR_ACCESS=$($CAST call $MARKET_REGISTRY 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)
echo "$MR_ACCESS" | grep -qi "true" && echo "✅ Admin role confirmed" || echo "FAIL - $MR_ACCESS"

echo -n "Position Manager access: "
PM_ACCESS=$($CAST call $POSITION_MANAGER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)
echo "$PM_ACCESS" | grep -qi "true" && echo "✅ Admin role confirmed" || echo "FAIL - $PM_ACCESS"

echo -n "Execution Engine access: "
EE_ACCESS=$($CAST call $EXECUTION_ENGINE 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)
echo "$EE_ACCESS" | grep -qi "true" && echo "✅ Admin role confirmed" || echo "FAIL - $EE_ACCESS"

echo ""
echo "=== RPC CONNECTION TEST ==="
echo -n "RPC Response Time: "
START_TIME=$(date +%s%3N)
TEST_CALL=$($CAST call $USDT_ADDRESS 'decimals()(uint8)' --rpc-url $RPC_URL 2>&1)
END_TIME=$(date +%s%3N)
RESPONSE_TIME=$((END_TIME - START_TIME))

if echo "$TEST_CALL" | grep -q "6"; then
    echo "✅ ${RESPONSE_TIME}ms (USDT decimals = 6)"
else
    echo "FAIL - ${RESPONSE_TIME}ms - $TEST_CALL"
fi

echo ""
echo "=== SUMMARY ==="
echo "All core contract data endpoints tested."
echo "Use this data structure for dashboard integration:"
echo "- TVL: \$LEVER_VAULT.totalAssets()"
echo "- Global OI: \$OI_LIMITS.getGlobalOI()"
echo "- Insurance: \$INSURANCE_FUND.getBalance()"
echo "- Max Leverage: \$LEVERAGE_MODEL.getEffectiveMaxLeverage(marketId)"
echo "- Utilization: \$OI_LIMITS.getGlobalUtilization()"