# LEVER Protocol — Full Redeployment Handoff v2 (FINAL)

**Created:** March 20, 2026  
**Supersedes:** All previous handoff docs  
**Purpose:** Zero-placeholder redeployment plan. Every command is copy-paste ready.  
**Execution:** Open Claude Code on the server, point it at this file, let it execute.

---

## 1. WHAT'S BROKEN AND WHY

### Bug 1: LeverVault → Wrong RewardsDistributor
LeverVault (`0x84a1Eb...`) was deployed pointing to empty RD (`0x77F8...`).  
Correct RD with $500K USDT: `0xab8DFA8cF72b054c356961026F8648dB7D860Cb0`.  
`rewardsDistributor` is immutable. Must redeploy vault.  
**Cascades to:** ExecutionEngine and SettlementEngine (both hold vault as immutable).

### Bug 2: LiquidationEngine — Constructor Args Were Scrambled
The original deployment passed constructor args **in the wrong order**. Audit results:

| Getter | Returns | What That Address Actually Is | Correct Value |
|--------|---------|-------------------------------|---------------|
| `positionManager()` | `0xf069...` | OracleAdapter | `0x25ba...` (PositionManager) |
| `leverVault()` | `0x39Ac...` | InsuranceFund | NEW_VAULT |
| `executionEngine()` | `0x25ba...` | PositionManager | NEW_EXEC |
| `marginEngine()` | `0xd4e8...` | ✅ Correct | — |

Every call to LiquidationEngine hits the wrong contract. Must redeploy.

### Stale Address Audit — Other Contracts Are Clean
| Contract | leverVault() | positionManager() | Verdict |
|----------|-------------|-------------------|---------|
| ExecutionEngine | `0x84a1...` (old vault) | `0x25ba...` ✅ | Redeploy (vault ref) |
| FeeRouter | N/A (no getter) | N/A | ✅ SAFE |
| AccountManager | N/A (no getter) | N/A | ✅ SAFE |
| MarginEngine | N/A (no getter) | `0x25ba...` ✅ | ✅ SAFE |

**Total contracts to redeploy: 4** (LeverVault, ExecutionEngine, SettlementEngine, LiquidationEngine)  
**No additional cascade discovered.**

---

## 2. COMPLETE ADDRESS REGISTRY

### ✅ KEEP — Do Not Redeploy
```
DEPLOYER             = 0x0e4D636c6D79c380A137f28EF73E054364cd5434
USDT                 = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E
MarketRegistry       = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
OracleAdapter        = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c
AccountManager       = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
PositionManager      = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b
LeverageModel        = 0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed
OILimits             = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd
BorrowFeeEngine      = 0x706578de003912C71e534949d8b8DDd5108950e1
FundingRateEngine    = 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
MarginEngine         = 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
RewardsDistributor   = 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0
InsuranceFund        = 0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8
FeeRouter            = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F
```

### ❌ REDEPLOY — Old Addresses (for reference / revoke roles)
```
OLD LeverVault       = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921
OLD ExecutionEngine  = 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D
OLD SettlementEngine = 0x9c7E9496A25Bf06f163A4483e5702ac350e8e9aD
OLD LiquidationEngine= 0x2A42Ef441CAbF34D3Ff9B9867CAf4Ae087FEC42E
```

### Demo Wallet
```
Address:     0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
Private Key: e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
```

---

## 3. SERVER ACCESS

```bash
ssh root@165.245.186.254
cd /home/lever/lever-protocol
source control-plane/deploy-env.sh
```

### Key Paths
```
/home/lever/lever-protocol/contracts/                             # Solidity source
/home/lever/lever-protocol/out/                                   # Compiled ABIs
/home/lever/lever-protocol/control-plane/deploy-env.sh            # All env vars
/home/lever/lever-protocol/frontend/user-app/                     # React frontend
/home/lever/lever-protocol/frontend/user-app/public/deployments/  # Address JSONs
/home/lever/lever-protocol/scripts/liquidator-bot.sh              # Liquidator keeper
```

### Services — Running (keep alive)
```
lever-bot, lever-frontend, lever-oracle, lever-fee-keeper, lever-accrue-keeper, lever-dashboard
```

### Services — Disabled (do NOT restart)
```
lever-loop, lever-qa, lever-seeder, lever-watchdog
```

### Redundant Process — Kill Before Starting
```bash
# Nohup borrow keeper is duplicate of lever-accrue-keeper systemd service
kill 2429674 2>/dev/null
```

---

## 4. DEPLOYMENT — EXACT COMMANDS

### Order matters:
```
Step 0:  Pause all keepers (prevent nonce conflicts during deploy)
Step 1:  forge build
Step 2:  Deploy LeverVault (no dependencies on other new contracts)
Step 3:  Grant LEVER_VAULT_ROLE on RewardsDistributor to new vault
Step 4:  Deploy ExecutionEngine (needs NEW_VAULT)
Step 5:  Deploy SettlementEngine (needs NEW_VAULT)
Step 6:  Deploy LiquidationEngine (needs NEW_VAULT + NEW_EXEC)
Step 7:  Grant ALL 18 roles across 6 contracts
Step 8:  Update deploy-env.sh with 4 new addresses
Step 9:  Update frontend deployment JSONs + verify frontend wiring
Step 10: Rebuild frontend
Step 11: Restart keepers
Step 12: Seed demo data (vault TVL)
Step 13: Integration tests (open, close, liquidate — prove it works end-to-end)
Step 14: Verify everything (read checks + frontend manual checks)
Step 15: Git commit and push
```

