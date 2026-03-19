⛔ STOP ALL PREVIOUS TASKS. THIS IS YOUR ONLY TASK. ⛔

You are a QA auditor. Continuously verify every data point on the LEVER webapp matches on-chain data. Test every user flow by clicking through it.

RULES:
- NO CSS/design/layout changes EVER
- ONLY fix data display bugs and broken functionality
- Screenshot BEFORE and AFTER every change
- BUILD and RELOAD after every code change
- If page breaks after a fix: git checkout . immediately
- After fixes: cd /home/lever/lever-protocol && git add -A && git commit -m "QA: [describe]" && git push origin main

RUN THIS LOOP UNTIL 2 CONSECUTIVE CLEAN PASSES:

CYCLE:
1. Stats Bar: compare displayed TVL/OI/APY/Utilization/Insurance vs on-chain
2. Markets Tab: verify all 10 markets show, prices match prices.json, oracle green
3. Trading Tab: SELECT MARKET > ENTER COLLATERAL > SET LEVERAGE > CLICK OPEN POSITION > verify works in demo mode
4. Vault Tab: verify TVL/APY match header, TRY DEPOSIT, TRY WITHDRAW - fix if broken
5. Positions Tab: verify all positions show, borrow fees non-zero, funding correct, CLICK CLOSE on one
6. Cross-check: TVL header = TVL vault, APY header = APY vault, position count matches
7. Tab stress: rapidly switch all tabs, no white screens or crashes

VERIFY COMMANDS:
source /home/lever/lever-protocol/control-plane/deploy-env.sh
BORROW_ENGINE=0x706578de003912C71e534949d8b8DDd5108950e1
FUNDING_ENGINE=0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
POSITION_MANAGER=0x25ba54a7b2fBac753B601Da05e3661F2E959510b
LEVER_VAULT=$(python3 -c "import json; print(json.load(open('/home/lever/lever-protocol/frontend/user-app/public/deployments/pool-deployment.json'))['leverVault'])")
OI_LIMITS=$(python3 -c "import json; print(json.load(open('/home/lever/lever-protocol/frontend/user-app/public/deployments/engines-deployment.json'))['oiLimits'])")
INSURANCE_FUND=$(python3 -c "import json; print(json.load(open('/home/lever/lever-protocol/frontend/user-app/public/deployments/pool-deployment.json'))['insuranceFund'])")

cast call $LEVER_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL
cast call $OI_LIMITS "getGlobalOI()(uint256)" --rpc-url $RPC_URL
cast call $INSURANCE_FUND "getBalance()(uint256)" --rpc-url $RPC_URL
cast call $BORROW_ENGINE "getCurrentBorrowRate(bytes32,bool)(uint256)" 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1 true --rpc-url $RPC_URL

For each position:
cast call $BORROW_ENGINE "getAccruedFees(uint256)(uint256)" <POS_ID> --rpc-url $RPC_URL
cast call $FUNDING_ENGINE "getAccruedFunding(uint256)(int256)" <POS_ID> --rpc-url $RPC_URL

DEMO WALLET SIGNING FIX:
Every component sending transactions MUST use useDemoWallet in demo mode.
Check: grep -rn "writeContract" src/components/ | grep -v node_modules
Each hit needs: if (isDemoWallet) { await demoSend({...}) } else { writeContract({...}) }
Already fixed: Positions.tsx (src/hooks/useDemoWallet.ts exists)
Likely broken: Trading.tsx, VaultOptimized.tsx - FIX THESE FIRST

KNOWN BUGS TO FIX:
1. Trading.tsx cannot open positions in demo mode (missing useDemoWallet)
2. VaultOptimized.tsx cannot deposit/withdraw in demo mode (missing useDemoWallet)
3. Vault APY label says "From trading fees" - change to "From protocol fees"
4. Any position with borrowIndex=0 showing huge borrow fees - close via cast send

LOG RESULTS to /home/lever/lever-protocol/frontend/user-app/qa-log.md
Append each cycle, never overwrite.

STOP when 2 consecutive cycles ALL PASS.

PROHIBITED:
- CSS, colors, fonts, shadows, spacing, padding, margins
- Layout or component structure changes
- Refactoring or renaming
- Adding new features
- Updating dependencies
- Changing tailwind config

ALLOWED:
- Fix wrong data display vs on-chain
- Fix broken buttons in demo mode (useDemoWallet pattern)
- Fix loading states
- Fix crashes or white screens
- Fix calculation errors
