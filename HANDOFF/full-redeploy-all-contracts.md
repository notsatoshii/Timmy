# FULL REDEPLOY — ALL 16 CONTRACTS
## March 21, 2026 — Investor Demo Prep

---

## WHY FULL REDEPLOY

10 of 16 contracts have stale immutable references to the old vault (`0x84a1`) or old OILimits (`0x5B98`). Patching individual contracts created a split-brain state where different contracts read different TVL values. The only clean fix is redeploying everything from scratch.

### Stale Vault Ref (0x84a1 — old vault with $68M)
- LeverageModel → wrong TVL for leverage ceiling (inflated 80x)
- InsuranceFund → wrong IFR calculations
- RewardsDistributor → rewards misrouted to old vault
- OILimits (old) → OI caps inflated 80x

### Stale OILimits Ref (0x5B98 — reads old vault)
- LeverageModel, BorrowFeeEngine, FundingRateEngine
- ExecutionEngine, LiquidationEngine, SettlementEngine

### Only 6 contracts have correct refs
- USDT, MarketRegistry, OracleAdapter, AccountManager, PositionManager, LeverVault

---

## CONTRACTS TO KEEP (do NOT redeploy)

```
USDT:            0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E  — MockUSDT, deployer can mint
MarketRegistry:  0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7  — 10 markets active, no stale refs
OracleAdapter:   0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c  — only refs MR (correct), smoothing params fixed
AccountManager:  0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684  — only refs USDT (correct)
PositionManager: 0x25ba54a7b2fBac753B601Da05e3661F2E959510b  — no immutable deps
```

**Reason to keep these**: They have no stale references. PositionManager holds all position data — redeploying it would lose position history. AccountManager holds all user balances. MarketRegistry has 10 markets registered. OracleAdapter has smoothing state for all markets.

**Important**: PositionManager still has existing (closed) positions. totalOpenPositions should be 0 after clearing. Any open positions must be closed BEFORE deployment begins.

---

## CONTRACTS TO REDEPLOY (11) — DEPENDENCY ORDER

### Circular Dependency: LeverVault ↔ RewardsDistributor

LeverVault needs RD address. RD needs LeverVault address. Both are immutable.

**Solution**: Pre-compute the LeverVault CREATE address using deployer nonce.
```bash
# After deploying RD, note the nonce that will be used for LeverVault
VAULT_NONCE=$((NONCE_AFTER_RD + 0))  # vault deploys immediately after RD
PREDICTED_VAULT=$(cast compute-address $DEPLOYER --nonce $VAULT_NONCE)
# Deploy RD with PREDICTED_VAULT
# Deploy LeverVault with RD address
# Verify LeverVault deployed at PREDICTED_VAULT
```

Alternatively, deploy them back-to-back ensuring no other tx sneaks in.

### Deploy Order (strictly sequential, each depends on previous)

```
Layer 1:  RewardsDistributor  (needs: USDT, predicted-LeverVault)
Layer 2:  LeverVault          (needs: USDT, RewardsDistributor)
Layer 3:  InsuranceFund       (needs: USDT, LeverVault)
Layer 4:  FeeRouter           (needs: USDT, InsuranceFund, RewardsDistributor, treasury=DEPLOYER)
Layer 5:  OILimits            (needs: MarketRegistry, LeverVault)
Layer 6:  LeverageModel       (needs: LeverVault, InsuranceFund, OILimits, MarketRegistry, OracleAdapter)
Layer 7a: BorrowFeeEngine     (needs: MarketRegistry, OILimits, PositionManager)
Layer 7b: FundingRateEngine   (needs: MarketRegistry, OILimits, PositionManager)
Layer 8:  MarginEngine        (needs: PositionManager, OracleAdapter, MarketRegistry, BorrowFeeEngine, FundingRateEngine)
Layer 9:  ExecutionEngine     (needs: PM, OILimits, MarginEngine, OA, MR, LeverageModel, FeeRouter, BFE, FRE, AM, LeverVault)
Layer 10: LiquidationEngine   (needs: MarginEngine, PM, ExecutionEngine, OILimits, AM, InsuranceFund, FeeRouter, LeverVault, MR)
Layer 11: SettlementEngine    (needs: MR, PM, OA, BFE, FRE, InsuranceFund, FeeRouter, OILimits, AM, LeverVault)
```

---

## CONSTRUCTOR SIGNATURES (exact args)

### 1. RewardsDistributor
```
constructor(address admin_, address usdt_, address leverVault_)
Args: DEPLOYER, USDT, PREDICTED_VAULT_ADDRESS
```

### 2. LeverVault
```
constructor(address admin_, address usdt_, address rewardsDistributor_)
Args: DEPLOYER, USDT, NEW_RD
```

### 3. InsuranceFund
```
constructor(address admin_, address usdt_, address leverVault_)
Args: DEPLOYER, USDT, NEW_VAULT
Note: Use InsuranceFund.sol (not InsuranceFundFixed.sol)
```

### 4. FeeRouter
```
constructor(address admin_, address usdt_, address insuranceFund_, address rewardsDistributor_, address protocolTreasury_)
Args: DEPLOYER, USDT, NEW_IF, NEW_RD, DEPLOYER
```

### 5. OILimits
```
constructor(address _marketRegistry, address _vault, address _admin)
Args: MARKET_REGISTRY, NEW_VAULT, DEPLOYER
```

