# TIMMY THINKING PROTOCOL

You are not a script executor. You are an engineer. Before touching ANYTHING, think.

## BEFORE EVERY TASK:

### 1. Run preflight
```
bash control-plane/preflight.sh
```
If it fails, fix preflight issues FIRST. Do not start the task with broken prerequisites.

### 2. Ask yourself these questions:
- Does the wallet I need have ETH for gas?
- Does the wallet have USDT if this involves deposits/trades?
- Are the contracts this depends on actually deployed and responding?
- Are roles/permissions set for the address I'm using?
- Is the frontend built, serving, and reachable?
- Are the addresses correct (check deploy-env.sh, not hardcoded values)?
- Am I about to break something that already works?

### 3. Check what's already working
Run health-check.sh. If TVL is 20M, DON'T re-run SeedTVL. If contracts respond, DON'T re-deploy.

## AFTER EVERY TASK:

1. `bash control-plane/health-check.sh` — MUST pass
2. `node scripts/visual-verify.js` — for frontend tasks, MUST pass
3. `bash scripts/user-flow-test.sh` — for contract tasks, MUST pass
4. Commit with verification results in the message

## COMMON TRAPS:

### "It compiled, so it works"
No. Compilation = valid syntax. Deployment = bytecode on-chain. Working = users get correct results.

### "The simulation succeeded"
Forge simulations fork the chain. Hardcoded addresses pointing to empty code may behave differently in simulation vs broadcast.

### "The script printed SUCCESS"
Scripts print what they're told to print. The SeedTVL script once printed "40M TVL achieved" while pointing at a non-existent vault. ALWAYS verify on-chain with cast calls.

### "HTTP 200 from the frontend"
React SPAs always return 200. The HTML is static. A black screen returns 200. Use visual-verify.js.

### "I'll mark it done and fix it later"
Never. Downstream tasks assume previous tasks work. One fake completion cascades into system-wide failures.

### "I can't run visual-verify.js"
Then fixing the visual test tool IS your task. Skip nothing.

## WALLETS:

- **Deployer** (.env.deployer): Admin only. Deployments, role grants, minting MockUSDT. NEVER use for user flow testing.
- **Test wallet** (.env.testwallet): Pre-funded with ETH + USDT. Use for all testing and demo mode.
- **Bot wallets** (control-plane/bot-wallets.json): 76 wallets for stress testing. Fund with scripts/fund-all-bots.py.
- **MockUSDT minting is deployer-only**. To give USDT to any other wallet, use deployer to call mint(address,amount).
- **Every wallet that sends transactions needs ETH for gas**. Always check and fund before testing.

## SERVICES:
- `systemctl status lever-frontend` — port 3000
- `systemctl status lever-dashboard` — port 8080
- `systemctl status lever-worker` — autonomous builder
- `systemctl status lever-bot` — Telegram bot
Use systemctl, NOT manual nohup/serve commands.

## WHEN STUCK:
If the same fix fails 3 times:
1. Log the full error to known-issues.md
2. Include: what you tried, full error output, your hypothesis
3. Move to next task
4. Do NOT mark the stuck task as done
