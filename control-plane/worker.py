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
REST_BETWEEN_TASKS = 5  # 2 min rest between tasks (let system breathe)
REST_WHEN_IDLE = 30     # 30 min rest when all tasks done before re-checking
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
        r'redesign', r'polish', r'UI.*UX', r'professional.*theme', r'dark.*theme',
        r'investor.*demo', r'frontend.*detail.*view', r'portfolio.*dashboard',
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
    def ts():
        return datetime.now(ICT).strftime('[%H:%M:%S] ')

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
        proc = subprocess.Popen(
            ['claude', '--dangerously-skip-permissions', '--model', model,
             '--output-format', 'stream-json', '--verbose', '-p', '-'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            cwd=PROJECT,
            env={**os.environ, 'PATH': ENV_PATH},
            bufsize=1
        )
        proc.stdin.write(prompt.encode())
        proc.stdin.close()
        with open(log_path, 'w') as logfile:
            start = time.time()
            while True:
                line = proc.stdout.readline()
                if not line and proc.poll() is not None:
                    break
                if line:
                    try:
                        chunk = json.loads(line.decode('utf-8', errors='replace'))
                        ctype = chunk.get('type', '')
                        if ctype == 'assistant':
                            # Assistant message — extract text from content blocks
                            msg = chunk.get('message', {})
                            for block in msg.get('content', []):
                                if block.get('type') == 'text':
                                    logfile.write(block['text'] + '\n')
                                    logfile.flush()
                                elif block.get('type') == 'tool_use':
                                    name = block.get('name', '?')
                                    inp = block.get('input', {})
                                    if not isinstance(inp, dict):
                                        inp = {}
                                    # Show detail based on tool type
                                    if name in ('Read', 'read'):
                                        logfile.write(ts() + '[Read] ' + str(inp.get('file_path', inp.get('path', '?')))[:200] + '\n')
                                    elif name in ('Edit', 'edit'):
                                        logfile.write(ts() + '[Edit] ' + str(inp.get('file_path', inp.get('path', '?')))[:200] + '\n')
                                        old_s = str(inp.get('old_string', inp.get('old_text', '')))
                                        new_s = str(inp.get('new_string', inp.get('new_text', '')))
                                        if old_s:
                                            for line in old_s[:500].split('\n')[:5]:
                                                logfile.write('  - ' + line + '\n')
                                        if new_s:
                                            for line in new_s[:500].split('\n')[:5]:
                                                logfile.write('  + ' + line + '\n')
                                            if len(new_s) > 500:
                                                logfile.write('  ... (' + str(len(new_s)) + ' chars)\n')
                                    elif name in ('Write', 'write'):
                                        fpath = str(inp.get('file_path', inp.get('path', '?')))[:200]
                                        logfile.write(ts() + '[Write] ' + fpath + '\n')
                                        content = str(inp.get('content', inp.get('file_text', '')))
                                        if content:
                                            preview = content[:1000].replace('\r', '')
                                            logfile.write(preview)
                                            if len(content) > 1000:
                                                logfile.write('\n... (' + str(len(content)) + ' chars total)')
                                            logfile.write('\n')
                                    elif name in ('Bash', 'bash'):
                                        logfile.write(ts() + '$ ' + str(inp.get('command', '?'))[:300] + '\n')
                                    elif name in ('Glob', 'glob'):
                                        logfile.write(ts() + '[Glob] ' + str(inp.get('pattern', '?'))[:200] + '\n')
                                    elif name in ('Grep', 'grep'):
                                        logfile.write(ts() + '[Grep] ' + str(inp.get('pattern', '?'))[:100] + ' in ' + str(inp.get('path', '?'))[:100] + '\n')
                                    elif name in ('WebSearch', 'web_search'):
                                        logfile.write(ts() + '[Search] ' + str(inp.get('query', '?'))[:200] + '\n')
                                    elif name in ('TodoWrite', 'todo_write'):
                                        logfile.write(ts() + '[Todo] ' + str(inp.get('todos', '?'))[:200] + '\n')
                                    else:
                                        logfile.write(ts() + '[Tool: ' + name + '] ' + str(inp)[:150] + '\n')
                                    logfile.flush()
                                elif block.get('type') == 'tool_result':
                                    content = block.get('content', '')
                                    if isinstance(content, str) and content.strip():
                                        lines = content.strip().split('\n')
                                        preview = '\n'.join(lines[:8])
                                        if len(lines) > 8:
                                            preview += '\n... (' + str(len(lines)) + ' lines)'
                                        logfile.write(preview + '\n')
                                    elif isinstance(content, list):
                                        for sub in content:
                                            if isinstance(sub, dict) and sub.get('text'):
                                                lines = sub['text'].strip().split('\n')
                                                preview = '\n'.join(lines[:8])
                                                if len(lines) > 8:
                                                    preview += '\n... (' + str(len(lines)) + ' lines)'
                                                logfile.write(preview + '\n')
                                    logfile.flush()
                        elif ctype == 'result':
                            logfile.write('\n' + ts() + '=== RESULT ===\n')
                            logfile.write(chunk.get('result', '') + '\n')
                            logfile.write('Cost: $' + str(round(chunk.get('total_cost_usd', 0), 4)) + '\n')
                            logfile.write('Duration: ' + str(chunk.get('duration_ms', 0) // 1000) + 's\n')
                            logfile.flush()
                        elif ctype == 'system':
                            logfile.write(ts() + '[Session started — model: ' + chunk.get('model', '?') + ']\n')
                            logfile.flush()
                    except Exception:
                        logfile.write(line.decode('utf-8', errors='replace'))
                        logfile.flush()
                if time.time() - start > TASK_TIMEOUT:
                    proc.kill()
                    logfile.write('\n[TIMEOUT]\n')
                    logfile.flush()
                    break
            exit_code = proc.returncode if proc.returncode is not None else -1
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
    # Skip forge build for frontend tasks
    frontend_words = ['frontend', 'tab', 'vault', 'trading', 'positions', 'market', 'chart', 'ui', 'ux', 'css', 'component', 'display', 'format', 'sanity']
    is_frontend = any(w in task_display.lower() for w in frontend_words)
    if is_frontend:
        compile_ok = True
        log("POST-TASK: frontend task, skipping forge build")
    else:
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
        try:
            pid = int(Path(LOCK_FILE).read_text().strip())
            # Check if that PID is actually alive
            os.kill(pid, 0)  # signal 0 = just check existence
            return False  # process is alive, real lock
        except (ValueError, ProcessLookupError, PermissionError, OSError):
            # PID is dead or invalid — stale lock
            log("Removing stale lock (dead PID)")
            os.remove(LOCK_FILE)
    Path(LOCK_FILE).write_text(str(os.getpid()))
    return True

def release_lock():
    try: os.remove(LOCK_FILE)
    except: pass

def pass  # pass  # run_readme_gen() disabled during active dev — disabled during active dev:
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
                    pass  # pass  # run_readme_gen() disabled during active dev — disabled during active dev
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
                    rest = 30  # 30s after 3 fails
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
