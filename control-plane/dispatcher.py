#!/usr/bin/env python3
"""
LEVER Protocol — Smart Parallel Dispatcher v3

You write plain tasks in build-plan.md. No lane or dependency tags needed.

Flow:
  1. Read build-plan.md
  2. Call Claude to analyze ALL remaining tasks → dependency graph + lane assignments
  3. Launch one Claude Code worker per lane for unblocked tasks (max 3 parallel)
  4. When a task completes, re-plan and fill the slot
  5. Repeat until all done

Safety: one task per lane (CONTRACT/FRONTEND/INFRA). Agents never touch the same files.
"""

import re
import subprocess
import time
import os
import json
from datetime import datetime
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────────

PROJECT_DIR = "/home/lever/lever-protocol"
BUILD_PLAN = f"{PROJECT_DIR}/control-plane/build-plan.md"
LOG_DIR = f"{PROJECT_DIR}/control-plane/dispatcher-logs"
LOCK_DIR = f"{PROJECT_DIR}/control-plane/locks"
SCREENSHOT_DIR = f"{PROJECT_DIR}/control-plane/screenshots"
PLAN_CACHE = f"{LOCK_DIR}/current-plan.json"

POLL_INTERVAL = 30   # seconds between polls
MAX_RETRIES = 2      # retries per failed task
MAX_PARALLEL = 3     # max simultaneous agents

# Claude CLI command — MUST match what works on your server.
# Run `which claude` and `claude --help` on the server to verify flags.
# The existing worker.py pipes prompts via stdin, which we replicate here.
MODEL = "claude-sonnet-4-20250514"
CLAUDE_CMD = ["claude", "--dangerously-skip-permissions", "--model", MODEL]
CLAUDE_PLANNER_CMD = ["claude", "--dangerously-skip-permissions", "--model", MODEL, "-p"]


# ── Planner ─────────────────────────────────────────────────────────────────

PLANNER_PROMPT = """You are a build planner for a Solidity + React project.

Project structure:
- src/*.sol, scripts/*.s.sol → Solidity contracts + Foundry scripts (CONTRACT lane)
- frontend/user-app/** → React/TypeScript/Vite frontend (FRONTEND lane)
- control-plane/*, scripts/*.sh, scripts/*.js → Infra, testing, automation (INFRA lane)

Here are ALL remaining incomplete tasks:

{tasks}

Return a JSON object assigning each task a lane and dependencies:

{{
  "tasks": [
    {{
      "id": "<task id>",
      "lane": "CONTRACT | FRONTEND | INFRA",
      "depends_on": ["<task id>", ...],
      "reason": "<why this lane, why these dependencies>"
    }}
  ]
}}

LANE RULES — assign by ROOT CAUSE (which files must change):
- CONTRACT: Solidity source, Foundry scripts, forge build/test, cast send/call, deploying contracts
- FRONTEND: React components, hooks, pages, styles, Vite config, npm build
- INFRA: Bash/Python/JS scripts, systemd services, puppeteer tests, control-plane configs, worker rules

If a task creates a new systemd service or bash script → INFRA even if it calls cast.
If a task fixes a display bug in React → FRONTEND even if it reads contract data.
If a task fixes Solidity math or redeploys a contract → CONTRACT.

DEPENDENCY RULES — B depends on A only when:
- B reads/displays data that A is fixing at the source (e.g., frontend displays leverage that the contract is fixing)
- B tests or validates something A creates
- B is "polish" or "final review" that assumes all prior fixes
- If no real data flow between them → depends_on = []

SAFETY:
- Same lane + could touch same files → must be sequential (add dependency)
- Different lanes with no data dependency → safe to parallelize
- When uncertain → ADD the dependency. Correct-and-slow beats broken-and-fast.

Return ONLY valid JSON. No markdown fences, no commentary."""


def call_planner(tasks_text):
    """Ask Claude to analyze tasks and return execution plan."""
    prompt = PLANNER_PROMPT.format(tasks=tasks_text)
    try:
        result = subprocess.run(
            CLAUDE_PLANNER_CMD,
            input=prompt.encode(),
            capture_output=True,
            timeout=120,
            cwd=PROJECT_DIR,
        )
        output = result.stdout.decode().strip()
        # Strip markdown fences
        output = re.sub(r'^```(?:json)?\s*\n?', '', output)
        output = re.sub(r'\n?\s*```$', '', output)
        return json.loads(output)
    except Exception as e:
        log(f"⚠️  Planner error: {e}")
        return None


# ── Build plan parser ───────────────────────────────────────────────────────

