#!/bin/bash
# LEVER Protocol — Real Data Display Validator
# Checks on-chain values and validates what the frontend would show.
# Uses cast calls against live contracts. No browser required.
# Exit 1 = data issues found, Exit 0 = all values in expected range.

set -e
source /home/lever/lever-protocol/control-plane/deploy-env.sh

PASS=0
FAIL=0
WARN=0
ISSUES=""

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); ISSUES="$ISSUES\n  - $1"; }
warn() { echo "  WARN: $1"; WARN=$((WARN+1)); }

echo "============================================"
echo "LEVER Protocol — Data Display Validator"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

# --- 1. TVL (totalAssets, 6 decimal USDT) ---
echo ""
echo "=== TVL ==="
TVL_RAW=$(cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
TVL_DOLLARS=$(echo "scale=2; $TVL_RAW / 1000000" | bc 2>/dev/null)
echo "  Raw: $TVL_RAW (6 dec USDT)"
echo "  Display: \$$TVL_DOLLARS"

if (( $(echo "$TVL_DOLLARS > 100000" | bc -l) )); then
    pass "TVL is \$$TVL_DOLLARS (above \$100K minimum)"
elif (( $(echo "$TVL_DOLLARS > 10000" | bc -l) )); then
    warn "TVL is \$$TVL_DOLLARS (below \$100K, above \$10K)"
else
    fail "TVL is \$$TVL_DOLLARS (too low for investor demo, expected >\$100K)"
fi

# --- 2. Total Supply (shares, 6 decimal) ---
echo ""
echo "=== Vault Shares ==="
SUPPLY_RAW=$(cast call $LEVER_VAULT "totalSupply()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
SUPPLY_SHARES=$(echo "scale=2; $SUPPLY_RAW / 1000000" | bc 2>/dev/null)
echo "  Raw: $SUPPLY_RAW"
echo "  Shares: $SUPPLY_SHARES"

if [ "$SUPPLY_RAW" != "0" ]; then
    pass "Total supply is non-zero ($SUPPLY_SHARES shares)"
else
    fail "Total supply is zero — vault has no deposits"
fi

# --- 3. Share Price ---
echo ""
echo "=== Share Price ==="
# Call convertToAssets(1e6) to get USDT per 1 share (both 6 dec)
SP_RAW=$(cast call $LEVER_VAULT "convertToAssets(uint256)(uint256)" "1000000" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
SP_DOLLARS=$(echo "scale=6; $SP_RAW / 1000000" | bc 2>/dev/null)
echo "  convertToAssets(1e6) = $SP_RAW"
echo "  Share price: \$$SP_DOLLARS"

if (( $(echo "$SP_DOLLARS >= 0.90 && $SP_DOLLARS <= 1.10" | bc -l) )); then
    pass "Share price \$$SP_DOLLARS is within normal range (0.90-1.10)"
elif (( $(echo "$SP_DOLLARS >= 0.50 && $SP_DOLLARS <= 2.00" | bc -l) )); then
    warn "Share price \$$SP_DOLLARS is outside normal but within bounds"
else
    fail "Share price \$$SP_DOLLARS is abnormal (expected ~\$1.00)"
fi

# --- 4. Global OI ---
echo ""
echo "=== Global Open Interest ==="
OI_RAW=$(cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
OI_DOLLARS=$(echo "scale=2; $OI_RAW / 1000000" | bc 2>/dev/null)
echo "  Raw: $OI_RAW"
echo "  Display: \$$OI_DOLLARS"

# Check OI format — if OI_RAW is huge (>1e15), it might be WAD not USDT
if (( $(echo "$OI_RAW > 1000000000000000" | bc -l) )); then
    # Likely WAD format
    OI_DOLLARS_WAD=$(echo "scale=2; $OI_RAW / 1000000000000000000" | bc 2>/dev/null)
    warn "OI raw value $OI_RAW looks like WAD format, not USDT. Dollar value if WAD: \$$OI_DOLLARS_WAD"
    OI_DOLLARS=$OI_DOLLARS_WAD
fi

# Utilization check
if [ "$TVL_DOLLARS" != "0" ] && [ "$TVL_DOLLARS" != "" ]; then
    UTIL=$(echo "scale=2; $OI_DOLLARS * 100 / $TVL_DOLLARS" | bc 2>/dev/null)
    echo "  Utilization: ${UTIL}%"
    if (( $(echo "$UTIL > 100" | bc -l) )); then
        fail "Utilization ${UTIL}% exceeds 100% — OI exceeds TVL (should be capped at 60%)"
    elif (( $(echo "$UTIL > 60" | bc -l) )); then
        warn "Utilization ${UTIL}% exceeds 60% cap"
    else
        pass "Utilization ${UTIL}% is within bounds"
    fi
fi

# --- 5. Insurance Fund ---
echo ""
echo "=== Insurance Fund ==="
INS_RAW=$(cast call $INSURANCE_FUND "getBalance()(uint256)" --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
echo "  Raw: $INS_RAW"
echo "  Raw length: ${#INS_RAW} digits"

# Insurance fund stores in WAD (18 decimals)
INS_DOLLARS=$(echo "scale=2; $INS_RAW / 1000000000000000000" | bc 2>/dev/null)
echo "  As WAD: \$$INS_DOLLARS"

# Frontend does WAD -> USDT conversion: divide by 1e12, then formatUsdt divides by 1e6
INS_USDT_FORMAT=$(echo "scale=0; $INS_RAW / 1000000000000" | bc 2>/dev/null)
INS_DISPLAY=$(echo "scale=2; $INS_USDT_FORMAT / 1000000" | bc 2>/dev/null)
echo "  Frontend would show: \$$INS_DISPLAY (after WAD->USDT conversion)"

if (( $(echo "$INS_DOLLARS == $INS_DISPLAY" | bc -l 2>/dev/null || echo 0) )); then
    pass "Insurance fund conversion is consistent (\$$INS_DOLLARS)"
else
    # Check if they're close (within 1%)
    DIFF=$(echo "scale=6; ($INS_DOLLARS - $INS_DISPLAY) / $INS_DOLLARS * 100" | bc 2>/dev/null || echo "999")
    ABS_DIFF=$(echo "$DIFF" | tr -d '-')
    if (( $(echo "$ABS_DIFF < 1" | bc -l) )); then
        pass "Insurance fund conversion OK (WAD: \$$INS_DOLLARS, display: \$$INS_DISPLAY, diff: ${ABS_DIFF}%)"
    else
        fail "Insurance fund display mismatch — actual: \$$INS_DOLLARS, frontend shows: \$$INS_DISPLAY"
    fi
fi

if (( $(echo "$INS_DOLLARS >= 1000" | bc -l) )); then
    pass "Insurance fund \$$INS_DOLLARS is above minimum (\$1K)"
else
    warn "Insurance fund \$$INS_DOLLARS is below \$1K"
fi

# --- 6. Borrow Rate ---
echo ""
echo "=== Borrow Rate ==="
SPACEX_MKT="0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1"
BR_RAW=$(cast call $BORROW_FEE_ENGINE "getCurrentBorrowRate(bytes32,bool)(uint256)" "$SPACEX_MKT" true --rpc-url $RPC_URL 2>/dev/null | tr -d '[:space:]' | sed 's/\[.*\]//')
echo "  Raw: $BR_RAW (WAD per hour)"
# Convert to percentage: BR_RAW / 1e18 * 100
BR_PCT=$(echo "scale=6; $BR_RAW / 1000000000000000000 * 100" | bc 2>/dev/null)
echo "  Rate: ${BR_PCT}% per hour"

if (( $(echo "$BR_PCT > 0 && $BR_PCT < 1" | bc -l) )); then
    pass "Borrow rate ${BR_PCT}%/hr is reasonable"
elif [ "$BR_RAW" == "0" ]; then
    warn "Borrow rate is 0 — may indicate market not active"
else
    warn "Borrow rate ${BR_PCT}%/hr — verify this is expected"
fi

# --- 7. APY Sanity Check ---
echo ""
echo "=== APY Display ==="
# Calculate what APY the frontend would show
if [ "$TVL_DOLLARS" != "0" ] && [ "$OI_DOLLARS" != "" ]; then
    # APY = (borrow_rate * OI * 8760 * 0.5) / TVL * 100
    APY_RAW=$(echo "scale=4; $BR_PCT / 100 * $OI_DOLLARS * 8760 * 0.5 / $TVL_DOLLARS * 100" | bc 2>/dev/null)
    echo "  Projected APY: ${APY_RAW}%"

    if (( $(echo "$APY_RAW > 200" | bc -l) )); then
        fail "APY projection ${APY_RAW}% exceeds 200% cap — will display as capped/0% (OI/TVL imbalance)"
    elif (( $(echo "$APY_RAW > 50" | bc -l) )); then
        warn "APY ${APY_RAW}% is high — verify this is expected"
    elif (( $(echo "$APY_RAW >= 0" | bc -l) )); then
        pass "APY ${APY_RAW}% is reasonable"
    fi
fi

# --- 8. Oracle Prices ---
# (renumbered from 7)
echo ""
echo "=== Oracle Prices ==="
PRICES_FILE="/home/lever/lever-protocol/frontend/user-app/public/prices.json"
if [ -f "$PRICES_FILE" ]; then
    PRICE_COUNT=$(node -e "const p=require('$PRICES_FILE'); console.log(Object.keys(p.prices).length)" 2>/dev/null)
    LAST_UPDATE=$(node -e "const p=require('$PRICES_FILE'); const age=Math.floor(Date.now()/1000)-p.lastUpdate; console.log(age)" 2>/dev/null)
    echo "  Markets with prices: $PRICE_COUNT"
    echo "  Price age: ${LAST_UPDATE}s"

    if [ "$PRICE_COUNT" -ge 5 ]; then
        pass "Have $PRICE_COUNT market prices"
    else
        fail "Only $PRICE_COUNT market prices (need at least 5)"
    fi

    if [ "$LAST_UPDATE" -lt 3600 ]; then
        pass "Prices are fresh (${LAST_UPDATE}s old)"
    elif [ "$LAST_UPDATE" -lt 86400 ]; then
        warn "Prices are ${LAST_UPDATE}s old (>1hr)"
    else
        fail "Prices are stale (${LAST_UPDATE}s old, >24hr)"
    fi

    # Check price values are in valid range (0-1)
    INVALID_PRICES=$(node -e "
        const p=require('$PRICES_FILE');
        let bad=0;
        for (const [k,v] of Object.entries(p.prices)) {
            if (v.probability < 0 || v.probability > 1) bad++;
        }
        console.log(bad);
    " 2>/dev/null)
    if [ "$INVALID_PRICES" == "0" ]; then
        pass "All prices in valid range [0,1]"
    else
        fail "$INVALID_PRICES prices outside valid range"
    fi
else
    fail "prices.json not found"
fi

# --- 8. Frontend Serving ---
echo ""
echo "=== Frontend Health ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
if [ "$HTTP_STATUS" == "200" ]; then
    pass "Frontend returns HTTP 200"
else
    fail "Frontend returns HTTP $HTTP_STATUS"
fi

# Check if JS bundle loads
JS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/static/js/ 2>/dev/null)
if [ "$JS_STATUS" == "200" ]; then
    pass "JS assets accessible"
else
    warn "JS assets returned HTTP $JS_STATUS"
fi

# Check deployment JSONs are accessible
CORE_DEPLOY=$(curl -s http://localhost:3000/deployments/core-deployment.json 2>/dev/null)
POOL_DEPLOY=$(curl -s http://localhost:3000/deployments/pool-deployment.json 2>/dev/null)
if echo "$CORE_DEPLOY" | grep -q "positionManager\|marketRegistry" 2>/dev/null && echo "$POOL_DEPLOY" | grep -q "leverVault\|insuranceFund" 2>/dev/null; then
    pass "Deployment JSONs contain expected contract data"
else
    warn "Deployment JSONs may not have expected contract data"
fi

# --- 9. Contract Address Consistency ---
echo ""
echo "=== Address Consistency ==="
DEPLOY_VAULT=$(curl -s http://localhost:3000/deployments/pool-deployment.json 2>/dev/null | node -e "
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
        try{const j=JSON.parse(d);console.log(j.LeverVault||j.leverVault||'NOT_FOUND')}
        catch(e){console.log('PARSE_ERROR')}
    })" 2>/dev/null)
echo "  deploy-env LEVER_VAULT: $LEVER_VAULT"
echo "  Frontend deployment JSON: $DEPLOY_VAULT"
if [ "$DEPLOY_VAULT" == "$LEVER_VAULT" ]; then
    pass "Vault address matches between deploy-env and frontend"
elif [ "$DEPLOY_VAULT" == "PARSE_ERROR" ] || [ "$DEPLOY_VAULT" == "NOT_FOUND" ]; then
    warn "Could not parse frontend deployment JSON for vault address"
else
    fail "Vault address MISMATCH: deploy-env=$LEVER_VAULT, frontend=$DEPLOY_VAULT"
fi

# --- Summary ---
echo ""
echo "============================================"
echo "SUMMARY"
echo "============================================"
echo "  PASS: $PASS"
echo "  WARN: $WARN"
echo "  FAIL: $FAIL"

RESULT_FILE="/home/lever/lever-protocol/control-plane/data-validation-result.json"
cat > "$RESULT_FILE" << ENDJSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pass": $PASS,
  "warn": $WARN,
  "fail": $FAIL,
  "tvl_dollars": $TVL_DOLLARS,
  "oi_dollars": $OI_DOLLARS,
  "share_price": $SP_DOLLARS,
  "insurance_dollars": $INS_DOLLARS,
  "borrow_rate_pct": $BR_PCT,
  "price_count": ${PRICE_COUNT:-0},
  "price_age_seconds": ${LAST_UPDATE:-999999},
  "all_passed": $([ $FAIL -eq 0 ] && echo true || echo false)
}
ENDJSON

echo ""
echo "Results saved to: $RESULT_FILE"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "FAILURES:$ISSUES"
    echo ""
    echo "DATA VALIDATION: FAILED ($FAIL issues)"
    exit 1
else
    echo ""
    echo "DATA VALIDATION: PASSED ($WARN warnings)"
    exit 0
fi
