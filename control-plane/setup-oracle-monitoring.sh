#!/bin/bash
# Setup automated Oracle Keeper monitoring via cron

set -e

CRON_JOB="*/5 * * * * /home/lever/lever-protocol/control-plane/oracle-monitor.sh >/dev/null 2>&1"
MONITOR_SCRIPT="/home/lever/lever-protocol/control-plane/oracle-monitor.sh"

echo "Setting up Oracle Keeper monitoring..."

# Make sure the monitor script is executable
chmod +x "$MONITOR_SCRIPT"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "oracle-monitor.sh"; then
    echo "INFO: Oracle monitor cron job already exists"
else
    # Add cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "SUCCESS: Added cron job to run oracle monitor every 5 minutes"
fi

# Create a log rotation config to prevent logs from growing too large
cat > /home/lever/lever-protocol/control-plane/rotate-oracle-logs.sh << 'EOF'
#!/bin/bash
# Rotate oracle logs to prevent disk space issues

LOG_FILE="/home/lever/lever-protocol/scripts/oracle/mock_keeper.log"
MONITOR_LOG="/home/lever/lever-protocol/control-plane/oracle-monitor.log"
MAX_SIZE=10485760  # 10MB

# Rotate mock keeper log
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_SIZE ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# Rotate monitor log
if [ -f "$MONITOR_LOG" ] && [ $(stat -f%z "$MONITOR_LOG" 2>/dev/null || stat -c%s "$MONITOR_LOG" 2>/dev/null || echo 0) -gt $MAX_SIZE ]; then
    tail -n 1000 "$MONITOR_LOG" > "${MONITOR_LOG}.tmp"
    mv "${MONITOR_LOG}.tmp" "$MONITOR_LOG"
fi
EOF

chmod +x /home/lever/lever-protocol/control-plane/rotate-oracle-logs.sh

# Add log rotation cron job (daily at 2 AM)
ROTATION_JOB="0 2 * * * /home/lever/lever-protocol/control-plane/rotate-oracle-logs.sh >/dev/null 2>&1"

if crontab -l 2>/dev/null | grep -q "rotate-oracle-logs.sh"; then
    echo "INFO: Log rotation cron job already exists"
else
    (crontab -l 2>/dev/null; echo "$ROTATION_JOB") | crontab -
    echo "SUCCESS: Added daily log rotation cron job"
fi

echo ""
echo "Oracle monitoring setup complete!"
echo "- Monitor runs every 5 minutes"
echo "- Logs rotate daily at 2 AM"
echo "- Manual monitor: $MONITOR_SCRIPT"
echo "- View current jobs: crontab -l"