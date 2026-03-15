#!/bin/bash
set -euo pipefail
PROJECT_DIR="/home/lever/lever-protocol"
LOG_DIR="$PROJECT_DIR/control-plane/nightly-logs"
CYCLE_LOG="$LOG_DIR/cycle-$(date +%Y%m%d-%H%M%S).log"
ISSUES_FILE="$PROJECT_DIR/control-plane/known-issues.md"
PERSONA_FILE="$PROJECT_DIR/control-plane/agent-persona.md"
TG_TOKEN="8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk"
TG_CHAT="422985839"
FORGE_BIN="/root/.foundry/bin"
export PATH="$FORGE_BIN:/usr/local/bin:/usr/bin:/bin:/home/lever/.local/bin:$PATH"
MODEL="claude-sonnet-4-20250514"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$CYCLE_LOG") 2>&1

tg() {
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT" -d parse_mode="Markdown" -d text="$1" >/dev/null 2>&1 || true
}

tg "🌙 *Nightly cycle started* (sonnet) — $(date '+%H:%M %Z, %b %d')"

GIT_STATUS=$(cd "$PROJECT_DIR" && git status --short 2>&1 || echo "failed")
GIT_LOG=$(cd "$PROJECT_DIR" && git log --oneline -10 2>&1 || echo "failed")
COMPILE=$(cd "$PROJECT_DIR" && forge build --sizes 2>&1 || echo "COMPILE FAILED")
TESTS=$(cd "$PROJECT_DIR" && timeout 1200 forge test --summary 2>&1 || echo "TESTS FAILED/TIMED OUT")
ISSUES=""
[ -f "$ISSUES_FILE" ] && ISSUES=$(cat "$ISSUES_FILE")
PERSONA=""
[ -f "$PERSONA_FILE" ] && PERSONA=$(cat "$PERSONA_FILE")
UNCOMMITTED=$(cd "$PROJECT_DIR" && git diff --name-only 2>/dev/null || echo "")

read -r -d '' PROMPT << PEND || true
${PERSONA}

---

You are the nightly maintenance agent. Stay in character.

## STATE
### Git Status
${GIT_STATUS}

### Recent Commits
${GIT_LOG}

### Uncommitted Changes
${UNCOMMITTED}

### Compile Result
${COMPILE}

### Test Results
${TESTS}

### Known Issues
${ISSUES}

## PRIORITIES
1. Fix any compile errors
2. Fix any failing tests
3. Address HIGH/CRITICAL severity items from known-issues.md
4. Address MEDIUM severity items
5. Run full test suite and record results
6. Write summary to ${LOG_DIR}/summary-$(date +%Y%m%d).md
7. Commit and push all changes to origin main

Stay efficient. Fix what you can. Document what you cannot.
PEND

cd "$PROJECT_DIR"
timeout 3600 claude --dangerously-skip-permissions --model "$MODEL" -p "$PROMPT" 2>&1 | tee -a "$CYCLE_LOG" || {
    EC=$?
    [ $EC -eq 124 ] && tg "⚠️ *Nightly timed out*" || tg "❌ *Nightly failed* — exit $EC"
}

FC=$(cd "$PROJECT_DIR" && forge build 2>&1 && echo "PASS" || echo "FAIL")
SM="$LOG_DIR/summary-$(date +%Y%m%d).md"
S="No summary."
[ -f "$SM" ] && S=$(head -40 "$SM")

tg "🌅 *Nightly Done* | Compile: $FC
${S:0:3500}"
