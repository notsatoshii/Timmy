#!/usr/bin/env python3
"""
LEVER Watchdog - keeps services alive, cleans stale locks, monitors resources.
Runs every 60 seconds.
"""

import subprocess, time, os, glob, psutil
from datetime import datetime
from pathlib import Path

BASE = Path("/home/lever/lever-protocol")
CP = BASE / "control-plane"
LOCKS = CP / "locks"
LOGS = CP / "dispatcher-logs"
LOG_FILE = LOGS / "watchdog.log"

SERVICES = {
    "lever-frontend": {"port": 3000, "critical": True},
    "lever-dashboard": {"port": 8080, "critical": True},
    "lever-loop": {"port": None, "critical": True},
}

TG_TOKEN_FILE = BASE / ".telegram-token"
TG_CHAT_ID = "422985839"

restart_counts = {}  # track restarts per service per 5min window

def log(msg, level="INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    line = f"[{ts}] [{level}] {msg}"
    print(line, flush=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def tg(msg):
    try:
        if TG_TOKEN_FILE.exists():
            token = TG_TOKEN_FILE.read_text().strip()
            subprocess.run(["curl","-s","-X","POST",
                f"https://api.telegram.org/bot{token}/sendMessage",
                "-d",f"chat_id={TG_CHAT_ID}","-d",f"text=Watchdog: {msg}"],
                capture_output=True, timeout=10)
    except: pass

def check_service(name):
    r = subprocess.run(["systemctl","is-active",name], capture_output=True, text=True)
    return r.stdout.strip() == "active"

def restart_service(name):
    key = name
    now = time.time()
    # Track restarts
    if key not in restart_counts:
        restart_counts[key] = []
    restart_counts[key] = [t for t in restart_counts[key] if now - t < 300]  # last 5min
    
    if len(restart_counts[key]) >= 3:
        log(f"CRASH LOOP: {name} restarted 3+ times in 5min", "ERROR")
        tg(f"CRASH LOOP: {name}")
        return False
    
    log(f"Restarting {name}...")
    subprocess.run(["systemctl","restart",name], capture_output=True)
    restart_counts[key].append(now)
    time.sleep(3)
    
    if check_service(name):
        log(f"{name} restarted OK")
        return True
    else:
        log(f"{name} failed to restart", "ERROR")
        return False

def check_port(port):
    try:
        r = subprocess.run(
            ["curl","-s","-o","/dev/null","-w","%{http_code}",f"http://localhost:{port}"],
            capture_output=True, text=True, timeout=5
        )
        return r.stdout.strip() in ["200","304"]
    except:
        return False

def clean_stale_locks():
    """Remove running-* locks where no claude process exists."""
    running = glob.glob(str(LOCKS / "running-*"))
    if not running:
        return
    
    # Check if any claude processes are alive
    claude_procs = subprocess.run(
        ["pgrep","-f","claude.*--dangerously"], capture_output=True, text=True
    ).stdout.strip()
    
    if not claude_procs and running:
        for f in running:
            age = time.time() - os.path.getmtime(f)
            if age > 120:  # stale for 2+ minutes with no claude process
                task = os.path.basename(f).replace("running-","")
                log(f"Cleaning stale lock: {task} (age: {int(age)}s, no claude process)")
                os.remove(f)

def check_resources():
    disk = psutil.disk_usage("/")
    mem = psutil.virtual_memory()
    
    if disk.percent > 90:
        log(f"DISK WARNING: {disk.percent}% used", "WARN")
        tg(f"Disk {disk.percent}%")
    
    if mem.percent > 90:
        log(f"MEMORY WARNING: {mem.percent}% used", "WARN")
        tg(f"Memory {mem.percent}%")

def run_check():
    for name, cfg in SERVICES.items():
        if not check_service(name):
            log(f"{name} is DOWN")
            if cfg["critical"]:
                restart_service(name)
        elif cfg.get("port"):
            if not check_port(cfg["port"]):
                log(f"{name} port {cfg['port']} not responding")
                restart_service(name)
    
    clean_stale_locks()
    check_resources()

def main():
    log("Watchdog starting")
    while True:
        try:
            run_check()
        except Exception as e:
            log(f"Check error: {e}", "ERROR")
        time.sleep(60)

if __name__ == "__main__":
    main()
