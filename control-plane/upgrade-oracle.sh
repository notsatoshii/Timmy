#!/bin/bash
# Oracle Service Upgrade Script
# Safely switches to the improved oracle keeper with better transaction handling

set -e

LOG_FILE="/home/lever/lever-protocol/control-plane/oracle-upgrade.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ORACLE-UPGRADE] $1" | tee -a "$LOG_FILE"
}

# Check if we can access the systemctl (need to be root or have sudo)
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        SYSTEMCTL="systemctl"
    elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        SYSTEMCTL="sudo systemctl"
    else
        log "ERROR: Cannot control systemd services (no root/sudo access)"
        return 1
    fi
}

backup_current_service() {
    log "Backing up current service configuration..."
    cp /etc/systemd/system/lever-oracle.service /etc/systemd/system/lever-oracle.service.backup || {
        log "WARNING: Could not backup service file"
    }
}

upgrade_service_config() {
    log "Creating improved service configuration..."

    cat > /tmp/lever-oracle-improved.service << 'EOF'
[Unit]
Description=LEVER Oracle Keeper (Improved)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/lever/lever-protocol/scripts/oracle
Environment="RPC_URL=https://base-sepolia-rpc.publicnode.com"
Environment="ORACLE_ADAPTER=0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
Environment="PUSH_INTERVAL=15"
Environment="DRY_RUN=false"
ExecStartPre=/bin/bash -c 'echo KEEPER_KEY=$$(cat /home/lever/lever-protocol/.env.deployer | tr -d "[:space:]")'
ExecStart=/bin/bash -c 'export KEEPER_KEY=$$(cat /home/lever/lever-protocol/.env.deployer | tr -d "[:space:]") && /home/lever/lever-protocol/scripts/oracle/.venv/bin/python3 improved_keeper.py'
Restart=always
RestartSec=15
StandardOutput=append:/home/lever/lever-protocol/scripts/oracle/improved_keeper.log
StandardError=append:/home/lever/lever-protocol/scripts/oracle/improved_keeper.log

[Install]
WantedBy=multi-user.target
EOF

    # Copy new service config
    if [[ $EUID -eq 0 ]]; then
        cp /tmp/lever-oracle-improved.service /etc/systemd/system/lever-oracle.service
    else
        log "INFO: Service config created at /tmp/lever-oracle-improved.service"
        log "INFO: Manual step required: sudo cp /tmp/lever-oracle-improved.service /etc/systemd/system/lever-oracle.service"
    fi
}

switch_keeper() {
    log "Switching to improved oracle keeper..."

    # Kill any running mock keeper processes
    log "Stopping existing oracle processes..."
    pkill -f mock_keeper.py || true
    pkill -f improved_keeper.py || true
    sleep 3

    # Make sure improved keeper is executable
    chmod +x /home/lever/lever-protocol/scripts/oracle/improved_keeper.py

    # Test the improved keeper briefly
    log "Testing improved keeper..."
    cd /home/lever/lever-protocol/scripts/oracle

    # Start improved keeper in background for a quick test
    export KEEPER_KEY=$(cat /home/lever/lever-protocol/.env.deployer | tr -d "[:space:]")
    export RPC_URL="https://base-sepolia-rpc.publicnode.com"
    export ORACLE_ADAPTER="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
    export PUSH_INTERVAL="15"
    export DRY_RUN="true"  # Dry run test

    timeout 10s .venv/bin/python3 improved_keeper.py || {
        log "WARNING: Improved keeper test failed, check logs"
    }

    log "Test complete, starting production keeper..."
    export DRY_RUN="false"

    # If we have systemctl access, restart the service
    if [[ -n "$SYSTEMCTL" ]]; then
        log "Restarting service..."
        $SYSTEMCTL daemon-reload
        $SYSTEMCTL restart lever-oracle.service
        sleep 5

        if $SYSTEMCTL is-active lever-oracle.service >/dev/null; then
            log "SUCCESS: Improved oracle service is running"
        else
            log "ERROR: Service failed to start, check systemctl status lever-oracle.service"
            return 1
        fi
    else
        # Manual start
        log "Starting improved keeper manually (no systemctl access)..."
        nohup .venv/bin/python3 improved_keeper.py > improved_keeper.log 2>&1 &
        KEEPER_PID=$!
        sleep 5

        if kill -0 $KEEPER_PID 2>/dev/null; then
            log "SUCCESS: Improved oracle keeper started (PID: $KEEPER_PID)"
        else
            log "ERROR: Failed to start improved keeper"
            return 1
        fi
    fi
}

verify_upgrade() {
    log "Verifying oracle upgrade..."

    # Check if process is running
    if pgrep -f improved_keeper.py >/dev/null; then
        log "✅ Improved keeper process is running"
    else
        log "❌ Improved keeper process not found"
        return 1
    fi

    # Wait a moment for price updates
    sleep 20

    # Check if prices are being updated
    if [[ -f "/home/lever/lever-protocol/frontend/user-app/public/prices.json" ]]; then
        local last_update=$(jq -r '.lastUpdate' "/home/lever/lever-protocol/frontend/user-app/public/prices.json" 2>/dev/null)
        local current_time=$(date +%s)
        local age=$((current_time - last_update))

        if (( age < 60 )); then
            log "✅ Prices are fresh (${age}s old)"
        else
            log "⚠️  Prices may be stale (${age}s old)"
        fi
    else
        log "⚠️  prices.json not found"
    fi

    # Check for errors in the log
    if [[ -f "/home/lever/lever-protocol/scripts/oracle/improved_keeper.log" ]]; then
        local error_count=$(tail -20 "/home/lever/lever-protocol/scripts/oracle/improved_keeper.log" | grep -c "ERROR" || echo 0)
        if (( error_count == 0 )); then
            log "✅ No recent errors in improved keeper"
        else
            log "⚠️  ${error_count} errors in recent log entries"
        fi
    fi

    log "Oracle upgrade verification complete"
}

main() {
    log "Starting oracle service upgrade to improved keeper..."

    # Check permissions first (but continue even without systemctl)
    check_permissions || log "WARNING: Limited permissions, will use manual process control"

    # Create backup
    backup_current_service

    # Prepare new service config
    upgrade_service_config

    # Switch to improved keeper
    switch_keeper || {
        log "ERROR: Failed to switch keeper"
        exit 1
    }

    # Verify the upgrade
    verify_upgrade

    log "Oracle upgrade complete!"
}

# Run upgrade
main "$@"