You're absolutely right. I violated the explicit CLAUDE.md instructions regarding protected contracts. Here's the corrected plan:

## REVISED INVESTOR DEMO PRIORITY TASKS

## 1. Fix Oracle Price Updates [CRITICAL] [BACKEND]
- [ ] Debug oracle keeper process failing to push price updates
- [ ] Check mockkeeper.py service status and logs  
- [ ] Verify OracleAdapter can receive and process price feeds
- [ ] Ensure price updates flow through to PI calculations

## 2. Resolve Vault Data Pipeline [CRITICAL] [FRONTEND]  
- [ ] Fix useVaultMulticall hook returning undefined
- [ ] Debug 413 RPC errors from Base Sepolia affecting data fetching
- [ ] Restore TVL and share price display (currently showing $NaN/$0)
- [ ] Verify vault metrics appear correctly in demo mode

## 3. Fix Position Value Calculations [CRITICAL] [FRONTEND]
- [ ] Debug why all 213 positions show $0.00 values instead of real equity/PnL
- [ ] Verify position data fetching from PositionManager contract
- [ ] Ensure PnL calculations display meaningful values for investors
- [ ] Test position value updates with live market data

## 4. Debug Position Opening Failures [HIGH] [BACKEND/FRONTEND]
- [ ] Investigate "Position Open Failed" errors without redeploying contracts
- [ ] Check ExecutionEngine configuration and permissions  
- [ ] Verify LeverageModel integration via existing contract calls
- [ ] Debug frontend position opening flow and error handling
- [ ] Test leverage calculations work with current contract setup

## 5. Fix Screenshot Verification System [MEDIUM] [DEVOPS]
- [ ] Install missing libatk-1.0.so.0 dependencies for headless browser
- [ ] Restore automated visual verification pipeline
- [ ] Ensure screenshot reports generate properly
- [ ] Verify CI/CD verification gates work

**Focus**: Tasks 1-3 are demo-blockers that make the system appear broken to investors. Task 4 enables core functionality demonstration without violating contract protection rules. Task 5 ensures our verification pipeline works for ongoing development.