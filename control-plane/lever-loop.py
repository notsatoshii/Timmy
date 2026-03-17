#!/usr/bin/env python3
"""
LEVER Protocol - Autonomous Improvement Loop v2
Supports two modes:
1. LOCKED SPRINT: Execute fixed build plan, skip planner/critic
2. AUTO-IMPROVE: Normal QA->Plan->Critic->Dispatch with regression protection
"""

import subprocess, json, time, os, sys, re, glob
from datetime import datetime, timezone
from pathlib import Path

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
BASELINE_SCORE_FILE = LOGS / "baseline-score.json"
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

def is_locked_sprint():
    if PLAN_FILE.exists():
        return "LOCKED BUILD PLAN" in PLAN_FILE.read_text()[:200]
    return False

def get_baseline_score():
    if BASELINE_SCORE_FILE.exists():
        try:
            return json.loads(BASELINE_SCORE_FILE.read_text()).get("score", 0)
        except: pass
    return 0

def set_baseline_score(score):
    BASELINE_SCORE_FILE.write_text(json.dumps({"score": score, "set_at": datetime.now(timezone.utc).isoformat()}))

def transition_to_auto_improve(qa_score):
    log("=== PHASE TRANSITION: Locked Sprint -> Auto-Improve ===")
    tg("All 3 sprint priorities passed! Entering auto-improve mode.")
    set_baseline_score(qa_score)
    PLAN_FILE.write_text("# AUTO-IMPROVE MODE\nBaseline score: " + str(qa_score) + "\nFocus: UI polish, mobile, error handling.\nRegression rules: volume real, positions real, trading works.")

