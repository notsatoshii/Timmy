#!/usr/bin/env python3
"""
Oracle Feed Monitoring Dashboard — Persistent logging, gap detection, web interface.

Features:
- Persistent SQLite logging of all price updates
- Gap detection (periods with no updates)
- Stale feed alerting with escalation
- Web dashboard for feed health visualization
- Integration with existing feed_monitor.py

Usage:
    python feed_dashboard.py --daemon    # Run as background daemon
    python feed_dashboard.py --web       # Start web server only
    python feed_dashboard.py --check     # One-time health check
"""

import json
import logging
import sqlite3
import time
import threading
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List, Dict
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse
import sys

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.feed_monitor import FeedMonitor

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────
DB_PATH = Path("scripts/oracle/feed_logs.db")
WEB_PORT = 8081
CHECK_INTERVAL = 60  # seconds between health checks
GAP_THRESHOLD = 300  # 5 minutes = gap in price data
ALERT_COOLDOWN = 3600  # 1 hour between repeat alerts
DEFAULT_CONFIG = "scripts/oracle/market_config.json"

@dataclass
class PriceUpdate:
    """Single price update record."""
    timestamp: float
    market_id: str
    question: str
    price: float
    source: str  # "clob", "gamma", "cached"

@dataclass
class AlertRecord:
    """Alert tracking record."""
    timestamp: float
    market_id: str
    alert_type: str  # "stale", "critical", "gap"
    message: str


class FeedDatabase:
    """SQLite database for persistent feed logging."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        """Create tables if they don't exist."""
        with sqlite3.connect(self.db_path) as conn:
            # Price updates table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS price_updates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    market_id TEXT NOT NULL,
                    question TEXT NOT NULL,
                    price REAL NOT NULL,
                    source TEXT NOT NULL,
                    created_at REAL DEFAULT (unixepoch())
                )
            """)

            # Index for fast queries
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_market_timestamp
                ON price_updates(market_id, timestamp DESC)
            """)

            # Alerts table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    market_id TEXT NOT NULL,
                    alert_type TEXT NOT NULL,
                    message TEXT NOT NULL,
                    created_at REAL DEFAULT (unixepoch())
                )
            """)

    def log_price_update(self, update: PriceUpdate):
        """Log a price update."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO price_updates
                (timestamp, market_id, question, price, source)
                VALUES (?, ?, ?, ?, ?)
            """, (update.timestamp, update.market_id, update.question,
                  update.price, update.source))

    def log_alert(self, alert: AlertRecord):
        """Log an alert."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO alerts
                (timestamp, market_id, alert_type, message)
                VALUES (?, ?, ?, ?)
            """, (alert.timestamp, alert.market_id,
                  alert.alert_type, alert.message))

    def get_recent_updates(self, hours: int = 24) -> List[PriceUpdate]:
        """Get price updates from last N hours."""
        since = time.time() - (hours * 3600)
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT timestamp, market_id, question, price, source
                FROM price_updates
                WHERE timestamp > ?
                ORDER BY timestamp DESC
            """, (since,))

            return [PriceUpdate(*row) for row in cursor.fetchall()]

    def get_price_gaps(self, market_id: str, hours: int = 24) -> List[Dict]:
        """Detect gaps in price data for a market."""
        since = time.time() - (hours * 3600)
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT timestamp FROM price_updates
                WHERE market_id = ? AND timestamp > ?
                ORDER BY timestamp
            """, (market_id, since))

            timestamps = [row[0] for row in cursor.fetchall()]

        gaps = []
        for i in range(1, len(timestamps)):
            gap_duration = timestamps[i] - timestamps[i-1]
            if gap_duration > GAP_THRESHOLD:
                gaps.append({
                    "start": timestamps[i-1],
                    "end": timestamps[i],
                    "duration_seconds": gap_duration,
                    "duration_minutes": gap_duration / 60
                })

        return gaps

    def get_recent_alerts(self, hours: int = 24) -> List[AlertRecord]:
        """Get recent alerts."""
        since = time.time() - (hours * 3600)
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT timestamp, market_id, alert_type, message
                FROM alerts
                WHERE timestamp > ?
                ORDER BY timestamp DESC
            """, (since,))

            return [AlertRecord(*row) for row in cursor.fetchall()]

    def cleanup_old_data(self, days: int = 30):
        """Clean up data older than N days."""
        cutoff = time.time() - (days * 24 * 3600)
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM price_updates WHERE timestamp < ?", (cutoff,))
            conn.execute("DELETE FROM alerts WHERE timestamp < ?", (cutoff,))
            conn.commit()


