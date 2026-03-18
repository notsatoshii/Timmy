#!/bin/bash

# LEVER Frontend Development Server Deployment Script
set -e

echo "=== LEVER Frontend Development Deployment ==="

# Navigate to frontend directory
cd /home/lever/lever-protocol/frontend/user-app

echo "Stopping any existing frontend processes..."
pkill -f "npm.*start" 2>/dev/null || true
pkill -f "serve.*3000" 2>/dev/null || true
pkill -f "python3.*3000" 2>/dev/null || true
sleep 2

echo "Starting development server on port 3000..."
# Use development server which bypasses build permission issues
export PORT=3000
export BROWSER=none

# Start the development server in background
nohup npm start > /tmp/lever-frontend-dev.log 2>&1 &
DEV_PID=$!

echo "Waiting for development server to start..."
sleep 15

# Test the server
echo "Testing frontend response..."
RESPONSE=$(curl -s http://localhost:3000/ 2>/dev/null || echo "")

if echo "$RESPONSE" | grep -q "DOCTYPE html" && echo "$RESPONSE" | grep -q "div id=\"root\""; then
    echo "SUCCESS: Frontend development server is running correctly"
    echo "Frontend PID: $DEV_PID"
    echo "Log file: /tmp/lever-frontend-dev.log"
    echo "Type: Development server (npm start)"

    # Show first few lines of the response
    echo "Response preview:"
    echo "$RESPONSE" | head -3
else
    echo "Still waiting for server to fully start..."
    sleep 10
    RESPONSE=$(curl -s http://localhost:3000/ 2>/dev/null || echo "")

    if echo "$RESPONSE" | grep -q "DOCTYPE html" && echo "$RESPONSE" | grep -q "div id=\"root\""; then
        echo "SUCCESS: Frontend development server is now running correctly"
        echo "Frontend PID: $DEV_PID"
        echo "Log file: /tmp/lever-frontend-dev.log"
    else
        echo "ERROR: Frontend development server is not responding correctly"
        echo "Response received:"
        echo "$RESPONSE" | head -10
        echo "Check log file: /tmp/lever-frontend-dev.log"
        exit 1
    fi
fi

echo "Frontend deployment completed successfully!"
echo "The frontend is now accessible at http://localhost:3000"
echo "Note: Using development server. For production builds, resolve permission issues first."