---

### Step 0: Pause keepers to prevent nonce conflicts

All keepers use the same `$PRIVATE_KEY` as deployment. If a keeper sends a tx mid-deploy, nonces collide and the deploy reverts. Pause everything first.

```bash
cd /home/lever/lever-protocol
source control-plane/deploy-env.sh

# Stop systemd keepers
systemctl stop lever-fee-keeper
systemctl stop lever-accrue-keeper

# Kill nohup borrow keeper (redundant with accrue-keeper anyway)
kill 2429674 2>/dev/null

# Kill liquidator bot
pkill -f "liquidator-bot" 2>/dev/null

# Verify nothing is sending transactions:
ps aux | grep -E "cast send|accrueAll|distributeFees|liquidator" | grep -v grep
# Should return nothing
```

> ⚠ Keepers are OFF. Borrow indices will not accrue and fees will not distribute until Step 11 restarts them. This is fine — indices resume cleanly from wherever they left off.

---

### Step 1: Compile
```bash
cd /home/lever/lever-protocol
source control-plane/deploy-env.sh
forge build
```
If this fails, fix compile errors before proceeding.

---

### Step 2: Deploy new LeverVault

**Constructor:** `(address admin_, address usdt_, address rewardsDistributor_)`

```bash
forge create contracts/LeverVault.sol:LeverVault \
  --constructor-args \
    0x0e4D636c6D79c380A137f28EF73E054364cd5434 \
    0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E \
    0xab8DFA8cF72b054c356961026F8648dB7D860Cb0 \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Save the deployed address:**
```bash
export NEW_VAULT=<paste deployed address here>
echo "NEW_VAULT=$NEW_VAULT"
```

**Verify it points to correct RD:**
```bash
cast call $NEW_VAULT "rewardsDistributor()(address)" --rpc-url $RPC_URL
# MUST return: 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0
```

---

### Step 3: Grant LEVER_VAULT_ROLE on RewardsDistributor

```bash
LEVER_VAULT_ROLE=$(cast keccak "LEVER_VAULT_ROLE")
cast send 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0 \
  "grantRole(bytes32,address)" $LEVER_VAULT_ROLE $NEW_VAULT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Verify:**
```bash
cast call 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0 \
  "hasRole(bytes32,address)(bool)" $LEVER_VAULT_ROLE $NEW_VAULT \
  --rpc-url $RPC_URL
# MUST return: true
```

---

### Step 4: Deploy new ExecutionEngine

**Constructor:** `(positionManager, oiLimits, marginEngine, oracleAdapter, marketRegistry, leverageModel, feeRouter, borrowFeeEngine, fundingRateEngine, accountManager, leverVault, admin)`

```bash
forge create contracts/ExecutionEngine.sol:ExecutionEngine \
  --constructor-args \
    0x25ba54a7b2fBac753B601Da05e3661F2E959510b \
    0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd \
    0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce \
    0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c \
    0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7 \
    0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed \
    0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F \
    0x706578de003912C71e534949d8b8DDd5108950e1 \
    0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe \
    0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684 \
    $NEW_VAULT \
    0x0e4D636c6D79c380A137f28EF73E054364cd5434 \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Save:**
```bash
export NEW_EXEC=<paste deployed address here>
echo "NEW_EXEC=$NEW_EXEC"
```

**Verify:**
```bash
cast call $NEW_EXEC "leverVault()(address)" --rpc-url $RPC_URL
# MUST return: $NEW_VAULT

cast call $NEW_EXEC "positionManager()(address)" --rpc-url $RPC_URL
# MUST return: 0x25ba54a7b2fBac753B601Da05e3661F2E959510b
```

---

### Step 5: Deploy new SettlementEngine

**Constructor:** `(admin_, marketRegistry_, positionManager_, oracleAdapter_, borrowFeeEngine_, fundingRateEngine_, insuranceFund_, feeRouter_, oiLimits_, accountManager_, leverVault_)`

```bash
forge create contracts/SettlementEngine.sol:SettlementEngine \
  --constructor-args \
    0x0e4D636c6D79c380A137f28EF73E054364cd5434 \
    0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7 \
    0x25ba54a7b2fBac753B601Da05e3661F2E959510b \
    0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c \
    0x706578de003912C71e534949d8b8DDd5108950e1 \
    0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe \
    0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8 \
    0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F \
    0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd \
    0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684 \
    $NEW_VAULT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Save:**
```bash
export NEW_SETTLEMENT=<paste deployed address here>
echo "NEW_SETTLEMENT=$NEW_SETTLEMENT"
```

**Verify:**
```bash
cast call $NEW_SETTLEMENT "leverVault()(address)" --rpc-url $RPC_URL
# MUST return: $NEW_VAULT
```

---

### Step 6: Deploy new LiquidationEngine

**Constructor:** `(admin_, marginEngine_, positionManager_, executionEngine_, oiLimits_, accountManager_, insuranceFund_, feeRouter_, leverVault_, marketRegistry_)`

> ⚠ This is the contract that was originally deployed with scrambled args. The order below matches the Solidity source EXACTLY.

```bash
forge create contracts/LiquidationEngine.sol:LiquidationEngine \
  --constructor-args \
    0x0e4D636c6D79c380A137f28EF73E054364cd5434 \
    0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce \
    0x25ba54a7b2fBac753B601Da05e3661F2E959510b \
    $NEW_EXEC \
    0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd \
    0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684 \
    0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8 \
    0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F \
    $NEW_VAULT \
    0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7 \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Save:**
```bash
export NEW_LIQUIDATION=<paste deployed address here>
echo "NEW_LIQUIDATION=$NEW_LIQUIDATION"
```

**Verify all getters are correct:**
```bash
cast call $NEW_LIQUIDATION "positionManager()(address)" --rpc-url $RPC_URL
# MUST return: 0x25ba54a7b2fBac753B601Da05e3661F2E959510b

