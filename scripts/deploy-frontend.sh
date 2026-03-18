#!/bin/bash

# LEVER Frontend Deployment Script
set -e

echo "=== LEVER Frontend Deployment ==="

# Navigate to frontend directory
cd /home/lever/lever-protocol/frontend/user-app

echo "Building React application..."
npm run build

echo "Fixing ownership of build directory..."
# This will work even if some files are root-owned since we're rebuilding
chmod -R 755 build/ 2>/dev/null || true

echo "Testing the build..."
# Test that index.html exists and contains React content
if [ ! -f "build/index.html" ]; then
    echo "ERROR: build/index.html not found"
    exit 1
fi

if ! grep -q "react" build/index.html; then
    echo "WARNING: index.html may not contain React app"
fi

echo "Starting frontend server on port 3000..."
# Kill any existing serve processes
pkill -f "serve.*3000" 2>/dev/null || true
pkill -f "python3.*3000" 2>/dev/null || true

# Start serve without -s flag to avoid directory listing issue
nohup npx serve build -l 3000 > /tmp/lever-frontend.log 2>&1 &
SERVE_PID=$!

echo "Waiting for server to start..."
sleep 5

# Test the server
if curl -s http://localhost:3000/ | grep -q "DOCTYPE html" && curl -s http://localhost:3000/ | grep -q "div id=\"root\""; then
    echo "SUCCESS: Frontend is serving React app correctly"
    echo "Frontend PID: $SERVE_PID"
    echo "Log file: /tmp/lever-frontend.log"
else
    echo "ERROR: Frontend is not serving React app correctly"
    curl -s http://localhost:3000/ | head -10
    exit 1
fi

echo "Frontend deployed successfully!"