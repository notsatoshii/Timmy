#!/bin/bash

# LEVER Frontend Fix Script
set -e

echo "=== LEVER Frontend Deployment Fix ==="

# Navigate to frontend directory
cd /home/lever/lever-protocol/frontend/user-app

echo "Testing the existing build..."
if [ ! -f "build/index.html" ]; then
    echo "ERROR: build/index.html not found"
    exit 1
fi

echo "Stopping any existing frontend processes..."
# Kill any existing serve processes
pkill -f "serve.*3000" 2>/dev/null || true
pkill -f "python3.*3000" 2>/dev/null || true
sleep 2

echo "Starting frontend server on port 3000 without -s flag..."
# Start serve without -s flag to avoid directory listing issue
nohup npx serve build -l 3000 > /tmp/lever-frontend.log 2>&1 &
SERVE_PID=$!

echo "Waiting for server to start..."
sleep 5

# Test the server
echo "Testing frontend response..."
RESPONSE=$(curl -s http://localhost:3000/)

if echo "$RESPONSE" | grep -q "DOCTYPE html" && echo "$RESPONSE" | grep -q "div id=\"root\""; then
    echo "SUCCESS: Frontend is serving React app correctly"
    echo "Frontend PID: $SERVE_PID"
    echo "Log file: /tmp/lever-frontend.log"

    # Show first few lines of the response
    echo "Response preview:"
    echo "$RESPONSE" | head -3
else
    echo "ERROR: Frontend is not serving React app correctly"
    echo "Response received:"
    echo "$RESPONSE" | head -10
    exit 1
fi

echo "Frontend deployment fixed successfully!"
echo "The frontend should now be accessible at http://localhost:3000"