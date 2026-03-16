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