cast call $NEW_LIQUIDATION "executionEngine()(address)" --rpc-url $RPC_URL
# MUST return: $NEW_EXEC

cast call $NEW_LIQUIDATION "leverVault()(address)" --rpc-url $RPC_URL
# MUST return: $NEW_VAULT

cast call $NEW_LIQUIDATION "marginEngine()(address)" --rpc-url $RPC_URL
# MUST return: 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
```

---

### Step 7: Grant ALL roles to new contracts (18 grants across 6 contracts)

> **This step is the most critical in the entire deployment.**
> Source code audit of ALL contracts confirmed these exact requirements.
> The original handoff doc had 3 grants. The real number is 18.
> Missing ANY single grant causes a specific user-facing action to revert.

```bash
# ═══════════════════════════════════════
# ROLE HASHES — note ENGINE vs ENGINE_ROLE
# ═══════════════════════════════════════
ENGINE_ROLE=$(cast keccak "ENGINE_ROLE")                     # PositionManager uses this
AM_ENGINE=$(cast keccak "ENGINE")                             # AccountManager uses "ENGINE" (different!)
EXEC_ENGINE_ROLE=$(cast keccak "EXECUTION_ENGINE_ROLE")
LIQ_ENGINE_ROLE=$(cast keccak "LIQUIDATION_ENGINE_ROLE")
SETTLEMENT_ENGINE_ROLE=$(cast keccak "SETTLEMENT_ENGINE_ROLE")

# ═══════════════════════════════════════
# CONTRACT REFERENCES
# ═══════════════════════════════════════
PM=0x25ba54a7b2fBac753B601Da05e3661F2E959510b
AM=0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
IF=0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8
OI=0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd
FR=0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F

# ─────────────────────────────────────────
# GRANTS 1-3: PositionManager → ENGINE_ROLE
# Without: engines cannot open/close/modify positions
# ─────────────────────────────────────────
echo "--- [1/18] PositionManager → ExecEngine ---"
cast send $PM "grantRole(bytes32,address)" $ENGINE_ROLE $NEW_EXEC \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [2/18] PositionManager → SettlementEngine ---"
cast send $PM "grantRole(bytes32,address)" $ENGINE_ROLE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [3/18] PositionManager → LiquidationEngine ---"
cast send $PM "grantRole(bytes32,address)" $ENGINE_ROLE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANTS 4-6: AccountManager → ENGINE (note: "ENGINE" not "ENGINE_ROLE")
# Without: lockCollateral, creditPnL, debitPnL, transferOut ALL revert
# This means NO positions can open, close, or settle
# ─────────────────────────────────────────
echo "--- [4/18] AccountManager → ExecEngine ---"
cast send $AM "grantRole(bytes32,address)" $AM_ENGINE $NEW_EXEC \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [5/18] AccountManager → SettlementEngine ---"
cast send $AM "grantRole(bytes32,address)" $AM_ENGINE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [6/18] AccountManager → LiquidationEngine ---"
cast send $AM "grantRole(bytes32,address)" $AM_ENGINE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANTS 7-9: NEW LeverVault roles
# Without 7: winning traders CANNOT get paid (fundTraderPnL reverts)
# Without 8-9: bad debt cannot be socialized to LPs (socializeLoss reverts)
# ─────────────────────────────────────────
echo "--- [7/18] Vault → ExecEngine (EXECUTION_ENGINE_ROLE) ---"
cast send $NEW_VAULT "grantRole(bytes32,address)" $EXEC_ENGINE_ROLE $NEW_EXEC \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [8/18] Vault → LiquidationEngine (LIQUIDATION_ENGINE_ROLE) ---"
cast send $NEW_VAULT "grantRole(bytes32,address)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [9/18] Vault → SettlementEngine (LIQUIDATION_ENGINE_ROLE) ---"
cast send $NEW_VAULT "grantRole(bytes32,address)" $LIQ_ENGINE_ROLE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANTS 10-12: OILimits roles
# Without: position opens revert (can't update OI), liquidations revert, settlements revert
# ─────────────────────────────────────────
echo "--- [10/18] OILimits → ExecEngine ---"
cast send $OI "grantRole(bytes32,address)" $EXEC_ENGINE_ROLE $NEW_EXEC \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [11/18] OILimits → LiquidationEngine ---"
cast send $OI "grantRole(bytes32,address)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [12/18] OILimits → SettlementEngine ---"
cast send $OI "grantRole(bytes32,address)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANTS 13-15: FeeRouter roles
# Without: fee routing reverts on every trade close, liquidation, and settlement
# ─────────────────────────────────────────
echo "--- [13/18] FeeRouter → ExecEngine ---"
cast send $FR "grantRole(bytes32,address)" $EXEC_ENGINE_ROLE $NEW_EXEC \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [14/18] FeeRouter → LiquidationEngine ---"
cast send $FR "grantRole(bytes32,address)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [15/18] FeeRouter → SettlementEngine ---"
cast send $FR "grantRole(bytes32,address)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANTS 16-17: InsuranceFund roles
# Without: bad debt absorption reverts (absorbBadDebt is role-gated)
# ─────────────────────────────────────────
echo "--- [16/18] InsuranceFund → LiquidationEngine ---"
cast send $IF "grantRole(bytes32,address)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
echo "--- [17/18] InsuranceFund → SettlementEngine ---"
cast send $IF "grantRole(bytes32,address)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# ─────────────────────────────────────────
# GRANT 18: RewardsDistributor — already done in Step 3 but verify here
# ─────────────────────────────────────────
echo "--- [18/18] Verify RD → Vault (from Step 3) ---"
LEVER_VAULT_ROLE=$(cast keccak "LEVER_VAULT_ROLE")
cast call 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0 \
  "hasRole(bytes32,address)(bool)" $LEVER_VAULT_ROLE $NEW_VAULT --rpc-url $RPC_URL
