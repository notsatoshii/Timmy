#!/bin/bash
# Oracle Keeper systemd Installation Script
# This script sets up the lever-oracle-keeper systemd service for auto-restart on failure

set -e

SERVICE_NAME="lever-oracle-keeper"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Installing LEVER Oracle Keeper systemd service..."

# Check if running as root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo privileges"
    echo "Usage: sudo bash $0"
    exit 1
fi

# Copy service file to systemd directory
echo "Copying service file to ${SERVICE_FILE}..."
cp /home/lever/lever-protocol/control-plane/lever-oracle-keeper.service "$SERVICE_FILE"

# Update permissions
chown root:root "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable service for auto-start
echo "Enabling service for auto-start..."
systemctl enable "$SERVICE_NAME"

# Check if manual mock keeper is running and stop it
echo "Stopping any manual mock keeper processes..."
pkill -f mock_keeper.py || true
sleep 2

# Start the service
echo "Starting ${SERVICE_NAME} service..."
systemctl start "$SERVICE_NAME"

# Wait a moment and check status
sleep 3
echo "Checking service status..."
systemctl status "$SERVICE_NAME" --no-pager

echo ""
echo "✅ Oracle Keeper systemd service installed successfully!"
echo ""
echo "Service management commands:"
echo "  Check status:  systemctl status $SERVICE_NAME"
echo "  View logs:     journalctl -u $SERVICE_NAME -f"
echo "  Restart:       systemctl restart $SERVICE_NAME"
echo "  Stop:          systemctl stop $SERVICE_NAME"
echo "  Disable:       systemctl disable $SERVICE_NAME"
echo ""
echo "The service will now automatically restart on failure."