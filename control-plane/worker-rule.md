# WORKER VERIFICATION RULE

After completing ANY task in Phase 0B or later deployment phases:

1. Run: `bash /home/lever/lever-protocol/control-plane/health-check.sh`
2. Read the output.
3. If ANY check shows FAIL, the task is NOT complete. Fix the failure before marking done.
4. If health check exits 0 (all pass), task is complete.
5. Include health check output in the shift report.

Before running ANY forge script:
1. Source deploy-env.sh: `source /home/lever/lever-protocol/control-plane/deploy-env.sh`
2. Verify the script reads addresses from env vars, not hardcoded. If hardcoded, fix first.
3. After running, verify on-chain with cast calls. "Script printed SUCCESS" is NOT verification.

NEVER mark a task as done based on script stdout alone. On-chain state is the only truth.
