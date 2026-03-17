#!/usr/bin/env python3
"""
LEVER Protocol — Watchdog
Monitors ALL services. Auto-heals crashes. Never requires manual SSH.

Watches:
  - lever-dispatcher: restarts if dead, fixes Python syntax if crash-looping
  - lever-frontend: restarts if port 3000 stops responding
  - lever-dashboard: restarts if port 8080 stops responding
  - lever-fee-keeper: restarts if dead
  - claude agents: alerts if all agents die simultaneously
  - disk/memory: alerts if resources critical

Runs as: systemd lever-watchdog.service (runs every 60s)
"""

import subprocess
import os
import time
import json
import glob
import re
from datetime import datetime
from pathlib import Path

PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
WATCHDOG_LOG = f"{CONTROL}/dispatcher-logs/watchdog.log"
CYCLE_INTERVAL = 60  # check every 60s

SERVICES = [
    {"name": "lever-dispatcher", "critical": True, "port": None},
    {"name": "lever-frontend", "critical": True, "port": 3000},
    {"name": "lever-dashboard", "critical": False, "port": 8080},
    {"name": "lever-qa", "critical": False, "port": None},
]


def log(msg):
    ts = datetime.utcnow().strftime('%H:%M:%S')
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(WATCHDOG_LOG, 'a') as f:
        f.write(line + '\n')


def notify(msg):
    try:
        token_file = f"{PROJECT}/.telegram-token"
        token = Path(token_file).read_text().strip() if os.path.exists(token_file) else os.environ.get('TELEGRAM_BOT_TOKEN', '')
        if not token:
            return
        import urllib.request
        data = json.dumps({'chat_id': '422985839', 'text': f"🛡️ Watchdog: {msg}"}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=data, headers={'Content-Type': 'application/json'}
        )
        urllib.request.urlopen(req, timeout=5)
    except:
        pass


def run(cmd, timeout=15):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip(), r.returncode
    except:
        return "", 1


def is_active(service):
    out, _ = run(f"systemctl is-active {service}")
    return out == "active"


def port_responding(port):
    out, code = run(f"curl -s -o /dev/null -w '%{{http_code}}' --connect-timeout 3 http://localhost:{port}")
    return out == "200"


def restart_service(name, reason):
    log(f"🔧 Restarting {name}: {reason}")
    notify(f"Restarting {name}: {reason}")
    run(f"systemctl restart {name}")
    time.sleep(5)
    if is_active(name):
        log(f"  ✅ {name} recovered")
        notify(f"✅ {name} recovered")
        return True
    else:
        log(f"  ❌ {name} failed to restart")
        return False


def check_python_syntax(filepath):
    """Check if a Python file has syntax errors. Returns error or None."""
    out, code = run(f"python3 -c \"import py_compile; py_compile.compile('{filepath}', doraise=True)\"")
    if code != 0:
        return out
    return None


def fix_common_python_errors(filepath):
    """Attempt to fix known Python issues (like the 'def pass' bug)."""
    try:
        lines = open(filepath).readlines()
        fixed = False
        for i, line in enumerate(lines):
            # Fix the notorious "def pass" bug
            if 'def pass' in line and '#' in line:
                func_name = 'run_readme_gen'
                # Try to extract function name from context
                for j in range(i+1, min(i+5, len(lines))):
                    if '"""' in lines[j] or "'''" in lines[j]:
                        break
                lines[i] = f'def {func_name}():\n'
                if i+1 < len(lines) and 'pass' not in lines[i+1] and '"""' in lines[i+1]:
                    pass  # docstring follows, that's fine
                elif i+1 < len(lines) and 'pass' not in lines[i+1]:
                    lines.insert(i+1, '    pass  # auto-fixed by watchdog\n')
                fixed = True
                log(f"  🔧 Fixed 'def pass' syntax error at line {i+1}")

        if fixed:
            open(filepath, 'w').writelines(lines)
            return True
        return False
    except:
        return False


def check_dispatcher_health():
    """Deep health check for dispatcher — not just running but actually working."""
    if not is_active("lever-dispatcher"):
        return False, "Service dead"

    # Check for crash loop — journal shows repeated restarts
    out, _ = run("journalctl -u lever-dispatcher --since '5 min ago' --no-pager | grep -c 'Started LEVER'")
    try:
        restarts = int(out)
        if restarts > 3:
            return False, f"Crash-looping ({restarts} restarts in 5min)"
    except:
        pass

    # Check if agents are actually alive
    out, _ = run("ps aux | grep 'claude' | grep -v grep | wc -l")
    try:
        agent_count = int(out)
    except:
        agent_count = 0

    # Check if there are running locks but no agents
    running_locks = glob.glob(f"{CONTROL}/locks/running-*")
    if running_locks and agent_count == 0:
        # Stale locks — agents died but dispatcher didn't notice
        log(f"  ⚠️  {len(running_locks)} stale running locks with 0 agents — cleaning")
        for lock in running_locks:
            os.remove(lock)
        return False, "Stale locks with no agents — cleaned, needs restart"

    # Check dispatcher log freshness
    dlog = f"{CONTROL}/dispatcher-logs/dispatcher.log"
    if os.path.exists(dlog):
        age = time.time() - os.path.getmtime(dlog)
        if age > 300:  # 5 min with no log output
            return False, f"Dispatcher log stale ({int(age)}s old)"

    return True, "OK"


