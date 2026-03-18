#!/bin/bash
# Script to secure frontend builds by removing sensitive files
# This should be run after every build to prevent security exposure

BUILD_DIR="/home/lever/lever-protocol/frontend/user-app/build"

if [ ! -d "$BUILD_DIR" ]; then
    echo "❌ Build directory does not exist: $BUILD_DIR"
    exit 1
fi

echo "🔒 Securing frontend build..."

# Remove sensitive files and directories
SENSITIVE_PATHS=(
    "$BUILD_DIR/deployments"
    "$BUILD_DIR/health.html"
    "$BUILD_DIR/*.env"
    "$BUILD_DIR/.env*"
    "$BUILD_DIR/config"
    "$BUILD_DIR/keys"
)

for path in "${SENSITIVE_PATHS[@]}"; do
    if [ -e "$path" ]; then
        echo "🗑️  Removing sensitive path: $(basename "$path")"
        rm -rf "$path"
    fi
done

# Verify index.html exists
if [ ! -f "$BUILD_DIR/index.html" ]; then
    echo "❌ CRITICAL: index.html missing from build directory!"
    echo "   This will cause directory listing exposure"
    exit 1
fi

# Verify static directory exists
if [ ! -d "$BUILD_DIR/static" ]; then
    echo "⚠️  WARNING: static directory missing from build"
fi

echo "✅ Build secured successfully"
echo "📁 Build contents:"
ls -la "$BUILD_DIR" | head -10