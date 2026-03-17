# WORKER VERIFICATION RULES

## READ FIRST
Before starting ANY task, read control-plane/thinking-protocol.md.

## MANDATORY WORKFLOW

### Before every task:
1. `bash control-plane/preflight.sh` — fix issues before proceeding
2. `source control-plane/deploy-env.sh` — load addresses and keys

### After every task:
1. `bash control-plane/health-check.sh` — system health, MUST exit 0
2. Take screenshots and visually review (frontend tasks) — see VISUAL REVIEW section below
3. `bash scripts/user-flow-test.sh` — for contract tasks, MUST exit 0

### Definition of DONE:
ALL applicable verification scripts pass. "Script stdout said SUCCESS" is NEVER sufficient.

## FRONTEND TASKS
- After ANY change: rebuild (`npm run build`), restart (`systemctl restart lever-frontend`)
- Copy deployment JSONs to build/deployments/ AND public/deployments/
- Run visual-verify.js — check screenshots in control-plane/screenshots/
- A black screen means React crashed. Check App.tsx provider wrappers.
- $0.00 in stats means wrong contract addresses. Check config/contracts.ts.
- **MANDATORY TAB VALIDATION:** After ANY frontend task, you MUST run `node scripts/tab-sanity.js`. If any tab FAILs either the data check or the visual check, the task is NOT done — fix the failing values or layout issues and re-run until all tabs PASS both layers. Include the screenshot filenames and the vision review output in your completion message. A frontend task is not complete if any tab fails either validation layer, regardless of whether the code compiles and renders without crashing.

## CONTRACT TASKS
- Source deploy-env.sh before running ANY forge script
- If script has hardcoded addresses, fix them to use env vars or correct addresses
- After broadcast, verify on-chain with cast calls
- If "AccessControlUnauthorized": wrong wallet or missing role grant
- If "SourceNotActive": oracle source not registered
- If "MarketNotFound": markets not onboarded

## BOT SYSTEM
- Bot wallets: control-plane/bot-wallets.json (76 wallets)
- Fund bots: python3 scripts/fund-all-bots.py
- Every bot needs ETH for gas AND USDT for deposits/trades
- MockUSDT minting is deployer-only — fund-all-bots.py handles this
- Orchestrator coordinates bot activity, not individual bot scripts

## FILE OWNERSHIP
All repo files must be owned by lever:lever. If you create files, run:
`chown -R lever:lever /home/lever/lever-protocol`

## NIGHTLY CYCLE
The nightly script runs at 2AM UTC. It should NOT:
- Re-deploy contracts
- Overwrite deployment JSONs
- Kill running services
- Revert manual fixes
If nightly breaks things, fix nightly.py.


## AUTOMATED SANITY CHECK (replaces manual screenshot review)
After ANY frontend change:
1. Rebuild: 
> user-app@0.1.0 build
> react-app-rewired build

Creating an optimized production build...
Compiled with warnings.

Module not found: Error: Can't resolve '@react-native-async-storage/async-storage' in '/home/lever/lever-protocol/frontend/user-app/node_modules/@metamask/sdk/dist/browser/es'

[eslint] 
src/components/FeeBreakdown.tsx
  Line 4:26:  'BORROW_FEE_ENGINE_ABI' is defined but never used    @typescript-eslint/no-unused-vars
  Line 4:49:  'FUNDING_RATE_ENGINE_ABI' is defined but never used  @typescript-eslint/no-unused-vars

src/components/MarketDetail.tsx
  Line 8:3:    'ORACLE_ADAPTER_ABI' is defined but never used                                                                   @typescript-eslint/no-unused-vars
  Line 9:3:    'POSITION_MANAGER_ABI' is defined but never used                                                                 @typescript-eslint/no-unused-vars
  Line 12:8:   'Skeleton' is defined but never used                                                                             @typescript-eslint/no-unused-vars
  Line 79:17:  'globalOI' is assigned a value but never used                                                                    @typescript-eslint/no-unused-vars
  Line 119:6:  React Hook useEffect has a missing dependency: 'market.price'. Either include it or remove the dependency array  react-hooks/exhaustive-deps
  Line 152:6:  React Hook useEffect has a missing dependency: 'market.price'. Either include it or remove the dependency array  react-hooks/exhaustive-deps

