#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh 2>/dev/null

echo "=== PREFLIGHT CHECK $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
ISSUES=0

# Deployer ETH
echo -n "Deployer ETH: "
DEP_BAL=$(cast balance $DEPLOYER --rpc-url $RPC_URL 2>&1)
if echo "$DEP_BAL" | grep -qi "error"; then
    echo "CANT CHECK (RPC down?)"
    ISSUES=$((ISSUES+1))
else
    echo "$DEP_BAL"
fi

# Test wallet
if [ -f /home/lever/lever-protocol/.env.testwallet ]; then
    TEST_ADDR=$(cast wallet address --private-key $TEST_WALLET_KEY 2>/dev/null)
    echo -n "Test wallet ($TEST_ADDR) ETH: "
    TEST_BAL=$(cast balance $TEST_ADDR --rpc-url $RPC_URL 2>&1)
    echo "$TEST_BAL"
    echo -n "Test wallet USDT: "
    cast call $USDT_ADDRESS "balanceOf(address)(uint256)" $TEST_ADDR --rpc-url $RPC_URL 2>&1
else
    echo "WARNING: No test wallet at .env.testwallet"
    ISSUES=$((ISSUES+1))
fi

# Frontend
echo -n "Frontend (3000): "
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
if [ "$HTTP" = "200" ]; then echo "UP"; else echo "DOWN"; ISSUES=$((ISSUES+1)); fi

# Dashboard
echo -n "Dashboard (8080): "
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null)
if [ "$HTTP" = "200" ]; then echo "UP"; else echo "DOWN"; ISSUES=$((ISSUES+1)); fi

# Contracts
echo -n "Vault TVL: "
cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL 2>&1 | head -1

echo -n "MarketRegistry: "
cast call $MARKET_REGISTRY "owner()(address)" --rpc-url $RPC_URL 2>&1 | head -1

# File ownership
OWNER=$(stat -c '%U' /home/lever/lever-protocol/control-plane/build-plan.md 2>/dev/null)
if [ "$OWNER" != "lever" ]; then
    echo "WARNING: Files owned by $OWNER, not lever"
    ISSUES=$((ISSUES+1))
fi

# Stale addresses
STALE=$(grep -r "0x13e01E\|0xf846E3\|0x1acab9\|0x463697\|0x4F0224\|0xe0f420\|0x5D538d" /home/lever/lever-protocol/script/ 2>/dev/null | wc -l)
if [ "$STALE" -gt 0 ]; then echo "WARNING: $STALE stale addresses in scripts"; ISSUES=$((ISSUES+1)); fi

# Puppeteer
if [ -d /home/lever/lever-protocol/frontend/user-app/node_modules/puppeteer ] || [ -d /home/lever/lever-protocol/node_modules/puppeteer ]; then
    echo "Puppeteer: installed"
else
    echo "WARNING: Puppeteer not found"
    ISSUES=$((ISSUES+1))
fi

echo ""
if [ "$ISSUES" -gt 0 ]; then
    echo "=== PREFLIGHT: $ISSUES ISSUES ==="
    exit 1
else
    echo "=== PREFLIGHT: ALL CLEAR ==="
    exit 0
fi
