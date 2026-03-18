Based on the QA report showing a broken frontend (directory listing instead of React app) and recent deployment issues, here are the prioritized tasks:

### 1. **CRITICAL FRONTEND REPAIR** [CRITICAL] [DEPLOYMENT]
- [ ] Fix React app deployment - frontend showing directory listing instead of LEVER Protocol interface, completely blocking investor demo

### 2. **WEB SERVER CONFIGURATION** [CRITICAL] [INFRASTRUCTURE] 
- [ ] Configure proper web server routing to serve React SPA with index.html as default route and hide internal file structure

### 3. **SPRINT PRIORITIES VERIFICATION** [HIGH] [VALIDATION]
- [ ] Verify all three priorities in control-plane/build-plan.md are actually functional despite frontend deployment issues

### 4. **INSURANCE FUND FLOW** [MEDIUM] [CONTRACTS]
- [ ] Investigate why Insurance Fund stuck at $10K bootstrap - fees not flowing through FeeRouter properly

### 5. **ORACLE MONITORING** [LOW] [OPERATIONS]
- [ ] Check oracle keeper (mockkeeper.py) status to ensure prices don't go stale during demo

**Current Status**: Despite contracts functioning (TVL $60.5M, 246 positions), the frontend deployment failure creates a complete investor demo blocker. Priority 1-2 must be resolved immediately before any other work.