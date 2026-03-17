#!/bin/bash
# Check price timestamps for all markets to verify oracle keeper is working

cd "$(dirname "$0")"
cd ../..

export PATH="/home/lever/.foundry/bin:$PATH"
source control-plane/deploy-env.sh

echo "Checking price timestamps for all markets..."
echo "Oracle Adapter: $ORACLE_ADAPTER"
echo "Current time: $(date)"
echo "=========================="

current_time=$(date +%s)
ten_minutes_ago=$((current_time - 600))

# Extract market IDs from config
market_ids=($(jq -r '.[].marketId' scripts/oracle/market_config.json))

fresh_count=0
stale_count=0
error_count=0

for market_id in "${market_ids[@]}"; do
    market_name=$(jq -r --arg id "$market_id" '.[] | select(.marketId == $id) | .name' scripts/oracle/market_config.json | cut -c1-40)

    # Try to get price and timestamp from oracle
    result=$(cast call --rpc-url https://sepolia.base.org $ORACLE_ADAPTER "getPI(bytes32)" $market_id 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        # Parse the PI value
        pi_value_hex=$(echo $result | sed 's/0x//')
        pi_value_decimal=$(echo "ibase=16; ${pi_value_hex^^}" | bc)
        pi_float=$(echo "scale=6; $pi_value_decimal / 1000000000000000000" | bc)

        # Check timestamp
        timestamp_result=$(cast call --rpc-url https://sepolia.base.org $ORACLE_ADAPTER "getLastUpdate(bytes32)" $market_id 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$timestamp_result" ]; then
            timestamp_hex=$(echo $timestamp_result | sed 's/0x//')
            timestamp_decimal=$(echo "ibase=16; ${timestamp_hex^^}" | bc)

            if [ $timestamp_decimal -gt $ten_minutes_ago ]; then
                echo "✓ FRESH: $market_name | PI=$pi_float | Last update: $(date -d @$timestamp_decimal)"
                ((fresh_count++))
            else
                echo "✗ STALE: $market_name | PI=$pi_float | Last update: $(date -d @$timestamp_decimal)"
                ((stale_count++))
            fi
        else
            echo "? ERROR: $market_name | Could not get timestamp"
            ((error_count++))
        fi
    else
        echo "? ERROR: $market_name | Could not get PI"
        ((error_count++))
    fi
done

echo "=========================="
echo "Summary:"
echo "Fresh markets (< 10 min): $fresh_count"
echo "Stale markets (> 10 min): $stale_count"
echo "Error/unknown: $error_count"

if [ $fresh_count -eq 10 ]; then
    echo "✓ SUCCESS: All markets have fresh prices!"
    exit 0
elif [ $stale_count -gt 0 ]; then
    echo "✗ FAIL: Some markets have stale prices!"
    exit 1
else
    echo "? UNKNOWN: Could not verify all markets"
    exit 2
fi