You're absolutely correct. I misunderstood the situation completely. Let me revise the plan to focus exclusively on the three locked sprint priorities:

## REVISED PLAN - LOCKED SPRINT PRIORITIES ONLY

### 1. **CRITICAL FRONTEND REPAIR** [CRITICAL] [DEPLOYMENT]
- [ ] **Diagnose directory listing issue**: Check why the frontend is serving directory contents instead of the React app
- [ ] **Fix React app deployment**: Restore proper React application serving 
- [ ] **Verify React app loads**: Confirm LEVER Protocol interface appears instead of file listing
- [ ] **Test core functionality**: Ensure wallet connection and basic navigation work

### 2. **WEB SERVER CONFIGURATION** [CRITICAL] [INFRASTRUCTURE] 
- [ ] **Configure SPA routing**: Set index.html as default route for single-page application
- [ ] **Hide internal file structure**: Prevent directory listing exposure
- [ ] **Test routing**: Verify all React routes work properly (no 404s on refresh)
- [ ] **Secure configuration**: Ensure proper web server security

### 3. **SPRINT PRIORITIES VERIFICATION** [HIGH] [VALIDATION]
- [ ] **Run health-check.sh**: Verify system-wide pass/fail status
- [ ] **Take screenshots**: Document that React app is properly deployed and functional
- [ ] **Verify user flows**: Test that critical demo paths work end-to-end
- [ ] **Confirm QA improvement**: Re-run verification to show QA score improvement from fixing deployment

**CONSTRAINT**: Work ONLY on these three priorities. Do NOT add additional tasks or work on anything else until all three pass verification.

The 52/100 QA score reflects the deployment failure, not feature issues. Let me start with Priority 1 - diagnosing the directory listing problem.