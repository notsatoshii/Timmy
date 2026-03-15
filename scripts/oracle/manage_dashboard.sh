#!/bin/bash
# LEVER Oracle Feed Dashboard Management Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICE_FILE="$SCRIPT_DIR/lever-feed-dashboard.service"
DASHBOARD_SCRIPT="$SCRIPT_DIR/feed_dashboard.py"

cd "$PROJECT_ROOT"

usage() {
    echo "Usage: $0 {start|stop|restart|status|install|check|web|logs}"
    echo ""
    echo "Commands:"
    echo "  start     Start dashboard daemon (background)"
    echo "  stop      Stop dashboard daemon"
    echo "  restart   Restart dashboard daemon"
    echo "  status    Show dashboard status"
    echo "  install   Install systemd service (requires sudo)"
    echo "  check     One-time health check"
    echo "  web       Start web server only (foreground)"
    echo "  logs      Show recent logs (if using systemd)"
    exit 1
}

check_config() {
    if [[ ! -f "scripts/oracle/market_config.json" ]]; then
        echo "❌ Market config not found: scripts/oracle/market_config.json"
        echo "Run: python3 scripts/oracle/onboard_markets.py first"
        exit 1
    fi
}

case "${1:-}" in
    check)
        echo "🔍 Performing one-time feed health check..."
        check_config
        python3 "$DASHBOARD_SCRIPT" --check
        ;;

    web)
        echo "🌐 Starting web server (foreground)..."
        echo "Access: http://localhost:8081/dashboard"
        echo "Press Ctrl+C to stop"
        check_config
        python3 "$DASHBOARD_SCRIPT" --web
        ;;

    start)
        echo "🚀 Starting dashboard daemon..."
        check_config

        # Try systemd first, fallback to manual
        if systemctl --user is-active lever-feed-dashboard >/dev/null 2>&1; then
            echo "✅ Service already running (systemd)"
        elif systemctl --user status lever-feed-dashboard >/dev/null 2>&1; then
            systemctl --user start lever-feed-dashboard
            echo "✅ Service started (systemd)"
        else
            echo "⚠️  Starting manually (systemd service not installed)"
            nohup python3 "$DASHBOARD_SCRIPT" --daemon > logs/dashboard.log 2>&1 &
            echo $! > /tmp/lever-dashboard.pid
            echo "✅ Dashboard started (PID: $!)"
            echo "Web interface: http://localhost:8081/dashboard"
            echo "Logs: tail -f logs/dashboard.log"
        fi
        ;;

    stop)
        echo "🛑 Stopping dashboard daemon..."

        # Try systemd first
        if systemctl --user is-active lever-feed-dashboard >/dev/null 2>&1; then
            systemctl --user stop lever-feed-dashboard
            echo "✅ Service stopped (systemd)"
        elif [[ -f /tmp/lever-dashboard.pid ]]; then
            PID=$(cat /tmp/lever-dashboard.pid)
            if kill -0 "$PID" 2>/dev/null; then
                kill -TERM "$PID"
                sleep 2
                if kill -0 "$PID" 2>/dev/null; then
                    kill -KILL "$PID"
                fi
                rm -f /tmp/lever-dashboard.pid
                echo "✅ Dashboard stopped (PID: $PID)"
            else
                echo "⚠️  PID file exists but process not running"
                rm -f /tmp/lever-dashboard.pid
            fi
        else
            echo "⚠️  No running dashboard found"
        fi
        ;;

    restart)
        echo "🔄 Restarting dashboard..."
        $0 stop
        sleep 2
        $0 start
        ;;

    status)
        echo "📊 Dashboard status:"

        # Check systemd service
        if systemctl --user status lever-feed-dashboard >/dev/null 2>&1; then
            systemctl --user status lever-feed-dashboard --no-pager
        elif [[ -f /tmp/lever-dashboard.pid ]]; then
            PID=$(cat /tmp/lever-dashboard.pid)
            if kill -0 "$PID" 2>/dev/null; then
                echo "✅ Running manually (PID: $PID)"
            else
                echo "❌ PID file exists but process dead"
            fi
        else
            echo "❌ Not running"
        fi

        # Test web interface
        if curl -s http://localhost:8081/api/health >/dev/null 2>&1; then
            echo "✅ Web interface responding (port 8081)"
        else
            echo "❌ Web interface not responding"
        fi

        # Check database
        if [[ -f "scripts/oracle/feed_logs.db" ]]; then
            echo "✅ Database exists ($(stat -f%z scripts/oracle/feed_logs.db 2>/dev/null || stat -c%s scripts/oracle/feed_logs.db 2>/dev/null || echo "unknown") bytes)"
        else
            echo "⚠️  Database not found"
        fi
        ;;

    install)
        echo "📦 Installing systemd service..."

        if [[ ! -f "$SERVICE_FILE" ]]; then
            echo "❌ Service file not found: $SERVICE_FILE"
            exit 1
        fi

        # Install for current user
        mkdir -p ~/.config/systemd/user
        cp "$SERVICE_FILE" ~/.config/systemd/user/
        systemctl --user daemon-reload
        systemctl --user enable lever-feed-dashboard

        echo "✅ Service installed and enabled"
        echo "Use: systemctl --user start lever-feed-dashboard"
        echo "Or:  $0 start"
        ;;

    logs)
        echo "📋 Recent dashboard logs:"
        if systemctl --user is-active lever-feed-dashboard >/dev/null 2>&1; then
            journalctl --user -u lever-feed-dashboard --no-pager -n 50
        elif [[ -f logs/dashboard.log ]]; then
            tail -n 50 logs/dashboard.log
        else
            echo "⚠️  No logs found"
        fi
        ;;

    *)
        usage
        ;;
esac