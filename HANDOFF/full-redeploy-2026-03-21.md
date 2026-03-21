# FULL REDEPLOY HANDOFF — March 21, 2026

## GOAL
Redeploy all contracts with stale references, fix every known issue, and produce a clean investor-demo-ready system. Every tab, every number, every button must work.

---

## WHY FULL REDEPLOY IS NEEDED

The vault was redeployed on March 20. Several contracts have **immutable** references that still point to the old vault or old OILimits. These can't be updated — only redeployed.

### Stale Reference Chain
```
OILimits (0x5B98) → reads TVL from OLD vault (0x84a1, $68M) → caps inflated 80x
ExecutionEngine (0xafEA) → uses OILimits (0x5B98) → inflated OI caps
SettlementEngine (0xdfB4) → uses OILimits (0x5B98) → same
LiquidationEngine (0x0374) → liquidation reverts (unknown root cause, needs investigation)
```

### What Works and Should NOT Be Redeployed
```
USDT:                0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E  ✅ (MockUSDT, deployer mints)
MarketRegistry:      0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7  ✅ (10 markets active)
OracleAdapter:       0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c  ✅ (smoothing fixed, prices converging)
AccountManager:      0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684  ✅ (balances correct)
PositionManager:     0x25ba54a7b2fBac753B601Da05e3661F2E959510b  ✅ (position data)
LeverageModel:       0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed  ✅ (getEffectiveMaxLeverage works)
BorrowFeeEngine:     0x706578de003912C71e534949d8b8DDd5108950e1  ✅ (indices accruing after fix)
FundingRateEngine:   0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe  ✅ (initialized, accrueFunding works)
MarginEngine:        0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce  ✅
FeeRouter:           0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F  ✅
LeverVault:          0x1b623D8671c417fe5151cCDb38ec7cAB64332836  ✅ ($500K TVL, correct RD)
RewardsDistributor:  0xab8DFA8cF72b054c356961026F8648dB7D860Cb0  ✅
InsuranceFund:       0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8  ✅
```

---

## CONTRACTS TO REDEPLOY (4)

### 1. OILimits
```
Constructor: (address _marketRegistry, address _vault, address _admin)
Args: 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7, 0x1b623D8671c417fe5151cCDb38ec7cAB64332836, DEPLOYER
Why: Must read TVL from new vault for correct OI caps (60% of $500K = $300K, not $41M)
```

### 2. ExecutionEngine
```
Constructor: (
    address _positionManager,   // 0x25ba54a7b2fBac753B601Da05e3661F2E959510b
    address _oiLimits,          // NEW_OI_LIMITS (deployed in step 1)
    address _marginEngine,      // 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
    address _oracleAdapter,     // 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c
    address _marketRegistry,    // 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
    address _leverageModel,     // 0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed
    address _feeRouter,         // 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F
    address _borrowFeeEngine,   // 0x706578de003912C71e534949d8b8DDd5108950e1
    address _fundingRateEngine, // 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
    address _accountManager,    // 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
    address _leverVault,        // 0x1b623D8671c417fe5151cCDb38ec7cAB64332836
    address _admin              // DEPLOYER
)
Why: Must use new OILimits
Gas: ~2M for deploy
```

### 3. LiquidationEngine
```
Constructor: (
    address admin_,             // DEPLOYER
    address marginEngine_,      // 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
    address positionManager_,   // 0x25ba54a7b2fBac753B601Da05e3661F2E959510b
    address executionEngine_,   // NEW_EXECUTION_ENGINE (deployed in step 2)
    address oiLimits_,          // NEW_OI_LIMITS (deployed in step 1)
    address accountManager_,    // 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
    address insuranceFund_,     // 0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8
    address feeRouter_,         // 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F
    address leverVault_,        // 0x1b623D8671c417fe5151cCDb38ec7cAB64332836
    address marketRegistry_     // 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
)
Why: Must use new EE + new OILimits. Current one has liquidation failures.
```

