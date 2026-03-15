#!/usr/bin/env python3
"""
LEVER Protocol — Nightly Maintenance Cycle
Gathers state, feeds to Claude Code for fixes, reports via Telegram.
Runs daily via cron or manually.
"""

import subprocess, os, time
from datetime import datetime, timezone, timedelta
from pathlib import Path

PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
LOG_DIR = f"{CONTROL}/nightly-logs"
ISSUES_FILE = f"{CONTROL}/known-issues.md"
PERSONA_FILE = f"{CONTROL}/agent-persona.md"
README_GEN = f"{CONTROL}/generate-readme.py"
TG_TOKEN = "8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk"
TG_CHAT = "422985839"
ENV_PATH = "/root/.foundry/bin:/usr/local/bin:/usr/bin:/bin:/home/lever/.local/bin"
ICT = timezone(timedelta(hours=7))
TIMEOUT = 3600

def now_ict():
    return datetime.now(ICT).strftime("%Y-%m-%d %H:%M:%S ICT")

def now_file():
    return datetime.now(timezone.utc).strftime("%Y%m%d")

def read(path):
    try: return Path(path).read_text(errors='replace')
    except: return ""

def run(cmd, cwd=PROJECT, timeout=60):
    try: return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, timeout=timeout).stdout.strip()
    except: return ""

def tg(msg):
    try:
        subprocess.run(['curl', '-s', '-X', 'POST',
            f'https://api.telegram.org/bot{TG_TOKEN}/sendMessage',
            '-d', f'chat_id={TG_CHAT}', '-d', 'parse_mode=Markdown',
            '-d', f'text={msg[:4000]}'], capture_output=True, timeout=15)
    except: pass

def main():
    os.makedirs(LOG_DIR, exist_ok=True)
    ts = now_file()
    log_path = f"{LOG_DIR}/cycle-{ts}-{datetime.now(timezone.utc).strftime('%H%M%S')}.log"
    summary_path = f"{LOG_DIR}/summary-{ts}.md"

    print(f"[{now_ict()}] Nightly cycle starting")
    tg(f"🌙 *Nightly cycle started* — {now_ict()}")

    # Gather state
    git_status = run(['git', 'status', '--short'])
    git_log = run(['git', 'log', '--oneline', '-10'])
    uncommitted = run(['git', 'diff', '--name-only'])
    compile_out = run(['forge', 'build', '--sizes'], timeout=300)
    test_out = run(['forge', 'test', '--summary'], timeout=1200)
    issues = read(ISSUES_FILE)
    persona = read(PERSONA_FILE)

    prompt = f"""{persona}

---

You are the nightly maintenance agent. Stay in character.

## STATE
### Git Status
{git_status or 'Clean'}

### Recent Commits
{git_log}

### Uncommitted Changes
{uncommitted or 'None'}

### Compile Result
{compile_out[-2000:]}

### Test Results
{test_out[-2000:]}

### Known Issues
{issues}

## PRIORITIES
1. Fix any compile errors
2. Fix any failing tests
3. Address CRITICAL/HIGH severity items from known-issues.md
4. Address MEDIUM severity items if time permits
5. Run full test suite and record results
6. Write summary to: {summary_path}
7. Commit and push all changes to origin main

Stay efficient. Fix what you can. Document what you cannot.
"""

    # Run Claude Code
    try:
        with open(log_path, 'w') as logfile:
            proc = subprocess.Popen(
                ['claude', '--dangerously-skip-permissions', '--model', 'claude-sonnet-4-20250514', '-p', prompt],
                stdout=logfile, stderr=subprocess.STDOUT,
                cwd=PROJECT, env={**os.environ, 'PATH': ENV_PATH}
            )
            proc.wait(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.kill()
        tg("⚠️ *Nightly cycle timed out*")
    except Exception as e:
        tg(f"❌ *Nightly cycle crashed*: {str(e)[:300]}")

    # Post-run compile check
    compile_ok = "PASS" if run(['forge', 'build'], timeout=300) else "UNKNOWN"

    # Regenerate README
    if os.path.exists(README_GEN):
        try:
            subprocess.run(['python3', README_GEN], timeout=30, cwd=PROJECT)
            run(['git', 'add', 'README.md', 'CONTRIBUTING.md'])
        except: pass

    # Read summary
    summary = read(summary_path)[:3500] if os.path.exists(summary_path) else "No summary generated."

    tg(f"🌅 *Nightly Done* | Compile: {compile_ok}\n\n{summary}")
    print(f"[{now_ict()}] Nightly cycle complete")

if __name__ == '__main__':
    main()
