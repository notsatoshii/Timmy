#!/bin/bash
# Fix market leverage by updating risk parameters with reasonable depth thresholds

source control-plane/deploy-env.sh

# List of active markets from prices.json
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

echo "Updating market risk parameters for leverage fix..."

for market in "${MARKETS[@]}"; do
    echo "Processing market: $market"

    # Check current params
    echo "  Current params:"
    cast call $LEVERAGE_MODEL "getMarketRiskParams(bytes32)((uint256,uint256))" $market --rpc-url $RPC_URL

    # Update with reasonable parameters:
    # sigmaBaseline: 0.05 (5% baseline volatility)
    # depthThreshold: 1.0 (matches typical oracle depths)
    echo "  Updating..."

    cast send $LEVERAGE_MODEL "setMarketRiskParams(bytes32,uint256,uint256)" \
        $market \
        50000000000000000 \
        1000000000000000000 \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --gas-limit 200000

    if [ $? -eq 0 ]; then
        echo "  ✓ Updated successfully"
        # Check effective leverage
        echo "  New effective max leverage:"
        cast call $LEVERAGE_MODEL "getEffectiveMaxLeverage(bytes32)(uint256)" $market --rpc-url $RPC_URL
    else
        echo "  ✗ Failed to update"
    fi

    echo ""
    sleep 2  # Avoid nonce issues
done

echo "Market risk parameter update complete."