### 4. SettlementEngine
```
Constructor: (
    address admin_,             // DEPLOYER
    address marketRegistry_,    // 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
    address positionManager_,   // 0x25ba54a7b2fBac753B601Da05e3661F2E959510b
    address oracleAdapter_,     // 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c
    address borrowFeeEngine_,   // 0x706578de003912C71e534949d8b8DDd5108950e1
    address fundingRateEngine_, // 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
    address insuranceFund_,     // 0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8
    address feeRouter_,         // 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F
    address oiLimits_,          // NEW_OI_LIMITS
    address accountManager_,    // 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
    address leverVault_         // 0x1b623D8671c417fe5151cCDb38ec7cAB64332836
)
Why: Must use new OILimits
```

---

## DEPLOYMENT ORDER (CRITICAL — dependencies)

```
1. OILimits (no dependency on other new contracts)
2. ExecutionEngine (depends on new OILimits)
3. LiquidationEngine (depends on new EE + new OILimits)
4. SettlementEngine (depends on new OILimits)
```

---

## POST-DEPLOY: ROLE GRANTS

ENGINE_ROLE = keccak256("ENGINE_ROLE") = 0x5d0c23b505d97686a7eb149c2db3c9cdda71d0f1778515d411985ce042bf17a1

### New OILimits needs ENGINE from:
- New ExecutionEngine
- New LiquidationEngine
- New SettlementEngine

### PositionManager needs ENGINE from:
- New ExecutionEngine (already has old EE)
- New LiquidationEngine
- New SettlementEngine

### AccountManager needs ENGINE from:
- New ExecutionEngine
- New LiquidationEngine

### MarginEngine needs ENGINE from:
- New ExecutionEngine

### BorrowFeeEngine needs ENGINE from:
- New ExecutionEngine

### FundingRateEngine needs ENGINE from:
- New ExecutionEngine

### FeeRouter needs ENGINE from:
- New ExecutionEngine
- New LiquidationEngine

### LeverVault needs ENGINE from:
- New ExecutionEngine
- New LiquidationEngine
- New SettlementEngine

### InsuranceFund needs ENGINE from:
- New LiquidationEngine

Total: ~20 role grants

---

## POST-DEPLOY: MARKET INITIALIZATION

### BorrowFeeEngine — already initialized, indices accruing
Verify: `cast call $BORROW_FEE_ENGINE "getBorrowIndex(bytes32,bool)(uint256)" MARKET_ID true`
Should be > 1e18. If not, call `accrueAll()`.

### FundingRateEngine — initialized in this session
For each of the 10 markets, verify:
```bash
cast call $FUNDING_RATE_ENGINE "getFundingIndex(bytes32)(int256)" MARKET_ID
```
If it reverts, call:
```bash
cast send $FUNDING_RATE_ENGINE "initializeMarketIndex(bytes32)" MARKET_ID
cast send $FUNDING_RATE_ENGINE "updateMarketRiskParams(bytes32,uint256,uint256,uint256,uint256,uint256,uint256)" \
    MARKET_ID \
    20000000000000000 \   # sigmaCurrent = 0.02
    20000000000000000 \   # sigmaBaseline = 0.02
    10000000000000000000000 \ # externalDepth = 10000 WAD
    500000000000000000 \  # depthThreshold = 0.5 WAD
    0 \                   # marketOI = 0
    0                     # globalOI = 0
```

### OracleAdapter — smoothing params (already set)
All markets should have: alpha=0.50, deltaMax=0.15, epsilon=0.05, spreadLimit=0.15, depthMin=0
Verify: `cast call $ORACLE_ADAPTER "getSmoothingParams(bytes32)" MARKET_ID`

---

## POST-DEPLOY: UPDATE ADDRESSES

### deploy-env.sh
Update OI_LIMITS, EXECUTION_ENGINE, LIQUIDATION_ENGINE, SETTLEMENT_ENGINE

### Frontend config (src/config/contracts.ts)
Update: oiLimits, executionEngine, liquidationEngine, settlementEngine
Remove: oiLimitsNew (no longer needed — single OILimits with correct vault)

### Deployment JSONs
Update: public/deployments/engines-deployment.json, deployment.json

### PROTECTED CONTRACTS list in CLAUDE.md
Update with new addresses

---

## POST-DEPLOY: CLEAR OLD DATA & SEED

### Close all orphaned positions
Deployer has ENGINE role on PositionManager. Force-close any open positions:
```bash
for pid in $(seq 1 300); do
    IS_OPEN=$(cast call $POSITION_MANAGER "isPositionOpen(uint256)(bool)" $pid --rpc-url $RPC_URL 2>/dev/null)
    if [ "$IS_OPEN" == "true" ]; then
        cast send $POSITION_MANAGER "closePosition(uint256)" $pid --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 300000
    fi
done
```

