#!/bin/bash
set -e

echo "Installing LEVER Oracle Keeper systemd service..."

# Copy service file to systemd directory
sudo cp /home/lever/lever-protocol/control-plane/services/lever-oracle-keeper.service /etc/systemd/system/

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable lever-oracle-keeper
sudo systemctl start lever-oracle-keeper

# Check status
sleep 2
sudo systemctl status lever-oracle-keeper --no-pager

echo "Oracle Keeper service installed and started!"
echo "To check logs: journalctl -u lever-oracle-keeper -f"
echo "To restart: sudo systemctl restart lever-oracle-keeper"