def parse_tasks(path):
    """Parse build-plan.md. Expected format per task:
        ### <id>. <title> [PRIORITY]
        - [ ] <id>. <description...>    (or [x] if done)
        **DONE:** ...
        **FAIL:** ...
    """
    tasks = []
    current = None

    with open(path, 'r') as f:
        lines = f.readlines()

    for line in lines:
        s = line.rstrip()

        # Task header
        m = re.match(r'^###\s+(\w+)\.\s+(.+?)\s*\[(\w+)\]\s*$', s)
        if m:
            if current:
                tasks.append(current)
            current = {
                'id': m.group(1),
                'title': m.group(2),
                'priority': m.group(3),
                'done': False,
                'body': '',
            }
            continue

        if current is None:
            continue

        # Checkbox — detect done status
        cm = re.match(r'^-\s*\[([ x])\]\s*' + re.escape(current['id']), s)
        if cm:
            current['done'] = (cm.group(1) == 'x')

        current['body'] += line

    if current:
        tasks.append(current)
    return tasks


# ── Worker ──────────────────────────────────────────────────────────────────

def build_prompt(task, plan_entry):
    lane = plan_entry.get('lane', 'GENERAL')
    tid = task['id']

    return f"""You are an autonomous build agent for LEVER Protocol.

## Your task: {tid}. {task['title']} [{task['priority']}]

{task['body'].strip()}

---

IMPORTANT — LANE BOUNDARIES:
Your lane is {lane}. You may ONLY modify files in your lane:
  CONTRACT → src/*.sol, scripts/*.s.sol, test/*, forge/cast commands
  FRONTEND → frontend/user-app/** only
  INFRA    → control-plane/*, scripts/*.sh, scripts/*.js, systemd configs

WORKFLOW:
1. Read the relevant source files to understand the current state
2. Implement the fix
3. Verify the DONE condition stated above — actually run the check commands
4. If the FAIL condition is true after your fix, you are NOT done — debug and retry
5. Run verification:
   - CONTRACT tasks: bash control-plane/health-check.sh
   - FRONTEND tasks: npm run build in frontend/user-app && bash scripts/sanity-check-frontend.sh
   - INFRA tasks: test that your script/service actually runs
6. Commit: git add -A && git commit -m "fix({tid}): <what you fixed>"
7. Signal done: touch {LOCK_DIR}/done-{tid}

If you truly cannot fix it after multiple attempts, write the reason to:
  {LOCK_DIR}/fail-{tid}

DO NOT touch files outside your lane. Other agents are working in parallel on other lanes."""


def launch_worker(task, plan_entry):
    prompt = build_prompt(task, plan_entry)
    lane = plan_entry.get('lane', 'GENERAL')
    tid = task['id']
    ts = datetime.now().strftime('%H%M%S')
    log_file = f"{LOG_DIR}/task-{tid}-{ts}.log"

    proc = subprocess.Popen(
        CLAUDE_CMD,
        stdin=subprocess.PIPE,
        stdout=open(log_file, 'w'),
        stderr=subprocess.STDOUT,
        cwd=PROJECT_DIR,
        env={**os.environ, 'CLAUDE_TASK_ID': tid},
    )
    proc.stdin.write(prompt.encode())
    proc.stdin.close()

    meta = {
        'task_id': tid,
        'lane': lane,
        'title': task['title'],
        'started': datetime.now().isoformat(),
        'pid': proc.pid,
        'log': log_file,
    }
    Path(f"{LOCK_DIR}/running-{tid}").write_text(json.dumps(meta, indent=2))
    return proc


def check_completion(tid):
    if os.path.exists(f"{LOCK_DIR}/done-{tid}"):
        return 'done'
    if os.path.exists(f"{LOCK_DIR}/fail-{tid}"):
        return 'failed'
    return None


def mark_done(tid):
    with open(BUILD_PLAN, 'r') as f:
        content = f.read()
    content = content.replace(f"- [ ] {tid}.", f"- [x] {tid}.")
    with open(BUILD_PLAN, 'w') as f:
        f.write(content)


def cleanup_lock(tid):
    lock = f"{LOCK_DIR}/running-{tid}"
    if os.path.exists(lock):
        os.remove(lock)


# ── Telegram ────────────────────────────────────────────────────────────────