```

**Verify ALL 18 grants (DO NOT SKIP — each "false" here is a broken feature):**
```bash
echo "═══ PositionManager ═══"
echo "[1] ExecEngine ENGINE_ROLE:"
cast call $PM "hasRole(bytes32,address)(bool)" $ENGINE_ROLE $NEW_EXEC --rpc-url $RPC_URL
echo "[2] Settlement ENGINE_ROLE:"
cast call $PM "hasRole(bytes32,address)(bool)" $ENGINE_ROLE $NEW_SETTLEMENT --rpc-url $RPC_URL
echo "[3] Liquidation ENGINE_ROLE:"
cast call $PM "hasRole(bytes32,address)(bool)" $ENGINE_ROLE $NEW_LIQUIDATION --rpc-url $RPC_URL

echo "═══ AccountManager ═══"
echo "[4] ExecEngine ENGINE:"
cast call $AM "hasRole(bytes32,address)(bool)" $AM_ENGINE $NEW_EXEC --rpc-url $RPC_URL
echo "[5] Settlement ENGINE:"
cast call $AM "hasRole(bytes32,address)(bool)" $AM_ENGINE $NEW_SETTLEMENT --rpc-url $RPC_URL
echo "[6] Liquidation ENGINE:"
cast call $AM "hasRole(bytes32,address)(bool)" $AM_ENGINE $NEW_LIQUIDATION --rpc-url $RPC_URL

echo "═══ LeverVault ═══"
echo "[7] ExecEngine EXECUTION_ENGINE_ROLE:"
cast call $NEW_VAULT "hasRole(bytes32,address)(bool)" $EXEC_ENGINE_ROLE $NEW_EXEC --rpc-url $RPC_URL
echo "[8] Liquidation LIQUIDATION_ENGINE_ROLE:"
cast call $NEW_VAULT "hasRole(bytes32,address)(bool)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION --rpc-url $RPC_URL
echo "[9] Settlement LIQUIDATION_ENGINE_ROLE:"
cast call $NEW_VAULT "hasRole(bytes32,address)(bool)" $LIQ_ENGINE_ROLE $NEW_SETTLEMENT --rpc-url $RPC_URL

echo "═══ OILimits ═══"
echo "[10] ExecEngine EXECUTION_ENGINE_ROLE:"
cast call $OI "hasRole(bytes32,address)(bool)" $EXEC_ENGINE_ROLE $NEW_EXEC --rpc-url $RPC_URL
echo "[11] Liquidation LIQUIDATION_ENGINE_ROLE:"
cast call $OI "hasRole(bytes32,address)(bool)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION --rpc-url $RPC_URL
echo "[12] Settlement SETTLEMENT_ENGINE_ROLE:"
cast call $OI "hasRole(bytes32,address)(bool)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT --rpc-url $RPC_URL

echo "═══ FeeRouter ═══"
echo "[13] ExecEngine EXECUTION_ENGINE_ROLE:"
cast call $FR "hasRole(bytes32,address)(bool)" $EXEC_ENGINE_ROLE $NEW_EXEC --rpc-url $RPC_URL
echo "[14] Liquidation LIQUIDATION_ENGINE_ROLE:"
cast call $FR "hasRole(bytes32,address)(bool)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION --rpc-url $RPC_URL
echo "[15] Settlement SETTLEMENT_ENGINE_ROLE:"
cast call $FR "hasRole(bytes32,address)(bool)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT --rpc-url $RPC_URL

echo "═══ InsuranceFund ═══"
echo "[16] Liquidation LIQUIDATION_ENGINE_ROLE:"
cast call $IF "hasRole(bytes32,address)(bool)" $LIQ_ENGINE_ROLE $NEW_LIQUIDATION --rpc-url $RPC_URL
echo "[17] Settlement SETTLEMENT_ENGINE_ROLE:"
cast call $IF "hasRole(bytes32,address)(bool)" $SETTLEMENT_ENGINE_ROLE $NEW_SETTLEMENT --rpc-url $RPC_URL

echo "═══ RewardsDistributor ═══"
echo "[18] Vault LEVER_VAULT_ROLE:"
cast call 0xab8DFA8cF72b054c356961026F8648dB7D860Cb0 \
  "hasRole(bytes32,address)(bool)" $LEVER_VAULT_ROLE $NEW_VAULT --rpc-url $RPC_URL