### 6. LeverageModel
```
constructor(address _vault, address _insuranceFund, address _oiLimits, address _marketRegistry, address _oracleAdapter, address _admin)
Args: NEW_VAULT, NEW_IF, NEW_OI, MARKET_REGISTRY, ORACLE_ADAPTER, DEPLOYER
Note: Use LeverageModel.sol (not LeverageModelFixed.sol) — check which is deployed
```

### 7a. BorrowFeeEngine
```
constructor(address admin_, address marketRegistry_, address oiLimits_, address positionManager_)
Args: DEPLOYER, MARKET_REGISTRY, NEW_OI, POSITION_MANAGER
```

### 7b. FundingRateEngine
```
constructor(address admin_, address marketRegistry_, address oiLimits_, address positionManager_)
Args: DEPLOYER, MARKET_REGISTRY, NEW_OI, POSITION_MANAGER
```

### 8. MarginEngine
```
constructor(address admin_, address positionManager_, address oracle_, address marketRegistry_, address borrowFeeEngine_, address fundingRateEngine_)
Args: DEPLOYER, POSITION_MANAGER, ORACLE_ADAPTER, MARKET_REGISTRY, NEW_BFE, NEW_FRE
```

### 9. ExecutionEngine
```
constructor(
    address _positionManager, address _oiLimits, address _marginEngine,
    address _oracleAdapter, address _marketRegistry, address _leverageModel,
    address _feeRouter, address _borrowFeeEngine, address _fundingRateEngine,
    address _accountManager, address _leverVault, address _admin
)
Args: POSITION_MANAGER, NEW_OI, NEW_ME, ORACLE_ADAPTER, MARKET_REGISTRY, NEW_LM,
      NEW_FR, NEW_BFE, NEW_FRE, ACCOUNT_MANAGER, NEW_VAULT, DEPLOYER
```

### 10. LiquidationEngine
```
constructor(
    address admin_, address marginEngine_, address positionManager_,
    address executionEngine_, address oiLimits_, address accountManager_,
    address insuranceFund_, address feeRouter_, address leverVault_,
    address marketRegistry_
)
Args: DEPLOYER, NEW_ME, POSITION_MANAGER, NEW_EE, NEW_OI, ACCOUNT_MANAGER,
      NEW_IF, NEW_FR, NEW_VAULT, MARKET_REGISTRY
```

### 11. SettlementEngine
```
constructor(
    address admin_, address marketRegistry_, address positionManager_,
    address oracleAdapter_, address borrowFeeEngine_, address fundingRateEngine_,
    address insuranceFund_, address feeRouter_, address oiLimits_,
    address accountManager_, address leverVault_
)
Args: DEPLOYER, MARKET_REGISTRY, POSITION_MANAGER, ORACLE_ADAPTER, NEW_BFE, NEW_FRE,
      NEW_IF, NEW_FR, NEW_OI, ACCOUNT_MANAGER, NEW_VAULT
```

---

## POST-DEPLOY: ROLE GRANTS (~30 grants)

ENGINE_ROLE = 0x5d0c23b505d97686a7eb149c2db3c9cdda71d0f1778515d411985ce042bf17a1
KEEPER_ROLE = keccak256("KEEPER_ROLE")

### PositionManager (kept) — grant ENGINE to new contracts
```
grantRole(ENGINE, NEW_EE)
grantRole(ENGINE, NEW_LE)
grantRole(ENGINE, NEW_SE)
```

### AccountManager (kept) — grant ENGINE to new contracts
```
grantRole(ENGINE, NEW_EE)
grantRole(ENGINE, NEW_LE)
```

### New OILimits
```
grantRole(ENGINE, NEW_EE)
grantRole(ENGINE, NEW_LE)
grantRole(ENGINE, NEW_SE)
```

### New BorrowFeeEngine
```
grantRole(ENGINE, NEW_EE)
grantRole(KEEPER_ROLE, DEPLOYER)  — for accrueAll()
```

### New FundingRateEngine
```
grantRole(ENGINE, NEW_EE)
grantRole(KEEPER_ROLE, DEPLOYER)  — for accrueFunding()
```

### New MarginEngine
```
grantRole(ENGINE, NEW_EE)
```

### New FeeRouter
```
grantRole(ENGINE, NEW_EE)
grantRole(ENGINE, NEW_LE)
```

### New LeverVault
```
grantRole(ENGINE, NEW_EE)
grantRole(ENGINE, NEW_LE)
grantRole(ENGINE, NEW_SE)
```

### New InsuranceFund
```
grantRole(ENGINE, NEW_LE)
```

### New RewardsDistributor
```
grantRole(ENGINE, NEW_FR)  — FeeRouter distributes to RD
```

### OracleAdapter (kept) — grant ORACLE to deployer (already has it, verify)
```
# Deployer needs ORACLE_ROLE to push prices via keeper
# Verify: cast call $ORACLE_ADAPTER "hasRole(bytes32,address)(bool)" ORACLE_ROLE DEPLOYER
```

---

## POST-DEPLOY: MARKET INITIALIZATION

### OracleAdapter — Smoothing Params (already set, verify)
All 10 markets should have: alpha=0.50, deltaMax=0.15
```bash
cast call $ORACLE_ADAPTER "getSmoothingParams(bytes32)" MARKET_ID --rpc-url $RPC_URL
```

### BorrowFeeEngine (NEW) — Initialize borrow indices
Borrow indices start at WAD (1e18) by default. Call accrueAll() once to set timestamps.
```bash
cast send NEW_BFE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000
```