### Zero stale OI on new OILimits
New OILimits starts at 0 OI, so no cleanup needed.
But if old positions added OI before they were closed, may need decreaseOI.

### Seed demo positions (use 2M gas!)
```bash
DEMO_KEY=e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5

# Ensure USDT approved + deposited to AccountManager
# Then open 4 positions with tuple syntax:
cast send $NEW_EE "openPosition((bytes32,bool,uint256,uint256))" \
    "(MARKET_ID,true,500000000,3000000000000000000)" \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 2000000
```

### Vault deposit from demo wallet
```bash
cast send $USDT_ADDRESS "approve(address,uint256)" $LEVER_VAULT 10000000000 --private-key $DEMO_KEY
cast send $LEVER_VAULT "deposit(uint256,address)" 1000000000 $DEMO --private-key $DEMO_KEY
```

---

## FRONTEND FIXES ALREADY APPLIED (do not revert)

### 1. useLivePrices.ts — REWRITTEN
- Was: random walk simulation starting at 0.5
- Now: fetches from /prices.json (real Polymarket data via keeper)

### 2. useMarketProbabilities.ts — FIXED
- Was: initialized with hardcoded fallback prices (caused flash of stale data)
- Now: starts null, shows loading skeleton until first fetch

### 3. connectors/demo.ts — FIXED
- `isDemoMode()` now returns `true` by default (localStorage !== 'false')
- `setDemoMode(false)` writes 'false' instead of removing key

### 4. ProfessionalStatusBar.tsx — FIXED
- Was: Math.random() simulation showing DEGRADED randomly
- Now: real RPC health check

### 5. ProtocolStats.tsx — FIXED
- APY uses only useRealAPY (no inline fallback formula)
- Utilization cap removed (can exceed 100% for leveraged perps)
- Volume shows "—" when 0

### 6. useVolumeCalculation.ts — FIXED
- Event ABI was missing 4 fields (entryPI, entryPrice, impact, timestamp)
- positionSize was decoding from wrong data slot → always showed $0

### 7. MarketDetail.tsx — FIXED
- OI breakdown bar: min 2% width, 1-decimal for sub-1% values

### 8. VaultOptimized.tsx — FIXED
- APY uses `apyPercent !== undefined ? apyPercent : metrics.annualizedAPY`
- Prevents 0% APY from falling back to hardcoded estimate

### 9. Trading.tsx — MAX POSITION DISPLAY ADDED
- Shows max notional, max collateral, binding constraint with actual cap value
- Reads caps from new OILimits, current OI from old (needs update after redeploy — single source)

---

## FRONTEND CHANGES NEEDED AFTER REDEPLOY

After redeploy, Trading.tsx should use a SINGLE oiLimits address for both caps and current OI.
Remove the `oiLimitsNew` field from contracts.ts and update Trading.tsx to use `CONTRACT_ADDRESSES.oiLimits` everywhere.

---

## KNOWN REMAINING ISSUES

1. **Accrue keeper nonce conflicts** — The accrue keeper and oracle keeper both use the deployer key. They compete for nonces causing frequent failures. Consider: separate keys, or combine into one script with sequential nonce management.

2. **openPosition requires ~1M gas** — Frontend useDemoWallet uses gas:2000000n. Keep this.

3. **forge create doesn't work** — The `forge create` command fails with "Error accessing local wallet" on this machine. Use `cast send --create` with compiled bytecode instead:
```bash
BYTECODE=$(python3 -c "import json; print(json.load(open('out/CONTRACT.sol/CONTRACT.json'))['bytecode']['object'])")
ARGS=$(cast abi-encode "constructor(type1,type2,...)" arg1 arg2 ... | cut -c3-)
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY --gas-limit 4000000 --create "${BYTECODE}${ARGS}"
```

4. **10 markets IDs** (for loops):
```
0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1  SpaceX IPO
0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a  US-Iran
0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d  Nothing Happens
0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2  FIFA
0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7  Fed Rate EOY
0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2  SpaceX Ackman
0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554  AAPL $250
0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc  OpenSea Token
0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f  Fed April Cut
0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea  Argentina USD
```

