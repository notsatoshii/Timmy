#!/bin/bash
# Complete Oracle Keeper Verification Script
# Verifies all requirements from task 6

echo "=== ORACLE KEEPER VERIFICATION SCRIPT ==="
echo "Verifying all requirements for task 6..."
echo ""

PASS=0
FAIL=0

# Helper function for checks
check() {
    local name="$1"
    local condition="$2"

    if eval "$condition"; then
        echo "✅ PASS: $name"
        PASS=$((PASS+1))
    else
        echo "❌ FAIL: $name"
        FAIL=$((FAIL+1))
    fi
}

echo "1. Checking if mock_keeper.py process is running..."
check "mock_keeper_process_running" "pgrep -f mock_keeper.py > /dev/null"

echo ""
echo "2. Verifying price update freshness (within 5 minutes)..."
ORACLE_LOG="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"

if [ -f "$ORACLE_LOG" ]; then
    # Get the last successful push timestamp
    LAST_PUSH_LINE=$(grep "PUSHED:" "$ORACLE_LOG" | tail -n1)

    if [ -n "$LAST_PUSH_LINE" ]; then
        LAST_PUSH_TIME=$(echo "$LAST_PUSH_LINE" | cut -d'|' -f1 | tr -d ' ')

        # Convert to seconds for comparison
        CURRENT_SECONDS=$(date '+%s')
        PUSH_HOUR=$(echo "$LAST_PUSH_TIME" | cut -d':' -f1)
        PUSH_MIN=$(echo "$LAST_PUSH_TIME" | cut -d':' -f2)
        PUSH_SEC=$(echo "$LAST_PUSH_TIME" | cut -d':' -f3)

        TODAY_MIDNIGHT=$(date -d 'today 00:00:00' '+%s')
        PUSH_TIMESTAMP=$((TODAY_MIDNIGHT + PUSH_HOUR*3600 + PUSH_MIN*60 + PUSH_SEC))

        TIME_DIFF=$((CURRENT_SECONDS - PUSH_TIMESTAMP))

        echo "   Last successful price push: $LAST_PUSH_TIME (${TIME_DIFF}s ago)"

        check "price_updates_fresh" "[ $TIME_DIFF -le 300 ]"  # 5 minutes = 300 seconds
    else
        echo "❌ FAIL: No successful price pushes found in log"
        FAIL=$((FAIL+1))
    fi
else
    echo "❌ FAIL: Oracle log file not found at $ORACLE_LOG"
    FAIL=$((FAIL+1))
fi

echo ""
echo "3. Checking systemd service file exists..."
SERVICE_FILE="/home/lever/lever-protocol/control-plane/lever-oracle-keeper.service"
check "systemd_service_file_exists" "[ -f '$SERVICE_FILE' ]"

if [ -f "$SERVICE_FILE" ]; then
    echo "   Service file contents preview:"
    head -n 5 "$SERVICE_FILE" | sed 's/^/   /'
fi

echo ""
echo "4. Checking systemd installation script exists..."
INSTALL_SCRIPT="/home/lever/lever-protocol/control-plane/install-oracle-keeper-systemd.sh"
check "systemd_install_script_exists" "[ -f '$INSTALL_SCRIPT' ] && [ -x '$INSTALL_SCRIPT' ]"

echo ""
echo "5. Testing price staleness detection in health-check.sh..."
cd /home/lever/lever-protocol
HEALTH_OUTPUT=$(bash control-plane/health-check.sh 2>/dev/null)
HEALTH_EXIT=$?

if [ $HEALTH_EXIT -eq 0 ]; then
    # Check specifically for oracle keeper checks
    if echo "$HEALTH_OUTPUT" | grep -q "PASS: oracle_keeper_process"; then
        echo "✅ PASS: health-check.sh detects oracle keeper process"
        PASS=$((PASS+1))
    else
        echo "❌ FAIL: health-check.sh does not detect oracle keeper process"
        FAIL=$((FAIL+1))
    fi

    if echo "$HEALTH_OUTPUT" | grep -q "PASS: oracle_price_freshness"; then
        echo "✅ PASS: health-check.sh detects fresh price updates"
        PASS=$((PASS+1))
    else
        echo "❌ FAIL: health-check.sh does not detect fresh price updates"
        FAIL=$((FAIL+1))
    fi
else
    echo "❌ FAIL: health-check.sh failed with exit code $HEALTH_EXIT"
    FAIL=$((FAIL+2))
fi

echo ""
echo "6. Additional checks..."

# Check if oracle adapter contract is accessible
source control-plane/deploy-env.sh
ORACLE_RESPONSE=$(/home/lever/.foundry/bin/cast call $ORACLE_ADAPTER 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC_URL 2>&1)
check "oracle_adapter_accessible" "echo '$ORACLE_RESPONSE' | grep -q 'true'"

# Check keeper configuration
KEEPER_CONFIG="/home/lever/lever-protocol/scripts/oracle/market_config.json"
check "keeper_market_config_exists" "[ -f '$KEEPER_CONFIG' ]"

if [ -f "$KEEPER_CONFIG" ]; then
    MARKET_COUNT=$(jq length "$KEEPER_CONFIG" 2>/dev/null || echo "0")
    echo "   Market config contains $MARKET_COUNT markets"
    check "markets_configured" "[ '$MARKET_COUNT' -gt 0 ]"
fi

echo ""
echo "=== VERIFICATION SUMMARY ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✅ ALL CHECKS PASSED - Oracle Keeper is properly configured and running!"
    echo ""
    echo "To install systemd service (requires sudo):"
    echo "  sudo bash $INSTALL_SCRIPT"
    exit 0
else
    echo "❌ Some checks failed. Review the output above."
    exit 1
fi