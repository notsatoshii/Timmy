#!/usr/bin/env python3
"""
LEVER Protocol - Autonomous Improvement Loop
=============================================
QA (test as human) -> Planner (generate tasks) -> Critic (review plan) -> Dispatch (execute) -> repeat
"""

import subprocess, json, time, os, sys, re, glob
from datetime import datetime, timezone
from pathlib import Path

# Config
BASE = Path("/home/lever/lever-protocol")
CP = BASE / "control-plane"
LOCKS = CP / "locks"
LOGS = CP / "dispatcher-logs"
LOOP_LOG = LOGS / "loop.log"
QA_LOG = LOGS / "qa-agent.log"
PLAN_FILE = CP / "build-plan.md"
KNOWN_ISSUES = CP / "known-issues.md"
FRONTEND_URL = "http://localhost:3000"
DASHBOARD_URL = "http://localhost:8080"
MODEL = "claude-sonnet-4-20250514"
CLAUDE_CMD = ["claude", "--dangerously-skip-permissions", "--model", MODEL]
MAX_CRITIC_ROUNDS = 2
CYCLE_PAUSE = 30

TG_TOKEN_FILE = BASE / ".telegram-token"
TG_CHAT_ID = "422985839"

def log(msg, level="INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    line = f"[{ts}] [{level}] {msg}"
    print(line, flush=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    with open(LOOP_LOG, "a") as f:
        f.write(line + "\n")

def tg(msg):
    try:
        if TG_TOKEN_FILE.exists():
            token = TG_TOKEN_FILE.read_text().strip()
            subprocess.run(["curl","-s","-X","POST",
                f"https://api.telegram.org/bot{token}/sendMessage",
                "-d",f"chat_id={TG_CHAT_ID}","-d",f"text=LEVER Loop: {msg}"],
                capture_output=True, timeout=10)
    except: pass

def run_cmd(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout, cwd=str(BASE))
        return r.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]"
    except Exception as e:
        return f"[ERROR: {e}]"

def claude_call(prompt, timeout=120):
    try:
        r = subprocess.run(
            CLAUDE_CMD + ["-p", prompt],
            capture_output=True, text=True, timeout=timeout, cwd=str(BASE)
        )
        return r.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[CLAUDE TIMEOUT]"
    except Exception as e:
        return f"[CLAUDE ERROR: {e}]"


# ============================================
# PHASE 1: QA - Test as a human investor would
# ============================================

def run_qa():
    log("=== QA PHASE ===")
    findings = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "frontend_status": "unknown",
        "data_checks": [],
        "visual_issues": [],
        "functional_issues": [],
        "critical_blockers": [],
        "score": 0
    }

    # Frontend up?
    http_code = run_cmd(f"curl -s -o /dev/null -w '%{{http_code}}' {FRONTEND_URL}")
    findings["frontend_status"] = "UP" if http_code == "200" else f"DOWN ({http_code})"
    if http_code != "200":
        findings["critical_blockers"].append(f"Frontend down: HTTP {http_code}")
        log(f"CRITICAL: Frontend down ({http_code})", "ERROR")

    # On-chain checks
    src = f"source {CP}/deploy-env.sh"
    checks = [
        ("TVL", f"{src} && cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Positions", f"{src} && cast call $POSITION_MANAGER 'nextPositionId()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Global OI", f"{src} && cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Insurance Fund", f"{src} && cast call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Max Leverage", f"{src} && cast call $LEVERAGE_MODEL 'getEffectiveMaxLeverage(bytes32)(uint256)' 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1 --rpc-url $RPC_URL 2>/dev/null"),
    ]
    for name, cmd in checks:
        val = run_cmd(cmd)
        findings["data_checks"].append({"name": name, "value": val[:100], "status": "ok" if val and "[" not in val[:5] else "error"})

    # Dashboard
    dash_code = run_cmd(f"curl -s -o /dev/null -w '%{{http_code}}' {DASHBOARD_URL}")
    if dash_code != "200":
        findings["functional_issues"].append(f"Dashboard down: HTTP {dash_code}")

    # Services
    for svc in ["lever-frontend", "lever-dashboard"]:
        status = run_cmd(f"systemctl is-active {svc} 2>/dev/null")
        if status != "active":
            findings["functional_issues"].append(f"{svc} is {status}")

    # Claude Vision - human perspective review of the frontend
    log("Running Claude Vision review of frontend...")
    vision_prompt = f"""Look at the LEVER Protocol frontend at {FRONTEND_URL}.
You are an investor seeing this DeFi platform for the first time.

Check these files to understand current state:
- cat {CP}/known-issues.md
- curl -s {FRONTEND_URL} | head -100

Then assess:
1. Does the homepage load and look professional?
2. Are there any obvious broken elements, missing data, or errors visible?
3. Would you trust this platform with money based on first impression?
4. What are the top 3 things that would make you close the tab?

Respond in this exact JSON format (no markdown, no backticks):
{{"professional_score": 1-10, "trust_score": 1-10, "deal_breakers": ["issue1", "issue2"], "improvements": ["fix1", "fix2", "fix3"]}}"""

    vision_result = claude_call(vision_prompt, timeout=90)
    try:
        # Try to extract JSON from response
        json_match = re.search(r'\{.*\}', vision_result, re.DOTALL)
        if json_match:
            vision_data = json.loads(json_match.group())
            findings["vision_review"] = vision_data
            if vision_data.get("deal_breakers"):
                for db in vision_data["deal_breakers"]:
                    findings["visual_issues"].append(f"Vision: {db}")
    except:
        findings["vision_review"] = {"raw": vision_result[:300]}

    # Recent git
    findings["recent_commits"] = run_cmd("git log --oneline -5")

    # Known issues
    if KNOWN_ISSUES.exists():
        findings["known_issues_count"] = len(KNOWN_ISSUES.read_text().splitlines())

    # Score
    score = 100
    score -= len(findings["critical_blockers"]) * 30
    score -= len(findings["visual_issues"]) * 10
    score -= len(findings["functional_issues"]) * 15
    findings["score"] = max(0, score)

    log(f"QA Score: {findings['score']}/100 | Blockers:{len(findings['critical_blockers'])} Visual:{len(findings['visual_issues'])} Func:{len(findings['functional_issues'])}")

    with open(QA_LOG, "a") as f:
        f.write(f"\n{'='*60}\nQA Report - {findings['timestamp']}\nScore: {findings['score']}/100\n")
        f.write(json.dumps(findings, indent=2, default=str))
        f.write(f"\n{'='*60}\n")

    return findings


