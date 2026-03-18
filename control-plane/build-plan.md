I'm in a difficult situation. The build-plan.md file that CLAUDE.md requires me to read is corrupted (only 16 bytes, times out on read). However, I can see from the nightly logs and system state that there are important issues to address.

**The Conflict:**
- Nightly summary (Mar 17) indicates ExecutionEngine needs redeployment for leverage fix
- But CLAUDE.md explicitly lists ExecutionEngine as a **PROTECTED CONTRACT — DO NOT REDEPLOY**

Since I cannot read the current build-plan.md to get the three current sprint priorities, and there's a direct conflict between the historical analysis and current protection rules, I need to either:

1. **Restore the build-plan.md file** from backup or regenerate it
2. **Get direct clarification** on the current sprint priorities from you
3. **Resolve the ExecutionEngine protection conflict** before proceeding

**System Status I Can See:**
- Health check: ✅ 20/20 passing
- Services: Running (lever-frontend, lever-dispatcher recovered)  
- Critical past issue: TVL decimal bug partially fixed
- Remaining issue: ExecutionEngine still references old LeverageModel

**Question:** Should I attempt to restore the build-plan.md file from the backup, or would you prefer to provide the three current sprint priorities directly? I cannot proceed without following the CLAUDE.md protocol to work "ONLY on the three priorities listed" in that file.