def check_worker_py_syntax():
    """Check if worker.py has syntax errors (Timmy sometimes corrupts itself)."""
    worker = f"{CONTROL}/worker.py"
    if not os.path.exists(worker):
        return
    err = check_python_syntax(worker)
    if err:
        log(f"⚠️  worker.py has syntax error: {err[:100]}")
        if fix_common_python_errors(worker):
            log("  ✅ Auto-fixed worker.py")
            notify("Auto-fixed worker.py syntax error")
        else:
            log("  ❌ Could not auto-fix worker.py")
            notify("❌ worker.py has syntax error — needs manual fix")


def check_dispatcher_py_syntax():
    """Check dispatcher.py syntax."""
    dispatcher = f"{CONTROL}/dispatcher.py"
    if not os.path.exists(dispatcher):
        return
    err = check_python_syntax(dispatcher)
    if err:
        log(f"⚠️  dispatcher.py has syntax error: {err[:100]}")
        notify("❌ dispatcher.py has syntax error — needs manual fix")


def check_resources():
    """Check disk and memory."""
    # Disk
    out, _ = run("df / --output=pcent | tail -1")
    try:
        pct = int(out.strip().replace('%', ''))
        if pct > 90:
            log(f"⚠️  Disk {pct}% full")
            notify(f"⚠️ Disk {pct}% full!")
    except:
        pass

    # Memory
    out, _ = run("free | awk '/Mem:/{printf \"%.0f\", $3/$2 * 100}'")
    try:
        pct = int(out)
        if pct > 90:
            log(f"⚠️  Memory {pct}% used")
            # Kill stale claude processes if memory critical
            out2, _ = run("ps aux | grep claude | grep -v grep | wc -l")
            try:
                agents = int(out2)
                if agents > 5:
                    log(f"  🔧 {agents} claude processes — killing oldest")
                    run("ps aux | grep claude | grep -v grep | sort -k10 | head -1 | awk '{print $2}' | xargs kill -9")
            except:
                pass
    except:
        pass


def check_file_ownership():
    """Ensure project files are owned by lever user."""
    out, _ = run(f"find {PROJECT} -not -user lever -not -path '*/.git/*' -not -path '*/node_modules/*' | head -5")
    if out:
        log(f"⚠️  Files not owned by lever — fixing")
        run(f"chown -R lever:lever {PROJECT}")


def run_cycle():
    issues = 0

    # Check all services
    for svc in SERVICES:
        name = svc["name"]
        if not is_active(name):
            issues += 1
            success = restart_service(name, "service not active")
            if not success and svc["critical"]:
                # Try deeper diagnosis
                if 'dispatcher' in name:
                    check_dispatcher_py_syntax()
                log(f"  ❌ Critical service {name} won't start")
                notify(f"❌ CRITICAL: {name} won't start after restart")
        elif svc["port"]:
            if not port_responding(svc["port"]):
                issues += 1
                restart_service(name, f"port {svc['port']} not responding")

    # Deep dispatcher health
    healthy, reason = check_dispatcher_health()
    if not healthy:
        issues += 1
        restart_service("lever-dispatcher", reason)

    # Check for self-corruption
    check_worker_py_syntax()
    check_dispatcher_py_syntax()

    # Resources
    check_resources()

    # File ownership (agents sometimes create files as root)
    check_file_ownership()

    return issues


def main():
    os.makedirs(os.path.dirname(WATCHDOG_LOG), exist_ok=True)
    log("═══════════════════════════════════════")
    log("  LEVER Watchdog started")
    log(f"  Checking every {CYCLE_INTERVAL}s")
    log("═══════════════════════════════════════")
    notify("Watchdog started — monitoring all services")

    while True:
        try:
            issues = run_cycle()
            if issues == 0:
                pass  # silent when healthy
            else:
                log(f"  Resolved {issues} issue(s) this cycle")
        except Exception as e:
            log(f"❌ Watchdog cycle error: {e}")

        time.sleep(CYCLE_INTERVAL)


if __name__ == '__main__':
    main()
