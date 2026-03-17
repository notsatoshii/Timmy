#!/bin/bash
set -e

echo "Setting up LEVER Oracle Keeper service..."

# Check if we're running with appropriate permissions
if [ "$EUID" -eq 0 ]; then
    echo "Installing systemd service..."
    # Copy service file to systemd directory
    cp /home/lever/lever-protocol/control-plane/services/lever-oracle-keeper.service /etc/systemd/system/

    # Reload systemd daemon
    systemctl daemon-reload

    # Enable and start the service
    systemctl enable lever-oracle-keeper
    systemctl start lever-oracle-keeper

    # Check status
    sleep 2
    systemctl status lever-oracle-keeper --no-pager

    echo "Oracle Keeper service installed and started!"
    echo "To check logs: journalctl -u lever-oracle-keeper -f"
    echo "To restart: systemctl restart lever-oracle-keeper"
else
    echo "Creating installation script for root..."
    cat > /tmp/install-oracle-keeper-root.sh << 'EOF'
#!/bin/bash
cp /home/lever/lever-protocol/control-plane/services/lever-oracle-keeper.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable lever-oracle-keeper
systemctl start lever-oracle-keeper
echo "Oracle Keeper service installed and started!"
systemctl status lever-oracle-keeper --no-pager
EOF
    chmod +x /tmp/install-oracle-keeper-root.sh

    echo "Manual installation required. Run as root:"
    echo "  sudo /tmp/install-oracle-keeper-root.sh"
    echo ""
    echo "Or run the keeper manually for testing:"
    echo "  cd /home/lever/lever-protocol"
    echo "  export KEEPER_KEY=\$(cat .env.deployer)"
    echo "  export RPC_URL=https://sepolia.base.org"
    echo "  export ORACLE_ADAPTER=0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
    echo "  export MARKET_CONFIG=/home/lever/lever-protocol/scripts/oracle/market_config.json"
    echo "  python3 scripts/oracle/mock_keeper.py"
fi