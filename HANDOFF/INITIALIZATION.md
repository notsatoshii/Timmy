# COMPLETE INITIALIZATION — After Deploy + Role Grants

Every contract that has per-market state needs initialization for ALL 10 markets.
Without this, trades will revert with ZeroDepthThreshold, indices won't accrue, etc.

---

## MARKET IDS (used in every loop below)

```bash
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
```

---

## 1. BorrowFeeEngine — 3 steps per market

### 1a. Initialize borrow indices (sets long/short index to WAD, timestamps to now)
```bash
for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_BFE "initializeMarketIndex(bytes32)" $MID \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 1b. Set risk params (depthThreshold, sigma, depth)
```bash
# updateMarketRiskParams(bytes32, sigmaCurrent, sigmaBaseline, externalDepth, depthThreshold, marketOI, globalOI)
SIGMA="20000000000000000"          # 0.02 WAD
DEPTH="10000000000000000000000"    # 10000 WAD
DEPTH_THRESH="500000000000000000"  # 0.5 WAD

for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_BFE "updateMarketRiskParams(bytes32,uint256,uint256,uint256,uint256,uint256,uint256)" \
        $MID $SIGMA $SIGMA $DEPTH $DEPTH_THRESH 0 0 \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 1c. Initial accrual
```bash
NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
cast send $NEW_BFE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 2000000
```

### 1d. Verify
```bash
for MID in "${MARKETS[@]}"; do
    IDX=$(cast call $NEW_BFE "getBorrowIndex(bytes32,bool)(uint256)" $MID true --rpc-url $RPC_URL | awk '{print $1}')
    DT=$(cast call $NEW_BFE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    echo "$MID: index=$IDX depthThreshold=$DT"
    # index must be >= 1e18 (WAD), depthThreshold must be 5e17
done
```

---

## 2. FundingRateEngine — 3 steps per market

### 2a. Initialize funding indices
```bash
for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_FRE "initializeMarketIndex(bytes32)" $MID \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 2b. Set risk params
```bash
# updateMarketRiskParams(bytes32, sigmaCurrent, sigmaBaseline, externalDepth, depthThreshold, marketOI, globalOI)
for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_FRE "updateMarketRiskParams(bytes32,uint256,uint256,uint256,uint256,uint256,uint256)" \
        $MID $SIGMA $SIGMA $DEPTH $DEPTH_THRESH 0 0 \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 2c. Initial accrual
```bash
for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_FRE "accrueFunding(bytes32)" $MID \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 300000
    sleep 4
done
```

### 2d. Verify
```bash
for MID in "${MARKETS[@]}"; do
    IDX=$(cast call $NEW_FRE "getFundingIndex(bytes32)(int256)" $MID --rpc-url $RPC_URL 2>&1)
    DT=$(cast call $NEW_FRE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    echo "$MID: fundingIndex=$IDX depthThreshold=$DT"
    # Must not revert. DT must be 5e17.
done
```

---

## 3. MarginEngine — risk params per market

