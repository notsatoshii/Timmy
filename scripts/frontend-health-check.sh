#!/bin/bash

# LEVER Protocol - Frontend Health Check
# Verifies frontend is running and responsive without requiring puppeteer

set -e

FRONTEND_URL="http://localhost:3000"
SCREENSHOTS_DIR="/home/lever/lever-protocol/control-plane/screenshots"
TIMESTAMP=$(date -Iseconds | tr ':' '-')

echo "🔍 LEVER Protocol Frontend Health Check"
echo "======================================="

# Ensure screenshots directory exists
mkdir -p "$SCREENSHOTS_DIR"

# Function to check if frontend is running
check_frontend_process() {
    echo -n "📊 Checking frontend process... "
    if systemctl is-active --quiet lever-frontend 2>/dev/null; then
        echo "✓ lever-frontend service is active"
        return 0
    elif pgrep -f "npm.*start.*frontend" > /dev/null; then
        echo "✓ Frontend process found (npm)"
        return 0
    elif pgrep -f "node.*frontend" > /dev/null; then
        echo "✓ Frontend process found (node)"
        return 0
    else
        echo "✗ No frontend process found"
        return 1
    fi
}

# Function to test HTTP response
test_http_response() {
    echo -n "🌐 Testing HTTP response... "
    if response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$FRONTEND_URL"); then
        if [ "$response" = "200" ]; then
            echo "✓ Frontend responding (HTTP $response)"
            return 0
        else
            echo "⚠️  Frontend returned HTTP $response"
            return 1
        fi
    else
        echo "✗ Frontend not reachable"
        return 1
    fi
}

# Function to check content
check_content() {
    echo -n "📄 Checking content... "
    if content=$(curl -s --connect-timeout 5 --max-time 10 "$FRONTEND_URL"); then
        if echo "$content" | grep -q "root\|React\|bundle"; then
            size=$(echo "$content" | wc -c)
            echo "✓ React app detected ($size bytes)"
            return 0
        else
            echo "⚠️  Content served but doesn't appear to be React app"
            return 1
        fi
    else
        echo "✗ Failed to retrieve content"
        return 1
    fi
}

# Function to test specific routes
test_routes() {
    echo "🔗 Testing routes..."
    routes=("/" "/static/css/" "/static/js/")
    for route in "${routes[@]}"; do
        echo -n "   $route ... "
        if response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "${FRONTEND_URL}${route}"); then
            if [ "$response" = "200" ] || [ "$response" = "404" ]; then
                echo "✓ ($response)"
            else
                echo "⚠️  ($response)"
            fi
        else
            echo "✗ (timeout)"
        fi
    done
}

# Function to create health report
create_health_report() {
    local status="$1"
    local details="$2"

    report_json="{
  \"timestamp\": \"$(date -Iseconds)\",
  \"status\": \"$status\",
  \"frontend_url\": \"$FRONTEND_URL\",
  \"check_type\": \"health_check_fallback\",
  \"details\": \"$details\",
  \"manual_verification_needed\": $([[ "$status" != "healthy" ]] && echo "true" || echo "false")
}"

    echo "$report_json" > "$SCREENSHOTS_DIR/latest-review.json"

    report_text="LEVER Protocol Frontend Health Check
======================================
Timestamp: $(date)
Status: $status
Frontend URL: $FRONTEND_URL
Details: $details

Manual Verification Steps (for investor demo):
1. Open $FRONTEND_URL in your browser
2. Verify Markets tab shows market data
3. Click Trading tab - verify position interface loads
4. Click Vault tab - verify vault interface loads
5. Click Positions tab - verify positions table loads
6. Check browser console for errors (F12)

Report saved to: $SCREENSHOTS_DIR/latest-review.json"

    echo "$report_text" > "$SCREENSHOTS_DIR/health-check-${TIMESTAMP}.txt"
}

# Main execution
echo "Starting health check at $(date)..."
echo

# Run all checks
process_ok=false
http_ok=false
content_ok=false

check_frontend_process && process_ok=true
test_http_response && http_ok=true
check_content && content_ok=true
test_routes

echo
echo "📋 SUMMARY:"
echo "==========="

if $process_ok && $http_ok && $content_ok; then
    echo "✅ Frontend is healthy and ready for investor demo"
    create_health_report "healthy" "All checks passed - frontend is serving React app"
    echo "📁 Report saved to: $SCREENSHOTS_DIR/"
    echo
    echo "🎯 INVESTOR DEMO READY:"
    echo "  • Frontend is running and responsive"
    echo "  • React application is loading properly"
    echo "  • Manual verification recommended for final confirmation"
    exit 0
elif $http_ok; then
    echo "⚠️  Frontend is responding but may have issues"
    create_health_report "warning" "HTTP OK but process/content checks failed"
    echo "📁 Report saved to: $SCREENSHOTS_DIR/"
    echo "⚠️  Manual verification required before investor demo"
    exit 1
else
    echo "❌ Frontend is not healthy"
    create_health_report "unhealthy" "Frontend not responding to HTTP requests"
    echo "📁 Report saved to: $SCREENSHOTS_DIR/"
    echo "🚨 Frontend needs attention before investor demo"
    exit 1
fi