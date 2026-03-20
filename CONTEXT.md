# LEVER Protocol — Persistent Context for Build Agents

**Last Updated:** March 20, 2026  
**Do not delete this file. It is the source of truth for all build agents.**

---

## CRITICAL: DO NOT CHANGE DESIGN/CSS

Any build agent working on this codebase must NOT change:
- CSS, colors, fonts, shadows, spacing, padding, margins
- Layout or component structure
- Tailwind config or design system
- Component naming or file structure

Only fix: data display bugs, broken functionality, loading states, crashes.

---

## KNOWN STATE

### Working
- Positions open via demo wallet (Trading.tsx + useDemoWallet with gas: 800000n)
- Positions close via demo wallet (Positions.tsx)
- Vault deposit/withdraw via demo wallet (VaultOptimized.tsx)
- Borrow indices accruing every 60s (lever-accrue-keeper service)
- 10 markets registered and active with live oracle prices
- Frontend builds and serves on port 3000

### FIXED — Redeployed March 20, 2026

**Bug 1: Vault → RewardsDistributor mismatch** — FIXED
- Redeployed LeverVault pointing to correct RD (`0xab8D`)
- Cascaded redeployment to ExecutionEngine and SettlementEngine

**Bug 2: LiquidationEngine — Constructor args scrambled** — FIXED
- Redeployed with correct constructor arg order
- All getters verified: positionManager, executionEngine, leverVault, marginEngine

### Known Frontend Bugs
1. Vault utilization may still show 0.0%
2. Wallet balance may show wrong decimals
3. No "Claim Rewards" or "Compound" button on vault page (no longer blocked — redeployment complete)
4. Funding shows $0.00 on all positions
5. Error toasts on Trading show generic message, not actual revert reason
6. `useRealAPY` hook shows inflated 52.6% APY — likely theoretical, not realized
7. `useLivePrices.ts` has dead `DEMO_INITIAL_PRICES` code

### Fixed (Do Not Re-Break)
- useDemoWallet.ts: uses writeContract with gas:800000n, NOT simulateContract
- Trading.tsx: demo mode sends via sendDemoTransaction
- VaultOptimized.tsx: has useNotifications for error/success toasts
- useMemoizedCalculations.ts: uses Number(value)/1e6 NOT parseFloat(formatUsdt())
- MarketDetail.tsx: borrow rate shows hourly (not annual)
- accrue-keeper.sh: uses accrueAll() not per-market accrueIndex()
- public/index.html: CSP upgrade-insecure-requests tag removed from template
- build/index.html: must strip CSP tag after every build
- Positions.tsx: fake demo positions removed, real timestamps added

---

## CONTRACT ADDRESSES

### ✅ Do Not Redeploy (Working)
```
DEPLOYER:            0x0e4D636c6D79c380A137f28EF73E054364cd5434
USDT:                0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E
MarketRegistry:      0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
OracleAdapter:       0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c
AccountManager:      0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
PositionManager:     0x25ba54a7b2fBac753B601Da05e3661F2E959510b
LeverageModel:       0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed
OILimits:            0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd
BorrowFeeEngine:     0x706578de003912C71e534949d8b8DDd5108950e1
FundingRateEngine:   0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
MarginEngine:        0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
RewardsDistributor:  0xab8DFA8cF72b054c356961026F8648dB7D860Cb0
InsuranceFund:       0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8
FeeRouter:           0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F
```

### ✅ Redeployed (March 20, 2026)
```
LeverVault:          0x1b623D8671c417fe5151cCDb38ec7cAB64332836  ← Points to correct RD
ExecutionEngine:     0xafEA713Dc2d6ebec15B21aB92bd15bC733D5B786  ← Points to new vault
SettlementEngine:    0xdfB429809e0862e01Dcc73A6621b8729325F5691  ← Points to new vault
LiquidationEngine:   0x0374edd7DCd819548C9dBf53c36f15880FaD69eD  ← Correct constructor args
```

### Demo Wallet
```
Address: 0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da
Private Key: e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5
```

---

## BUILD PROCESS

```bash
cd /home/lever/lever-protocol/frontend/user-app
npx react-app-rewired build 2>&1 | tail -5
sed -i 's/<meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"\/>//' build/index.html
systemctl restart lever-frontend
```

**After every fix, verify the page loads before moving on.**
**If the page breaks: git checkout . and try again.**

---

## GIT

```bash
cd /home/lever/lever-protocol
git add -A && git commit -m "description of change" && git push origin main
```

SSH auth is configured. Remote: git@github.com:notsatoshii/Timmy.git

---

## SERVICES

### Running (keep alive)
- lever-bot, lever-frontend, lever-oracle, lever-fee-keeper, lever-accrue-keeper, lever-dashboard

### Disabled (do not restart)
- lever-loop, lever-qa, lever-seeder, lever-watchdog

---

## QA LOOP

If assigned QA tasks, follow /home/lever/lever-protocol/control-plane/qa-task.md exactly.
Log results to /home/lever/lever-protocol/frontend/user-app/qa-log.md (append, never overwrite).
Commit and push after each cycle of fixes.