### 3a. Set risk params
```bash
# updateMarketRiskParams(bytes32, sigmaCurrent, sigmaBaseline, externalDepth, depthThreshold, marketOI, globalOI, marketUtilization)
# Note: ME has 8 args (extra marketUtilization compared to BFE/FRE's 7)
for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_ME "updateMarketRiskParams(bytes32,uint256,uint256,uint256,uint256,uint256,uint256,uint256)" \
        $MID $SIGMA $SIGMA $DEPTH $DEPTH_THRESH 0 0 0 \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 3b. Verify
```bash
for MID in "${MARKETS[@]}"; do
    DT=$(cast call $NEW_ME "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    echo "$MID: depthThreshold=$DT (must be 5e17)"
done
```

---

## 4. LeverageModel — market risk params

### 4a. Set risk params
```bash
# setMarketRiskParams(bytes32, sigmaBaseline, depthThreshold)
# Note: This uses KEEPER_ROLE, not ADMIN_ROLE — deployer must have KEEPER on LM
KEEPER=$(cast keccak "KEEPER_ROLE")
# Grant KEEPER to deployer first:
cast send $NEW_LM "grantRole(bytes32,address)" $KEEPER $DEPLOYER --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 200000
sleep 4

for MID in "${MARKETS[@]}"; do
    NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
    cast send $NEW_LM "setMarketRiskParams(bytes32,uint256,uint256)" \
        $MID $SIGMA $DEPTH_THRESH \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 200000
    sleep 4
done
```

### 4b. Verify
```bash
# getEffectiveMaxLeverage should return a reasonable number (not revert)
for MID in "${MARKETS[@]}"; do
    LEV=$(cast call $NEW_LM "getEffectiveMaxLeverage(bytes32)(uint256)" $MID --rpc-url $RPC_URL 2>&1)
    echo "$MID: maxLeverage=$LEV"
    # Should be a WAD number like 4-15e18 (4x-15x). Must NOT revert.
done
```

---

## 5. OracleAdapter — smoothing params (already set on kept contract)

### 5a. Verify smoothing params are still set
```bash
for MID in "${MARKETS[@]}"; do
    PARAMS=$(cast call $ORACLE_ADAPTER "getSmoothingParams(bytes32)" $MID --rpc-url $RPC_URL | head -1)
    echo "$MID: $PARAMS"
done
# alpha should be ~5e17 (0.50), deltaMax ~1.5e17 (0.15)
```

### 5b. If any market has alpha=0 (default/unset), set it:
```bash
SMOOTH_PARAMS="(500000000000000000,150000000000000000,50000000000000000,150000000000000000,0)"
cast send $ORACLE_ADAPTER "updateSmoothingParams(bytes32,(uint256,uint256,uint256,uint256,uint256))" \
    $MID "$SMOOTH_PARAMS" \
    --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 200000
```

---

## 6. Update accrue-keeper.sh with new addresses

The keeper script at `control-plane/accrue-keeper.sh` has hardcoded addresses.
Update to use the new BFE and FRE addresses:

```bash
#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh
while true; do
  cast send $BORROW_FEE_ENGINE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000 2>/dev/null
  for MKT in ${MARKETS[@]}; do
    cast send $FUNDING_RATE_ENGINE "accrueFunding(bytes32)" "$MKT" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 300000 2>/dev/null
  done
  sleep 60
done
```

---

## INITIALIZATION GATE CHECK

Before opening any positions, verify ALL of these:

```bash
echo "=== INIT GATE CHECK ==="

# 1. BFE indices initialized for all markets
for MID in "${MARKETS[@]}"; do
    IDX=$(cast call $NEW_BFE "getBorrowIndex(bytes32,bool)(uint256)" $MID true --rpc-url $RPC_URL | awk '{print $1}')
    if [ "$IDX" == "0" ]; then echo "FAIL: BFE index 0 for $MID"; fi
done

# 2. FRE initialized for all markets
for MID in "${MARKETS[@]}"; do
    cast call $NEW_FRE "getFundingIndex(bytes32)(int256)" $MID --rpc-url $RPC_URL > /dev/null 2>&1 || echo "FAIL: FRE not initialized for $MID"
done

# 3. Depth thresholds set everywhere
for MID in "${MARKETS[@]}"; do
    DT_BFE=$(cast call $NEW_BFE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    DT_FRE=$(cast call $NEW_FRE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    DT_ME=$(cast call $NEW_ME "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    if [ "$DT_BFE" == "0" ] || [ "$DT_FRE" == "0" ] || [ "$DT_ME" == "0" ]; then
        echo "FAIL: depthThreshold 0 on $MID (BFE=$DT_BFE FRE=$DT_FRE ME=$DT_ME)"
    fi
done

# 4. LeverageModel returns valid leverage for all markets
for MID in "${MARKETS[@]}"; do
    LEV=$(cast call $NEW_LM "getEffectiveMaxLeverage(bytes32)(uint256)" $MID --rpc-url $RPC_URL 2>&1)
    if echo "$LEV" | grep -q "Error\|revert"; then
        echo "FAIL: LM revert for $MID"
    fi
done

# 5. TVL > 0
TVL=$(cast call $NEW_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL | awk '{print $1}')
if [ "$TVL" == "0" ]; then echo "FAIL: TVL is 0 — deposit to vault first"; fi

# 6. Oracle prices are live
for MID in "${MARKETS[@]}"; do
    PI=$(cast call $ORACLE_ADAPTER "getPI(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    if [ "$PI" == "0" ]; then echo "FAIL: PI is 0 for $MID"; fi
done

echo "=== If no FAILs above, proceed to position testing ==="
```

**DO NOT open positions until this gate check passes with zero failures.**