echo ""
echo "ALL 18 MUST BE true. Any false = broken feature."
```

---

### Step 8: Update deploy-env.sh

```bash
sed -i "s|^export LEVER_VAULT=.*|export LEVER_VAULT=$NEW_VAULT|" /home/lever/lever-protocol/control-plane/deploy-env.sh
sed -i "s|^export EXECUTION_ENGINE=.*|export EXECUTION_ENGINE=$NEW_EXEC|" /home/lever/lever-protocol/control-plane/deploy-env.sh
sed -i "s|^export SETTLEMENT_ENGINE=.*|export SETTLEMENT_ENGINE=$NEW_SETTLEMENT|" /home/lever/lever-protocol/control-plane/deploy-env.sh
sed -i "s|^export LIQUIDATION_ENGINE=.*|export LIQUIDATION_ENGINE=$NEW_LIQUIDATION|" /home/lever/lever-protocol/control-plane/deploy-env.sh

# Re-source and verify:
source /home/lever/lever-protocol/control-plane/deploy-env.sh
echo "LEVER_VAULT=$LEVER_VAULT"
echo "EXECUTION_ENGINE=$EXECUTION_ENGINE"
echo "SETTLEMENT_ENGINE=$SETTLEMENT_ENGINE"
echo "LIQUIDATION_ENGINE=$LIQUIDATION_ENGINE"
```

---

### Step 9: Update frontend deployment JSONs + contracts.ts fallbacks

**9a. Update deployment JSONs with exact sed commands:**

```bash
cd /home/lever/lever-protocol

# pool-deployment.json — update leverVault only (other 3 are unchanged)
sed -i "s|0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921|$NEW_VAULT|g" \
  frontend/user-app/public/deployments/pool-deployment.json

# engines-deployment.json — update executionEngine, liquidationEngine, settlementEngine
sed -i "s|0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D|$NEW_EXEC|g" \
  frontend/user-app/public/deployments/engines-deployment.json
sed -i "s|0x2A42Ef441CAbF34D3Ff9B9867CAf4Ae087FEC42E|$NEW_LIQUIDATION|g" \
  frontend/user-app/public/deployments/engines-deployment.json
sed -i "s|0x9c7E9496A25Bf06f163A4483e5702ac350e8e9aD|$NEW_SETTLEMENT|g" \
  frontend/user-app/public/deployments/engines-deployment.json

# core-deployment.json — no changes needed (all contracts unchanged)

# Verify:
echo "=== pool ==="
cat frontend/user-app/public/deployments/pool-deployment.json
echo "=== engines ==="
cat frontend/user-app/public/deployments/engines-deployment.json
```

**9b. CRITICAL — Update fallback addresses in contracts.ts:**

> The frontend loads addresses from JSONs at runtime via `fetch()`, but
> `src/config/contracts.ts` has hardcoded FALLBACK addresses starting at line 142.
> If JSON fetch fails (which causes white screens), it uses these stale addresses.
> **Both JSONs AND fallbacks must be updated or trades will silently hit old contracts.**

```bash
cd /home/lever/lever-protocol/frontend/user-app

# Update fallback addresses in contracts.ts
sed -i "s|0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921|$NEW_VAULT|g" src/config/contracts.ts
sed -i "s|0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D|$NEW_EXEC|g" src/config/contracts.ts
sed -i "s|0x2A42Ef441CAbF34D3Ff9B9867CAf4Ae087FEC42E|$NEW_LIQUIDATION|g" src/config/contracts.ts
sed -i "s|0x9c7E9496A25Bf06f163A4483e5702ac350e8e9aD|$NEW_SETTLEMENT|g" src/config/contracts.ts

# Verify no old addresses remain anywhere in frontend:
echo "=== Checking for ANY stale addresses in entire frontend ==="
grep -rn "0x84a1Eb" src/ 2>/dev/null
grep -rn "0xc749C6" src/ 2>/dev/null
grep -rn "0x2A42Ef" src/ 2>/dev/null
grep -rn "0x9c7E94" src/ 2>/dev/null
# ALL should return nothing
```

**9c. ABIs — no changes needed:**
ABIs live in `src/config/abis` (hand-maintained, not from `out/`). Since we're redeploying
identical source code, all interfaces are unchanged. No ABI updates required.

---

### Step 10: Rebuild frontend

```bash
cd /home/lever/lever-protocol/frontend/user-app
npx react-app-rewired build 2>&1 | tail -5
sed -i 's/<meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"\/>//' build/index.html
systemctl restart lever-frontend
```

**Verify page loads:**
```bash
curl -s http://165.245.186.254:3000 | head -5
```
Also check in a browser: `http://165.245.186.254:3000`

---

### Step 11: Restart keepers

All keepers source `deploy-env.sh` at startup, so updating the env file (Step 8) is sufficient — just restart.

```bash
# Kill redundant nohup borrow keeper
kill 2429674 2>/dev/null

# Restart systemd keepers
systemctl restart lever-fee-keeper
systemctl restart lever-accrue-keeper

# Verify they're running:
systemctl status lever-fee-keeper --no-pager | head -5
systemctl status lever-accrue-keeper --no-pager | head -5

# Restart liquidator bot (sources deploy-env.sh → picks up new LIQUIDATION_ENGINE)
pkill -f "liquidator-bot" 2>/dev/null
nohup bash /home/lever/lever-protocol/scripts/liquidator-bot.sh > /tmp/liquidator-bot.log 2>&1 &
echo "Liquidator PID: $!"
```

> **TODO (non-blocking):** Convert liquidator-bot.sh to a systemd service for reboot persistence.

---

### Step 12: Seed demo data

```bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh

# Approve USDT for new vault (1M USDT = 1000000e6 = 1000000000000)
cast send 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E \
  "approve(address,uint256)" $LEVER_VAULT 1000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Deposit 500K USDT into vault
cast send $LEVER_VAULT \
  "deposit(uint256,address)" 500000000000 0x0e4D636c6D79c380A137f28EF73E054364cd5434 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Verify TVL
cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL
# Should return ~500000000000 (500K USDT in 6 decimals)
```