# ============================================
# PHASE 2: PLANNER - Generate build plan
# ============================================

def run_planner(qa_findings):
    log("=== PLANNER PHASE ===")

    ki = KNOWN_ISSUES.read_text()[:2000] if KNOWN_ISSUES.exists() else "None"
    git_log = run_cmd("git log --oneline -10")
    old_plan = PLAN_FILE.read_text()[:1000] if PLAN_FILE.exists() else "No existing plan"

    # Check previous cycle results
    history_file = LOGS / "cycle-history.jsonl"
    prev_results = ""
    if history_file.exists():
        lines = history_file.read_text().strip().split("\n")[-3:]
        prev_results = "\n".join(lines)

    prompt = f"""You are the PLANNER for LEVER Protocol's autonomous build system.

LEVER is a DeFi perpetuals platform for prediction markets. Base Sepolia testnet.
Frontend: {FRONTEND_URL} (React/Vite) at /home/lever/lever-protocol/frontend/user-app/
Contracts: /home/lever/lever-protocol/contracts/
Dashboard: {DASHBOARD_URL} (Python) at /home/lever/lever-protocol/control-plane/dashboard.py

QA Agent findings:
{json.dumps(qa_findings, indent=2, default=str)}

Known issues:
{ki}

Recent git:
{git_log}

Previous plan:
{old_plan}

Previous cycle results:
{prev_results}

Generate 5-10 prioritized tasks. Each task must:
1. Fix a real issue found by QA or improve from human user perspective
2. Be specific - include exact file paths, function names, what to change
3. Be executable by a Claude Code agent autonomously
4. Be tagged with lane: [CONTRACT], [FRONTEND], or [INFRA]

PRIORITIES: CRITICAL > HIGH > MEDIUM > LOW
Think like an investor at a demo. What would make them close the tab?

If previous cycles failed on certain tasks, either skip them or provide a DIFFERENT approach.

Output ONLY this markdown (no preamble):

### 1. Task Title [PRIORITY] [LANE]
- [ ] 1. Detailed description with file paths and specific changes

### 2. Task Title [PRIORITY] [LANE]
- [ ] 2. Detailed description

(continue for all tasks)"""

    plan = claude_call(prompt, timeout=90)
    log(f"Planner generated {len(plan)} chars")
    return plan


