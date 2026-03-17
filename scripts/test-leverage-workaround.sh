#!/bin/bash
# Test script to investigate leverage limitation workarounds
# Since contract redeployment is restricted, this explores parameter overrides and new market creation

source /home/lever/lever-protocol/control-plane/deploy-env.sh

CAST="/home/lever/.foundry/bin/cast"
echo "=== LEVERAGE LIMITATION WORKAROUND TEST ==="
echo "Date: $(date -u)"
echo ""

# Current problematic market
MARKET_ID="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"

echo "=== 1. Current Market Analysis ==="
echo "Market ID: $MARKET_ID"
echo "Platform Ceiling: $($CAST call $LEVERAGE_MODEL 'getPlatformCeiling()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
echo "Market Max Leverage: $($CAST call $LEVERAGE_MODEL 'getEffectiveMaxLeverage(bytes32)(uint256)' $MARKET_ID --rpc-url $RPC_URL 2>/dev/null)"
echo "M_market Adjustment: $($CAST call $LEVERAGE_MODEL 'getMarketAdjustment(bytes32)(uint256)' $MARKET_ID --rpc-url $RPC_URL 2>/dev/null)"

echo ""
echo "=== 2. Admin Function Investigation ==="

# Check for admin override functions
echo "Checking for admin override functions..."

# Test if LeverageModel has override functions
echo -n "setMarketAdjustment function: "
$CAST call $LEVERAGE_MODEL 'setMarketAdjustment(bytes32,uint256)' $MARKET_ID 1000000000000000000 --rpc-url $RPC_URL 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"

echo -n "setBaseMaxLeverage function: "
$CAST call $LEVERAGE_MODEL 'setBaseMaxLeverage(uint256)' 30000000000000000000 --rpc-url $RPC_URL 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"

echo -n "Emergency override function: "
$CAST call $LEVERAGE_MODEL 'setEmergencyMode(bool)' true --rpc-url $RPC_URL 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"

echo ""
echo "=== 3. Market Creation Test ==="

# Get current timestamp + 30 days for a test market
FUTURE_TIMESTAMP=$(($(date +%s) + 2592000))
echo "Testing new market creation with future timestamp: $FUTURE_TIMESTAMP"

# Note: This is just a test call, not actual creation (would require admin rights)
echo "Note: Actual market creation requires admin permissions and proper market setup"
echo "Would create market with resolution timestamp: $FUTURE_TIMESTAMP"

echo ""
echo "=== 4. Parameter Analysis ==="

# Check various parameters that could affect leverage
echo "Checking parameter sources..."
echo "TVL: $($CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
echo "Global OI: $($CAST call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
echo "Insurance Fund: $($CAST call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"
echo "Global Utilization: $($CAST call $OI_LIMITS 'getGlobalUtilization()(uint256)' --rpc-url $RPC_URL 2>/dev/null)"

echo ""
echo "=== 5. Alternative Markets Check ==="

# Check if there are other markets that might work better
echo "Checking for other registered markets..."
# This would require iterating through market IDs or having a market list function

echo ""
echo "=== SUMMARY ==="
echo "1. Current market M_market = 0.001 (causing 1x limit)"
echo "2. Platform ceiling is normal (~19.45x)"
echo "3. Issue appears to be market-specific timestamp/configuration problem"
echo "4. Workaround options:"
echo "   - Admin parameter override (if functions exist)"
echo "   - New market with correct timestamp"
echo "   - Frontend warning + demo with 1x only"
echo ""
echo "See /home/lever/lever-protocol/control-plane/position-opening-limitation-report.md for details"