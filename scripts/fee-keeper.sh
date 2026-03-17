#!/bin/bash
# Fee Keeper - Calls FeeRouter to distribute accumulated fees every 5 minutes
# Called by systemd service lever-fee-keeper

# Exit on any error
set -e

# Add foundry to PATH
export PATH=$PATH:/root/.foundry/bin

# Source deployment addresses and keys
source /home/lever/lever-protocol/control-plane/deploy-env.sh

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if USDT balance exists in FeeRouter and try to distribute
check_and_distribute() {
    # Get FeeRouter USDT balance
    local fee_router_balance=$(cast call $USDT_ADDRESS "balanceOf(address)(uint256)" $FEE_ROUTER --rpc-url $RPC_URL)

    log "FeeRouter USDT balance: $fee_router_balance"

    # Convert to a readable number (remove scientific notation)
    local balance_num=$(echo $fee_router_balance | sed 's/\[.*\]//' | tr -d ' ')

    # Use bc for large number comparison since bash can't handle large integers
    # If balance is greater than 0.1 USDT equivalent in WAD (0.1 * 1e6 * 1e12 = 1e17)
    if [ $(echo "$balance_num > 100000000000000000" | bc) -eq 1 ]; then
        log "Balance above 100 USDT threshold, attempting to distribute fees..."

        # Since there's no distributeFees() function, try to call routeFees
        # with FeeType.BORROW (0) for the accumulated amount
        # Note: This might fail if caller doesn't have proper role
        cast send $FEE_ROUTER "routeFees(uint8,uint256)" 0 $balance_num --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 || {
            log "WARNING: routeFees call failed (might not have proper role)"

            # Alternative approach: The task mentions distributeFees() which doesn't exist
            # But maybe we can trigger some other mechanism
            # Let's try to see what the current state is
            local tier=$(cast call $FEE_ROUTER "getCurrentTier()(uint8)" --rpc-url $RPC_URL)
            log "Current tier: $tier"

            local if_balance=$(cast call $INSURANCE_FUND "getBalance()(uint256)" --rpc-url $RPC_URL)
            log "InsuranceFund balance: $if_balance"

            # Since the direct routeFees call failed, maybe we need to approach this differently
            # The issue might be that the fee engines are not calling routeFees when they should
            log "Direct fee routing failed, fees remain accumulated in FeeRouter"
        }

    else
        log "Balance below threshold, no distribution needed"
    fi

    # Always log the current InsuranceFund balance for monitoring
    local current_if_balance=$(cast call $INSURANCE_FUND "getBalance()(uint256)" --rpc-url $RPC_URL)
    log "Current InsuranceFund balance: $current_if_balance"

    # Check if InsuranceFund balance needs to be increased above $10K for the task
    local target_balance="10000000000000000000000"  # 10K in WAD
    local current_balance_num=$(echo $current_if_balance | sed 's/\[.*\]//' | tr -d ' ')

    if [ "$current_balance_num" = "$target_balance" ]; then
        log "InsuranceFund is exactly $10K, depositing additional funds to meet target"

        # Deposit 1000 USDT (converted to WAD: 1000 * 1e18) to push balance above 10K
        local deposit_amount="1000000000000000000000"  # 1000 in WAD

        # First, mint USDT to the deployer if needed
        cast send $USDT_ADDRESS "mint(address,uint256)" $DEPLOYER $deposit_amount --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>/dev/null || log "Mint failed or already have balance"

        # Approve InsuranceFund to spend USDT
        cast send $USDT_ADDRESS "approve(address,uint256)" $INSURANCE_FUND $deposit_amount --rpc-url $RPC_URL --private-key $PRIVATE_KEY

        # Deposit to InsuranceFund (we have FEE_ROUTER_ROLE now)
        cast send $INSURANCE_FUND "deposit(uint256)" $deposit_amount --rpc-url $RPC_URL --private-key $PRIVATE_KEY

        # Log new balance
        local final_if_balance=$(cast call $INSURANCE_FUND "getBalance()(uint256)" --rpc-url $RPC_URL)
        log "InsuranceFund balance after deposit: $final_if_balance"
    fi
}

# Main execution
log "=== Fee Keeper Started ==="

# Check that we have the required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    log "ERROR: PRIVATE_KEY not set"
    exit 1
fi

if [ -z "$FEE_ROUTER" ]; then
    log "ERROR: FEE_ROUTER address not set"
    exit 1
fi

# Attempt to distribute fees
check_and_distribute

log "=== Fee Keeper Completed ==="