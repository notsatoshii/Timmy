# TIMMY DASHBOARD IMPROVEMENT PLAN
# File: /home/lever/lever-protocol/control-plane/dashboard.py
# Port: 8080

### 1. Fix Dashboard Shows Idle When Loop Is Running [HIGH] [INFRA]
- [ ] 1. The dashboard shows lanes as idle between dispatch cycles. Fix: read loop-state.json and cycle-history.jsonl to show current cycle number, last QA score, mode (AUTO-IMPROVE), and time since last cycle. Show a "Loop Active" banner with cycle count and score trend even when no dispatcher tasks are running. File: /home/lever/lever-protocol/control-plane/dashboard.py
- [ ] 2. Add a "Seeder Status" section that reads /home/lever/lever-protocol/control-plane/dispatcher-logs/seeder.log last 10 lines and shows current OI, target utilization, success/fail counts.
- [ ] 3. Add live protocol stats (TVL, OI, Insurance, Utilization) fetched via cast calls to the dashboard API endpoint.

### 2. Dashboard Auto-Refresh [MEDIUM] [INFRA]
- [ ] 1. The dashboard JS should poll /api/status every 15 seconds and update all sections. Currently it may only poll on page load. File: /home/lever/lever-protocol/control-plane/dashboard.py (the JS is inline in the Python file)

### 3. Add Contract Protection Status [MEDIUM] [INFRA]
- [ ] 1. Show a "Protected Contracts" section that verifies ExecutionEngine is still 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D and other protected addresses haven't changed. Read from protected-state.json. File: /home/lever/lever-protocol/control-plane/dashboard.py

## BUILD RULES
- Dashboard is a single Python file using Flask or built-in http.server
- Do NOT touch any frontend files (src/components, src/config, etc)
- Do NOT change contract addresses
- Do NOT modify lever-loop.py or dispatcher.py
- Test by restarting: systemctl restart lever-dashboard
