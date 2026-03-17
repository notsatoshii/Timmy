## Phase 0-FINAL: Ship Investor Demo

RULES:
- Every task has a DONE condition and a FAIL condition. Verify DONE before marking [x].
- Do NOT mark a task done if any displayed value is $0, $NaN, negative, or obviously wrong.
- Run `bash control-plane/health-check.sh` after every contract change.
- After every frontend change, run `node scripts/tab-sanity.js` (once task 8a is complete).
- Keep git commits under 80 chars. Commit after each completed task.

---

### 1a. Fix Vault Tab Data [CRITICAL]
- [x] 1a. Vault tab shows TVL $0, APY 0.0%, Share Price $NaN. Stats banner on landing page reads correct values from the same contracts. Find where Vault.tsx reads TVL/APY/SharePrice and make it use the same contract read logic as the stats banner. TVL = totalAssets()/1e6. SharePrice = convertToAssets(1e18)/1e6. APY = utilization × borrowRate × 8760 × 0.50 / TVL.
**DONE:** Vault tab shows TVL >$50M, APY >0% and <100%, SharePrice between $0.99 and $1.10.
**FAIL:** Any value is $0, $NaN, or negative.

### 2a. Fix MarketDetail OI Display [CRITICAL]
- [x] 2a. MarketDetail page shows OI as ~$39B instead of ~$150K. Root cause: OILimits returns USDT (6 decimals) but frontend divides by 1e18 (WAD). Change to divide by 1e6 everywhere OI is displayed — MarketDetail page AND market cards on the Trade tab.
**DONE:** MarketDetail OI for any market is between $1K and $10M. Market cards also show correct OI.
**FAIL:** Any OI value exceeds $100M or shows $0 on any page.

### 3a. Fix 24h Volume Display [CRITICAL]
- [x] 3a. 24h Volume on stats banner and market cards shows only collateral amount. Must show notional = collateral × leverage. Find where volume is calculated and multiply by leverage.
**DONE:** Volume numbers are larger than sum of collateral deposits.
**FAIL:** Volume equals raw collateral amounts.

### 4a. Fix Frontend Position Opening [CRITICAL]
- [ ] 4a. Open Position from Trading tab fails with "Position Open Failed" but `cast send` works from CLI. Debug in this order: (1) Check frontend contract addresses match deploy-env.sh — especially ExecutionEngine. (2) Check demo mode wallet has USDT approval for ExecutionEngine address. (3) Check parameter encoding: collateral in 6 decimals (USDT), leverage in 18 decimals (WAD), direction as uint8, marketId as bytes32. (4) Check that demo mode actually signs with the test wallet private key, not a null signer.
**DONE:** Position can be opened from the UI in demo mode. New position appears in Positions tab. Verify on-chain with `cast call $POSITION_MANAGER "getPosition(uint256)"` for the new position ID.
**FAIL:** Button still errors, or position doesn't appear on-chain.

### 5a. Fix Leverage Model Contract Bug [CRITICAL]
- [ ] 5a. LeverageModel caps leverage at ~1.8x for all markets. For SpaceX (288 days, tau=2073h), R(τ)=1-e^(-2.0×2073/24)≈1.0, maxLeverage should be ~30x. Bug is likely units mismatch in tau calc (seconds vs hours, or k scaled wrong). Read LeverageModel.sol, find maxLeverage function, trace all units. Fix the math. If redeployment is needed: (1) forge script deploy new LeverageModel, (2) update address in deploy-env.sh, (3) re-run role configuration so all contracts that call LeverageModel have the new address, (4) update frontend contract config with new address, (5) rebuild frontend.
**DONE:** `cast call $LEVERAGE_MODEL "getMaxLeverage(bytes32)(uint256)" $SPACEX_MARKET_ID` returns ≥20e18 (20x). All other contracts that reference LeverageModel still function (health-check.sh passes).
**FAIL:** Result <5e18, or health-check.sh fails after redeployment, or other contracts revert when calling new LeverageModel.