def notify(msg):
    try:
        token_file = f"{PROJECT_DIR}/.telegram-token"
        token = Path(token_file).read_text().strip() if os.path.exists(token_file) else os.environ.get('TELEGRAM_BOT_TOKEN', '')
        if not token:
            return
        import urllib.request
        data = json.dumps({'chat_id': '422985839', 'text': f"🔧 {msg}"}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=data, headers={'Content-Type': 'application/json'}
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass


# ── Logging ─────────────────────────────────────────────────────────────────

def log(msg):
    ts = datetime.now().strftime('%H:%M:%S')
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(f"{LOG_DIR}/dispatcher.log", 'a') as f:
        f.write(line + '\n')


# ── Main loop ───────────────────────────────────────────────────────────────

def main():
    for d in [LOG_DIR, LOCK_DIR, SCREENSHOT_DIR]:
        os.makedirs(d, exist_ok=True)

    # Clean stale locks from previous run
    for pattern in ["running-*", "done-*", "fail-*"]:
        for f in Path(LOCK_DIR).glob(pattern):
            f.unlink()

    active = {}        # tid → (task, plan_entry, process)
    retry_counts = {}  # tid → int
    plan = None        # {tid: entry} from planner

    log("═══════════════════════════════════════")
    log("  LEVER Smart Dispatcher v3")
    log(f"  Max parallel: {MAX_PARALLEL} agents")
    log(f"  Claude cmd:   {' '.join(CLAUDE_CMD)}")
    log("═══════════════════════════════════════")
    notify("Dispatcher v3 started — analyzing tasks")

    while True:
        # ── 1. Check completed workers ──────────────────────────────────
        finished = []
        for tid, (task, entry, proc) in list(active.items()):
            if proc.poll() is None:
                continue  # still running

            status = check_completion(tid)
            if status == 'done':
                mark_done(tid)
                log(f"✅ {tid} DONE — {task['title']}")
                notify(f"✅ {tid}: {task['title']}")
                plan = None  # trigger re-plan
            elif status == 'failed':
                reason = Path(f"{LOCK_DIR}/fail-{tid}").read_text().strip()[:200]
                log(f"❌ {tid} FAILED — {reason}")
                notify(f"❌ {tid}: {reason[:80]}")
                plan = None
            else:
                r = retry_counts.get(tid, 0)
                if r < MAX_RETRIES:
                    retry_counts[tid] = r + 1
                    log(f"⚠️  {tid} RETRY {r+1}/{MAX_RETRIES} — exited without done/fail signal")
                    plan = None
                else:
                    log(f"💀 {tid} ABANDONED — needs human intervention")
                    notify(f"💀 {tid} needs human: {task['title']}")
            finished.append(tid)

        for tid in finished:
            del active[tid]
            cleanup_lock(tid)

        # ── 2. Parse current state ──────────────────────────────────────
        tasks = parse_tasks(BUILD_PLAN)
        done_ids = {t['id'] for t in tasks if t['done']}
        remaining = [t for t in tasks if not t['done'] and t['id'] not in active]

        if not remaining and not active:
            log("🎉 ALL TASKS COMPLETE")
            notify("🎉 Phase 0-FINAL complete!")
            break

        # ── 3. Plan if we need to ───────────────────────────────────────
        slots = MAX_PARALLEL - len(active)
        if remaining and plan is None and slots > 0:
            text = "\n\n".join(
                f"### {t['id']}. {t['title']} [{t['priority']}]\n{t['body']}"
                for t in remaining
            )
            log(f"🧠 Analyzing {len(remaining)} tasks for parallelism...")
            result = call_planner(text)

            if result and 'tasks' in result:
                plan = {e['id']: e for e in result['tasks']}
                log("📋 EXECUTION PLAN:")
                for e in result['tasks']:
                    deps = ', '.join(e['depends_on']) if e['depends_on'] else '—'
                    log(f"   {e['id']:>4} │ {e['lane']:<10} │ waits: {deps}")
                    log(f"        └─ {e.get('reason','')}")
                Path(PLAN_CACHE).write_text(json.dumps(result, indent=2))
            else:
                log("⚠️  Planning failed — retrying next cycle")
                time.sleep(POLL_INTERVAL)
                continue

        if plan is None:
            time.sleep(POLL_INTERVAL)
            continue

        # ── 4. Find runnable tasks ──────────────────────────────────────
        active_lanes = {entry['lane'] for _, (_, entry, _) in active.items()}
        runnable = []

        for t in remaining:
            entry = plan.get(t['id'])
            if not entry:
                continue
            # Dependencies satisfied?
            if not all(d in done_ids for d in entry.get('depends_on', [])):
                continue
            # Lane available?
            lane = entry.get('lane', 'GENERAL')
            if lane in active_lanes:
                continue
            runnable.append((t, entry))
            active_lanes.add(lane)

        # ── 5. Launch ───────────────────────────────────────────────────
        for task, entry in runnable[:slots]:
            lane = entry['lane']
            log(f"🚀 LAUNCH {task['id']} → {lane} │ {task['title']}")
            notify(f"🚀 {task['id']}: {task['title']}")
            proc = launch_worker(task, entry)
            active[task['id']] = (task, entry, proc)

        # ── 6. Status ───────────────────────────────────────────────────
        total = len(tasks)
        done_count = len(done_ids)
        if active:
            tags = " ".join(f"[{e['lane'][0]}]{tid}" for tid, (_, e, _) in active.items())
            log(f"   ⚡ {tags} │ {done_count}/{total} done │ {len(remaining)} waiting")

        time.sleep(POLL_INTERVAL)

    log("═══════════════════════════════════════")
    log("  Dispatcher shut down")
    log("═══════════════════════════════════════")


if __name__ == '__main__':
    main()
