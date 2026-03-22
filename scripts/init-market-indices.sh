#!/bin/bash
# Initialize fee engine indices for all active markets

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

echo "Initializing fee engine indices for all markets..."

for market in "${MARKETS[@]}"; do
    echo "Processing market: $market"

    # Initialize borrow fee index
    echo "  Initializing borrow fee index..."
    cast send $BORROW_FEE_ENGINE "initializeMarketIndex(bytes32)" $market \
        --rpc-url $RPC_URL --private-key $PRIVATE_KEY --gas-limit 150000 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "  ✓ Borrow fee index initialized"
    else
        echo "  - Borrow fee index already initialized or failed"
    fi

    # Initialize funding rate index
    echo "  Initializing funding rate index..."
    cast send $FUNDING_RATE_ENGINE "initializeMarketIndex(bytes32)" $market \
        --rpc-url $RPC_URL --private-key $PRIVATE_KEY --gas-limit 150000 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "  ✓ Funding rate index initialized"
    else
        echo "  - Funding rate index already initialized or failed"
    fi

    echo ""
    sleep 1  # Avoid nonce issues
done

echo "Index initialization complete."