### 5b. Open High-Leverage Positions [CRITICAL]
- [ ] 5b. After leverage model is fixed (5a must be done first), open 5 high-leverage positions (10x, 15x, 20x, 25x, 30x) on long-dated markets using test wallet via `cast send`. Use SpaceX and at least 2 other markets with >90 days to resolution.
**DONE:** `cast call $POSITION_MANAGER "getPosition(uint256)"` shows leverage ≥10x for at least 3 new positions across at least 2 different markets.
**FAIL:** No positions above 5x exist.

### 6a. Fix Fee Routing [CRITICAL]
- [x] 6a. FeeRouter.distributeFees() is never called. Fees accumulate but never split to LP (50%) / Protocol (30%) / Insurance (20%). Fix with a persistent keeper: create scripts/fee-keeper.sh that calls `cast send $FEE_ROUTER "distributeFees()"` every 5 minutes, then create a systemd service (lever-fee-keeper) with auto-restart so it survives SSH disconnects. Source deploy-env.sh for addresses and keys.
**DONE:** (1) lever-fee-keeper service is running: `systemctl status lever-fee-keeper`. (2) InsuranceFund balance > $10,000: `cast call $INSURANCE_FUND "getBalance()(uint256)"` returns more than 10000000000000000000000 (1e22). (3) Keeper calls distributeFees at least once every 5 minutes.
**FAIL:** InsuranceFund still exactly $10K, or keeper service doesn't exist, or keeper dies after one run.

### 6b. Verify Oracle Keeper [HIGH]
- [ ] 6b. Oracle keeper may not be running — prices could be stale. Check: `ps aux | grep keeper`. If not running, restart it. Verify prices are fresh: `cast call $ORACLE_ADAPTER "getPrice(bytes32)(uint256,uint256)" $SPACEX_MARKET_ID` — second return value is timestamp, must be within last 10 minutes. If keeper process doesn't exist, find how it was originally started (check systemd services, crontab, or nohup commands in bash history) and restart it as a systemd service.
**DONE:** Oracle keeper is running. Price timestamps for all 10 markets are within last 10 minutes.
**FAIL:** Any market has a price older than 30 minutes, or keeper is not running.

### 7a. Fix Positions Tab [HIGH]
- [ ] 7a. Positions tab may crash with error boundary. Check for: undefined position data, division by zero in PnL calc, missing market metadata for a position's marketId. Also verify PnL calculation uses correct decimal scaling (collateral is 6 decimals USDT, PnL may be WAD).
**DONE:** Positions tab loads and shows at least 10 positions with valid PnL numbers (not $NaN, not $0 for all).
**FAIL:** Error boundary appears or any position shows $NaN or all PnLs show exactly $0.

### 7b. Verify Funding Rate Engine [HIGH]
- [ ] 7b. SpaceX market has 98% long / 2% short imbalance. Funding rate engine is unverified. Check: `cast call $FUNDING_RATE_ENGINE "getCurrentFundingRate(bytes32)(int256)" $SPACEX_MARKET_ID` — result should be positive (longs pay shorts) and nonzero given the extreme imbalance. If funding rate is 0, check that the engine is properly initialized and connected. If rate seems wrong, check the formula parameters.
**DONE:** Funding rate for SpaceX is positive (longs paying shorts) and nonzero. Value is reasonable (<1% per hour).
**FAIL:** Funding rate is exactly 0 despite 98/2 imbalance, or is negative (shorts paying longs), or exceeds 1% per hour.

### 8a. Build Tab Sanity Check — Data + Visual [HIGH]
- [ ] 8a. Current sanity-check-frontend.sh only tests the landing page stats banner. Build a NEW script at scripts/tab-sanity.js using puppeteer (visual-verify.js already exists as reference). The script has TWO validation layers:

