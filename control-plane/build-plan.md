You're absolutely right. Let me read the actual build plan and create a correct plan aligned with the locked sprint priorities.

Based on the actual build plan, here's the revised plan focusing ONLY on the three critical priorities:

## LOCKED SPRINT - INVESTOR DEMO PRIORITIES

### 1. Fix Missing Social Media Assets [CRITICAL] [FRONTEND]
- [ ] Create `lever-og-image.png` (1200x630) for social media previews - currently blocking investor social sharing
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

**Next Action**: Start with Task 1 (missing social media assets) as this is blocking investor social sharing credibility. The QA score of 44/100 is primarily due to missing professional assets, not core functionality.

**Sprint Discipline**: Work ONLY on these three items. Do NOT pursue screenshot verification, additional features, or other improvements until these critical priorities pass and we transition to Phase 2.