---

### Step 13: Integration Tests — Prove It Works End-to-End

> **Do NOT skip this.** Read checks (Step 14) only verify wiring.
> These tests verify actual transactions flow through the full stack.
> Each test exercises a different role grant. If any reverts, you know exactly which grant is missing.

```bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh
DEMO_KEY=e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
DEMO_WALLET=0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
SPACEX=0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1

# ─────────────────────────────────────────
# TEST 1: Open a position (exercises: ExecEngine → PM, AM, OILimits, FeeRouter, Vault)
# This is the single most important test — it touches 5 of the 6 role-gated contracts
# ─────────────────────────────────────────
echo "=== TEST 1: Open position ==="

# First ensure demo wallet has USDT deposited in AccountManager
DEMO_BALANCE=$(cast call $ACCOUNT_MANAGER "getBalance(address)(uint256)" $DEMO_WALLET --rpc-url $RPC_URL)
echo "Demo wallet AccountManager balance: $DEMO_BALANCE"

# If balance is 0, deposit some:
# cast send $USDT_ADDRESS "transfer(address,uint256)" $DEMO_WALLET 100000000000 \
#   --private-key $PRIVATE_KEY --rpc-url $RPC_URL
# Then demo wallet deposits into AccountManager...
# (Claude Code should check and handle this)

# Open a 3x long on SpaceX with 100 USDT collateral
# collateral = 100e6, leverage = 3e18
NONCE=$(cast nonce $DEMO_WALLET --rpc-url $RPC_URL)
echo "Opening position..."
cast send $EXECUTION_ENGINE \
  "openPosition(bytes32,bool,uint256,uint256)" \
  $SPACEX true 100000000 3000000000000000000 \
  --private-key $DEMO_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 800000

# Check it landed
TOTAL=$(cast call $POSITION_MANAGER "totalOpenPositions()(uint256)" --rpc-url $RPC_URL)
echo "Total open positions after: $TOTAL"
# Should be 253 (was 252)

# ─────────────────────────────────────────
# TEST 2: Close a position (exercises: ExecEngine → Vault.fundTraderPnL or AM.transferOut)
# ─────────────────────────────────────────
echo "=== TEST 2: Close position ==="

# Get the position we just opened (it should be the latest)
LATEST_POS=$(cast call $POSITION_MANAGER "totalPositions()(uint256)" --rpc-url $RPC_URL)
echo "Closing position $LATEST_POS..."

NONCE=$(cast nonce $DEMO_WALLET --rpc-url $RPC_URL)
cast send $EXECUTION_ENGINE \
  "closePosition(uint256)" $LATEST_POS \
  --private-key $DEMO_KEY --rpc-url $RPC_URL --nonce $NONCE --gas-limit 800000

echo "Close result — check if reverted above"

# ─────────────────────────────────────────
# TEST 3: Fee distribution (exercises: FeeRouter → RD, Protocol, InsuranceFund)
# ─────────────────────────────────────────
echo "=== TEST 3: Fee distribution ==="

# Check RD balance before
RD_BEFORE=$(cast call $USDT_ADDRESS "balanceOf(address)(uint256)" $REWARDS_DISTRIBUTOR --rpc-url $RPC_URL)
echo "RD balance before: $RD_BEFORE"

NONCE=$(cast nonce $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $RPC_URL)
cast send $FEE_ROUTER "distributeFees()" \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --nonce $NONCE

RD_AFTER=$(cast call $USDT_ADDRESS "balanceOf(address)(uint256)" $REWARDS_DISTRIBUTOR --rpc-url $RPC_URL)
echo "RD balance after: $RD_AFTER"

# ─────────────────────────────────────────
# TEST 4: Vault pending yield (exercises: Vault → RD integration)
# ─────────────────────────────────────────
echo "=== TEST 4: Vault pending yield ==="
cast call $LEVER_VAULT "pendingYield(address)(uint256)" 0x0e4D636c6D79c380A137f28EF73E054364cd5434 --rpc-url $RPC_URL
echo "(Should be non-zero if fees have been distributed)"

# ─────────────────────────────────────────
# TEST 5: Check FeeRouter tier (automatic based on IFR)
# ─────────────────────────────────────────
echo "=== TEST 5: FeeRouter tier ==="
cast call $FEE_ROUTER "getCurrentTier()(uint8)" --rpc-url $RPC_URL
echo "(1 = normal 50/30/20, 2 = stressed 50/50/0)"

# ─────────────────────────────────────────
# TEST 6: Liquidation check (exercises: LiqEngine → MarginEngine, PM)
# Note: may not find a liquidatable position — that's OK, we're testing the call doesn't revert
# ─────────────────────────────────────────
echo "=== TEST 6: Liquidation scan (read-only) ==="
# Check first 5 positions
for PID in 1 2 3 4 5; do
  LIQ=$(cast call $MARGIN_ENGINE "isLiquidatable(uint256)(bool)" $PID --rpc-url $RPC_URL 2>/dev/null)
  echo "Position $PID liquidatable: $LIQ"
done

echo ""
echo "═══ ALL TESTS COMPLETE ═══"
echo "If any cast send above reverted, check the role grant for that specific flow."
echo "Test 1 revert → check grants 1,4,7,10,13 (PM, AM, Vault, OI, FR roles for ExecEngine)"
echo "Test 2 revert → same as Test 1 plus grant 7 (Vault EXECUTION_ENGINE_ROLE)"
echo "Test 3 revert → check that FeeRouter has BORROW_FEE_ENGINE_ROLE for BorrowFeeEngine (pre-existing)"
```

