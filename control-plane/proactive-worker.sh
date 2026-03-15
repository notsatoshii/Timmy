#!/bin/bash
set -euo pipefail
PROJECT_DIR="/home/lever/lever-protocol"
CD="$PROJECT_DIR/control-plane"
LOG_DIR="$CD/worker-logs"
WLOG="$LOG_DIR/worker-$(date +%Y%m%d-%H%M%S).log"
LOCK="/tmp/lever-worker.lock"
FORGE_BIN="/root/.foundry/bin"
export PATH="$FORGE_BIN:/usr/local/bin:/usr/bin:/bin:/home/lever/.local/bin:$PATH"
TG_TOKEN="8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk"
TG_CHAT="422985839"
ROUTER="$CD/model-router.sh"

# Lock check
if [ -f "$LOCK" ]; then
    LA=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    [ "$LA" -lt 3600 ] && exit 0
    rm -f "$LOCK"
fi
trap 'rm -f "$LOCK"' EXIT
touch "$LOCK"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$WLOG") 2>&1

tg() {
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT" -d parse_mode="Markdown" -d text="$1" >/dev/null 2>&1 || true
}

[ ! -f "$CD/build-plan.md" ] && exit 0

# Extract the first unchecked P0 task description for model routing
NEXT_TASK=$(grep -m1 '^\- \[ \] \*\*P0\*\*' "$CD/build-plan.md" || grep -m1 '^\- \[ \] \*\*P1\*\*' "$CD/build-plan.md" || echo "self-audit")

PLAN=$(cat "$CD/build-plan.md")
PERSONA=""
[ -f "$CD/agent-persona.md" ] && PERSONA=$(cat "$CD/agent-persona.md")
ISSUES=""
[ -f "$CD/known-issues.md" ] && ISSUES=$(cat "$CD/known-issues.md")
SPEC=""
[ -f "$PROJECT_DIR/CLAUDE.md" ] && SPEC=$(cat "$PROJECT_DIR/CLAUDE.md")
CC=$(cd "$PROJECT_DIR" && forge build 2>&1 | tail -5 || echo "COMPILE FAILED")

# Pick model
MODEL="claude-sonnet-4-20250514"
[ -f "$ROUTER" ] && MODEL=$("$ROUTER" "$NEXT_TASK" 2>/dev/null || echo "claude-sonnet-4-20250514")
MODEL_SHORT="${MODEL##*-}"
MODEL_SHORT="${MODEL%%+([0-9])}"

read -r -d '' PROMPT << PEND || true
${PERSONA}

---

You are the proactive worker. Current state:

### Build Plan
${PLAN}

### Known Issues
${ISSUES}

### Compile Status
${CC}

### Project Spec (CLAUDE.md)
${SPEC}

## INSTRUCTIONS
1. If codebase does not compile, fix that FIRST.
2. Find the FIRST unchecked P0 task in the build plan.
3. Execute that task fully. Follow the QA gate from your persona.
4. After completing, update build-plan.md: change [ ] to [x], add completion log entry with date.
5. New issues go to known-issues.md.
6. Commit all changes with a clear message and push to origin main.
7. Write a shift report to: ${LOG_DIR}/report-$(date +%Y%m%d-%H%M%S).md
8. If ALL tasks are complete, self-audit the 3 most recently completed contracts.

Stay in character. Be efficient.
PEND

tg "🔧 *Worker shift started* — $MODEL_SHORT
Task: ${NEXT_TASK:0:100}"

cd "$PROJECT_DIR"
timeout 2700 claude --dangerously-skip-permissions --model "$MODEL" -p "$PROMPT" 2>&1 | tee -a "$WLOG" || {
    EC=$?
    [ $EC -eq 124 ] && tg "⚠️ *Worker timed out* ($MODEL_SHORT)" || tg "❌ *Worker failed* — exit $EC"
}

# Post-work verification
FC=$(cd "$PROJECT_DIR" && forge build 2>&1 | tail -3)
FOK="PASS"
echo "$FC" | grep -qi "error\|failed" && { FOK="FAIL"; tg "🔴 *Worker left codebase broken!*"; }

LR=$(ls -t "$LOG_DIR"/report-*.md 2>/dev/null | head -1 || echo "")
if [ -n "$LR" ] && [ -f "$LR" ]; then
    tg "📋 *Shift Report* ($MODEL_SHORT)
$(head -30 "$LR" | head -c 3500)"
else
    RC=$(cd "$PROJECT_DIR" && git log --oneline -3 2>/dev/null || echo "none")
    tg "📋 *Worker done* | $MODEL_SHORT | Compile: $FOK | $RC"
fi