# ============================================
# PHASE 3: CRITIC - Review the plan
# ============================================

def run_critic(plan_text, qa_findings):
    log("=== CRITIC PHASE ===")

    prompt = f"""You are the CRITIC for LEVER Protocol's autonomous build system.
Review this build plan from an INVESTOR and HUMAN USER perspective.

You think differently than the Planner:
- Planner thinks about technical fixes
- YOU think about: Would an investor care? Is priority order right for a demo?
  Are tasks specific enough to execute? Did planner miss something obvious?
  Is planner repeating a failed fix? Does this make the platform feel REAL?

QA findings:
{json.dumps(qa_findings, indent=2, default=str)}

Proposed plan:
{plan_text}

Respond with EXACTLY one of:

APPROVED
(if plan is good - well-prioritized, specific, addresses real issues)

OR

REJECTED
<feedback>
- Issue 1
- Issue 2
- What's missing
- What to reprioritize
</feedback>

Be strict but fair. Only reject if priorities are wrong, tasks are too vague, or critical issues are ignored."""

    critique = claude_call(prompt, timeout=60)
    log(f"Critic: {critique[:80]}...")

    if critique.strip().startswith("APPROVED"):
        return {"approved": True, "feedback": ""}
    feedback = critique.replace("REJECTED", "").strip()
    if "<feedback>" in feedback:
        feedback = feedback.split("<feedback>")[1].split("</feedback>")[0].strip()
    return {"approved": False, "feedback": feedback}


def run_planner_revision(original_plan, critic_feedback, qa_findings):
    log("=== PLANNER REVISION ===")

    prompt = f"""You are the PLANNER for LEVER Protocol. The Critic REJECTED your plan.

Your original plan:
{original_plan}

Critic feedback:
{critic_feedback}

QA findings:
{json.dumps(qa_findings, indent=2, default=str)}

Revise the plan addressing every point the critic raised.
Output ONLY the revised plan in the same markdown format:

### 1. Title [PRIORITY] [LANE]
- [ ] 1. Description

(etc)"""

    revised = claude_call(prompt, timeout=90)
    log(f"Planner revised: {len(revised)} chars")
    return revised


# ============================================
# PHASE 4: DISPATCH - Execute via parallel agents
# ============================================

def run_dispatch(plan_text):
    log("=== DISPATCH PHASE ===")

    # Write approved plan
    PLAN_FILE.write_text(plan_text)
    log(f"Wrote {len(plan_text)} chars to build-plan.md")

    # Clean old locks
    for f in glob.glob(str(LOCKS / "done-*")) + glob.glob(str(LOCKS / "fail-*")) + glob.glob(str(LOCKS / "running-*")):
        os.remove(f)
    # Also clean plan json
    plan_json = LOCKS / "current-plan.json"
    if plan_json.exists():
        plan_json.unlink()
    log("Cleaned locks")

    # Start dispatcher
    log("Starting dispatcher...")
    run_cmd("systemctl start lever-dispatcher 2>/dev/null")
    time.sleep(5)

    status = run_cmd("systemctl is-active lever-dispatcher 2>/dev/null")
    if status != "active":
        log("Dispatcher service not active, launching directly...")
        subprocess.Popen(
            ["python3", str(CP / "dispatcher.py")],
            cwd=str(BASE),
            stdout=open(LOGS / "dispatcher.log", "a"),
            stderr=subprocess.STDOUT
        )
        time.sleep(5)

    log("Dispatcher running. Waiting...")
    tg("Agents dispatched")

    max_wait = 3600
    start = time.time()
    last_log = ""
    stale_count = 0

    while time.time() - start < max_wait:
        done = glob.glob(str(LOCKS / "done-*"))
        running = glob.glob(str(LOCKS / "running-*"))
        failed = glob.glob(str(LOCKS / "fail-*"))

        s = f"D:{len(done)} R:{len(running)} F:{len(failed)}"
        if s != last_log:
            log(f"  {s}")
            last_log = s
            stale_count = 0
        else:
            stale_count += 1

        # If nothing running and we have results, we're done
        if len(running) == 0 and (len(done) + len(failed)) > 0:
            time.sleep(20)
            running2 = glob.glob(str(LOCKS / "running-*"))
            if len(running2) == 0:
                break

        # If stale for 10 minutes (20 * 30s), break
        if stale_count > 20:
            log("Stale for 10min, breaking", "WARN")
            break

        time.sleep(30)

    # Stop dispatcher
    run_cmd("systemctl stop lever-dispatcher 2>/dev/null")
    run_cmd("pkill -f dispatcher.py 2>/dev/null")
    run_cmd("pkill -f claude 2>/dev/null")

    done = glob.glob(str(LOCKS / "done-*"))
    failed = glob.glob(str(LOCKS / "fail-*"))

    result = {
        "done": [os.path.basename(f).replace("done-", "") for f in done],
        "failed": [os.path.basename(f).replace("fail-", "") for f in failed],
        "duration_min": round((time.time() - start) / 60, 1)
    }

    log(f"Dispatch: {len(done)} done, {len(failed)} failed, {result['duration_min']}min")
    tg(f"Done:{len(done)} Failed:{len(failed)} Time:{result['duration_min']}m")

    run_cmd("git add -A && git commit -m 'auto: cycle tasks complete' 2>/dev/null")
    return result