class AlertManager:
    """Manages alert generation with cooldown."""

    def __init__(self, db: FeedDatabase):
        self.db = db
        self.last_alerts = {}  # market_id -> {alert_type -> timestamp}

    def should_alert(self, market_id: str, alert_type: str) -> bool:
        """Check if we should send an alert (respecting cooldown)."""
        now = time.time()
        market_alerts = self.last_alerts.get(market_id, {})
        last_time = market_alerts.get(alert_type, 0)

        return (now - last_time) > ALERT_COOLDOWN

    def send_alert(self, market_id: str, alert_type: str, message: str):
        """Send an alert and record it."""
        if not self.should_alert(market_id, alert_type):
            return

        now = time.time()

        # Record alert
        alert = AlertRecord(
            timestamp=now,
            market_id=market_id,
            alert_type=alert_type,
            message=message
        )
        self.db.log_alert(alert)

        # Update cooldown tracking
        if market_id not in self.last_alerts:
            self.last_alerts[market_id] = {}
        self.last_alerts[market_id][alert_type] = now

        # Log to console
        logger.warning(f"ALERT [{alert_type.upper()}] {message}")


class FeedDashboard:
    """Main dashboard coordinating monitoring, logging, and alerting."""

    def __init__(self, config_path: Path):
        # Load market config
        with open(config_path) as f:
            self.market_config = json.load(f)

        # Initialize components
        self.db = FeedDatabase(DB_PATH)
        self.monitor = FeedMonitor(self.market_config)
        self.alert_mgr = AlertManager(self.db)
        self.running = False

    def check_feeds_once(self) -> Dict:
        """Perform single health check and log results."""
        logger.info("Performing feed health check...")

        updates_logged = 0
        alerts_sent = 0

        # Check each market
        for market_id in self.monitor.feeds:
            feed = self.monitor.feeds[market_id]

            # Attempt to fetch current price
            price = self.monitor.fetch_price_with_fallback(market_id)

            if price is not None:
                # Log successful price update
                update = PriceUpdate(
                    timestamp=feed.last_update,
                    market_id=market_id,
                    question=feed.question,
                    price=price,
                    source=feed.last_source
                )
                self.db.log_price_update(update)
                updates_logged += 1

            # Check for alerts
            if feed.is_critical:
                self.alert_mgr.send_alert(
                    market_id, "critical",
                    f"{feed.question} — CRITICAL: no update for {feed.age_seconds:.0f}s"
                )
                alerts_sent += 1
            elif feed.is_stale:
                self.alert_mgr.send_alert(
                    market_id, "stale",
                    f"{feed.question} — STALE: no update for {feed.age_seconds:.0f}s"
                )
                alerts_sent += 1

            # Check for gaps in recent data
            gaps = self.db.get_price_gaps(market_id, hours=1)  # Check last hour
            for gap in gaps:
                if gap["duration_minutes"] > 10:  # Alert on gaps > 10min
                    self.alert_mgr.send_alert(
                        market_id, "gap",
                        f"{feed.question} — GAP: {gap['duration_minutes']:.1f}min silence"
                    )
                    alerts_sent += 1

        # Generate health report
        health_report = self.monitor.get_health_report()
        health_report["updates_logged"] = updates_logged
        health_report["alerts_sent"] = alerts_sent

        logger.info(f"Check complete: {updates_logged} updates, {alerts_sent} alerts")
        return health_report

    def run_daemon(self):
        """Run as background daemon, checking feeds periodically."""
        logger.info(f"Starting feed dashboard daemon (check interval: {CHECK_INTERVAL}s)")
        self.running = True

        try:
            while self.running:
                try:
                    self.check_feeds_once()
                    time.sleep(CHECK_INTERVAL)
                except KeyboardInterrupt:
                    logger.info("Dashboard daemon stopped by user")
                    break
                except Exception as e:
                    logger.error(f"Dashboard daemon error: {e}")
                    time.sleep(10)  # Brief pause on errors
        finally:
            self.cleanup()

    def cleanup(self):
        """Clean up resources."""
        self.running = False
        self.monitor.close()
        # Clean up old data (keep last 30 days)
        self.db.cleanup_old_data(30)


