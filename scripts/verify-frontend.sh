#!/bin/bash

# LEVER Protocol - Smart Frontend Verification
# Tries screenshot automation first, falls back to health check if needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOTS_DIR="/home/lever/lever-protocol/control-plane/screenshots"

echo "🎯 LEVER Protocol Frontend Verification"
echo "======================================="
echo "Smart verification for investor demo readiness"
echo

# Ensure screenshots directory exists
mkdir -p "$SCREENSHOTS_DIR"

# Function to run screenshot automation
try_screenshot_automation() {
    echo "🤖 Attempting automated screenshot verification..."
    if node "$SCRIPT_DIR/take-screenshots.js"; then
        echo "✅ Screenshot automation successful!"
        return 0
    else
        echo "⚠️  Screenshot automation failed, trying backup method..."
        return 1
    fi
}

# Function to run health check fallback
run_health_check() {
    echo "🏥 Running health check verification..."
    if bash "$SCRIPT_DIR/frontend-health-check.sh"; then
        echo "✅ Health check verification successful!"
        return 0
    else
        echo "❌ Health check failed!"
        return 1
    fi
}

# Main execution
main() {
    local verification_successful=false

    # Try screenshot automation first
    if try_screenshot_automation; then
        verification_successful=true
        echo
        echo "🎉 VERIFICATION COMPLETE - Screenshot automation worked!"
    # Fall back to health check
    elif run_health_check; then
        verification_successful=true
        echo
        echo "🎉 VERIFICATION COMPLETE - Health check fallback worked!"
    else
        echo
        echo "💥 VERIFICATION FAILED - Both methods failed!"
    fi

    echo
    echo "📊 INVESTOR DEMO STATUS:"
    echo "======================="

    if $verification_successful; then
        echo "✅ Frontend verified and ready for investor demo"
        echo "📁 Reports saved in: $SCREENSHOTS_DIR/"
        echo
        echo "🚀 READY FOR DEMO:"
        echo "  • Frontend is running and responsive"
        echo "  • All critical UI components should be loading"
        echo "  • Manual spot-check recommended before presenting"
        echo
        echo "💡 Quick manual check:"
        echo "  1. Open http://localhost:3000"
        echo "  2. Verify all tabs (Markets/Trading/Vault/Positions) load"
        echo "  3. Check browser console for any errors"

        exit 0
    else
        echo "❌ Frontend verification failed"
        echo "🔧 Action required before investor demo"
        echo "📁 Error reports saved in: $SCREENSHOTS_DIR/"
        echo
        echo "🚨 DEMO NOT READY:"
        echo "  • Frontend may not be responsive"
        echo "  • Check if frontend service is running"
        echo "  • Review error reports for details"

        exit 1
    fi
}

# Run with error handling
if ! main "$@"; then
    echo "Script execution failed" >&2
    exit 1
fi