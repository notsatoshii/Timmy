You're absolutely correct. Here's the **corrected plan** based on the actual build priorities and current status:

---

## CORRECTED INVESTOR DEMO PRIORITIES

### Current Status:
- **QA Score**: 100/100 (all systems UP)
- **Task #2 COMPLETE**: 24h volume display fixed in commit a1b10234 (formatWad instead of formatUsdt)

### Remaining Critical Tasks:

### 1. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND] 
- [ ] Take screenshots and test MarketDetail tab with real market data
- [ ] Verify navigation, price charts, and market metadata render properly  
- [ ] Ensure no error boundaries during investor demo walkthrough
- [ ] Document any remaining blockers for demo readiness

### 2. ✅ Fix 24h Volume Display [CRITICAL] [FRONTEND] **COMPLETED**
- ✅ Volume calculation corrected to use formatWad for WAD-formatted positionSize
- ✅ Both regular and fallback displays now show proper leveraged volume amounts
- ✅ Fix verified and deployed in commit a1b10234

### 3. Improve Loading States for Professional Demo [HIGH] [FRONTEND]
- [ ] Add loading spinners/skeleton screens for initial app load
- [ ] Implement proper error boundaries with user-friendly messages  
- [ ] Add meaningful content during JavaScript loading to prevent blank screen
- [ ] Ensure professional presentation quality for investor walkthrough

---

**Focus**: Complete tasks #1 and #3 only. Do NOT work on oracle verification (#4) or insurance fund investigation (#5) until these investor-critical items pass.

**Next Action**: Verify MarketDetail tab functionality first, then improve loading states.