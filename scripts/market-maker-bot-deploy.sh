#!/bin/bash
# Market Maker Bot Deployment Script
# Deploys all 3 market maker bots with 5x-10x leverage on both sides

set -e

REPO="/home/lever/lever-protocol"
cd "$REPO"

# Load environment
source control-plane/deploy-env.sh

# Bot configuration
MARKET_MAKER_KEYS=(
    "e650b182e7bc42e68feaf60d34d16095dfb5ebf7562dc71260d8779f13129998" # market_maker_000
    "3ccff497d95ce0a4c042149212d26fd3a7463aa81b8d332f58ca550f52256495" # market_maker_001
    "e2d9519c5f5aa1f261e46d8f58298beb889eef2a8430f505bb01803b4722757c" # market_maker_002
)

COLLATERAL_DEPOSIT=500000000000  # 500K USDT in 6 decimals

echo "=== Market Maker Bot Deployment ==="
echo "Deploying 3 market maker bots with 5x-10x leverage"
echo "Target markets: 5 (top volume)"
echo "Strategy: Both-sided liquidity provision"
echo ""

# Check that contracts are deployed
if [[ -z "$EXECUTION_ENGINE" ]]; then
    echo "ERROR: EXECUTION_ENGINE not set in deploy-env.sh"
    exit 1
fi

if [[ -z "$ACCOUNT_MANAGER" ]]; then
    echo "ERROR: ACCOUNT_MANAGER not set in deploy-env.sh"
    exit 1
fi

echo "Using contracts:"
echo "  ExecutionEngine: $EXECUTION_ENGINE"
echo "  AccountManager: $ACCOUNT_MANAGER"
echo "  USDT: $USDT_ADDRESS"
echo ""

# Deploy each market maker bot
for i in {0..2}; do
    echo "=== Market Maker Bot $i ==="

    PRIVATE_KEY=${MARKET_MAKER_KEYS[$i]}
    MM_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")

    echo "  Address: $MM_ADDRESS"

    # Check ETH balance
    ETH_BALANCE=$(cast balance "$MM_ADDRESS" --rpc-url "$RPC_URL")
    echo "  ETH balance: $ETH_BALANCE"

    if [[ "$ETH_BALANCE" == "0" ]]; then
        echo "  ERROR: No ETH for gas"
        continue
    fi

    # Check USDT balance
    USDT_BALANCE=$(cast call "$USDT_ADDRESS" "balanceOf(address)(uint256)" "$MM_ADDRESS" --rpc-url "$RPC_URL")
    echo "  USDT balance: $USDT_BALANCE"

    if [[ "$USDT_BALANCE" == "0" ]]; then
        echo "  ERROR: No USDT balance"
        continue
    fi

    # Check if already deposited to AccountManager
    ACCOUNT_BALANCE=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$MM_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
    echo "  AccountManager balance: $ACCOUNT_BALANCE"

    # Deposit collateral if needed
    if [[ "$ACCOUNT_BALANCE" == "0" ]] || [[ "$ACCOUNT_BALANCE" -lt "$COLLATERAL_DEPOSIT" ]]; then
        echo "  Depositing $COLLATERAL_DEPOSIT USDT to AccountManager..."

        # Approve USDT
        echo "    Approving USDT..."
        cast send "$USDT_ADDRESS" "approve(address,uint256)" "$ACCOUNT_MANAGER" "$COLLATERAL_DEPOSIT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" \
            --gas-limit 100000 > /dev/null

        sleep 1

        # Deposit to AccountManager
        echo "    Depositing to AccountManager..."
        cast send "$ACCOUNT_MANAGER" "deposit(uint256)" "$COLLATERAL_DEPOSIT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" \
            --gas-limit 200000 > /dev/null

        sleep 1

        # Verify deposit
        NEW_BALANCE=$(cast call "$ACCOUNT_MANAGER" "getBalance(address)(uint256)" "$MM_ADDRESS" --rpc-url "$RPC_URL")
        echo "    New AccountManager balance: $NEW_BALANCE"

        if [[ "$NEW_BALANCE" -ge "$COLLATERAL_DEPOSIT" ]]; then
            echo "    SUCCESS: Collateral deposited"
        else
            echo "    ERROR: Deposit failed"
            continue
        fi
    else
        echo "  Already has sufficient AccountManager balance"
    fi

    echo "  Market Maker Bot $i ready for trading"
    echo ""
done

echo "=== Market Maker Bot Summary ==="
echo "3 market maker bots deployed with:"
echo "- 500K USDT collateral each"
echo "- 5x-10x leverage range"
echo "- Both-sided positioning strategy"
echo "- Focus on top 5 markets"
echo ""
echo "To start market making activity:"
echo "  forge script script/MarketMakerActivity.s.sol --rpc-url \$RPC_URL --broadcast"
echo ""
echo "To run continuous market making:"
echo "  python3 scripts/seed/market_maker_bot.py"
echo ""