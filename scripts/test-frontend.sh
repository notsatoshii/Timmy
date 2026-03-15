#!/usr/bin/env bash
# LEVER Protocol — Frontend Test Gate
# Run after EVERY frontend change. Fails = change is broken. No exceptions.
# Usage: ./scripts/test-frontend.sh

set -euo pipefail

FRONTEND_DIR="$(cd "$(dirname "$0")/../frontend/user-app" && pwd)"
PORT=3000
LOG="/tmp/lever-frontend-test-$$.log"
PAGE="/tmp/lever-frontend-page-$$.html"
DEV_PID=""
RESULT=0

cleanup() {
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    kill "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
  rm -f "$LOG" "$PAGE"
}
trap cleanup EXIT

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; RESULT=1; }
die()  { echo "  FAIL  $1"; cleanup; exit 1; }

echo "=== LEVER Frontend Test Gate ==="
echo "Dir: $FRONTEND_DIR"
echo ""
cd "$FRONTEND_DIR"

# -----------------------------------------------------------
# 1. Production build must exit 0
# -----------------------------------------------------------
echo "[1/5] Production build..."
BUILD_OUT=$(npm run build 2>&1) || die "npm run build exited non-zero"

if echo "$BUILD_OUT" | grep -q "Failed to compile"; then
  echo "$BUILD_OUT" | tail -20
  die "Build failed to compile"
fi
pass "npm run build succeeded"

# -----------------------------------------------------------
# 2. No BREAKING CHANGE or real module-not-found errors
#    (filter out optional wagmi connector warnings)
# -----------------------------------------------------------
echo "[2/5] Checking build output for real errors..."
if echo "$BUILD_OUT" | grep -q "BREAKING CHANGE"; then
  echo "$BUILD_OUT" | grep -B2 "BREAKING CHANGE"
  die "BREAKING CHANGE detected"
fi

# Strip known optional connector warnings, then check for remaining Module not found
REAL_MODULE_ERRORS=$(echo "$BUILD_OUT" \
  | grep "Module not found" \
  | grep -v "@coinbase/wallet-sdk" \
  | grep -v "@metamask/sdk" \
  | grep -v "porto" \
  | grep -v "@safe-global" \
  | grep -v "@walletconnect/ethereum-provider" \
  | grep -v "@base-org/account" \
  || true)

if [ -n "$REAL_MODULE_ERRORS" ]; then
  echo "$REAL_MODULE_ERRORS"
  die "Module not found errors in our code (not optional connectors)"
fi
pass "No critical errors in build output"

# -----------------------------------------------------------
# 3. Dev server starts and compiles
# -----------------------------------------------------------
echo "[3/5] Starting dev server on port $PORT..."
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

BROWSER=none PORT=$PORT npm start > "$LOG" 2>&1 &
DEV_PID=$!

WAITED=0
while [ $WAITED -lt 60 ]; do
  if grep -q "webpack compiled" "$LOG" 2>/dev/null; then
    break
  fi
  if grep -q "Failed to compile" "$LOG" 2>/dev/null; then
    grep -A5 "Failed to compile" "$LOG"
    die "Dev server failed to compile"
  fi
  if ! kill -0 "$DEV_PID" 2>/dev/null; then
    die "Dev server process died"
  fi
  sleep 2
  WAITED=$((WAITED + 2))
done

if [ $WAITED -ge 60 ]; then
  die "Dev server did not compile within 60s"
fi
pass "Dev server compiled"

# -----------------------------------------------------------
# 4. HTTP 200 from localhost
# -----------------------------------------------------------
echo "[4/5] Checking http://localhost:$PORT..."
HTTP_CODE=$(curl -s -o "$PAGE" -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
  die "Expected HTTP 200, got $HTTP_CODE"
fi
pass "HTTP 200 received"

# -----------------------------------------------------------
# 5. Page has React root + JS bundle loads
# -----------------------------------------------------------
echo "[5/5] Validating page content..."
if ! grep -q 'id="root"' "$PAGE"; then
  die "Missing React root div in HTML"
fi
pass "React root div present"

if ! grep -q '<script' "$PAGE"; then
  die "No script tags found"
fi
pass "Script tags present"

# Try to fetch the JS bundle
BUNDLE_PATH=$(grep -oP 'src="(/static/js/[^"]+)"' "$PAGE" | head -1 | sed 's/src="//;s/"//')
if [ -n "$BUNDLE_PATH" ]; then
  BUNDLE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT$BUNDLE_PATH" 2>/dev/null || echo "000")
  if [ "$BUNDLE_CODE" = "200" ]; then
    pass "JS bundle loads (HTTP 200)"
  else
    fail "JS bundle returned HTTP $BUNDLE_CODE"
  fi
fi

# Check dev server log for real errors (excluding optional connectors)
DEV_REAL_ERRORS=$(grep "Module not found" "$LOG" 2>/dev/null \
  | grep -v "@coinbase/wallet-sdk" \
  | grep -v "@metamask/sdk" \
  | grep -v "porto" \
  | grep -v "@safe-global" \
  | grep -v "@walletconnect/ethereum-provider" \
  | grep -v "@base-org/account" \
  || true)

if [ -n "$DEV_REAL_ERRORS" ]; then
  echo "$DEV_REAL_ERRORS"
  fail "Module not found errors in dev server (not optional connectors)"
fi

if grep -q "BREAKING CHANGE" "$LOG" 2>/dev/null; then
  fail "BREAKING CHANGE in dev server output"
fi

echo ""
if [ $RESULT -eq 0 ]; then
  echo "=== ALL CHECKS PASSED ==="
else
  echo "=== SOME CHECKS FAILED ==="
  exit 1
fi