class DashboardWebHandler(BaseHTTPRequestHandler):
    """HTTP handler for web dashboard interface."""

    def __init__(self, dashboard: FeedDashboard, *args, **kwargs):
        self.dashboard = dashboard
        super().__init__(*args, **kwargs)

    def do_GET(self):
        """Handle GET requests."""
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path == "/" or path == "/dashboard":
                self.serve_dashboard()
            elif path == "/api/health":
                self.serve_health_api()
            elif path == "/api/gaps":
                self.serve_gaps_api()
            elif path == "/api/alerts":
                self.serve_alerts_api()
            else:
                self.send_error(404)
        except Exception as e:
            logger.error(f"Web handler error: {e}")
            self.send_error(500)

    def serve_dashboard(self):
        """Serve main dashboard HTML."""
        html = """
<!DOCTYPE html>
<html>
<head>
    <title>LEVER Oracle Feed Dashboard</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: monospace; margin: 20px; background: #1a1a1a; color: #eee; }
        .header { border-bottom: 2px solid #333; padding-bottom: 10px; margin-bottom: 20px; }
        .status-ok { color: #0f0; }
        .status-stale { color: #fa0; }
        .status-critical { color: #f00; }
        .status-nodata { color: #888; }
        .feed-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(600px, 1fr)); gap: 20px; }
        .feed-card { border: 1px solid #333; padding: 15px; border-radius: 5px; background: #222; }
        .feed-header { font-weight: bold; margin-bottom: 10px; }
        .metric { margin: 5px 0; }
        .alerts { margin-top: 30px; }
        .alert { padding: 10px; margin: 5px 0; border-left: 4px solid #f00; background: #300; }
        .refresh { float: right; }
        button { background: #333; color: #eee; border: 1px solid #666; padding: 5px 10px; cursor: pointer; }
        button:hover { background: #444; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔮 LEVER Oracle Feed Dashboard</h1>
        <button class="refresh" onclick="location.reload()">Refresh</button>
        <div>Real-time monitoring of Polymarket → LEVER price feeds</div>
    </div>

    <div id="content">Loading...</div>

    <script>
        async function loadDashboard() {
            try {
                const health = await fetch('/api/health').then(r => r.json());
                const alerts = await fetch('/api/alerts').then(r => r.json());

                let html = `
                    <div class="summary">
                        <strong>Feed Summary:</strong>
                        <span class="status-ok">${health.healthy} healthy</span>,
                        <span class="status-stale">${health.stale} stale</span>,
                        <span class="status-critical">${health.critical} critical</span>,
                        <span class="status-nodata">${health.no_data} no data</span>
                    </div>

                    <div class="feed-grid">
                `;

                health.feeds.forEach(feed => {
                    const statusClass = `status-${feed.status.toLowerCase().replace('_', '')}`;
                    const ageDisplay = feed.age_seconds ? `${Math.round(feed.age_seconds)}s ago` : 'Never';
                    const priceDisplay = feed.price ? feed.price.toFixed(4) : 'N/A';

                    html += `
                        <div class="feed-card">
                            <div class="feed-header ${statusClass}">
                                [${feed.status}] ${feed.question}
                            </div>
                            <div class="metric">Price: <strong>${priceDisplay}</strong> (via ${feed.source})</div>
                            <div class="metric">Last Update: ${ageDisplay}</div>
                            <div class="metric">Updates: ${feed.total_updates} success, ${feed.total_failures} failed</div>
                            <div class="metric">Consecutive Failures: ${feed.consecutive_failures}</div>
                        </div>
                    `;
                });

                html += '</div>';

                // Add alerts section
                if (alerts.length > 0) {
                    html += '<div class="alerts"><h2>Recent Alerts (24h)</h2>';
                    alerts.slice(0, 10).forEach(alert => {
                        const time = new Date(alert.timestamp * 1000).toLocaleString();
                        html += `<div class="alert">[${alert.alert_type.toUpperCase()}] ${time}: ${alert.message}</div>`;
                    });
                    html += '</div>';
                }

                document.getElementById('content').innerHTML = html;

            } catch (e) {
                document.getElementById('content').innerHTML = `<div class="alert">Error loading dashboard: ${e}</div>`;
            }
        }

        loadDashboard();
        // Auto-refresh every 30 seconds
        setInterval(loadDashboard, 30000);
    </script>
</body>
</html>
        """

        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

    def serve_health_api(self):
        """Serve health status as JSON."""
        health = self.dashboard.check_feeds_once()

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(health, indent=2).encode())

    def serve_gaps_api(self):
        """Serve gap analysis as JSON."""
        # Get gaps for all markets in last 24h
        gaps_by_market = {}
        for market_id in self.dashboard.monitor.feeds:
            gaps = self.dashboard.db.get_price_gaps(market_id, hours=24)
            if gaps:
                gaps_by_market[market_id] = gaps

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(gaps_by_market, indent=2).encode())

    def serve_alerts_api(self):
        """Serve recent alerts as JSON."""
        alerts = self.dashboard.db.get_recent_alerts(hours=24)
        alert_dicts = [asdict(alert) for alert in alerts]

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(alert_dicts, indent=2).encode())


