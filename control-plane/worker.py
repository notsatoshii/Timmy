#!/usr/bin/env python3
"""
LEVER Protocol — Timmy Worker (Python)
Loops forever. Picks tasks. Self-heals on failure. systemd restarts on death.
"""

import subprocess, os, sys, time, re, json, signal
from datetime import datetime, timezone, timedelta
from pathlib import Path

# === Config ===
PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
WORKER_LOGS = f"{CONTROL}/worker-logs"
BUILD_PLAN = f"{CONTROL}/build-plan.md"
KNOWN_ISSUES = f"{CONTROL}/known-issues.md"
PERSONA_FILE = f"{CONTROL}/agent-persona.md"
CLAUDE_MD = f"{PROJECT}/CLAUDE.md"
LOCK_FILE = "/tmp/lever-worker.lock"
README_GEN = f"{CONTROL}/generate-readme.py"

TG_TOKEN = "8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk"
TG_CHAT = "422985839"

TASK_TIMEOUT = 2700       # 45 min max per Claude Code invocation
REST_BETWEEN_TASKS = 120  # 2 min rest between tasks (let system breathe)
REST_WHEN_IDLE = 1800     # 30 min rest when all tasks done before re-checking
MAX_CONSECUTIVE_FAILS = 3 # after 3 fails in a row, long rest

ICT = timezone(timedelta(hours=7))
FORGE_PATH = "/root/.foundry/bin"
ENV_PATH = f"{FORGE_PATH}:/usr/local/bin:/usr/bin:/bin:/home/lever/.local/bin"

# === Helpers ===

def now_ict():
    return datetime.now(ICT).strftime("%Y-%m-%d %H:%M:%S ICT")

def now_utc_file():
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")

def log(msg):
    print(f"[{now_ict()}] {msg}", flush=True)

def read_file(path):
    try:
        return Path(path).read_text(errors='replace')
    except:
        return ""

def tg(msg):
    """Send Telegram message. Truncate to 4000 chars."""
    try:
        msg = msg[:4000]
        subprocess.run([
            'curl', '-s', '-X', 'POST',
            f'https://api.telegram.org/bot{TG_TOKEN}/sendMessage',
            '-d', f'chat_id={TG_CHAT}',
            '-d', 'parse_mode=Markdown',
            '-d', f'text={msg}'
        ], capture_output=True, timeout=15)
    except:
        pass

def forge_build():
    """Returns (success, output)"""
    try:
        r = subprocess.run(
            ['forge', 'build'],
            capture_output=True, text=True, cwd=PROJECT, timeout=300,
            env={**os.environ, 'PATH': ENV_PATH}
        )
        ok = r.returncode == 0
        return ok, (r.stdout + r.stderr)[-500:]
    except Exception as e:
        return False, str(e)

# === Task Detection ===

def get_next_task():
    """Read build plan, return first unchecked task or None."""
    content = read_file(BUILD_PLAN)
    if not content:
        return None, None

    # P0 first, then P1, then unmarked
    for priority in [r'\*\*P0\*\*', r'\*\*P1\*\*', r'']:
        for line in content.split('\n'):
            pattern = r'^\s*-\s*\[\s*\]\s*' + priority
            if re.match(pattern, line.strip()):
                task = line.strip()
                # Clean up for display
                display = re.sub(r'^-\s*\[\s*\]\s*', '', task).strip()
                return task, display

    return None, None

def pick_model(task_description):
    """Route to Opus or Sonnet based on task content."""
    opus_patterns = [
        r'audit.*spec', r'spec.*audit', r'compare.*spec',
        r'fix.*bug', r'debug.*integration', r'reentrancy', r'vulnerability',
        r'integration.*fail', r'lifecycle.*fail',
        r'security', r'access.control', r'attack.*vector',
        r'token.*transfer.*gap', r'settlement.*wir', r'PnL.*transfer',
    ]
    desc = task_description.lower() if task_description else ""
    for p in opus_patterns:
        if re.search(p, desc, re.IGNORECASE):
            return "claude-opus-4-20250514", "opus"
    return "claude-sonnet-4-20250514", "sonnet"

# === Task Execution ===

