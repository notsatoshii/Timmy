Based on the build plan and QA report (score: 44), here are the critical priorities for the investor demo:

### 1. Fix Missing Social Media Assets [CRITICAL] [FRONTEND]
- [ ] Create `lever-og-image.png` (1200x630) for social media previews — QA report shows this breaks investor social sharing
- [ ] Create missing PWA icons (`logo192.png`, `logo512.png`) referenced in manifest
- [ ] Test social media sharing to ensure images display properly

### 2. Fix Insurance Fund Display Bug [CRITICAL] [FRONTEND] 
- [ ] Insurance Fund shows "5.011e24" (quintillions) instead of ~$10K bootstrap amount
- [ ] Investigate WAD/USDT decimal conversion in insurance fund display formatting
- [ ] Verify fix shows proper $10,000 value in dashboard

### 3. Update Known Issues Documentation [CRITICAL] [DOCUMENTATION]
- [ ] Mark MarketDetail tab as RESOLVED (commit 7a0a4242 shows "verification complete")
- [ ] Mark 24h Volume calculation as RESOLVED (recent commit fixed formatWad vs formatUsdt)
- [ ] Update known-issues.md status to reflect current state

### 4. Verify Oracle Health for Demo [MEDIUM] [OPERATIONS]
- [ ] Check if `mockkeeper.py` is actively running and feeding fresh prices
- [ ] Ensure price updates are flowing properly during demo period
- [ ] Test market price refreshes in frontend

### 5. Address "In Progress" Status Indicators [LOW] [FRONTEND]
- [ ] Review dashboard status displays showing "Audit: In Progress" and "Security: Pending" 
- [ ] Consider if these can be updated for better investor confidence (within factual limits)

**Focus**: The social media assets (#1) are blocking investor social sharing credibility. The 44/100 QA score is primarily due to missing professional assets, not core functionality.