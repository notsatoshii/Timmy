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

## VERIFICATION CHECKLIST (MUST ALL PASS)

### 1. Contract references (verify every immutable)
```bash
for each new contract:
  cast call NEW_CONTRACT "vault()(address)" → should be NEW_VAULT
  cast call NEW_CONTRACT "oiLimits()(address)" → should be NEW_OI
  etc.
```

### 2. OI caps correct
```bash
cast call NEW_OI "getGlobalOICap()(uint256)"  # should be ~60% of TVL
```

### 3. Borrow fees accruing
```bash
cast call NEW_BFE "getAccruedFees(uint256)(uint256)" PID  # should be > 0 after accrual
```

### 4. Funding rates working
```bash
cast call NEW_FRE "getFundingIndex(bytes32)(int256)" MARKET_ID  # should not revert
cast call NEW_FRE "getAccruedFunding(uint256)(int256)" PID  # should return value
```

### 5. Liquidation works
```bash
# Open a small 30x position, wait for it to become liquidatable, then:
cast call NEW_ME "isLiquidatable(uint256)(bool)" PID  # true
cast send NEW_LE "liquidate(uint256)" PID --gas-limit 2000000  # should succeed
```

### 6. Frontend data matches on-chain
```
TVL in stats bar = cast call NEW_VAULT "totalAssets()"
OI in stats bar = cast call NEW_OI "getGlobalOI()"
Share price = cast call NEW_VAULT "convertToAssets(1e18)"
Positions show correct borrow fees
Prices match prices.json (no stale flash)
Status bar shows OPERATIONAL
Volume shows real number (not $0 or —)
```

### 7. All tabs functional
- Markets: 10 markets, live prices, Long/Short buttons
- Trading: select market, open position, verify on-chain
- Positions: show all positions, close one, verify
- Vault: deposit, withdraw (request), claim, compound
- MarketDetail: OI breakdown, borrow rate, price chart

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
