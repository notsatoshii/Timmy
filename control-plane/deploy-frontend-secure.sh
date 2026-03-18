#!/bin/bash
# Secure frontend deployment script
# Builds the React app and ensures no sensitive files are exposed

set -e

FRONTEND_DIR="/home/lever/lever-protocol/frontend/user-app"
BUILD_DIR="$FRONTEND_DIR/build"
BACKUP_DIR="$FRONTEND_DIR/build.backup-$(date +%Y%m%d-%H%M)"

echo "🚀 Starting secure frontend deployment..."

# Change to frontend directory
cd "$FRONTEND_DIR"

# Backup existing build if it exists
if [ -d "$BUILD_DIR" ]; then
    echo "📦 Backing up existing build to: $(basename "$BACKUP_DIR")"
    mv "$BUILD_DIR" "$BACKUP_DIR"
fi

# Build the React app
echo "⚙️  Building React application..."
npm run build

# Verify build was successful
if [ ! -f "$BUILD_DIR/index.html" ]; then
    echo "❌ BUILD FAILED: index.html not found"

    # Restore backup if available
    if [ -d "$BACKUP_DIR" ]; then
        echo "🔄 Restoring backup build..."
        mv "$BACKUP_DIR" "$BUILD_DIR"
    fi

    exit 1
fi

# Security check
echo "🔒 Running security validation..."

# Check for sensitive files that should not be in production
SECURITY_VIOLATIONS=0

if [ -d "$BUILD_DIR/deployments" ]; then
    echo "⚠️  WARNING: deployments directory found in build (will be removed)"
    ((SECURITY_VIOLATIONS++))
fi

if [ -f "$BUILD_DIR/health.html" ]; then
    echo "⚠️  WARNING: health.html found in build (will be removed)"
    ((SECURITY_VIOLATIONS++))
fi

if ls "$BUILD_DIR"/*.env* 1> /dev/null 2>&1; then
    echo "⚠️  WARNING: Environment files found in build (will be removed)"
    ((SECURITY_VIOLATIONS++))
fi

# Run security script to clean up
if [ $SECURITY_VIOLATIONS -gt 0 ]; then
    echo "🧹 Cleaning up security violations..."
    bash /home/lever/lever-protocol/scripts/secure-build.sh
fi

# Restart frontend service
echo "🔄 Restarting frontend service..."
sudo systemctl restart lever-frontend

# Wait for service to start
sleep 3

# Verify service is running
if ! systemctl is-active --quiet lever-frontend; then
    echo "❌ Frontend service failed to start!"

    # Restore backup if available
    if [ -d "$BACKUP_DIR" ]; then
        echo "🔄 Restoring backup build due to service failure..."
        sudo systemctl stop lever-frontend
        rm -rf "$BUILD_DIR"
        mv "$BACKUP_DIR" "$BUILD_DIR"
        sudo systemctl start lever-frontend
    fi

    exit 1
fi

# Test the deployment
echo "🧪 Testing deployment..."

# Test that main page serves React app, not directory listing
RESPONSE=$(curl -s http://localhost:3000/ | head -1)
if [[ $RESPONSE == *"Index of"* ]]; then
    echo "❌ CRITICAL: Frontend serving directory listing instead of React app!"
    exit 1
fi

if [[ $RESPONSE == *"<!doctype html>"* ]]; then
    echo "✅ Frontend serving React application correctly"
else
    echo "⚠️  WARNING: Unexpected response from frontend"
    echo "Response: $RESPONSE"
fi

# Test that sensitive paths are protected
TEST_DEPLOYMENT_RESPONSE=$(curl -s http://localhost:3000/deployments/core-deployment.json | head -1)
if [[ $TEST_DEPLOYMENT_RESPONSE != *"<!doctype html>"* ]]; then
    echo "❌ CRITICAL: Sensitive deployment files still accessible!"
    exit 1
fi

echo "✅ Secure frontend deployment completed successfully"
echo "🌐 Frontend available at: http://localhost:3000"

# Cleanup old backups (keep only last 3)
echo "🗑️  Cleaning up old backups..."
cd "$FRONTEND_DIR"
ls -t build.backup-* 2>/dev/null | tail -n +4 | xargs -r rm -rf

echo "🎉 Deployment complete!"