Also set depthThreshold for each market:
```bash
# Check if BFE has updateMarketRiskParams or separate setter
grep -n "depthThreshold\|setDepthThreshold\|updateMarketRiskParams" contracts/BorrowFeeEngine.sol
```
Current BFE has depthThreshold=0.5 WAD per market. New one starts at 0. Must set for all 10 markets.

### FundingRateEngine (NEW) — Initialize ALL 10 markets
For each market:
```bash
cast send NEW_FRE "initializeMarketIndex(bytes32)" MARKET_ID
cast send NEW_FRE "updateMarketRiskParams(bytes32,uint256,uint256,uint256,uint256,uint256,uint256)" \
    MARKET_ID \
    20000000000000000 \    # sigmaCurrent = 0.02 WAD
    20000000000000000 \    # sigmaBaseline = 0.02 WAD
    10000000000000000000000 \  # externalDepth = 10000 WAD
    500000000000000000 \   # depthThreshold = 0.5 WAD
    0 \                    # marketOI = 0
    0                      # globalOI = 0
```

### MarginEngine (NEW) — Set depth thresholds
```bash
# Check setter:
grep -n "depthThreshold\|setMarketParams" contracts/MarginEngine.sol
# Set for all 10 markets
```

### LeverageModel (NEW) — Set market risk params if needed
```bash
grep -n "setMarketRiskParams\|updateMarketRiskParams" contracts/LeverageModel.sol
```

---

## POST-DEPLOY: TVL SEEDING

