# Oracle Feed Monitoring Dashboard

Comprehensive monitoring solution for LEVER Protocol's oracle price feeds.

## Features

- **Persistent Logging**: SQLite database stores all price updates with timestamps
- **Gap Detection**: Identifies periods with no price updates (>5min gaps flagged)
- **Stale Feed Alerts**: Multi-tier alerting (stale @ 2min, critical @ 5min)
- **Web Dashboard**: Real-time web interface on port 8081
- **Fallback Monitoring**: Tracks which source provided each price (CLOB/Gamma/cached)

## Usage

```bash
# One-time health check
python3 scripts/oracle/feed_dashboard.py --check

# Run monitoring daemon + web server
python3 scripts/oracle/feed_dashboard.py --daemon

# Web server only (useful if you have monitoring elsewhere)
python3 scripts/oracle/feed_dashboard.py --web

# Custom port
python3 scripts/oracle/feed_dashboard.py --daemon --port 8082
```

## Web Interface

Access the web dashboard at: `http://localhost:8081/dashboard`

**API Endpoints:**
- `/api/health` - Current feed health status (JSON)
- `/api/gaps` - Price data gaps by market (JSON)
- `/api/alerts` - Recent alerts (JSON)

## Database

**Location**: `scripts/oracle/feed_logs.db` (SQLite)

**Tables**:
- `price_updates`: All price updates with source tracking
- `alerts`: Alert history with cooldown management

**Retention**: 30 days (auto-cleanup)

## Alert Types

- **STALE**: No price update for >2 minutes
- **CRITICAL**: No price update for >5 minutes
- **GAP**: Detected gap in price data >10 minutes

**Cooldown**: 1 hour between repeat alerts for same market/type

## Integration

Works with existing oracle infrastructure:
- Uses `feed_monitor.py` for health checking
- Reads from `market_config.json`
- Compatible with keeper bot operation

## Production Setup

For production deployment, consider:

1. **Systemd Service** (see example below)
2. **Log Rotation** (dashboard logs to stdout/stderr)
3. **Monitoring** the monitor (external health check of dashboard process)
4. **Disk Space** (SQLite grows over time, 30-day retention helps)

### Example Systemd Service

```ini
[Unit]
Description=LEVER Oracle Feed Dashboard
After=network.target

[Service]
Type=simple
User=lever
WorkingDirectory=/home/lever/lever-protocol
ExecStart=/usr/bin/python3 scripts/oracle/feed_dashboard.py --daemon
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## Dependencies

- Python 3.12+
- sqlite3 (built into Python)
- Existing oracle infrastructure (feed_monitor.py, polymarket_client.py)

## Monitoring Philosophy

This dashboard implements **defense in depth** for oracle reliability:

1. **Primary**: Polymarket CLOB midpoint prices (most accurate)
2. **Fallback**: Gamma API embedded prices (secondary source)
3. **Emergency**: Last known cached price (prevents total failure)
4. **Detection**: Gap analysis and staleness alerts
5. **Persistence**: Historical data for post-incident analysis

The goal is **zero oracle downtime** even when individual data sources fail.