def run_web_server(dashboard: FeedDashboard, port: int = WEB_PORT):
    """Run web server for dashboard interface."""

    def handler(*args, **kwargs):
        DashboardWebHandler(dashboard, *args, **kwargs)

    httpd = HTTPServer(("", port), handler)
    logger.info(f"Feed dashboard web server starting on port {port}")
    logger.info(f"Access: http://localhost:{port}/dashboard")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Web server stopped")
        httpd.server_close()


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Oracle Feed Monitoring Dashboard")
    parser.add_argument("--daemon", action="store_true", help="Run as background daemon")
    parser.add_argument("--web", action="store_true", help="Start web server only")
    parser.add_argument("--check", action="store_true", help="One-time health check")
    parser.add_argument("--config", default=DEFAULT_CONFIG, help="Market config path")
    parser.add_argument("--port", type=int, default=WEB_PORT, help="Web server port")
    args = parser.parse_args()

    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Check config exists
    config_path = Path(args.config)
    if not config_path.exists():
        logger.error(f"Config not found: {config_path}")
        logger.error("Run: python scripts/oracle/onboard_markets.py first")
        sys.exit(1)

    # Initialize dashboard
    dashboard = FeedDashboard(config_path)

    try:
        if args.check:
            # One-time check
            report = dashboard.check_feeds_once()
            print(json.dumps(report, indent=2))

        elif args.web:
            # Web server only
            run_web_server(dashboard, args.port)

        elif args.daemon:
            # Daemon mode - run both monitoring and web server
            web_thread = threading.Thread(
                target=run_web_server,
                args=(dashboard, args.port),
                daemon=True
            )
            web_thread.start()

            # Run main monitoring loop
            dashboard.run_daemon()

        else:
            print("Usage: feed_dashboard.py [--daemon|--web|--check]")
            print("  --daemon  Run monitoring daemon + web server")
            print("  --web     Run web server only")
            print("  --check   One-time health check")

    finally:
        dashboard.cleanup()


if __name__ == "__main__":
    main()