#!/bin/bash

# Direct leverage parameter fix using cast calls
# Applies market risk parameter overrides to work around TVL decimal bug

export PATH="$PATH:/home/lever/.foundry/bin"
source control-plane/deploy-env.sh

# The old LeverageModel that ExecutionEngine actually uses
OLD_LEVERAGE_MODEL="0x63B98Ec1e559E3b24199eb2115F0a57222e9818c"

# Market IDs
SPACEX_MARKET="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"
US_IRAN_MARKET="0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a"
FIFA_SPAIN_MARKET="0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7"
ARGENTINA_MARKET="0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea"
FED_RATE_MARKET="0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554"

# Fixed parameters to maximize leverage despite TVL bug
SIGMA_BASELINE="50000000000000000"  # 5% baseline volatility (was 25%)
DEPTH_THRESHOLD="1000000000000000000"  # 1 USDT depth threshold (was 5)

echo "=== Applying Leverage Parameter Overrides ==="
echo "Old LeverageModel: $OLD_LEVERAGE_MODEL"
echo "Sigma Baseline: $SIGMA_BASELINE (5%)"
echo "Depth Threshold: $DEPTH_THRESHOLD (1 USDT)"
echo ""

function check_leverage() {
    local market_id=$1
    local market_name=$2

    echo "Checking $market_name leverage..."

    # getEffectiveMaxLeverage(bytes32) function
    local leverage_result=$(cast call $OLD_LEVERAGE_MODEL "getEffectiveMaxLeverage(bytes32)" $market_id --rpc-url $RPC_URL 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$leverage_result" ]; then
        # Convert from WAD to human readable
        local leverage_wad=$leverage_result
        local leverage=$(echo "scale=2; $leverage_wad / 1000000000000000000" | bc -l)
        echo "  Current leverage: ${leverage}x"
    else
        echo "  Could not read leverage"
    fi
}

function apply_market_fix() {
    local market_id=$1
    local market_name=$2

    echo "=== Fixing $market_name Market ==="

    # Check current leverage
    check_leverage $market_id $market_name

    # Apply parameter fix
    echo "Applying risk parameter override..."
    local result=$(cast send $OLD_LEVERAGE_MODEL "setMarketRiskParams(bytes32,uint256,uint256)" $market_id $SIGMA_BASELINE $DEPTH_THRESHOLD --private-key $PRIVATE_KEY --rpc-url $RPC_URL 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "  ✅ Parameters updated"

        # Check new leverage
        echo "Checking new leverage..."
        check_leverage $market_id $market_name
    else
        echo "  ❌ Failed to update parameters"
    fi

    echo ""
}

# Apply fixes to all markets
apply_market_fix $SPACEX_MARKET "SpaceX"
apply_market_fix $US_IRAN_MARKET "US-Iran"
apply_market_fix $FIFA_SPAIN_MARKET "FIFA Spain"
apply_market_fix $ARGENTINA_MARKET "Argentina"
apply_market_fix $FED_RATE_MARKET "Fed Rate"

echo "=== Fix Complete ==="
echo "Next step: Test position opening with high leverage"
echo "Run: node scripts/validate-high-leverage.js"