New vault starts at $0. Deployer has ~$33 quadrillion mock USDT (it's mock, unlimited).

```bash
# Approve and deposit $500K
cast send $USDT "approve(address,uint256)" NEW_VAULT 500000000000 --private-key $PRIVATE_KEY
cast send NEW_VAULT "deposit(uint256,address)" 500000000000 $DEPLOYER --private-key $PRIVATE_KEY
```

### InsuranceFund — Bootstrap
InsuranceFund constructor sets `_balance = INSURANCE_BOOTSTRAP` (10000 WAD = $10K).
Need to actually transfer USDT to fund it:
```bash
cast send $USDT "transfer(address,uint256)" NEW_IF 10000000000 --private-key $PRIVATE_KEY
```

### Demo wallet setup
```bash
DEMO=0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
DEMO_KEY=e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5

# Fund ETH for gas
cast send $DEMO --value 50000000000000000 --private-key $PRIVATE_KEY  # 0.05 ETH

# Approve and deposit to AccountManager
cast send $USDT "approve(address,uint256)" $ACCOUNT_MANAGER 999999999999999 --private-key $DEMO_KEY
cast send $ACCOUNT_MANAGER "deposit(uint256)" 500000000000 --private-key $DEMO_KEY  # $500K

# Deposit to vault (for vault tab display)
cast send $USDT "approve(address,uint256)" NEW_VAULT 10000000000 --private-key $DEMO_KEY
cast send NEW_VAULT "deposit(uint256,address)" 1000000000 $DEMO --private-key $DEMO_KEY  # $1K
```

---

## POST-DEPLOY: POSITION CLEANUP & SEEDING

### Clear orphaned positions
Deployer needs ENGINE role on PositionManager (already granted).
```bash
for pid in $(seq 1 300); do
    IS_OPEN=$(cast call $POSITION_MANAGER "isPositionOpen(uint256)(bool)" $pid --rpc-url $RPC_URL 2>/dev/null)
    if [ "$IS_OPEN" == "true" ]; then
        NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
        cast send $POSITION_MANAGER "closePosition(uint256)" $pid \
            --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 300000
        sleep 5
    fi
done
```
IMPORTANT: Stop ALL keepers first to avoid nonce conflicts.

### Seed 4 demo positions
```bash
# Use tuple syntax, 2M gas minimum
cast send NEW_EE "openPosition((bytes32,bool,uint256,uint256))" \
    "(MARKET_ID,isLong,collateral_6dec,leverage_WAD)" \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 2000000

# Positions to create:
# 1. SpaceX 3x Long, $500 — (0x2841..., true, 500000000, 3000000000000000000)
# 2. US-Iran 2x Short, $300 — (0x9fe6..., false, 300000000, 2000000000000000000)
# 3. FIFA 5x Long, $200 — (0xe824..., true, 200000000, 5000000000000000000)
# 4. Fed Rate 3x Short, $400 — (0x14c6..., false, 400000000, 3000000000000000000)
```

---

## POST-DEPLOY: UPDATE ALL CONFIGS

### control-plane/deploy-env.sh
Update ALL contract addresses. Remove OI_LIMITS_NEW (single OILimits now).

### frontend/user-app/src/config/contracts.ts
Update ALL addresses in FALLBACK_ADDRESSES.
Remove `oiLimitsNew` field — single OILimits address for everything.
Update Trading.tsx to use `CONTRACT_ADDRESSES.oiLimits` everywhere (remove oiLimitsNew refs).

### frontend/user-app/public/deployments/*.json
Update all deployment JSONs with new addresses.

### CLAUDE.md
Update PROTECTED CONTRACTS section with new addresses.

### CONTEXT.md
Update all addresses and current state.

---

## FRONTEND FIXES ALREADY APPLIED (do NOT revert these)

1. **useLivePrices.ts** — reads from prices.json (was random walk simulation)
2. **useMarketProbabilities.ts** — null init, no stale price flash
3. **connectors/demo.ts** — demo mode ON by default
4. **ProfessionalStatusBar.tsx** — real RPC health check (was Math.random)
5. **ProtocolStats.tsx** — useRealAPY only, utilization uncapped, volume "—" when 0
6. **useVolumeCalculation.ts** — correct 11-field event ABI
7. **MarketDetail.tsx** — OI bar min 2% width
8. **VaultOptimized.tsx** — APY null check
9. **Trading.tsx** — max position display with OI cap breakdown

### Frontend fix needed AFTER redeploy
- Trading.tsx: remove `oiLimitsNew` references, use single `oiLimits` for both caps and OI
- useVolumeCalculation.ts: update DEPLOYMENT_BLOCK to the block of the new ExecutionEngine

---

## OPERATIONAL NOTES

### forge create doesn't work on this machine
Use `cast send --create` with compiled bytecode:
```bash
forge build  # compile all
BYTECODE=$(python3 -c "import json; print(json.load(open('out/CONTRACT.sol/CONTRACT.json'))['bytecode']['object'])")
ARGS=$(cast abi-encode "constructor(type1,type2,...)" arg1 arg2 ... | cut -c3-)
NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY --nonce $NONCE --gas-limit 4000000 --create "${BYTECODE}${ARGS}"
```

### Nonce conflicts
The oracle keeper and accrue keeper both use deployer key. STOP BOTH before any deployment:
```bash
systemctl stop lever-oracle lever-accrue-keeper
pkill -f keeper
# Verify nonce is stable:
N1=$(cast nonce $DEPLOYER --rpc-url $RPC_URL); sleep 5; N2=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
echo "$N1 -> $N2"  # must be same
```

### Gas requirements
- Contract deploys: 2-4M gas each
- openPosition: ~1M gas (use 2M limit)
- Role grants: ~120K gas (use 200K limit)
- accrueAll: ~700K gas (use 2M limit)

### 10 Market IDs
```
SpaceX IPO:       0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1
US-Iran:          0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a
Nothing Happens:  0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d
FIFA:             0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2
Fed Rate EOY:     0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7
SpaceX Ackman:    0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2
AAPL $250:        0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554
OpenSea Token:    0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc
Fed April Cut:    0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f
Argentina USD:    0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea
```

### Demo wallet
```
Address: 0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
Key: e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
```

---

## PHASE A: CONTRACT REFERENCE VERIFICATION

After all 11 deploys complete, verify EVERY immutable ref is correct. Do NOT proceed if any is wrong.

```bash
source control-plane/deploy-env.sh

echo "=== Immutable Reference Audit ==="

# LeverVault
echo "LeverVault.rewardsDistributor: $(cast call $LEVER_VAULT 'rewardsDistributor()(address)' --rpc-url $RPC_URL)"
# Must equal NEW_RD

# RewardsDistributor
echo "RD.leverVault: $(cast call $REWARDS_DISTRIBUTOR 'leverVault()(address)' --rpc-url $RPC_URL)"
# Must equal NEW_VAULT

# InsuranceFund
echo "IF.leverVault: $(cast call $INSURANCE_FUND 'leverVault()(address)' --rpc-url $RPC_URL)"
# Must equal NEW_VAULT

# FeeRouter
echo "FR.insuranceFund: $(cast call $FEE_ROUTER 'insuranceFund()(address)' --rpc-url $RPC_URL)"
echo "FR.rewardsDistributor: $(cast call $FEE_ROUTER 'rewardsDistributor()(address)' --rpc-url $RPC_URL)"
# Must equal NEW_IF and NEW_RD

# OILimits
echo "OI.vault: $(cast call $OI_LIMITS 'vault()(address)' --rpc-url $RPC_URL)"
echo "OI.marketRegistry: $(cast call $OI_LIMITS 'marketRegistry()(address)' --rpc-url $RPC_URL)"
# vault = NEW_VAULT, MR = 0x3Cc9

# LeverageModel
echo "LM.vault: $(cast call $LEVERAGE_MODEL 'vault()(address)' --rpc-url $RPC_URL)"
echo "LM.insuranceFund: $(cast call $LEVERAGE_MODEL 'insuranceFund()(address)' --rpc-url $RPC_URL)"
echo "LM.oiLimits: $(cast call $LEVERAGE_MODEL 'oiLimits()(address)' --rpc-url $RPC_URL)"
# All must be NEW addresses

# BorrowFeeEngine
echo "BFE.oiLimits: $(cast call $BORROW_FEE_ENGINE 'oiLimits()(address)' --rpc-url $RPC_URL)"
echo "BFE.positionManager: $(cast call $BORROW_FEE_ENGINE 'positionManager()(address)' --rpc-url $RPC_URL)"

# FundingRateEngine
echo "FRE.oiLimits: $(cast call $FUNDING_RATE_ENGINE 'oiLimits()(address)' --rpc-url $RPC_URL)"
echo "FRE.positionManager: $(cast call $FUNDING_RATE_ENGINE 'positionManager()(address)' --rpc-url $RPC_URL)"

# MarginEngine
echo "ME.positionManager: $(cast call $MARGIN_ENGINE 'positionManager()(address)' --rpc-url $RPC_URL)"
echo "ME.borrowFeeEngine: $(cast call $MARGIN_ENGINE 'borrowFeeEngine()(address)' --rpc-url $RPC_URL)"
echo "ME.fundingRateEngine: $(cast call $MARGIN_ENGINE 'fundingRateEngine()(address)' --rpc-url $RPC_URL)"

# ExecutionEngine
echo "EE.positionManager: $(cast call $EXECUTION_ENGINE 'positionManager()(address)' --rpc-url $RPC_URL)"
echo "EE.oiLimits: $(cast call $EXECUTION_ENGINE 'oiLimits()(address)' --rpc-url $RPC_URL)"
echo "EE.marginEngine: $(cast call $EXECUTION_ENGINE 'marginEngine()(address)' --rpc-url $RPC_URL)"
echo "EE.leverVault: $(cast call $EXECUTION_ENGINE 'leverVault()(address)' --rpc-url $RPC_URL)"

# LiquidationEngine
echo "LE.positionManager: $(cast call $LIQUIDATION_ENGINE 'positionManager()(address)' --rpc-url $RPC_URL)"
echo "LE.executionEngine: $(cast call $LIQUIDATION_ENGINE 'executionEngine()(address)' --rpc-url $RPC_URL)"
echo "LE.oiLimits: $(cast call $LIQUIDATION_ENGINE 'oiLimits()(address)' --rpc-url $RPC_URL)"
echo "LE.leverVault: $(cast call $LIQUIDATION_ENGINE 'leverVault()(address)' --rpc-url $RPC_URL)"

# SettlementEngine
echo "SE.oiLimits: $(cast call $SETTLEMENT_ENGINE 'oiLimits()(address)' --rpc-url $RPC_URL)"
echo "SE.leverVault: $(cast call $SETTLEMENT_ENGINE 'leverVault()(address)' --rpc-url $RPC_URL)"
```

**GATE**: Every address must match. If ANY is wrong, the constructor args were scrambled. Fix before continuing.

---

## PHASE B: OI CAP MATH VERIFICATION

```bash
TVL=$(cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL | awk '{print $1}')
GLOBAL_CAP=$(cast call $OI_LIMITS "getGlobalOICap()(uint256)" --rpc-url $RPC_URL | awk '{print $1}')

python3 -c "
tvl = int('$TVL')
gc = int('$GLOBAL_CAP')
ratio = gc / tvl if tvl > 0 else 0
print(f'TVL: \${tvl/1e6:,.0f}')
print(f'Global Cap: \${gc/1e6:,.0f}')
print(f'Ratio: {ratio:.4f} (MUST be 0.60 ± 0.001)')
assert 0.599 < ratio < 0.601, f'FAIL: ratio is {ratio}, expected 0.60'
print('PASS')
"

# Per-market caps (check SpaceX)
SPACEX=0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1
MARKET_CAP=$(cast call $OI_LIMITS "getMarketOICap(bytes32)(uint256)" $SPACEX --rpc-url $RPC_URL | awk '{print $1}')
SIDE_CAP=$(cast call $OI_LIMITS "getSideOICap(bytes32)(uint256)" $SPACEX --rpc-url $RPC_URL | awk '{print $1}')
USER_CAP=$(cast call $OI_LIMITS "getUserOICap(bytes32)(uint256)" $SPACEX --rpc-url $RPC_URL | awk '{print $1}')

python3 -c "
mc = int('$MARKET_CAP'); sc = int('$SIDE_CAP'); uc = int('$USER_CAP')
print(f'Market Cap: \${mc/1e6:,.0f}')
print(f'Side Cap:   \${sc/1e6:,.0f} ({sc/mc:.2f} of market, expected 0.70)')
print(f'User Cap:   \${uc/1e6:,.0f} ({uc/mc:.2f} of market, expected 0.20)')
assert 0.69 < sc/mc < 0.71, 'FAIL: side ratio'
assert 0.19 < uc/mc < 0.21, 'FAIL: user ratio'
print('PASS')
"
```

---

## PHASE C: BORROW FEE VERIFICATION

### C1. Index accrual works
```bash
# Accrue and check index moved
IDX_BEFORE=$(cast call $BORROW_FEE_ENGINE "getBorrowIndex(bytes32,bool)(uint256)" $SPACEX true --rpc-url $RPC_URL | awk '{print $1}')
cast send $BORROW_FEE_ENGINE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000
sleep 5
IDX_AFTER=$(cast call $BORROW_FEE_ENGINE "getBorrowIndex(bytes32,bool)(uint256)" $SPACEX true --rpc-url $RPC_URL | awk '{print $1}')
echo "Before: $IDX_BEFORE After: $IDX_AFTER"
# IDX_AFTER must be >= IDX_BEFORE (equal if accrued very recently, > if time passed)
```

### C2. Position borrow fees accumulate over time
```bash
# After opening demo positions, wait 60s, accrue, check fees
sleep 60
cast send $BORROW_FEE_ENGINE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000
sleep 5
for PID in POSITION_IDS; do
    FEES=$(cast call $BORROW_FEE_ENGINE "getAccruedFees(uint256)(uint256)" $PID --rpc-url $RPC_URL | awk '{print $1}')
    echo "PID $PID fees: $FEES (must be > 0 for leveraged positions)"
done
```

### C3. Borrow rate is reasonable
```bash
# getCurrentBorrowRate should return ~0.02-0.10% per hour in WAD
RATE=$(cast call $BORROW_FEE_ENGINE "getCurrentBorrowRate(bytes32,bool)(uint256)" $SPACEX true --rpc-url $RPC_URL | awk '{print $1}')
python3 -c "
r = int('$RATE')
pct_per_hr = r / 1e18 * 100
print(f'Borrow rate: {pct_per_hr:.4f}% per hour')
assert 0.01 < pct_per_hr < 1.0, f'FAIL: rate {pct_per_hr}% outside expected range'
print('PASS')
"
```

### C4. depthThreshold set for all 10 markets
```bash
for MID in MARKET_IDS; do
    DT=$(cast call $BORROW_FEE_ENGINE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    echo "$MID depthThreshold=$DT (must be > 0)"
done
```

---

## PHASE D: FUNDING RATE VERIFICATION

### D1. All 10 markets initialized
```bash
for MID in MARKET_IDS; do
    IDX=$(cast call $FUNDING_RATE_ENGINE "getFundingIndex(bytes32)(int256)" $MID --rpc-url $RPC_URL 2>&1)
    echo "$MID fundingIndex=$IDX (must not revert)"
done
```

### D2. accrueFunding succeeds on all markets
```bash
for MID in MARKET_IDS; do
    cast send $FUNDING_RATE_ENGINE "accrueFunding(bytes32)" $MID \
        --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 300000 2>&1 | grep "status"
    sleep 3
done
```

### D3. Funding direction correct (heavy side pays)
```bash
# After opening positions: SpaceX has long OI only → longs should pay
# getAccruedFunding should be negative for long positions
PID_LONG=<spacex_long_pid>
FUNDING=$(cast call $FUNDING_RATE_ENGINE "getAccruedFunding(uint256)(int256)" $PID_LONG --rpc-url $RPC_URL)
echo "Long position funding: $FUNDING (should be negative = paying)"
```

### D4. depthThreshold set for all markets
```bash
for MID in MARKET_IDS; do
    DT=$(cast call $FUNDING_RATE_ENGINE "depthThreshold(bytes32)(uint256)" $MID --rpc-url $RPC_URL | awk '{print $1}')
    echo "$MID depthThreshold=$DT (must be > 0)"
done
```

---

## PHASE E: LIQUIDATION TEST

### E1. Open a tiny high-leverage position designed to be liquidatable
```bash
# Open $10 collateral at max leverage on a volatile market
# This will be near liquidation threshold immediately
DEMO_KEY=e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
SPACEX=0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1

# Get max leverage
MAX_LEV=$(cast call $LEVERAGE_MODEL "getEffectiveMaxLeverage(bytes32)(uint256)" $SPACEX --rpc-url $RPC_URL | awk '{print $1}')
echo "Max leverage: $MAX_LEV"

# Open position at max leverage with tiny collateral
cast send $EXECUTION_ENGINE "openPosition((bytes32,bool,uint256,uint256))" \
    "($SPACEX,true,10000000,$MAX_LEV)" \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 2000000
# Note the PID from the PositionOpened event or check totalPositions
```

### E2. Wait for borrow fees to erode equity, check liquidatability
```bash
# After 5-10 minutes of borrow accrual:
cast send $BORROW_FEE_ENGINE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000
sleep 5
LIQ_PID=<the_tiny_position_pid>
IS_LIQ=$(cast call $MARGIN_ENGINE "isLiquidatable(uint256)(bool)" $LIQ_PID --rpc-url $RPC_URL)
echo "isLiquidatable: $IS_LIQ"
```

### E3. Execute liquidation
```bash
cast send $LIQUIDATION_ENGINE "liquidate(uint256)" $LIQ_PID \
    --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 2000000 2>&1 | grep -E "status|gasUsed"
# status must be 1
# Verify position is now closed:
cast call $POSITION_MANAGER "isPositionOpen(uint256)(bool)" $LIQ_PID --rpc-url $RPC_URL
# Must be false
```

### E4. Verify liquidation accounting
```bash
# After liquidation:
# - Position closed in PositionManager ✓ (checked above)
# - OI decreased in OILimits
# - Insurance fund may have absorbed bad debt
# - Account balance adjusted
echo "Global OI after liq: $(cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL)"
echo "IF balance: $(cast call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL)"
```

---

## PHASE F: POSITION LIFECYCLE TEST

### F1. Open position
```bash
cast send $EXECUTION_ENGINE "openPosition((bytes32,bool,uint256,uint256))" \
    "($SPACEX,true,100000000,3000000000000000000)" \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 2000000
# Verify: totalOpenPositions increased, OI increased, AM balance decreased
```

### F2. Add collateral
```bash
cast send $EXECUTION_ENGINE "addCollateral(uint256,uint256)" PID 50000000 \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 500000
# Verify: position collateral increased
```

### F3. Close position
```bash
cast send $EXECUTION_ENGINE "closePosition(uint256)" PID \
    --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 2000000
# Verify: position closed, OI decreased, PnL settled, AM balance updated
OPEN_BEFORE=<count_before>
OPEN_AFTER=$(cast call $POSITION_MANAGER "totalOpenPositions()(uint256)" --rpc-url $RPC_URL)
echo "Positions: $OPEN_BEFORE → $OPEN_AFTER (must decrease by 1)"
```

### F4. Vault PnL impact
```bash
# If position had profit: vault totalAssets should decrease (vault paid trader)
# If position had loss: vault totalAssets should increase (vault took trader's loss)
echo "Vault TVL after close: $(cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL)"
```

---

## PHASE G: VAULT OPERATIONS TEST

### G1. Deposit
```bash
SHARES_BEFORE=$(cast call $LEVER_VAULT "balanceOf(address)(uint256)" $DEMO --rpc-url $RPC_URL)
cast send $USDT "approve(address,uint256)" $LEVER_VAULT 1000000000 --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 100000
sleep 3
cast send $LEVER_VAULT "deposit(uint256,address)" 100000000 $DEMO --private-key $DEMO_KEY --rpc-url $RPC_URL --gas-limit 300000
sleep 3
SHARES_AFTER=$(cast call $LEVER_VAULT "balanceOf(address)(uint256)" $DEMO --rpc-url $RPC_URL)
echo "Shares: $SHARES_BEFORE → $SHARES_AFTER (must increase)"
```

### G2. Share price sanity
```bash
SP=$(cast call $LEVER_VAULT "convertToAssets(uint256)(uint256)" 1000000000000000000 --rpc-url $RPC_URL | awk '{print $1}')
python3 -c "
sp = int('$SP') / 1e18
print(f'Share price: \${sp:.6f}')
assert 0.90 < sp < 1.10, f'FAIL: share price {sp} out of range'
print('PASS')
"
```

### G3. Withdrawal request
```bash
# requestWithdrawal exists? Check:
grep -n "function requestWithdrawal\|function withdraw\|function redeem" contracts/LeverVault.sol | head -5
# If withdrawal queue: request, wait 48h (skip for testnet), execute
# If direct: just call withdraw/redeem
```

### G4. Fee distribution check
```bash
# After a position close (which generates fees):
echo "RD pending yield: $(cast call $REWARDS_DISTRIBUTOR 'pendingYield(address)(uint256)' $DEMO --rpc-url $RPC_URL 2>/dev/null || echo 'check function name')"
echo "IF balance: $(cast call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL)"
# Fees should have been split 50% LP (→RD), 30% Protocol (→treasury), 20% Insurance (→IF)
```

---

## PHASE H: OI CAP ENFORCEMENT TEST

### H1. Try to exceed user OI cap
```bash
USER_CAP=$(cast call $OI_LIMITS "getUserOICap(bytes32)(uint256)" $SPACEX --rpc-url $RPC_URL | awk '{print $1}')
echo "User cap: $USER_CAP"
# Try opening a position larger than the user cap
# Should revert with OILimits__UserCapExceeded
cast call $EXECUTION_ENGINE "openPosition((bytes32,bool,uint256,uint256))" \
    "($SPACEX,true,999999000000,2000000000000000000)" \
    --from $DEMO --rpc-url $RPC_URL 2>&1
# Must revert
```

### H2. Verify OI tracks correctly
```bash
OI_BEFORE=$(cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL)
# Open a position...
OI_AFTER=$(cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL)
echo "OI: $OI_BEFORE → $OI_AFTER (must increase by position notional)"
# Close the position...
OI_FINAL=$(cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL)
echo "OI after close: $OI_FINAL (must return to ~$OI_BEFORE)"
```

---

## PHASE I: FRONTEND DATA CONSISTENCY

### I1. Stats bar vs on-chain
```bash
# Read on-chain values, compare to what frontend should display
TVL=$(cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL | awk '{print $1}')
OI=$(cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL | awk '{print $1}')
python3 -c "
tvl = int('$TVL'); oi = int('$OI')
util = oi / tvl * 100 if tvl > 0 else 0
print(f'Frontend should show:')
print(f'  TVL: \${tvl/1e6:,.2f}')
print(f'  OI:  \${oi/1e6:,.2f}')
print(f'  Utilization: {util:.2f}%')
"
# Visually compare with what the browser shows
```

### I2. Cross-tab consistency
```
Stats bar TVL must equal Vault tab TVL
Stats bar APY must equal Vault tab APY (within 0.1%)
Stats bar OI must equal sum of all position notionals
Position count in Positions tab must equal totalOpenPositions on-chain
Each position's borrow fee in UI must match getAccruedFees on-chain (within 1 minute lag)
```

### I3. Price display — no stale flash
```
Load the page fresh (hard refresh).
Markets tab prices must NOT briefly show 50% or 65% before jumping to real values.
Prices should either show a loading skeleton OR the correct price immediately.
```

### I4. Demo mode verification
```
Header should show "DEMO 0xafB3...34Da" (not a connected wallet address)
All positions should be demo wallet's positions
Vault shares should show demo wallet's shares
Trading should auto-fund from demo wallet
```

### I5. Error handling
```
Try opening position with 0 collateral → should show error toast, not crash
Try opening position exceeding leverage → should show error with max leverage
Try depositing 0 into vault → should be disabled or show error
```

---

## PHASE J: KEEPER VERIFICATION

### J1. Oracle keeper running and prices fresh
```bash
systemctl is-active lever-oracle
# Check prices.json timestamp is < 60s old
python3 -c "
import json, time
d = json.load(open('/home/lever/lever-protocol/frontend/user-app/public/prices.json'))
age = time.time() - d['lastUpdate']
print(f'Price age: {age:.0f}s (must be < 60s)')
assert age < 120, f'FAIL: prices are {age:.0f}s old'
"
```

### J2. Accrue keeper running and updating indices
```bash
systemctl is-active lever-accrue-keeper
# Check that borrow indices are moving over 2 minutes
IDX1=$(cast call $BORROW_FEE_ENGINE "getBorrowIndex(bytes32,bool)(uint256)" $SPACEX true --rpc-url $RPC_URL | awk '{print $1}')
sleep 120
IDX2=$(cast call $BORROW_FEE_ENGINE "getBorrowIndex(bytes32,bool)(uint256)" $SPACEX true --rpc-url $RPC_URL | awk '{print $1}')
python3 -c "
i1 = int('$IDX1'); i2 = int('$IDX2')
print(f'Index: {i1} → {i2}')
assert i2 > i1, 'FAIL: borrow index not moving — keeper may not be working'
print('PASS')
"
```

### J3. No nonce conflict errors
```bash
# Check keeper logs for nonce errors
journalctl -u lever-oracle --no-pager -n 20 2>/dev/null | grep -c "nonce"
journalctl -u lever-accrue-keeper --no-pager -n 20 2>/dev/null | grep -c "nonce"
# Both should be 0 or very low
```

---

## PHASE K: FULL TAB-BY-TAB WALKTHROUGH

### K1. Markets Tab
- [ ] All 10 markets visible with names and categories
- [ ] Prices are live (match prices.json), NOT stale 50%/65%
- [ ] "LIVE" badge (not "DEMO DATA") on each market
- [ ] Long/Short buttons visible and clickable on each
- [ ] Time to resolution shows correct dates
- [ ] Market detail link works for each market

### K2. Trading Tab
- [ ] Market dropdown shows all 10 markets
- [ ] Selecting market updates leverage slider max
- [ ] Max Position / Max Collateral display shows correct values
- [ ] OI Capacity breakdown shows correct caps and current usage
- [ ] Binding constraint correctly identifies tightest limit
- [ ] "Open Position" button works in demo mode
- [ ] After opening: success toast, position count updates
- [ ] Error toast for invalid inputs (0 collateral, etc.)

### K3. Positions Tab
- [ ] Shows all open demo wallet positions
- [ ] Each position shows: market name, direction (LONG/SHORT), collateral, notional, entry price
- [ ] Current price matches prices.json
- [ ] Unrealized PnL is calculated and displayed
- [ ] Borrow fees show non-zero (accruing) values
- [ ] Funding shows non-zero values (negative for heavy side)
- [ ] "Close Position" button works
- [ ] After closing: position disappears, success toast

### K4. Vault Tab
- [ ] TVL matches on-chain totalAssets()
- [ ] Share price shows ~$1.00
- [ ] APY shows reasonable number (same as stats bar within 0.1%)
- [ ] Utilization matches stats bar
- [ ] Demo wallet shares shown (non-zero)
- [ ] Wallet USDT balance shown
- [ ] "Approve USDT" button works
- [ ] "Deposit" button works (with amount)
- [ ] After deposit: shares increase, TVL increases
- [ ] Pending yield display (may be 0 if vault is fresh — that's OK)
- [ ] "Claim Rewards" button works (or shows "nothing to claim")
- [ ] "Compound" button works (or shows "nothing to compound")

### K5. Market Detail Tab
- [ ] Select any market → detail page loads
- [ ] Price/probability displayed correctly
- [ ] Resolution date shown
- [ ] OI breakdown bar shows both Long and Short sides
- [ ] Even very small sides are visible (min 2% width)
- [ ] Borrow rate shown (hourly, non-zero)
- [ ] Back button returns to markets list

### K6. Stats Bar
- [ ] TVL matches vault totalAssets
- [ ] OI matches OILimits.getGlobalOI
- [ ] Utilization = OI / TVL (can exceed 100%)
- [ ] APY matches useRealAPY calculation
- [ ] Volume shows real number (from PositionOpened events)
- [ ] Insurance Fund shows real balance
- [ ] All badges show "LIVE" (not "DEMO DATA")

### K7. Status Bar (bottom)
- [ ] Shows "SYSTEM OPERATIONAL"
- [ ] CONTRACTS shows "OPERATIONAL" (no random DEGRADED)
- [ ] Network latency shows real ms value
- [ ] No error badges

---

## FINAL GATE

ALL phases A through K must pass before committing. If any phase fails, fix the issue and re-run that phase before moving to the next.

After all pass:
```bash
cd /home/lever/lever-protocol
git add -A
git commit -m "full redeploy: all 11 contracts with correct refs, init, and verified

<details of what was deployed>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git push origin main
```

---

## EXECUTION SEQUENCE SUMMARY

```
1. Stop all keepers (oracle, accrue, liquidator)
2. Verify nonce stability
3. forge build (compile all)
4. Deploy 11 contracts in order (Layers 1-11)
5. Grant ~30 ENGINE/KEEPER roles
6. Initialize BFE (depthThreshold + accrueAll) for 10 markets
7. Initialize FRE (initializeMarketIndex + updateMarketRiskParams) for 10 markets
8. Initialize ME (depthThreshold) for 10 markets
9. Seed TVL ($500K deployer deposit to vault)
10. Fund InsuranceFund ($10K USDT transfer)
11. Close all orphaned positions in PositionManager
12. Setup demo wallet (ETH, USDT, AM deposit, vault deposit)
13. Open 4 demo positions
14. Update deploy-env.sh, contracts.ts, deployment JSONs, CLAUDE.md, CONTEXT.md
15. Update useVolumeCalculation DEPLOYMENT_BLOCK
16. Remove oiLimitsNew from Trading.tsx
17. Build frontend, strip CSP, restart
18. Restart keepers (oracle, accrue)
19. Wait 60s for prices to converge
20. Run full verification checklist
21. Git commit and push
```