def execute_task(task_raw, task_display):
    """Run one task via Claude Code. Returns (success, report_path)."""
    ts = now_utc_file()
    log_path = f"{WORKER_LOGS}/worker-{ts}.log"
    report_path = f"{WORKER_LOGS}/report-{ts}.md"

    model, model_short = pick_model(task_display)
    log(f"Task: {task_display[:80]}")
    log(f"Model: {model_short}")

    # Log model decision
    try:
        with open(f"{WORKER_LOGS}/model-decisions.log", "a") as f:
            f.write(f"[{now_ict()}] {model_short} | {task_display[:80]}\n")
    except: pass

    tg(f"🔧 *Worker: new task* ({model_short})\n`{task_display[:100]}`")

    # Build prompt
    plan = read_file(BUILD_PLAN)
    persona = read_file(PERSONA_FILE)
    issues = read_file(KNOWN_ISSUES)
    spec = read_file(CLAUDE_MD)

    # Pre-check compile
    compile_ok, compile_out = forge_build()

    prompt = f"""{persona}

---

You are the proactive worker. Execute ONE task, then stop.

### Current Task
{task_display}

### Build Plan
{plan}

### Known Issues
{issues}

### Compile Status
{"CLEAN" if compile_ok else "BROKEN: " + compile_out}

### Project Spec (CLAUDE.md)
{spec}

## INSTRUCTIONS
1. If codebase does not compile, fix that FIRST — ignore the task until it compiles.
2. Execute the task described above. Follow the QA gate from your persona.
3. After completing, update build-plan.md: change the task from [ ] to [x], add date and brief result.
4. Add a completion log entry at the bottom of build-plan.md.
5. If you find new issues, add them to known-issues.md with severity.
6. Commit all changes with a clear descriptive message.
7. Push to origin main.
8. Write a shift report to: {report_path}

Shift report format:
# Shift Report — [timestamp]
## Task: [what you worked on]
## Result: [what happened — be specific]
## QA Gate: Compile PASS/FAIL | Tests X passed Y failed | Spec match | Regressions
## Issues Found: [new issues or None]
## Next Priority: [what the next task should be]
## Build Health: [1 sentence]

Stay in character. Be efficient. Do ONE task well.
"""

    # Run Claude Code
    try:
        with open(log_path, 'w') as logfile:
            proc = subprocess.Popen(
                ['claude', '--dangerously-skip-permissions', '--model', model, '-p', prompt],
                stdout=logfile, stderr=subprocess.STDOUT,
                cwd=PROJECT,
                env={**os.environ, 'PATH': ENV_PATH}
            )
            proc.wait(timeout=TASK_TIMEOUT)
            exit_code = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        log(f"TIMEOUT after {TASK_TIMEOUT}s")
        tg(f"⚠️ *Worker timed out* on: `{task_display[:60]}`")
        return False, report_path
    except Exception as e:
        log(f"CRASH: {e}")
        tg(f"❌ *Worker crashed*: {str(e)[:200]}")
        return False, report_path

    if exit_code != 0:
        log(f"Claude Code exited with code {exit_code}")

    # Post-task verification
    compile_ok, _ = forge_build()
    if not compile_ok:
        tg(f"🔴 *Codebase broken after task!* `{task_display[:60]}`")
        log("POST-TASK: compile FAILED")
        return False, report_path

    # Send report if it exists
    if os.path.exists(report_path):
        report_content = read_file(report_path)[:3500]
        tg(f"📋 *Shift Report* ({model_short})\n\n{report_content}")
    else:
        # No report written — send basic summary
        recent = subprocess.run(
            ['git', 'log', '--oneline', '-3'],
            capture_output=True, text=True, cwd=PROJECT
        ).stdout.strip()
        tg(f"📋 *Task done* ({model_short}) | Compile: {'PASS' if compile_ok else 'FAIL'}\n`{recent}`")

    log(f"Task complete. Compile: {'PASS' if compile_ok else 'FAIL'}")
    return True, report_path

# === Main Loop ===

def acquire_lock():
    if os.path.exists(LOCK_FILE):
        age = time.time() - os.path.getmtime(LOCK_FILE)
        if age < 3600:
            return False  # someone else is running
        os.remove(LOCK_FILE)  # stale lock
    Path(LOCK_FILE).write_text(str(os.getpid()))
    return True

def release_lock():
    try: os.remove(LOCK_FILE)
    except: pass

def run_readme_gen():
    """Regenerate README after tasks complete."""
    if os.path.exists(README_GEN):
        try:
            subprocess.run(['python3', README_GEN], timeout=30, cwd=PROJECT)
            subprocess.run(
                ['git', 'add', 'README.md', 'CONTRIBUTING.md'],
                cwd=PROJECT, timeout=10
            )
            log("README regenerated")
        except:
            pass

def main():
    log("Timmy Worker starting")
    tg("🤖 *Timmy Worker started* — continuous mode")

    os.makedirs(WORKER_LOGS, exist_ok=True)

    consecutive_fails = 0
    tasks_completed = 0

    # Handle graceful shutdown
    running = True
    def shutdown(sig, frame):
        nonlocal running
        log(f"Received signal {sig}, shutting down gracefully")
        running = False
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while running:
        # Acquire lock
        if not acquire_lock():
            log("Another worker is running. Waiting 60s...")
            time.sleep(60)
            continue

        try:
            # Find next task
            task_raw, task_display = get_next_task()

            if task_raw is None:
                # All done — run self-audit or rest
                release_lock()
                if tasks_completed > 0:
                    run_readme_gen()
                    tg(f"✅ *All tasks complete!* ({tasks_completed} this session)\nResting {REST_WHEN_IDLE // 60} min before re-checking.")
                    tasks_completed = 0
                log(f"No tasks. Resting {REST_WHEN_IDLE // 60} min...")
                time.sleep(REST_WHEN_IDLE)
                continue

            # Execute
            success, report = execute_task(task_raw, task_display)

            if success:
                consecutive_fails = 0
                tasks_completed += 1
                log(f"Task #{tasks_completed} done. Resting {REST_BETWEEN_TASKS}s...")
                release_lock()
                time.sleep(REST_BETWEEN_TASKS)
            else:
                consecutive_fails += 1
                release_lock()

                if consecutive_fails >= MAX_CONSECUTIVE_FAILS:
                    rest = 900  # 15 min after 3 fails
                    log(f"{consecutive_fails} consecutive failures. Resting {rest // 60} min...")
                    tg(f"⚠️ *{consecutive_fails} consecutive failures.* Resting 15 min.")
                    time.sleep(rest)
                    consecutive_fails = 0
                else:
                    log(f"Fail #{consecutive_fails}. Resting {REST_BETWEEN_TASKS}s before retry...")
                    time.sleep(REST_BETWEEN_TASKS)

        except Exception as e:
            log(f"Unhandled error: {e}")
            tg(f"❌ *Worker error*: `{str(e)[:300]}`")
            release_lock()
            time.sleep(REST_BETWEEN_TASKS)

    # Graceful shutdown
    release_lock()
    log("Worker stopped")
    tg("🛑 *Timmy Worker stopped*")

if __name__ == '__main__':
    main()
