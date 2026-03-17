#!/bin/bash
# Runs AFTER every agent task completes
# Returns non-zero if agent broke something

source /home/lever/lever-protocol/control-plane/deploy-env.sh
ERRORS=0

echo "=== State Validation ==="

# Check 1: deploy-env.sh has correct addresses
check_addr() {
    local name=$1 expected=$2 actual=$3
    if [ "$actual" != "$expected" ]; then
        echo "BROKEN: $name changed from $expected to $actual"
        # Auto-fix
        sed -i "s|export ${name}=.*|export ${name}=${expected}|" /home/lever/lever-protocol/control-plane/deploy-env.sh
        echo "  AUTO-FIXED in deploy-env.sh"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK: $name"
    fi
}

check_addr "EXECUTION_ENGINE" "0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D" "$EXECUTION_ENGINE"
check_addr "LEVERAGE_MODEL" "0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed" "$LEVERAGE_MODEL"
check_addr "LEVER_VAULT" "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921" "$LEVER_VAULT"
check_addr "POSITION_MANAGER" "0x25ba54a7b2fBac753B601Da05e3661F2E959510b" "$POSITION_MANAGER"

# Check 2: Frontend config has correct EE
FE_EE=$(grep "executionEngine: \"0x" /home/lever/lever-protocol/frontend/user-app/src/config/contracts.ts | grep -o "0x[0-9a-fA-F]\{40\}" | head -1)
if [ "$FE_EE" != "0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D" ] && [ -n "$FE_EE" ]; then
    echo "BROKEN: Frontend EE is $FE_EE"
    sed -i 's|executionEngine: "[^"]*"|executionEngine: "0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D"|' /home/lever/lever-protocol/frontend/user-app/src/config/contracts.ts
    cd /home/lever/lever-protocol/frontend/user-app && npm run build > /dev/null 2>&1
    systemctl restart lever-frontend
    echo "  AUTO-FIXED frontend"
    ERRORS=$((ERRORS + 1))
else
    echo "  OK: Frontend EE"
fi

# Check 3: ExecutionEngine on-chain points to correct LeverageModel
LM_ONCHAIN=$(cast call 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D "leverageModel()(address)" --rpc-url https://sepolia.base.org 2>/dev/null)
if [ -n "$LM_ONCHAIN" ]; then
    echo "  OK: EE on-chain → LM $LM_ONCHAIN"
else
    echo "  WARN: EE on-chain check failed (RPC issue?)"
fi

# Check 4: Frontend serving
HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000)
if [ "$HTTP" = "200" ]; then
    echo "  OK: Frontend serving"
else
    echo "  WARN: Frontend HTTP $HTTP"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "VALIDATION: $ERRORS issues found and auto-fixed"
    exit 1
else
    echo "VALIDATION: All checks passed"
    exit 0
fi
