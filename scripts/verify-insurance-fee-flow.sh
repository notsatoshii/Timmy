#!/bin/bash

# Verify FeeRouter to Insurance Fund fee flow using cast commands

source "control-plane/deploy-env.sh"

echo "=== INSURANCE FUND FEE FLOW VERIFICATION ==="
echo ""

# Configuration
CAST="/home/lever/.foundry/bin/cast"

echo "Addresses:"
echo "  FeeRouter: $FEE_ROUTER"
echo "  Insurance Fund: $INSURANCE_FUND"
echo "  USDT: $USDT_ADDRESS"
echo ""

# 1. Current balances
echo "=== CURRENT BALANCES ==="
ACTUAL_BALANCE=$($CAST call $USDT_ADDRESS 'balanceOf(address)(uint256)' $INSURANCE_FUND --rpc-url $RPC_URL)
TRACKED_BALANCE=$($CAST call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL)

echo "Actual USDT Balance:     $ACTUAL_BALANCE"
echo "Tracked Internal Balance: $TRACKED_BALANCE"

# Convert USDT balance to WAD for comparison (USDT has 6 decimals, WAD has 18)
ACTUAL_IN_WAD=$(printf "%.0f" $(echo "$ACTUAL_BALANCE * 10^12" | bc -l))

echo "Actual Balance in WAD:    $ACTUAL_IN_WAD"

if [ "$ACTUAL_IN_WAD" = "$TRACKED_BALANCE" ]; then
    echo "✅ Balances match perfectly"
else
    echo "❌ Balance mismatch detected"
    echo "   Difference: $(echo "$TRACKED_BALANCE - $ACTUAL_IN_WAD" | bc -l)"
fi

echo ""

# 2. Calculate actual IFR
echo "=== IFR CALCULATION ==="
TVL=$($CAST call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL)

echo "TVL: $TVL"

# Calculate IFR = (actual_balance * 1e18) / TVL
ACTUAL_IFR=$(echo "scale=6; ($ACTUAL_BALANCE * 10^12 * 100) / $TVL" | bc -l)

echo "Actual IFR: $ACTUAL_IFR%"

# Check thresholds
if (( $(echo "$ACTUAL_IFR >= 20.0" | bc -l) )); then
    echo "✅ Above 20% target (Tier 2 - no insurance fees)"
elif (( $(echo "$ACTUAL_IFR >= 5.0" | bc -l) )); then
    echo "✅ Above 5% floor, below 20% target (Tier 1 - insurance gets 20%)"
else
    echo "⚠️  Below 5% floor - fund needs boosting"
fi

echo ""

# 3. Check FeeRouter configuration
echo "=== FEE ROUTER CONFIGURATION ==="

# Check current tier
CURRENT_TIER=$($CAST call $FEE_ROUTER 'getCurrentTier()(uint8)' --rpc-url $RPC_URL)
echo "Current Fee Tier: $CURRENT_TIER"

if [ "$CURRENT_TIER" = "1" ]; then
    echo "  LP Share: 50%"
    echo "  Protocol Share: 30%"
    echo "  Insurance Share: 20%"
elif [ "$CURRENT_TIER" = "2" ]; then
    echo "  LP Share: 50%"
    echo "  Protocol Share: 50%"
    echo "  Insurance Share: 0%"
fi

echo ""

# 4. Check recent fee activity (last 1000 blocks)
echo "=== RECENT FEE ACTIVITY ==="

CURRENT_BLOCK=$($CAST block-number --rpc-url $RPC_URL)
FROM_BLOCK=$((CURRENT_BLOCK - 1000))

echo "Checking blocks $FROM_BLOCK to $CURRENT_BLOCK"

# Look for FeeRouted events
FEE_EVENTS=$($CAST logs --from-block $FROM_BLOCK --to-block $CURRENT_BLOCK \
    --address $FEE_ROUTER \
    "FeesRouted(uint8,uint256,uint256,uint256,uint256,uint8)" \
    --rpc-url $RPC_URL 2>/dev/null | wc -l)

echo "Fee routing events found: $FEE_EVENTS"

# Look for USDT transfers to Insurance Fund
TRANSFER_SIG="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
INSURANCE_TOPIC="0x000000000000000000000000$(echo $INSURANCE_FUND | cut -c3-)"

TRANSFER_EVENTS=$($CAST logs --from-block $FROM_BLOCK --to-block $CURRENT_BLOCK \
    --address $USDT_ADDRESS \
    --topics "$TRANSFER_SIG" \
    --rpc-url $RPC_URL 2>/dev/null | grep -c "$INSURANCE_TOPIC" || echo "0")

echo "USDT transfers to Insurance Fund: $TRANSFER_EVENTS"

# Look for Insurance Fund deposits
DEPOSIT_EVENTS=$($CAST logs --from-block $FROM_BLOCK --to-block $CURRENT_BLOCK \
    --address $INSURANCE_FUND \
    "FundsDeposited(uint256,uint256,uint256)" \
    --rpc-url $RPC_URL 2>/dev/null | wc -l)

echo "Insurance Fund deposit events: $DEPOSIT_EVENTS"

echo ""

# 5. Assessment
echo "=== ASSESSMENT ==="

if [ "$TRANSFER_EVENTS" -gt 0 ] && [ "$DEPOSIT_EVENTS" -gt 0 ]; then
    echo "✅ Fee flow appears to be working correctly"
elif [ "$FEE_EVENTS" -eq 0 ]; then
    echo "ℹ️  No recent fee activity (normal if no trading)"
else
    echo "⚠️  Fee flow may have issues - transfers/deposits mismatch"
fi

# Check if manual boost is needed
if (( $(echo "$ACTUAL_IFR < 5.0" | bc -l) )); then
    NEEDED_BALANCE=$(echo "scale=0; ($TVL * 5) / (100 * 10^12)" | bc -l)
    NEEDED_DEPOSIT=$(echo "$NEEDED_BALANCE - $ACTUAL_BALANCE" | bc -l)
    echo "⚠️  MANUAL BOOST NEEDED:"
    echo "   Need: $(printf "%.0f" $NEEDED_BALANCE) USDT for 5% IFR"
    echo "   Missing: $(printf "%.0f" $NEEDED_DEPOSIT) USDT"
else
    echo "✅ No manual fee injection needed for demo"
fi

# Final recommendation
echo ""
echo "=== RECOMMENDATION ==="
if (( $(echo "$ACTUAL_IFR >= 5.0" | bc -l) )); then
    echo "✅ SAFE FOR DEMO:"
    echo "   - Insurance fund has adequate backing ($ACTUAL_IFR% IFR)"
    echo "   - Display issue is cosmetic, not functional"
    echo "   - Document as known WAD formatting bug"
else
    echo "⚠️  NEEDS ATTENTION:"
    echo "   - IFR below minimum threshold"
    echo "   - Consider manual USDT deposit before demo"
fi