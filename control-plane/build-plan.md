Based on the locked build plan, here are the 3 prioritized tasks for the investor demo sprint:

### 1. Verify Core Trading Flow End-to-End [DEMO-CRITICAL] [CORE]
- [ ] Execute user flow test: `bash scripts/user-flow-test.sh`
- [ ] Verify wallet connect → open position → dashboard view → close position works
- [ ] Document any trading flow failures blocking investor demo
- [ ] Move Priority 1 from ⚠️ to ✅ status in build plan

### 2. Complete Frontend Visual Verification [DEMO-CRITICAL] [UI]  
- [ ] Take comprehensive screenshots: `node scripts/take-screenshots.js`
- [ ] Visual inspection: all tabs render, real data displayed (not $0.00 placeholders)
- [ ] Verify no crashes, error boundaries, or broken UI elements
- [ ] Move Priority 2 from ⚠️ to ✅ status in build plan

### 3. Achieve Target Health Check Score ≥70 [DEMO-CRITICAL] [QA]
- [ ] Current QA score: 52 → Target: ≥70
- [ ] Investigate Insurance Fund display ($5e24 instead of $10K) 
- [ ] Address visual issues preventing proper investor assessment
- [ ] Move Priority 3 from ⚠️ to ✅ status in build plan

**Sprint Rules (Locked):**
- Work ONLY on these 3 priorities
- NO new tasks until all show ✅ 
- NO contract redeployment
- NO fake/fabricated data
- After all 3 pass → transition to Phase 2 auto-improve mode

**Next Action:** Execute Priority 1 user flow test to verify core trading functionality.