---

### Step 14: Verification — Read Checks

```bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh

echo "=== Contract wiring ==="
echo "Vault → RD:"
cast call $LEVER_VAULT "rewardsDistributor()(address)" --rpc-url $RPC_URL

echo "Vault TVL:"
cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL

echo "ExecEngine → Vault:"
cast call $EXECUTION_ENGINE "leverVault()(address)" --rpc-url $RPC_URL

echo "ExecEngine → PM:"
cast call $EXECUTION_ENGINE "positionManager()(address)" --rpc-url $RPC_URL

echo "LiqEngine → PM:"
cast call $LIQUIDATION_ENGINE "positionManager()(address)" --rpc-url $RPC_URL

echo "LiqEngine → Exec:"
cast call $LIQUIDATION_ENGINE "executionEngine()(address)" --rpc-url $RPC_URL

echo "LiqEngine → Vault:"
cast call $LIQUIDATION_ENGINE "leverVault()(address)" --rpc-url $RPC_URL

echo "Settlement → Vault:"
cast call $SETTLEMENT_ENGINE "leverVault()(address)" --rpc-url $RPC_URL

echo ""
echo "=== System health ==="
echo "Positions alive:"
cast call $POSITION_MANAGER "totalOpenPositions()(uint256)" --rpc-url $RPC_URL

echo "Borrow index (SpaceX long):"
cast call $BORROW_FEE_ENGINE \
  "getBorrowIndex(bytes32,bool)(uint256)" \
  0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1 true \
  --rpc-url $RPC_URL

echo "FeeRouter tier:"
cast call $FEE_ROUTER "getCurrentTier()(uint8)" --rpc-url $RPC_URL

echo "RD → Vault role:"
LEVER_VAULT_ROLE=$(cast keccak "LEVER_VAULT_ROLE")
cast call $REWARDS_DISTRIBUTOR \
  "hasRole(bytes32,address)(bool)" $LEVER_VAULT_ROLE $LEVER_VAULT \
  --rpc-url $RPC_URL
```

### Frontend Manual Checks
- [ ] Page loads at http://165.245.186.254:3000 without errors
- [ ] No console errors related to contract addresses or ABIs
- [ ] Stats bar shows TVL matching `totalAssets()` read above
- [ ] All 10 markets display with live oracle prices
- [ ] Open a long position via demo wallet (Trading tab) → confirm on Positions tab
- [ ] Close a position (Positions tab) → confirm it disappears
- [ ] Borrow fees display and increase over time
- [ ] Vault tab shows real deposit amount, not $0
- [ ] Vault pending yield shows non-zero after fee keeper runs (restart keepers, wait 5 min)
- [ ] No SSL/CSP errors in browser console

---

### Step 15: Git commit and push

```bash
cd /home/lever/lever-protocol
git add -A
git commit -m "redeploy: vault+exec+settlement+liquidation — fix RD mismatch, scrambled liq args, 18 role grants"
git push origin main
```

---

## 5. KEEPER REFERENCE

All keepers source `deploy-env.sh` so they automatically pick up new addresses after restart.

| Keeper | Type | References | What It Does |
|--------|------|------------|-------------|
| lever-fee-keeper | systemd | `$FEE_ROUTER` | Calls `distributeFees()` every 5 min |
| lever-accrue-keeper | systemd | `$BORROW_FEE_ENGINE` (unchanged) | Calls `accrueAll()` every 60s |
| liquidator-bot.sh | nohup | `$LIQUIDATION_ENGINE`, `$MARGIN_ENGINE`, `$POSITION_MANAGER` | Scans positions, liquidates qualifying ones every 30s |
| nohup borrow keeper (PID 2429674) | nohup | `BorrowFeeEngine` (hardcoded) | **REDUNDANT with lever-accrue-keeper — KILL IT** |

---

## 6. FRONTEND BUGS — Fix After Redeployment (Phase 3)

### Already Fixed — Do NOT Re-Break
- `useDemoWallet.ts`: `gas: 800000n`, skips `simulateContract`
- `Trading.tsx`: demo wallet uses `sendDemoTransaction`
- `VaultOptimized.tsx`: `useNotifications` for error toasts
- `useMemoizedCalculations.ts`: `Number(value)/1e6` not `parseFloat(formatUsdt())`
- `MarketDetail.tsx`: borrow rate hourly not annual
- `accrue-keeper.sh`: `accrueAll()` not per-market
- `public/index.html`: CSP tag removed (must also strip from `build/index.html` after every build)
- `Positions.tsx`: fake demo positions removed, real timestamps added

### Still Needs Fixing
1. Vault needs "Claim Rewards" button → calls `LeverVault.claim()`
2. Vault needs "Compound" button → calls `LeverVault.compound()`
3. APY should split: "Fee Yield APY" vs "Vault PnL" — `useRealAPY` shows inflated 52.6%
4. Vault utilization/wallet balance may show wrong values — verify after redeploy
5. Funding shows $0.00 on all positions
6. Error toasts show generic message, not revert reason
7. `useLivePrices.ts` has dead `DEMO_INITIAL_PRICES` code — clean it

### Build Process (for every frontend fix)
```bash
cd /home/lever/lever-protocol/frontend/user-app
npx react-app-rewired build 2>&1 | tail -5
sed -i 's/<meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"\/>//' build/index.html
systemctl restart lever-frontend
# Verify: http://165.245.186.254:3000
```