5. **Demo wallet**:
```
Address: 0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
Private Key: e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
USDT Balance: ~$1.9M
AM Balance: ~$800K
Vault Shares: ~12K
```

---

## VERIFICATION CHECKLIST (run after everything)

### On-chain
```bash
source control-plane/deploy-env.sh
echo "TVL:" && cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL
echo "Open positions:" && cast call $POSITION_MANAGER "totalOpenPositions()(uint256)" --rpc-url $RPC_URL
echo "Global OI:" && cast call $NEW_OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL
echo "Global OI Cap:" && cast call $NEW_OI_LIMITS "getGlobalOICap()(uint256)" --rpc-url $RPC_URL
echo "Share price:" && cast call $LEVER_VAULT "convertToAssets(uint256)(uint256)" 1000000000000000000 --rpc-url $RPC_URL

# For each position: check borrow fees > 0
cast call $BORROW_FEE_ENGINE "getAccruedFees(uint256)(uint256)" PID --rpc-url $RPC_URL

# Test liquidation: make a position liquidatable and verify liquidate() works
cast call $MARGIN_ENGINE "isLiquidatable(uint256)(bool)" PID --rpc-url $RPC_URL
cast send $NEW_LIQUIDATION_ENGINE "liquidate(uint256)" PID --private-key $PRIVATE_KEY --gas-limit 2000000
```

### Frontend (rebuild after every change)
```bash
cd frontend/user-app
npx react-app-rewired build
sed -i 's/<meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"\/>//' build/index.html
cp -r public/deployments build/deployments
systemctl restart lever-frontend
```

### Tab-by-tab verification
- **Markets**: 10 markets, prices match prices.json, no stale flash
- **Trading**: max position display with correct caps, open position works
- **Positions**: borrow fees non-zero, funding non-zero, close works
- **Vault**: TVL matches, share price ~$1, deposit/withdraw works
- **Stats bar**: TVL, OI, utilization, APY all match on-chain
- **Status bar**: OPERATIONAL (real RPC check)

### Services
```bash
systemctl is-active lever-frontend lever-oracle lever-accrue-keeper
```

---

## DEPLOYMENT SEQUENCE SCRIPT TEMPLATE

```bash
#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh

# STOP ALL KEEPERS FIRST
systemctl stop lever-oracle lever-accrue-keeper

# STEP 1: Deploy OILimits
cd /home/lever/lever-protocol
forge build
BYTECODE=$(python3 -c "import json; print(json.load(open('out/OILimits.sol/OILimits.json'))['bytecode']['object'])")
ARGS=$(cast abi-encode "constructor(address,address,address)" $MARKET_REGISTRY $LEVER_VAULT $DEPLOYER | cut -c3-)
NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
# Deploy and capture address...

# STEP 2: Deploy ExecutionEngine (12 constructor args)
# STEP 3: Deploy LiquidationEngine (10 constructor args)
# STEP 4: Deploy SettlementEngine (11 constructor args)

# STEP 5: Grant ~20 ENGINE roles
# STEP 6: Initialize funding for all 10 markets
# STEP 7: Call accrueAll() and accrueFunding() for all markets
# STEP 8: Close orphaned positions
# STEP 9: Seed 4 demo positions
# STEP 10: Update deploy-env.sh, contracts.ts, deployment JSONs
# STEP 11: Build and deploy frontend
# STEP 12: Restart keepers
# STEP 13: Verify everything
```

---

## GIT COMMIT MESSAGE

```
full redeploy: OILimits + EE + LE + SE — fix stale vault refs, OI caps, liquidations

Redeployed 4 contracts pointing to correct vault ($500K TVL):
- OILimits: correct OI caps (60% of real TVL)
- ExecutionEngine: uses new OILimits
- LiquidationEngine: uses new EE + OILimits, liquidations working
- SettlementEngine: uses new OILimits

Frontend fixes:
- useLivePrices reads from prices.json (not random simulation)
- useMarketProbabilities: no stale price flash on load
- Demo mode ON by default
- Volume event ABI fixed (11 fields)
- Borrow fees accruing, funding rates initialized
- Max position display with OI cap breakdown
- Status bar real health check

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```
