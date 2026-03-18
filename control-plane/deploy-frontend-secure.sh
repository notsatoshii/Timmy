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

# Restart frontend service (try secure service first, fallback to standard)
echo "🔄 Restarting frontend service..."

# Check if secure service is available and try it first
if systemctl is-enabled lever-frontend-secure &>/dev/null; then
    echo "  📡 Using secure frontend service..."
    sudo systemctl restart lever-frontend-secure
    SERVICE_NAME="lever-frontend-secure"
else
    echo "  📡 Using standard frontend service..."
    echo "  💡 For enhanced security, run: sudo bash control-plane/install-secure-frontend.sh"
    sudo systemctl restart lever-frontend
    SERVICE_NAME="lever-frontend"
fi

# Wait for service to start
sleep 3

# Verify service is running
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "❌ Frontend service failed to start!"

    # Restore backup if available
    if [ -d "$BACKUP_DIR" ]; then
        echo "🔄 Restoring backup build due to service failure..."
        sudo systemctl stop "$SERVICE_NAME"
        rm -rf "$BUILD_DIR"
        mv "$BACKUP_DIR" "$BUILD_DIR"
        sudo systemctl start "$SERVICE_NAME"
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

# Enhanced security tests if using secure service
if [ "$SERVICE_NAME" = "lever-frontend-secure" ]; then
    echo "🔒 Running enhanced security verification..."

    # Test health endpoint
    if curl -f -s http://localhost:3000/health > /dev/null; then
        echo "✅ Health endpoint working"
    else
        echo "⚠️  Health endpoint not responding"
    fi

    # Test 404 for missing assets
    HTTP_404_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/missing-asset.js)
    if [ "$HTTP_404_RESPONSE" = "404" ]; then
        echo "✅ Proper 404 responses for missing assets"
    else
        echo "⚠️  Missing asset returned HTTP $HTTP_404_RESPONSE instead of 404"
    fi

    # Test security headers
    SECURITY_HEADERS=$(curl -s -I http://localhost:3000/ | grep -E "(X-Frame-Options|Strict-Transport-Security|X-Content-Type-Options)" | wc -l)
    if [ "$SECURITY_HEADERS" -gt 0 ]; then
        echo "✅ Security headers present"
    else
        echo "⚠️  Security headers not detected"
    fi

    echo "🔒 Enhanced security features verified"
fi

echo "✅ Secure frontend deployment completed successfully"
echo "🌐 Frontend available at: http://localhost:3000"

# Cleanup old backups (keep only last 3)
echo "🗑️  Cleaning up old backups..."
cd "$FRONTEND_DIR"
ls -t build.backup-* 2>/dev/null | tail -n +4 | xargs -r rm -rf

echo "🎉 Deployment complete!"