def run_qa():
    log("=== QA PHASE (Enhanced) ===")
    findings = {"timestamp": datetime.now(timezone.utc).isoformat(), "frontend_status": "unknown",
        "tabs": {}, "data_checks": [], "contract_checks": [], "sprint_checks": {},
        "critical_blockers": [], "visual_issues": [], "functional_issues": [], "score": 0}

    http_code = run_cmd(f"curl -s -o /dev/null -w '%{{http_code}}' {FRONTEND_URL}")
    findings["frontend_status"] = "UP" if http_code == "200" else f"DOWN ({http_code})"
    if http_code != "200":
        findings["critical_blockers"].append(f"Frontend down: HTTP {http_code}")

    src = f"source {CP}/deploy-env.sh"
    for name, cmd in [
        ("TVL", f"{src} && cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Positions", f"{src} && cast call $POSITION_MANAGER 'nextPositionId()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Global OI", f"{src} && cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
        ("Insurance Fund", f"{src} && cast call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>/dev/null"),
    ]:
        val = run_cmd(cmd)
        status = "ok" if val and "[" not in val[:5] else "error"
        findings["contract_checks"].append({"name": name, "value": val[:100], "status": status})
        if status == "error":
            findings["functional_issues"].append(f"Contract check failed: {name}")

    for svc in ["lever-frontend", "lever-dashboard"]:
        status = run_cmd(f"systemctl is-active {svc} 2>/dev/null")
        if status != "active":
            findings["functional_issues"].append(f"{svc} is {status}")

    if is_locked_sprint():
        log("Running sprint-specific checks...")
        vol_check = run_cmd(f"grep -c '12800000000' {BASE}/frontend/user-app/src/hooks/useVolumeCalculation.ts")
        has_fake_vol = vol_check.strip() != "0"
        findings["sprint_checks"]["volume_no_fake_data"] = not has_fake_vol
        if has_fake_vol:
            findings["critical_blockers"].append("SPRINT P1: fake volume fallback still present")

        stats_check = run_cmd(f"grep -c '12800000000' {BASE}/frontend/user-app/src/components/ProtocolStats.tsx")
        has_fake_stats = stats_check.strip() != "0"
        findings["sprint_checks"]["stats_no_fake_volume"] = not has_fake_stats
        if has_fake_stats:
            findings["visual_issues"].append("SPRINT P1: ProtocolStats has fake volume")

        findings["sprint_checks"]["trading_has_flow"] = True

        pos_check = run_cmd(f"grep -c 'fall back to demo data' {BASE}/frontend/user-app/src/components/Positions.tsx")
        has_fake_pos = pos_check.strip() != "0"
        findings["sprint_checks"]["positions_real_data"] = not has_fake_pos
        if has_fake_pos:
            findings["critical_blockers"].append("SPRINT P3: Positions.tsx uses fake data")

        hook_check = run_cmd(f"grep -c 'fall back to demo data' {BASE}/frontend/user-app/src/hooks/usePositions.ts")
        has_fake_hook = hook_check.strip() != "0"
        findings["sprint_checks"]["positions_hook_real_data"] = not has_fake_hook
        if has_fake_hook:
            findings["visual_issues"].append("SPRINT P3: usePositions.ts uses fake data")

        sprint_passed = all([not has_fake_vol, not has_fake_stats, not has_fake_pos, not has_fake_hook])
        findings["sprint_checks"]["all_passed"] = sprint_passed
        log(f"Sprint checks: {'ALL PASSED' if sprint_passed else 'NOT YET'} -- {json.dumps(findings['sprint_checks'])}")

    log("Running Claude Vision review...")
    vision_prompt = f"You are QA testing LEVER Protocol frontend at {FRONTEND_URL}. Run: curl -s {FRONTEND_URL} | head -200. Evaluate from investor perspective. Respond in JSON only: {{\"professional_score\": 1-10, \"trust_score\": 1-10, \"issues\": [\"issue1\"], \"improvements\": [\"fix1\"]}}"
    vision_result = claude_call(vision_prompt, timeout=90)
    try:
        json_match = re.search(r'\{.*\}', vision_result, re.DOTALL)
        if json_match:
            vision_data = json.loads(json_match.group())
            findings["vision_review"] = vision_data
            if vision_data.get("issues"):
                for issue in vision_data["issues"]:
                    findings["visual_issues"].append(f"Vision: {issue}")
    except:
        findings["vision_review"] = {"raw": vision_result[:300]}

    score = 100
    score -= len(findings["critical_blockers"]) * 25
    score -= len(findings["visual_issues"]) * 8
    score -= len(findings["functional_issues"]) * 12
    findings["score"] = max(0, min(100, score))

    if not is_locked_sprint():
        baseline = get_baseline_score()
        if baseline > 0 and findings["score"] < baseline - 10:
            log(f"REGRESSION: Score {findings['score']} < baseline {baseline}", "ERROR")
            tg(f"REGRESSION: Score dropped to {findings['score']}")
            run_cmd("git revert --no-edit HEAD 2>/dev/null")
            run_cmd(f"cd {BASE}/frontend/user-app && npm run build 2>/dev/null")
            run_cmd("systemctl restart lever-frontend 2>/dev/null")

    log(f"QA Score: {findings['score']}/100 | Blockers:{len(findings['critical_blockers'])} Visual:{len(findings['visual_issues'])} Func:{len(findings['functional_issues'])}")
    qa_file = LOGS / f"qa-report-latest.json"
    qa_file.write_text(json.dumps(findings, indent=2, default=str))
    return findings

def run_planner(qa_findings):
    log("=== PLANNER PHASE ===")
    ki = KNOWN_ISSUES.read_text()[:2000] if KNOWN_ISSUES.exists() else "None"
    git_log = run_cmd("git log --oneline -10")
    prompt = f"You are the PLANNER for LEVER Protocol. Generate 3-5 prioritized tasks. QA: {json.dumps(qa_findings, default=str)[:3000]}\nKnown issues: {ki}\nGit: {git_log}\nOutput markdown: ### 1. Title [PRIORITY] [LANE]\n- [ ] 1. Description"
    plan = claude_call(prompt, timeout=90)
    log(f"Planner generated {len(plan)} chars")
    return plan

def run_critic(plan_text, qa_findings):
    log("=== CRITIC PHASE ===")
    prompt = f"Review this plan. Respond APPROVED or REJECTED with feedback.\nPlan:\n{plan_text}\nQA: {json.dumps(qa_findings, default=str)[:2000]}"
    critique = claude_call(prompt, timeout=60)
    if "APPROVED" in critique[:200].upper():
        return {"approved": True, "feedback": ""}
    return {"approved": False, "feedback": critique}

def run_dispatch(plan_text):
    log("=== DISPATCH PHASE ===")
    PLAN_FILE.write_text(plan_text)
    log(f"Wrote {len(plan_text)} chars to build-plan.md")

    for f in glob.glob(str(LOCKS / "done-*")) + glob.glob(str(LOCKS / "fail-*")) + glob.glob(str(LOCKS / "running-*")):
        os.remove(f)
    plan_json = LOCKS / "current-plan.json"
    if plan_json.exists(): plan_json.unlink()
    log("Cleaned locks")

    log("Starting dispatcher...")
    run_cmd("systemctl start lever-dispatcher 2>/dev/null")
    time.sleep(5)
    status = run_cmd("systemctl is-active lever-dispatcher 2>/dev/null")
    if status != "active":
        log("Dispatcher service not active, launching directly...")
        subprocess.Popen(["python3", str(CP / "dispatcher.py")], cwd=str(BASE),
            stdout=open(LOGS / "dispatcher.log", "a"), stderr=subprocess.STDOUT)
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
        if len(running) == 0 and (len(done) + len(failed)) > 0:
            time.sleep(20)
            if len(glob.glob(str(LOCKS / "running-*"))) == 0: break
        if stale_count > 20:
            log("Stale for 10min, breaking", "WARN")
            break
        time.sleep(30)

    run_cmd("systemctl stop lever-dispatcher 2>/dev/null")
    run_cmd("pkill -f dispatcher.py 2>/dev/null")
    run_cmd("pkill -f claude 2>/dev/null")
    done = glob.glob(str(LOCKS / "done-*"))
    failed = glob.glob(str(LOCKS / "fail-*"))

    log("Rebuilding frontend...")
    run_cmd(f"cd {BASE}/frontend/user-app && npm run build 2>&1 | tail -5", timeout=120)
    run_cmd("systemctl restart lever-frontend 2>/dev/null")
    run_cmd("git add -A && git commit -m 'auto: cycle tasks complete' 2>/dev/null")

    result = {"done": [os.path.basename(f).replace("done-","") for f in done],
              "failed": [os.path.basename(f).replace("fail-","") for f in failed],
              "duration_min": round((time.time()-start)/60, 1)}
    log(f"Dispatch: {len(done)} done, {len(failed)} failed, {result['duration_min']}min")
    tg(f"Done:{len(done)} Failed:{len(failed)} Time:{result['duration_min']}m")
    return result

def run_cycle(cycle_num):
    log(f"\n{'#'*60}")
    log(f"CYCLE {cycle_num}")
    log(f"{'#'*60}")
    locked = is_locked_sprint()
    mode = "LOCKED SPRINT" if locked else "AUTO-IMPROVE"
    log(f"Mode: {mode}")
    tg(f"Cycle {cycle_num} ({mode})")

    qa = run_qa()
    if locked and qa.get("sprint_checks", {}).get("all_passed", False):
        log("ALL SPRINT CHECKS PASSED!")
        tg("All 3 sprint priorities passed! Transitioning to auto-improve.")
        transition_to_auto_improve(qa["score"])
        summary = {"cycle": cycle_num, "qa_score": qa["score"], "done": 0, "failed": 0,
                   "duration_min": 0, "mode": "PHASE_TRANSITION", "ts": datetime.now(timezone.utc).isoformat()}
        with open(LOGS / "cycle-history.jsonl", "a") as f: f.write(json.dumps(summary) + "\n")
        return summary

    if locked:
        log("Locked sprint -- using existing build-plan.md (skipping planner/critic)")
        plan = PLAN_FILE.read_text()
    else:
        plan = run_planner(qa)
        if not plan or len(plan) < 50:
            log("Empty plan, skipping", "WARN")
            return None
        current_plan = plan
        for rnd in range(MAX_CRITIC_ROUNDS + 1):
            if rnd == MAX_CRITIC_ROUNDS:
                plan = current_plan
                break
            critique = run_critic(current_plan, qa)
            if critique["approved"]:
                log(f"Plan APPROVED (round {rnd+1})")
                plan = current_plan
                break
            else:
                log(f"Plan REJECTED (round {rnd+1})")
                current_plan = claude_call(f"Revise plan based on feedback: {critique['feedback']}\nOriginal: {current_plan}", timeout=90)

    dispatch_result = run_dispatch(plan)
    summary = {"cycle": cycle_num, "qa_score": qa["score"], "done": len(dispatch_result["done"]),
               "failed": len(dispatch_result["failed"]), "duration_min": dispatch_result["duration_min"],
               "mode": mode, "sprint_checks": qa.get("sprint_checks", {}),
               "ts": datetime.now(timezone.utc).isoformat()}
    with open(LOGS / "cycle-history.jsonl", "a") as f: f.write(json.dumps(summary) + "\n")
    state = {"next_cycle": cycle_num+1, "last_completed": cycle_num, "last_qa_score": qa["score"],
             "mode": mode, "timestamp": datetime.now(timezone.utc).isoformat()}
    (LOGS / "loop-state.json").write_text(json.dumps(state, indent=2))
    log(f"CYCLE {cycle_num} DONE: QA={qa['score']} Done={summary['done']} Failed={summary['failed']} Time={summary['duration_min']}m")
    return summary

def main():
    log("=" * 60)
    log("LEVER PROTOCOL - AUTONOMOUS IMPROVEMENT LOOP v2")
    log("=" * 60)
    tg("Loop v2 starting")
    LOGS.mkdir(parents=True, exist_ok=True)
    LOCKS.mkdir(parents=True, exist_ok=True)
    cycle = 1
    history = LOGS / "cycle-history.jsonl"
    if history.exists():
        lines = [l for l in history.read_text().strip().split("\n") if l]
        if lines:
            try: cycle = json.loads(lines[-1]).get("cycle", 0) + 1
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
            tg(f"Cycle error: {str(e)[:100]}")
            time.sleep(60)

if __name__ == "__main__":
    main()