**LAYER 1 — Data Validation (automated):**
(1) Launch headless Chrome at http://localhost:3000.
(2) For EACH tab — Trade, Vault, Positions, MarketDetail for SpaceX — navigate to the tab, wait for data load (networkidle + 3s), take a full-page screenshot saved to control-plane/screenshots/{tab}-{timestamp}.png.
(3) Extract displayed values from the page via page.evaluate (read text content of key data elements like TVL, APY, OI, Volume, PnL, Share Price, leverage values).
(4) Get on-chain ground truth via child_process.execSync running cast call commands (source deploy-env.sh first). Key comparisons: TVL vs totalAssets(), OI vs getGlobalOI(), InsuranceFund vs getBalance().
(5) AUTO-FAIL if any value is $0, $NaN, negative, "undefined", "Error", or differs from on-chain by >100x.
(6) AUTO-FAIL if any tab shows error boundary text, "Something went wrong", or a blank white page.

**LAYER 2 — Visual/UX Review (Claude Vision):**
(7) After all screenshots are taken, call `claude --no-input --print` with a prompt that includes: (a) the screenshot image file for each tab, (b) the content of control-plane/design-reference/DESIGN_BRIEF.md, and (c) instructions to evaluate each screenshot against the design brief.
(8) The vision prompt should ask Claude to check: Does the layout match the design brief? Are charts/graphs rendering (not empty boxes)? Is text readable (no truncation, no overflow, no overlapping elements)? Are colors/theme consistent? Do numbers have proper formatting ($ prefix, commas, % and × suffixes)? Are loading states clean (skeleton/spinner, not raw $0)? Is the overall UX professional enough for an investor demo?
(9) Claude returns a structured JSON verdict per tab: {"tab": "Vault", "data_pass": true, "visual_pass": true, "issues": ["chart is empty", "APY text overflows container"]}.
(10) Print combined summary: DATA PASS/FAIL + VISUAL PASS/FAIL per tab with specific issues listed.
(11) Exit 0 only if ALL tabs pass BOTH layers. Exit 1 if any fail. Screenshots are saved regardless.

**DONE:** `node scripts/tab-sanity.js` runs end-to-end, produces screenshots in control-plane/screenshots/, prints per-tab PASS/FAIL for both data and visual checks, exits 0 when everything passes. The vision review catches layout/UX issues that DOM checks miss.
**FAIL:** Script doesn't take screenshots, doesn't compare to on-chain data, doesn't run Claude Vision review, or doesn't exit nonzero on failure.

### 9a. Add Validation Gate to Worker Rules [HIGH]
- [ ] 9a. Add rule to worker-rule.md AND agent-persona.md: "After ANY frontend task, you MUST run `node scripts/tab-sanity.js`. If any tab FAILs either the data check or the visual check, the task is NOT done — fix the failing values or layout issues and re-run until all tabs PASS both layers. Include the screenshot filenames and the vision review output in your completion message. A frontend task is not complete if any tab fails either validation layer, regardless of whether the code compiles and renders without crashing."
**DONE:** Rule text exists in both worker-rule.md and agent-persona.md. Rule specifically references tab-sanity.js and requires all-PASS on both data and visual layers.
**FAIL:** Rule missing from either file, or doesn't require both validation layers.

### 10a. Visual Polish [MEDIUM]
- [ ] 10a. Final visual review after all critical and high-priority fixes are done. Run `node scripts/tab-sanity.js` and review its output. Fix any remaining visual issues flagged by the Claude Vision review: number formatting (commas, $ prefix), % and × suffixes, loading states (skeleton/spinner not $0), layout alignment, chart rendering, color consistency with DESIGN_BRIEF.md. No raw wei (1e18) or raw USDT (1e6) values visible anywhere. Re-run tab-sanity.js after each fix until all tabs pass both data and visual checks.
**DONE:** tab-sanity.js reports ALL PASS on every tab for both data and visual layers. Screenshots in control-plane/screenshots/ look professional and investor-ready.
**FAIL:** Any tab fails either validation layer, or any raw/unformatted number visible in screenshots.
