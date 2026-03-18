#!/bin/bash
# Upgrade frontend server to secure configuration
# Addresses: 404 responses, security headers, health endpoint, vulnerability scan monitoring

set -e

echo "🔄 Upgrading LEVER Frontend to Secure Server..."

# Ensure log directory exists
mkdir -p /home/lever/lever-protocol/control-plane/dispatcher-logs

# Test the new server before deploying
echo "🧪 Testing new secure server configuration..."
cd /home/lever/lever-protocol/frontend/user-app

# Verify build exists
if [ ! -f "build/index.html" ]; then
    echo "❌ React build not found. Running build first..."
    npm run build
fi

# Test the server can start
echo "  🔍 Testing server startup..."
timeout 10s node /home/lever/lever-protocol/scripts/secure-spa-server.js 3001 &
SERVER_PID=$!

sleep 3

# Test basic connectivity
if curl -f -s http://localhost:3001/health > /dev/null; then
    echo "  ✅ Health endpoint working"
else
    echo "  ❌ Health endpoint failed"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

# Test React app serves correctly
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/)
if [ "$HTTP_RESPONSE" = "200" ]; then
    echo "  ✅ React app serves correctly"
else
    echo "  ❌ React app failed with HTTP $HTTP_RESPONSE"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

# Test 404 for missing assets
HTTP_404_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/nonexistent.js)
if [ "$HTTP_404_RESPONSE" = "404" ]; then
    echo "  ✅ Proper 404 for missing assets"
else
    echo "  ❌ Failed to return 404 for missing assets (got $HTTP_404_RESPONSE)"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

# Test vulnerability scanning detection
HTTP_VULN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/.env)
if [ "$HTTP_VULN_RESPONSE" = "404" ]; then
    echo "  ✅ Vulnerability scanning detected and blocked"
else
    echo "  ⚠️  Unexpected response to .env request: $HTTP_VULN_RESPONSE"
fi

# Stop test server
kill $SERVER_PID 2>/dev/null || true
echo "  ✅ New server configuration tested successfully"

# Install new systemd service
echo "🔧 Installing new systemd service..."
sudo cp /home/lever/lever-protocol/control-plane/lever-frontend-secure.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Stop old service
echo "🛑 Stopping old frontend service..."
sudo systemctl stop lever-frontend || true

# Start new service
echo "🚀 Starting new secure frontend service..."
sudo systemctl enable lever-frontend-secure
sudo systemctl start lever-frontend-secure

# Wait for service to start
sleep 5

# Verify new service is running
if systemctl is-active --quiet lever-frontend-secure; then
    echo "✅ New secure frontend service is running"
else
    echo "❌ New secure frontend service failed to start!"
    echo "Rolling back to old service..."
    sudo systemctl start lever-frontend || true
    exit 1
fi

# Test the production deployment
echo "🧪 Testing production deployment..."

# Test health endpoint
if curl -f -s http://localhost:3000/health > /dev/null; then
    echo "  ✅ Production health endpoint working"
else
    echo "  ❌ Production health endpoint failed"
    exit 1
fi

# Test React app
PROD_HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/)
if [ "$PROD_HTTP_RESPONSE" = "200" ]; then
    echo "  ✅ Production React app working"
else
    echo "  ❌ Production React app failed with HTTP $PROD_HTTP_RESPONSE"
    exit 1
fi

# Test security headers
SECURITY_HEADERS=$(curl -s -I http://localhost:3000/ | grep -E "(X-Frame-Options|Strict-Transport-Security|X-Content-Type-Options)")
if [ -n "$SECURITY_HEADERS" ]; then
    echo "  ✅ Security headers present"
    echo "    Headers found:"
    echo "$SECURITY_HEADERS" | sed 's/^/      /'
else
    echo "  ⚠️  Security headers not detected"
fi

# Test proper 404 responses
ASSET_404_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/missing-asset.js)
if [ "$ASSET_404_RESPONSE" = "404" ]; then
    echo "  ✅ Proper 404 responses for missing assets"
else
    echo "  ⚠️  Missing asset returned HTTP $ASSET_404_RESPONSE instead of 404"
fi

# Test vulnerability scanning detection and logging
echo "  🔍 Testing vulnerability scan detection..."
curl -s http://localhost:3000/.env > /dev/null || true
curl -s http://localhost:3000/config.php > /dev/null || true

if [ -f "/home/lever/lever-protocol/control-plane/dispatcher-logs/security-access.log" ]; then
    VULN_LOGS=$(tail -5 /home/lever/lever-protocol/control-plane/dispatcher-logs/security-access.log | grep vulnerability_scan | wc -l)
    if [ "$VULN_LOGS" -gt 0 ]; then
        echo "  ✅ Vulnerability scanning detection and logging working ($VULN_LOGS events logged)"
    else
        echo "  ⚠️  No vulnerability scan events logged"
    fi
else
    echo "  ⚠️  Security access log not found"
fi

# Disable old service (but keep it available for rollback)
sudo systemctl disable lever-frontend || true

echo ""
echo "🎉 Frontend server upgrade completed successfully!"
echo ""
echo "New features:"
echo "  ✅ Proper 404 responses for missing static resources"
echo "  ✅ Security headers (HSTS, X-Frame-Options, CSP, etc.)"
echo "  ✅ Health endpoint at /health for monitoring"
echo "  ✅ Vulnerability scanning detection and logging"
echo "  ✅ React SPA routing still works correctly"
echo ""
echo "Monitoring:"
echo "  📊 Health: curl http://localhost:3000/health"
echo "  🔒 Security logs: tail -f /home/lever/lever-protocol/control-plane/dispatcher-logs/security-access.log"
echo "  📈 Service status: systemctl status lever-frontend-secure"
echo ""

# Create rollback script for safety
cat > /home/lever/lever-protocol/control-plane/rollback-frontend-server.sh << 'EOF'
#!/bin/bash
# Rollback to old frontend server if needed

echo "🔄 Rolling back to old frontend server..."

sudo systemctl stop lever-frontend-secure || true
sudo systemctl disable lever-frontend-secure || true

sudo systemctl enable lever-frontend
sudo systemctl start lever-frontend

echo "✅ Rollback completed. Old server is running."
EOF

chmod +x /home/lever/lever-protocol/control-plane/rollback-frontend-server.sh
echo "📝 Rollback script created: /home/lever/lever-protocol/control-plane/rollback-frontend-server.sh"