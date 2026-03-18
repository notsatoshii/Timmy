# LOCKED BUILD PLAN — DASHBOARD ONLY
# DO NOT TOUCH frontend/user-app/ — those files are being manually managed
# ONLY work on the Timmy dashboard at /home/lever/lever-protocol/control-plane/dashboard.py

### 1. Fix Dashboard Shows Idle [HIGH] [INFRA]
- [ ] 1. Read loop-state.json to show current cycle, QA score, mode. Show Loop Active banner with stats even between dispatches. Add last 5 cycle scores as a mini trend. File: /home/lever/lever-protocol/control-plane/dashboard.py only.
- [ ] 2. After changes: systemctl restart lever-dashboard

### 2. Add Live Protocol Stats to Dashboard [HIGH] [INFRA]
- [ ] 1. Add section showing TVL, OI, Utilization, Insurance Fund, Volume fetched via cast calls in the API endpoint. Show seeder status by reading last 10 lines of seeder.log. File: /home/lever/lever-protocol/control-plane/dashboard.py only.
- [ ] 2. After changes: systemctl restart lever-dashboard

### 3. Add Contract Protection Verification [MEDIUM] [INFRA]
- [ ] 1. Show protected contract addresses and verify they match expected values. Read from protected-state.json. Highlight in red if any changed. File: /home/lever/lever-protocol/control-plane/dashboard.py only.
- [ ] 2. After changes: systemctl restart lever-dashboard

## RULES
- ONLY modify dashboard.py — nothing else
- Do NOT touch frontend/user-app/ files
- Do NOT modify lever-loop.py or dispatcher.py
- Do NOT change contract addresses anywhere
- Test: systemctl restart lever-dashboard then curl http://localhost:8080
