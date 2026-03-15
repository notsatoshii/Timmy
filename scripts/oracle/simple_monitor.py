#!/usr/bin/env python3
"""
Simple 48-hour testnet monitoring system
Monitors oracle feeds, discovery system, and basic health metrics
"""

import sqlite3
import time
import json
import datetime
from pathlib import Path

def check_database_health():
    """Check database tables and recent activity"""
    results = {}

    # Feed logs database
    try:
        conn = sqlite3.connect('feed_logs.db')
        cursor = conn.cursor()

        cursor.execute('SELECT COUNT(*) FROM price_updates')
        price_count = cursor.fetchone()[0]

        cursor.execute('SELECT COUNT(*) FROM alerts')
        alert_count = cursor.fetchone()[0]

        cursor.execute('SELECT MAX(timestamp) FROM price_updates')
        last_price = cursor.fetchone()[0]

        results['feed_db'] = {
            'price_updates': price_count,
            'alerts': alert_count,
            'last_price_update': last_price
        }
        conn.close()
    except Exception as e:
        results['feed_db'] = {'error': str(e)}

    # Discovery database
    try:
        conn = sqlite3.connect('discovery.db')
        cursor = conn.cursor()

        cursor.execute('SELECT COUNT(*) FROM discovered_markets')
        market_count = cursor.fetchone()[0]

        cursor.execute('SELECT COUNT(*) FROM discovered_markets WHERE onboarding_score >= 65')
        high_score_count = cursor.fetchone()[0]

        cursor.execute('SELECT MAX(last_updated) FROM discovered_markets')
        last_discovery = cursor.fetchone()[0]

        results['discovery_db'] = {
            'total_markets': market_count,
            'high_score_markets': high_score_count,
            'last_discovery_update': last_discovery
        }
        conn.close()
    except Exception as e:
        results['discovery_db'] = {'error': str(e)}

    return results

def check_file_health():
    """Check configuration and data files"""
    files_to_check = [
        'market_config.json',
        'demo_markets.json',
        'candidates.json',
        'validation_report.json'
    ]

    results = {}
    for file in files_to_check:
        path = Path(file)
        if path.exists():
            results[file] = {
                'exists': True,
                'size': path.stat().st_size,
                'modified': path.stat().st_mtime
            }
        else:
            results[file] = {'exists': False}

    return results

def generate_health_report():
    """Generate comprehensive health report"""
    timestamp = datetime.datetime.now()

    report = {
        'timestamp': timestamp.isoformat(),
        'monitoring_start': '2026-03-15T15:10:00Z',
        'database_health': check_database_health(),
        'file_health': check_file_health(),
        'uptime_hours': (timestamp - datetime.datetime(2026, 3, 15, 15, 10)).total_seconds() / 3600
    }

    return report

def main():
    """Main monitoring loop"""
    print("Starting 48-hour testnet monitoring...")
    print(f"Monitor started at: {datetime.datetime.now()}")
    print("=" * 60)

    monitor_start = time.time()

    while True:
        try:
            report = generate_health_report()

            print(f"\n[{report['timestamp']}] Health Check")
            print(f"Uptime: {report['uptime_hours']:.2f} hours")

            # Database status
            feed_db = report['database_health'].get('feed_db', {})
            if 'error' not in feed_db:
                print(f"Feed DB: {feed_db['price_updates']} price updates, {feed_db['alerts']} alerts")
                if feed_db['last_price_update']:
                    last_update = datetime.datetime.fromtimestamp(feed_db['last_price_update'])
                    age = (datetime.datetime.now() - last_update).total_seconds() / 60
                    print(f"Last price update: {age:.1f} minutes ago")
            else:
                print(f"Feed DB ERROR: {feed_db['error']}")

            discovery_db = report['database_health'].get('discovery_db', {})
            if 'error' not in discovery_db:
                print(f"Discovery: {discovery_db['total_markets']} markets ({discovery_db['high_score_markets']} high-scoring)")
            else:
                print(f"Discovery DB ERROR: {discovery_db['error']}")

            # File status
            config_status = report['file_health'].get('market_config.json', {})
            print(f"Market config: {'✓' if config_status.get('exists') else '✗'}")

            # Save report
            with open(f"health_report_{int(time.time())}.json", 'w') as f:
                json.dump(report, f, indent=2)

            # Check if 48 hours elapsed
            if report['uptime_hours'] >= 48:
                print("\n🎉 48-hour monitoring period completed!")
                break

        except KeyboardInterrupt:
            print("\nMonitoring stopped by user")
            break
        except Exception as e:
            print(f"Monitor error: {e}")

        # Sleep for 30 minutes
        time.sleep(1800)

    print(f"Final monitoring report generated at {datetime.datetime.now()}")

if __name__ == "__main__":
    main()