Looking at the QA report, there's a **CRITICAL** frontend deployment failure that's completely blocking the investor demo. The systemd service is serving a directory listing instead of the React application.

## Priority Tasks

### 1. CRITICAL DEPLOYMENT FIX [CRITICAL] [FRONTEND]
- [ ] Fix systemd service configuration - it's serving directory listing instead of React app
- [ ] Copy working build from `build.safe/` to correct location OR reconfigure service path  
- [ ] Verify React app loads properly at localhost:3000 with functional UI
- [ ] Take screenshots to confirm investor demo readiness

### 2. Verify Core Demo Functionality [HIGH] [SYSTEM]
- [ ] Test position opening flow (5x, 10x, 15x leverage confirmed working)
- [ ] Verify all tabs render correctly (Trading, Positions, Vault, Markets)
- [ ] Confirm live data displays (TVL $60.5M, 236 positions, OI $12.5M)
- [ ] Run full health check and user flow tests

### 3. Oracle Keeper Monitoring [MEDIUM] [BACKEND] 
- [ ] Verify mockkeeper.py is running and updating prices
- [ ] Check price freshness and oracle pipeline stability
- [ ] Monitor for any stale price warnings

### 4. Insurance Fund Flow Investigation [MEDIUM] [CONTRACTS]
- [ ] Debug why Insurance Fund stuck at $10K bootstrap value  
- [ ] Verify FeeRouter is properly directing fees to insurance fund
- [ ] Check fee accumulation and distribution pipeline

### 5. LP APY Analysis [LOW] [SYSTEM]
- [ ] Investigate why LP APY is only 0.21% (expected to increase with higher OI)
- [ ] Monitor APY changes as more leveraged positions are created
- [ ] Document expected APY ranges for investor materials

**CRITICAL**: Task #1 must be completed immediately - the frontend is completely broken and would show investors only a file browser instead of the trading application.