---

## 7. ARCHITECTURE QUICK REFERENCE

### Position Struct (field order)
```solidity
struct Position {
    uint256 positionId;     // 0
    address owner;          // 1
    bytes32 marketId;       // 2
    bool isLong;            // 3
    uint256 entryPI;        // 4 (WAD)
    uint256 exitPI;         // 5
    uint256 positionSize;   // 6 (USDT 6 decimals)
    uint256 collateral;     // 7 (USDT 6 decimals)
    uint256 leverage;       // 8 (WAD)
    uint256 borrowIndex;    // 9 (WAD)
    int256 fundingIndex;    // 10
    uint256 timestamp;      // 11
    bool isOpen;            // 12
}
```

### Fee Flow (whitepaper spec — tier 1)
```
BorrowFeeEngine / ExecutionEngine → FeeRouter → 50% RewardsDistributor (LP claim)
                                               → 30% Protocol Treasury
                                               → 20% InsuranceFund
```

### Vault Dual Revenue
1. **NAV-based:** Trader PnL affects share price (traders lose = NAV up)
2. **Fee-based:** Accumulated in RewardsDistributor, claimed via `LeverVault.claim()`

### Trader Wins → Vault Pays (ExecutionEngine)
```
ExecutionEngine._closeTrade()
  → leverVault.fundTraderPnL(accountManager, amount)  // EXECUTION_ENGINE_ROLE required
  → accountManager.creditPnL(trader, pnlDelta)
```
If this role is missing, winning traders cannot collect profits.

### Bad Debt Waterfall — Liquidation Path
```
LiquidationEngine.liquidate(positionId)
  → equity < 0 → badDebt = |equity|
  → insuranceFund.absorbBadDebt(marketId, badDebt)   // LIQUIDATION_ENGINE_ROLE on IF
    → InsuranceFund determines tier (IFR-based), splits insurance vs ADL
    → returns (insurancePaid, socializedAmount)
  → if socializedAmount > 0:
      leverVault.socializeLoss(socializedAmount)       // LIQUIDATION_ENGINE_ROLE on Vault
      → LP share price decreases proportionally
```

### Bad Debt Waterfall — Settlement/Resolution Path (ADL lives here)
```
SettlementEngine.settle(marketId)
  → Closes all positions for resolved market
  → If bad debt remains after insurance:
      insuranceFund.absorbBadDebt()                   // SETTLEMENT_ENGINE_ROLE on IF
  → ADL: pro-rata haircut on winning positions
  → If still remainder:
      leverVault.socializeLoss(remainder)              // LIQUIDATION_ENGINE_ROLE on Vault
```

### Role Map Summary (18 grants required — verified from source code)
```
PositionManager:     keccak256("ENGINE_ROLE")
  → ExecutionEngine, SettlementEngine, LiquidationEngine

AccountManager:      keccak256("ENGINE")          ← NOTE: "ENGINE" not "ENGINE_ROLE"
  → ExecutionEngine, SettlementEngine, LiquidationEngine

LeverVault:          keccak256("EXECUTION_ENGINE_ROLE")
  → ExecutionEngine     (fundTraderPnL, updateUnrealizedPnL)
                     keccak256("LIQUIDATION_ENGINE_ROLE")
  → LiquidationEngine   (socializeLoss)
  → SettlementEngine     (socializeLoss)

OILimits:            keccak256("EXECUTION_ENGINE_ROLE")
  → ExecutionEngine     (update OI on position open/close)
                     keccak256("LIQUIDATION_ENGINE_ROLE")
  → LiquidationEngine   (update OI on liquidation)
                     keccak256("SETTLEMENT_ENGINE_ROLE")
  → SettlementEngine     (update OI on settlement)

FeeRouter:           keccak256("EXECUTION_ENGINE_ROLE")
  → ExecutionEngine     (route trading fees)
                     keccak256("LIQUIDATION_ENGINE_ROLE")
  → LiquidationEngine   (route liquidation fees)
                     keccak256("SETTLEMENT_ENGINE_ROLE")
  → SettlementEngine     (route settlement fees)
                     keccak256("BORROW_FEE_ENGINE_ROLE")  ← pre-existing, not redeploying
  → BorrowFeeEngine

InsuranceFund:       keccak256("LIQUIDATION_ENGINE_ROLE")
  → LiquidationEngine   (absorbBadDebt)
                     keccak256("SETTLEMENT_ENGINE_ROLE")
  → SettlementEngine     (absorbBadDebt)

RewardsDistributor:  keccak256("LEVER_VAULT_ROLE")
  → LeverVault          (claim/compound yield)
```

---

## 8. RULES FOR BUILD AGENTS

1. **DO NOT** change CSS, colors, fonts, layout, or design
2. **DO NOT** restart disabled services (lever-loop, lever-qa, lever-seeder, lever-watchdog)
3. **DO NOT** fabricate demo data or hardcode fake values
4. **DO NOT** use `$DEPLOYER_KEY` (empty) — always use `$PRIVATE_KEY`
5. **DO NOT** use `$SPACEX_MARKET_ID` (empty) — use hex: `0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1`
6. **ALWAYS** strip CSP meta tag from `build/index.html` after every frontend build
7. **ALWAYS** fetch fresh nonce before `cast send` (keeper nonce conflicts)
8. **ALWAYS** verify page loads after frontend changes
9. **ALWAYS** git commit and push after completing work
10. **ALWAYS** verify cast call outputs match expected values after each deploy step
