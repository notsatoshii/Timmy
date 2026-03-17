# LOCKED BUILD PLAN — INVESTOR DEMO SPRINT
# DO NOT DEVIATE FROM THESE THREE TASKS

### 1. Fix 24h Volume Display [CRITICAL] [FRONTEND]
- [x] 1. In frontend/user-app/src/hooks/useVolumeCalculation.ts remove the mock fallback BigInt 12800000000 in the catch block. Set volume to BigInt 0 when no events found. Change fromBlock to 0 to fetch ALL historical events.
- [ ] 2. In frontend/user-app/src/components/ProtocolStats.tsx change DEMO_FALLBACK_VALUES volume24h from BigInt 12800000000 to BigInt 0. Show zero not fake data.
- [ ] 3. After changes run cd /home/lever/lever-protocol/frontend/user-app and npm run build and systemctl restart lever-frontend

### 2. Fix Position Opening Auto-Fund Demo Wallet [CRITICAL] [FRONTEND]
- [x] 1. Demo wallet 0xB072263740D7c60f1Aa0BF46e737F83544C7b785 has 9M USDT but 0 in AccountManager which is why positions fail. In frontend/user-app/src/components/Trading.tsx add auto-fund for demo mode. When user clicks Open Position in demo mode first check AccountManager getBalance. If zero then call sendDemoTransaction to approve USDT for AccountManager then deposit 10000 USDT 10000000000 in 6 decimals then call openPosition. Show progress text while funding. The sendDemoTransaction function already exists.
- [ ] 2. After changes run cd /home/lever/lever-protocol/frontend/user-app and npm run build and systemctl restart lever-frontend

### 3. Fix Positions Read Real OnChain Data [CRITICAL] [FRONTEND]
- [x] 1. In frontend/user-app/src/components/Positions.tsx and frontend/user-app/src/hooks/usePositions.ts the fetchPositionDetails function creates HARDCODED FAKE DATA for every position ID instead of reading the contract. Fix by calling getPosition on PositionManager for each ID using publicClient.readContract. The getPosition function exists in POSITION_MANAGER_ABI. Run grep -A 100 getPosition frontend/user-app/src/config/abis.ts to see struct fields. Map returned struct to PositionData interface. Keep baseDemoPositions for visitors with no wallet only.
- [ ] 2. After changes run cd /home/lever/lever-protocol/frontend/user-app and npm run build and systemctl restart lever-frontend
