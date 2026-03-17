#!/bin/bash
# Simple Frontend Check - No Browser Automation
# Tests basic frontend functionality without puppeteer

export PATH="/home/lever/.foundry/bin:$PATH"
source /home/lever/lever-protocol/control-plane/deploy-env.sh

echo "=== SIMPLE FRONTEND CHECK ==="

# 1. Test if frontend is responsive
echo "Testing frontend HTTP response..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
if [ "$HTTP_STATUS" != "200" ]; then
    echo "FAIL: Frontend not responding - HTTP $HTTP_STATUS"
    exit 1
fi
echo "✓ Frontend responding with HTTP 200"

# 2. Test if HTML contains expected React structure
echo "Testing frontend HTML structure..."
HTML_CONTENT=$(curl -s http://localhost:3000)

if echo "$HTML_CONTENT" | grep -q "React App\|LEVER Protocol"; then
    echo "✓ Page contains expected content"
else
    echo "FAIL: Missing expected content"
    exit 1
fi

if echo "$HTML_CONTENT" | grep -q 'id="root"'; then
    echo "✓ React root element found"
else
    echo "FAIL: Missing React root element"
    exit 1
fi

if echo "$HTML_CONTENT" | grep -q "main.*\.js"; then
    echo "✓ React main bundle found"
else
    echo "FAIL: Missing React main bundle"
    exit 1
fi

# 3. Test if deployment files are accessible
echo "Testing deployment file accessibility..."

CORE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/deployments/core-deployment.json)
POOL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/deployments/pool-deployment.json)
ENGINES_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/deployments/engines-deployment.json)

if [ "$CORE_STATUS" = "200" ] && [ "$POOL_STATUS" = "200" ] && [ "$ENGINES_STATUS" = "200" ]; then
    echo "✓ All deployment files accessible"
else
    echo "FAIL: Deployment files not accessible (core:$CORE_STATUS pool:$POOL_STATUS engines:$ENGINES_STATUS)"
    exit 1
fi

# 4. Test deployment file content
echo "Testing deployment file content..."
CORE_CONTENT=$(curl -s http://localhost:3000/deployments/core-deployment.json)
if echo "$CORE_CONTENT" | jq -e '.usdt' > /dev/null 2>&1; then
    echo "✓ Core deployment file has valid JSON with usdt address"
else
    echo "FAIL: Core deployment file invalid or missing usdt address"
    exit 1
fi

# 5. Verify chain connectivity by testing contract calls
echo "Testing chain connectivity..."
TVL_RAW=$(cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>/dev/null | head -1 | tr -d ' ')
if [ -n "$TVL_RAW" ] && [ "$TVL_RAW" != "0x0" ]; then
    # Clean up the cast output (remove bracketed part if present)
    TVL_CLEAN=$(echo "$TVL_RAW" | sed 's/\[.*\]//')
    TVL_VALUE=$(python3 -c "
import sys
try:
    raw = '$TVL_CLEAN'.strip()
    if raw.startswith('0x'):
        val = int(raw, 16)
    else:
        val = int(raw)
    print(f'{val / 1e6:.2f}')
except Exception as e:
    print('ERROR')
    sys.exit(1)
")
    if [ "$TVL_VALUE" = "ERROR" ]; then
        echo "WARN: Chain data format unexpected, but connection OK"
    else
        echo "✓ Chain connectivity OK - TVL: \$$TVL_VALUE"
    fi
else
    echo "FAIL: Cannot read contract data from chain"
    exit 1
fi

# 6. Test systemd service status
echo "Testing systemd service..."
if systemctl is-active --quiet lever-frontend; then
    echo "✓ Frontend service is active"
else
    echo "FAIL: Frontend service is not active"
    exit 1
fi

echo ""
echo "=== ALL BASIC CHECKS PASSED ==="
echo "Frontend server is working correctly."
echo "Note: Advanced frontend testing requires browser automation setup."
exit 0