# ============================================
# MAIN LOOP
# ============================================

def run_cycle(cycle_num):
    log(f"\n{'#'*60}")
    log(f"CYCLE {cycle_num}")
    log(f"{'#'*60}")
    tg(f"Cycle {cycle_num} starting")

    qa = run_qa()
    plan = run_planner(qa)

    if not plan or len(plan) < 50:
        log("Empty plan, skipping", "WARN")
        return None

    # Critic loop
    approved_plan = None
    current_plan = plan
    for rnd in range(MAX_CRITIC_ROUNDS + 1):
        if rnd == MAX_CRITIC_ROUNDS:
            log("Max critic rounds, using current plan")
            approved_plan = current_plan
            break
        critique = run_critic(current_plan, qa)
        if critique["approved"]:
            log(f"Plan APPROVED (round {rnd+1})")
            approved_plan = current_plan
            break
        else:
            log(f"Plan REJECTED (round {rnd+1})")
            current_plan = run_planner_revision(current_plan, critique["feedback"], qa)

    if not approved_plan:
        log("No approved plan", "ERROR")
        return None

    dispatch_result = run_dispatch(approved_plan)

    summary = {
        "cycle": cycle_num,
        "qa_score": qa["score"],
        "done": len(dispatch_result["done"]),
        "failed": len(dispatch_result["failed"]),
        "duration_min": dispatch_result["duration_min"],
        "ts": datetime.now(timezone.utc).isoformat()
    }

    history = LOGS / "cycle-history.jsonl"
    with open(history, "a") as f:
        f.write(json.dumps(summary) + "\n")

    log(f"CYCLE {cycle_num} DONE: QA={qa['score']} Done={summary['done']} Failed={summary['failed']} Time={summary['duration_min']}m")
    return summary


def main():
    log("=" * 60)
    log("LEVER PROTOCOL - AUTONOMOUS IMPROVEMENT LOOP")
    log("=" * 60)
    tg("Loop starting")

    LOGS.mkdir(parents=True, exist_ok=True)
    LOCKS.mkdir(parents=True, exist_ok=True)

    cycle = 1
    history = LOGS / "cycle-history.jsonl"
    if history.exists():
        lines = [l for l in history.read_text().strip().split("\n") if l]
        if lines:
            try:
                cycle = json.loads(lines[-1]).get("cycle", 0) + 1
            except: pass

    while True:
        try:
            run_cycle(cycle)
            cycle += 1
            log(f"Pause {CYCLE_PAUSE}s...")
            time.sleep(CYCLE_PAUSE)
        except KeyboardInterrupt:
            log("Stopped by user")
            break
        except Exception as e:
            log(f"Cycle error: {e}", "ERROR")
            time.sleep(60)

if __name__ == "__main__":
    main()
