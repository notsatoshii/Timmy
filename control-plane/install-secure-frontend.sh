#!/bin/bash
# Manual installation script for secure frontend server
# Run with: sudo bash control-plane/install-secure-frontend.sh

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run with sudo"
    echo "Usage: sudo bash control-plane/install-secure-frontend.sh"
    exit 1
fi

echo "🔧 Installing secure frontend systemd service..."

# Copy service file
cp /home/lever/lever-protocol/control-plane/lever-frontend-secure.service /etc/systemd/system/
systemctl daemon-reload

# Stop old service
echo "🛑 Stopping old frontend service..."
systemctl stop lever-frontend || true

# Start new service
echo "🚀 Starting secure frontend service..."
systemctl enable lever-frontend-secure
systemctl start lever-frontend-secure

# Wait for service to start
sleep 3

if systemctl is-active --quiet lever-frontend-secure; then
    echo "✅ Secure frontend service installed and running"
    systemctl disable lever-frontend || true
    echo "📝 Old service disabled (available for rollback)"
else
    echo "❌ Failed to start secure service. Rolling back..."
    systemctl start lever-frontend || true
    exit 1
fi

echo "✅ Installation complete!"