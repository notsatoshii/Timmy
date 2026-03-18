Based on the QA report showing a score of **36** with critical frontend deployment failures, here are the prioritized tasks:

### 1. Fix React App Deployment [P0 CRITICAL] [FRONTEND]
- [ ] 1. **EMERGENCY: Restore functional React app** - Frontend serving directory listing instead of trading interface. React build completely failed with no index.html. Must restore working build from build.safe and fix deployment pipeline to stop reverting.

### 2. Verify Complete User Journey [P1 HIGH] [INTEGRATION]  
- [ ] 2. **End-to-end demo validation** - After frontend fix, run full investor demo flow: browse markets → open position → view portfolio → close position. All tabs must render properly without crashes or $0.00 display bugs.

### 3. Frontend Polish for Investor Demo [P1 HIGH] [FRONTEND]
- [ ] 3. **Visual QA pass** - Ensure all UI elements match design references (lever-concept.png, space-portfolio.png). Fix any remaining visual glitches, loading states, and error boundaries that could embarrass during investor presentations.

### 4. Oracle Price Stability [P2 MEDIUM] [INFRASTRUCTURE]
- [x] 4. **Verify oracle keeper running** - Check mockkeeper.py service status and restart if needed. Stale prices during demo would be problematic. Test price updates are flowing to frontend.

### 5. Performance Monitoring Setup [P2 MEDIUM] [OPERATIONS]
- [ ] 5. **Demo readiness check** - Run all verification scripts (health-check.sh, screenshots, user-flow-test). Set up real-time monitoring during investor demo to catch issues immediately.

**Critical Note:** The repeated identical commits for "Frontend Deployment Process" suggest the React build fix isn't persisting. Priority #1 must identify why the fix keeps reverting and create a permanent solution.