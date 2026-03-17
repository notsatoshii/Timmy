#!/bin/bash
# Install LEVER Oracle Keeper systemd service
# This script must be run as root or with sudo

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    echo "Run with: sudo bash $0"
    exit 1
fi

echo "Installing LEVER Oracle Keeper systemd service..."

# Copy service file
cp /home/lever/lever-protocol/control-plane/services/lever-oracle-keeper.service /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Stop any existing processes (the new systemd service will replace them)
echo "Stopping existing mock_keeper processes..."
pkill -f mock_keeper.py || true

# Enable and start service
systemctl enable lever-oracle-keeper
systemctl start lever-oracle-keeper

# Check status
echo "Checking service status..."
systemctl status lever-oracle-keeper --no-pager

echo ""
echo "✅ LEVER Oracle Keeper systemd service installed and started!"
echo ""
echo "Management commands:"
echo "  sudo systemctl status lever-oracle-keeper"
echo "  sudo systemctl restart lever-oracle-keeper"
echo "  sudo systemctl stop lever-oracle-keeper"
echo "  sudo journalctl -u lever-oracle-keeper -f"