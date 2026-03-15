#!/bin/bash
# =============================================================================
# LEVER Model Router — picks optimal model based on task description
# Usage: ./model-router.sh "task description" "full prompt"
# Outputs claude command with correct --model flag
# =============================================================================

TASK_DESC="$1"
PROMPT="$2"
LOG_DIR="/home/lever/lever-protocol/control-plane/worker-logs"

# Default
MODEL="claude-sonnet-4-20250514"
REASON="default"

# Opus triggers — pattern match on task description
if echo "$TASK_DESC" | grep -qiE "audit.*spec|spec.*audit|compare.*spec|verify.*against.*spec|deviation|whitepaper"; then
    MODEL="claude-opus-4-20250514"
    REASON="spec-audit"
elif echo "$TASK_DESC" | grep -qiE "fix.*bug|debug.*integration|debug.*liquidation|debug.*settlement|reentrancy|vulnerability"; then
    MODEL="claude-opus-4-20250514"
    REASON="complex-bugfix"
elif echo "$TASK_DESC" | grep -qiE "integration.*test.*fail|integration.*debug|lifecycle.*fail|multi.*contract"; then
    MODEL="claude-opus-4-20250514"
    REASON="integration-debug"
elif echo "$TASK_DESC" | grep -qiE "security|access.control|permission.*model|attack.*vector"; then
    MODEL="claude-opus-4-20250514"
    REASON="security-review"
elif echo "$TASK_DESC" | grep -qiE "ExecutionEngine.*token|settlement.*wir|PnL.*transfer|token.*flow"; then
    MODEL="claude-opus-4-20250514"
    REASON="architecture-fix"
fi

# Log the decision
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Model: $MODEL | Reason: $REASON | Task: ${TASK_DESC:0:80}" >> "$LOG_DIR/model-decisions.log" 2>/dev/null || true

echo "$MODEL"