src/components/Positions.tsx
  Line 4:41:   'WAD' is defined but never used                                                                                                                                                                              @typescript-eslint/no-unused-vars
  Line 8:3:    'ORACLE_ADAPTER_ABI' is defined but never used                                                                                                                                                               @typescript-eslint/no-unused-vars
  Line 9:3:    'MARKET_REGISTRY_ABI' is defined but never used                                                                                                                                                              @typescript-eslint/no-unused-vars
  Line 11:3:   'BORROW_FEE_ENGINE_ABI' is defined but never used                                                                                                                                                            @typescript-eslint/no-unused-vars
  Line 12:3:   'FUNDING_RATE_ENGINE_ABI' is defined but never used                                                                                                                                                          @typescript-eslint/no-unused-vars
  Line 113:6:  React Hook useEffect has missing dependencies: 'baseDemoPositions', 'createLivePosition', and 'demoMarketIds'. Either include them or remove the dependency array                                            react-hooks/exhaustive-deps
  Line 218:9:  The 'displayPositions' conditional could make the dependencies of useEffect Hook (at line 298) change on every render. To fix this, wrap the initialization of 'displayPositions' in its own useMemo() Hook  react-hooks/exhaustive-deps

src/components/ProtocolStats.tsx
  Line 3:55:  'WAD' is defined but never used             @typescript-eslint/no-unused-vars
  Line 8:3:   'FEE_ROUTER_ABI' is defined but never used  @typescript-eslint/no-unused-vars

src/components/Toast.tsx
  Line 38:6:  React Hook useEffect has a missing dependency: 'handleDismiss'. Either include it or remove the dependency array  react-hooks/exhaustive-deps

src/components/VaultOptimized.tsx
  Line 4:64:  'WAD' is defined but never used  @typescript-eslint/no-unused-vars

src/hooks/useMarketProbabilities.ts
  Line 99:17:  'firstMarketPI' is assigned a value but never used  @typescript-eslint/no-unused-vars

src/hooks/useMemoizedCalculations.ts
  Line 2:21:  'WAD' is defined but never used  @typescript-eslint/no-unused-vars

src/hooks/useMulticall.ts
  Line 70:6:  React Hook useMemo has a missing dependency: 'contracts'. Either include it or remove the dependency array  react-hooks/exhaustive-deps

src/hooks/useTradeHistory.ts
  Line 3:10:   'CONTRACT_ADDRESSES' is defined but never used     @typescript-eslint/no-unused-vars
  Line 4:10:   'EXECUTION_ENGINE_ABI' is defined but never used   @typescript-eslint/no-unused-vars
  Line 4:32:   'MARKET_REGISTRY_ABI' is defined but never used    @typescript-eslint/no-unused-vars
  Line 54:15:  'fromBlock' is assigned a value but never used     @typescript-eslint/no-unused-vars
  Line 58:15:  'openedEvents' is assigned a value but never used  @typescript-eslint/no-unused-vars
  Line 59:15:  'closedEvents' is assigned a value but never used  @typescript-eslint/no-unused-vars

Search for the keywords to learn more about each warning.
To ignore, add // eslint-disable-next-line to the line before.

File sizes after gzip:

  142.61 kB (+4 B)  build/static/js/main.0de4b9f3.js
  24.05 kB          build/static/js/933.189d6fed.chunk.js
  10.63 kB          build/static/js/456.f14ce822.chunk.js
  10.23 kB          build/static/js/724.6eac7fd5.chunk.js
  6.66 kB           build/static/js/845.e3d655c6.chunk.js
  6.45 kB           build/static/css/main.dae8617c.css
  4.96 kB           build/static/js/422.6a66345f.chunk.js
  3.15 kB           build/static/js/30.418337db.chunk.js
  3.14 kB           build/static/js/850.22b408fa.chunk.js
  3.1 kB            build/static/js/804.51cf6d5d.chunk.js
  2.14 kB           build/static/js/55.a2d1c2a8.chunk.js
  1.76 kB           build/static/js/453.8ee0ce74.chunk.js
  256 B             build/static/js/41.652206f6.chunk.js
  143 B             build/static/js/360.6287b135.chunk.js

The project was built assuming it is hosted at /.
You can control this with the homepage field in your package.json.

The build folder is ready to be deployed.
You may serve it with a static server:

  serve -s build

Find out more about deployment here:

  https://cra.link/deployment
2. Restart: 
3. Run: 
4. If it exits 1, YOUR FIX IS WRONG. The numbers are absurd. Debug and fix.
5. Do NOT mark the task done if sanity check fails.

This script checks:
- APY > 1000% = decimal bug (FAIL)
- Insurance > 1 billion = WAD formatting bug (FAIL)  
- TVL out of reasonable range = wrong data source (FAIL)
- OI > TVL = impossible state (FAIL)

It also computes the EXPECTED APY from on-chain values so you can compare what the frontend shows vs what it should show.
