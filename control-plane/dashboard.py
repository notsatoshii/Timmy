#!/usr/bin/env python3
"""
LEVER Protocol — Timmy Dashboard v3
All timestamps ICT (UTC+7). Live terminal. Lazy-loaded logs. Debug endpoint.
Run: python3 dashboard.py — Access: http://SERVER_IP:8080
"""

import http.server, json, os, subprocess, glob, urllib.parse, re, time, traceback
from datetime import datetime, timezone, timedelta


def parse_stream_json(raw_text):
    """Parse stream-json log into readable text."""
    lines = raw_text.strip().split('\n')
    output = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if not line.startswith('{'):
            output.append(line)
            continue
        try:
            chunk = json.loads(line)
            ctype = chunk.get('type', '')
            if ctype == 'system':
                model = chunk.get('model', '?')
                output.append(f'[Session started — model: {model}]')
            elif ctype == 'assistant':
                msg = chunk.get('message', {})
                for block in msg.get('content', []):
                    bt = block.get('type', '')
                    if bt == 'text':
                        output.append(block['text'])
                    elif bt == 'thinking':
                        thought = block.get('thinking', '')
                        if thought:
                            output.append(f'[Thinking] {thought[:500]}')
                    elif bt == 'tool_use':
                        name = block.get('name', '?')
                        inp = block.get('input', {})
                        output.append(f'[Tool: {name}]')
                        if isinstance(inp, dict):
                            cmd = inp.get('command', inp.get('content', inp.get('path', '')))
                            if cmd:
                                output.append(f'  > {str(cmd)[:300]}')
                    elif bt == 'tool_result':
                        content = block.get('content', '')
                        if isinstance(content, str) and content:
                            output.append(content[:500])
                        elif isinstance(content, list):
                            for sub in content:
                                if isinstance(sub, dict) and sub.get('text'):
                                    output.append(sub['text'][:500])
            elif ctype == 'result':
                output.append('')
                output.append('=== RESULT ===')
                output.append(chunk.get('result', ''))
                cost = chunk.get('total_cost_usd', 0)
                dur = chunk.get('duration_ms', 0)
                output.append(f'Cost: ${round(cost, 4)} | Duration: {dur // 1000}s')
        except (json.JSONDecodeError, Exception):
            output.append(line)
    return '\n'.join(output)

PORT = 8080
PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
ICT = timezone(timedelta(hours=7))
TRIGGER_COOLDOWN = 60
_last_trigger = 0

def now_ict():
    return datetime.now(ICT)

def fmt_ict():
    return now_ict().strftime('%Y-%m-%d %H:%M:%S ICT')

def mtime_ict(path):
    try:
        return datetime.fromtimestamp(os.path.getmtime(path), tz=ICT).strftime('%Y-%m-%d %H:%M:%S ICT')
    except:
        return ""

def mtime_epoch(path):
    try: return os.path.getmtime(path)
    except: return 0

def read_file(path, tail=None, head=None):
    try:
        with open(path, 'r', errors='replace') as f:
            c = f.read()
        if tail:
            lines = c.strip().split('\n')
            return '\n'.join(lines[-tail:])
        if head:
            lines = c.strip().split('\n')
            return '\n'.join(lines[:head])
        return c
    except Exception as ex:
        return f"[Error reading {path}: {ex}]"

def fsize(path):
    try: return os.path.getsize(path)
    except: return 0

def run_cmd(cmd, cwd=PROJECT, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, timeout=timeout).stdout.strip()
    except:
        return ""

def git_log(n=25):
    return run_cmd(['git', 'log', '--oneline', '--format=%h %s (%ar)', f'-{n}'])

def git_status():
    return run_cmd(['git', 'status', '--short']) or "Clean — no changes"

def git_diff_stat():
    return run_cmd(['git', 'diff', '--stat']) or "No uncommitted changes"

def git_last_diff():
    return run_cmd(['git', 'diff', 'HEAD~1', '--stat'])

def find_latest_log():
    """Find most recently modified log. Returns (path, age_seconds) or (None, None)."""
    logs = glob.glob(f"{CONTROL}/worker-logs/worker-*.log") + glob.glob(f"{CONTROL}/nightly-logs/cycle-*.log")
    if not logs:
        return None, None
    newest = max(logs, key=os.path.getmtime)
    age = time.time() - os.path.getmtime(newest)
    return newest, age

def list_logs(subdir, pattern, n=30):
    logs = sorted(glob.glob(f"{CONTROL}/{subdir}/{pattern}"), reverse=True)[:n]
    result = []
    for l in logs:
        name = os.path.basename(l)
        size = fsize(l)
        mt = mtime_ict(l)
        ep = mtime_epoch(l)
        dur = None
        m = re.search(r'(\d{8})-(\d{6})', name)
        if m:
            try:
                start = datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S')
                start = start.replace(tzinfo=timezone.utc).timestamp()
                dur = max(0, int(ep - start))
            except: pass
        result.append({
            "name": name, "path": l, "size": size, "time": mt,
            "duration_s": dur,
            "duration": f"{dur // 60}m {dur % 60}s" if dur and dur > 0 else None
        })
    return result

def list_reports(n=30):
    return [{"name": os.path.basename(r), "time": mtime_ict(r), "content": read_file(r)}
            for r in sorted(glob.glob(f"{CONTROL}/worker-logs/report-*.md"), reverse=True)[:n]]

def list_summaries(n=10):
    return [{"name": os.path.basename(s), "time": mtime_ict(s), "content": read_file(s)}
            for s in sorted(glob.glob(f"{CONTROL}/nightly-logs/summary-*.md"), reverse=True)[:n]]

def parse_plan(content):
    phases, cur = [], None
    for line in content.split('\n'):
        if line.startswith('## Phase'):
            if cur: phases.append(cur)
            cur = {"name": line.replace('## ', ''), "tasks": [], "done": 0, "total": 0}
        elif cur and line.strip().startswith('- ['):
            done = line.strip().startswith('- [x]')
            task = line.strip()[6:].strip()
            cur["tasks"].append({"task": task, "done": done})
            cur["total"] += 1
            if done: cur["done"] += 1
    if cur: phases.append(cur)
    return phases

def completion_log():
    content = read_file(f"{CONTROL}/build-plan.md")
    lines, capture = [], False
    for line in content.split('\n'):
        if '## Completion Log' in line: capture = True; continue
        if capture and line.strip() and not line.strip().startswith('<!--'):
            lines.append(line.strip())
    return lines

def worker_running():
    if not os.path.exists("/tmp/lever-worker.lock"): return False
    if time.time() - os.path.getmtime("/tmp/lever-worker.lock") > 3600: return False
    return True

def worker_elapsed():
    if not worker_running(): return None
    try: return int(time.time() - os.path.getmtime("/tmp/lever-worker.lock"))
    except: return None

def next_task():
    content = read_file(f"{CONTROL}/build-plan.md")
    for line in content.split('\n'):
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*P0\*\*', line):
            return line.strip().replace('- [ ] ', '')
    for line in content.split('\n'):
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*P1\*\*', line):
            return line.strip().replace('- [ ] ', '')
    return "All tasks complete"

def contract_health():
    contracts = [c for c in glob.glob(f"{PROJECT}/contracts/**/*.sol", recursive=True)
                 if '/interfaces/' not in c and '/libraries/' not in c]
    tests = glob.glob(f"{PROJECT}/test/*.t.sol") + glob.glob(f"{PROJECT}/test/**/*.t.sol", recursive=True)
    libs = glob.glob(f"{PROJECT}/contracts/libraries/*.sol")
    return {"contracts": len(contracts), "tests": len(tests), "libraries": len(libs)}

# --- API Endpoints ---

def api_status():
    bp = read_file(f"{CONTROL}/build-plan.md")
    log_path, log_age = find_latest_log()
    el = worker_elapsed()
    return {
        "now": fmt_ict(),
        "build_plan": parse_plan(bp),
        "completion_log": completion_log(),
        "known_issues": read_file(f"{CONTROL}/known-issues.md"),
        "git_log": git_log(), "git_status": git_status(),
        "git_diff": git_diff_stat(), "git_last_diff": git_last_diff(),
        "running": worker_running(),
        "elapsed_s": el,
        "elapsed": f"{el // 60}m {el % 60}s" if el else None,
        "next_task": next_task(),
        "active_log": os.path.basename(log_path) if log_path else None,
        "active_log_age": int(log_age) if log_age is not None else None,
        "worker_logs": list_logs("worker-logs", "worker-*.log"),
        "nightly_logs": list_logs("nightly-logs", "cycle-*.log"),
        "reports": list_reports(),
        "summaries": list_summaries(),
        "model_decisions": read_file(f"{CONTROL}/worker-logs/model-decisions.log", tail=40),
        "health": contract_health(),
    }

def api_live(n=200):
    log_path, log_age = find_latest_log()
    el = worker_elapsed()
    running = worker_running()
    if not log_path:
        # No logs at all — check if test-phase.log exists as fallback
        fallback = f"{PROJECT}/test-phase.log"
        if os.path.exists(fallback):
            return {
                "log": read_file(fallback, tail=n),
                "file": "test-phase.log (fallback)", "size": fsize(fallback),
                "running": running, "stale": True,
                "elapsed": None, "next_task": next_task(),
            }
        return {
            "log": "No log files found yet.\n\nWorker logs appear in: control-plane/worker-logs/\nNightly logs appear in: control-plane/nightly-logs/\n\nTrigger a worker run with the Run button above.",
            "file": None, "size": 0, "running": running, "stale": True,
            "elapsed": None, "next_task": next_task(),
        }
    return {
        "log": parse_stream_json(read_file(log_path, tail=n)),
        "file": os.path.basename(log_path),
        "size": fsize(log_path),
        "running": running,
        "stale": log_age is not None and log_age > 300,
        "elapsed_s": el,
        "elapsed": f"{el // 60}m {el % 60}s" if el else None,
        "next_task": next_task(),
    }

def api_log(path):
    if not path:
        return "[No path specified]"
    real = os.path.realpath(path)
    allowed_dirs = [
        os.path.realpath(CONTROL),
        os.path.realpath(f"{PROJECT}/test-phase.log"),
    ]
    ok = any(real.startswith(d) or real == d for d in allowed_dirs)
    if not ok:
        return f"[Access denied: {path} not in allowed directories]"
    if not os.path.exists(real):
        return f"[File not found: {path}]"
    content = read_file(path)
    if path.endswith(".log"):
        return parse_stream_json(content)
    return content

def api_trigger():
    global _last_trigger
    now = time.time()
    if now - _last_trigger < TRIGGER_COOLDOWN:
        return {"ok": False, "msg": f"Cooldown — wait {int(TRIGGER_COOLDOWN - (now - _last_trigger))}s"}
    if worker_running():
        return {"ok": False, "msg": "Worker already running."}
    try:
        subprocess.Popen(
            ['su', '-', 'lever', '-c', f'{CONTROL}/proactive-worker.sh'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        _last_trigger = now
        return {"ok": True, "msg": "Worker triggered. Watch the Live tab."}
    except Exception as e:
        return {"ok": False, "msg": str(e)}

def api_debug():
    log_path, log_age = find_latest_log()
    wlogs = glob.glob(f"{CONTROL}/worker-logs/worker-*.log")
    nlogs = glob.glob(f"{CONTROL}/nightly-logs/cycle-*.log")
    return {
        "now": fmt_ict(),
        "project_dir": PROJECT,
        "control_dir": CONTROL,
        "project_exists": os.path.isdir(PROJECT),
        "control_exists": os.path.isdir(CONTROL),
        "worker_log_count": len(wlogs),
        "nightly_log_count": len(nlogs),
        "worker_logs": sorted([os.path.basename(l) for l in wlogs], reverse=True)[:5],
        "nightly_logs": sorted([os.path.basename(l) for l in nlogs], reverse=True)[:5],
        "latest_log": os.path.basename(log_path) if log_path else None,
        "latest_log_age_s": int(log_age) if log_age is not None else None,
        "latest_log_size": fsize(log_path) if log_path else 0,
        "lock_exists": os.path.exists("/tmp/lever-worker.lock"),
        "build_plan_exists": os.path.exists(f"{CONTROL}/build-plan.md"),
        "persona_exists": os.path.exists(f"{CONTROL}/agent-persona.md"),
        "known_issues_exists": os.path.exists(f"{CONTROL}/known-issues.md"),
        "dashboard_pid": os.getpid(),
    }


# === HTML ===

HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Timmy — LEVER</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>&#x1F916;</text></svg>">
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;700&family=Instrument+Sans:wght@400;500;600;700&display=swap');
:root{
--bg:#050509;--s1:#0b0b14;--s2:#111120;--s3:#1a1a2e;
--bdr:#222240;--bdr2:#2d2d50;
--tx:#b0b0c8;--dim:#55557a;--wh:#e8e8f4;
--ac:#00e8b4;--acd:rgba(0,232,180,.1);--acb:rgba(0,232,180,.25);
--pp:#8060ff;--ppd:rgba(128,96,255,.1);
--rd:#ff4868;--rdd:rgba(255,72,104,.1);
--yl:#ffb830;--yld:rgba(255,184,48,.1);
--bl:#4898ff;--bld:rgba(72,152,255,.1);
--r:10px}
*{margin:0;padding:0;box-sizing:border-box}
html{font-size:14px}
body{background:var(--bg);color:var(--tx);font-family:'Instrument Sans',sans-serif;-webkit-font-smoothing:antialiased;padding-bottom:60px}
.mono{font-family:'JetBrains Mono',monospace}

/* Layout */
.app{max-width:1440px;margin:0 auto;padding:16px 16px 80px}

/* Header */
.hdr{display:flex;align-items:center;justify-content:space-between;padding:10px 0 16px;border-bottom:1px solid var(--bdr);margin-bottom:14px;flex-wrap:wrap;gap:8px}
.logo{display:flex;align-items:center;gap:10px}
.logo-icon{width:34px;height:34px;border-radius:9px;background:linear-gradient(135deg,var(--ac),var(--pp));display:grid;place-items:center;font:700 16px 'JetBrains Mono',monospace;color:var(--bg)}
.logo-title h1{font-size:16px;font-weight:700;color:var(--wh);line-height:1}
.logo-title span{font-size:10px;color:var(--dim);font-family:'JetBrains Mono',monospace}
.hdr-r{display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.pill{display:flex;align-items:center;gap:5px;padding:4px 10px;border-radius:99px;font:500 10px 'JetBrains Mono',monospace;border:1px solid var(--bdr);background:var(--s1);color:var(--dim)}
.dot{width:6px;height:6px;border-radius:50%}
.dot-on{background:var(--ac);box-shadow:0 0 8px var(--ac);animation:pulse 1.5s infinite}
.dot-off{background:var(--dim)}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
.btn{padding:4px 10px;border-radius:6px;border:1px solid var(--bdr);background:var(--s1);color:var(--dim);cursor:pointer;font:500 10px 'JetBrains Mono',monospace;transition:.15s;white-space:nowrap}
.btn:hover{border-color:var(--ac);color:var(--ac)}.btn:active{transform:scale(.96)}
.btn-go{border-color:var(--acb);color:var(--ac);background:var(--acd)}
.clock{font:400 10px 'JetBrains Mono',monospace;color:var(--dim);text-align:right;line-height:1.4}

/* Tabs */
.tabs{display:flex;gap:1px;overflow-x:auto;-webkit-overflow-scrolling:touch;margin-bottom:14px;border-bottom:1px solid var(--bdr);scrollbar-width:none}
.tabs::-webkit-scrollbar{display:none}
.tab{padding:7px 12px;cursor:pointer;white-space:nowrap;font:600 11px 'Instrument Sans',sans-serif;color:var(--dim);background:none;border:none;border-bottom:2px solid transparent;transition:.15s}
.tab:hover{color:var(--tx)}.tab.on{color:var(--ac);border-bottom-color:var(--ac)}
.view{display:none}.view.on{display:block}

/* Mobile nav */
.mnav{display:none;position:fixed;bottom:0;left:0;right:0;background:var(--s1);border-top:1px solid var(--bdr);z-index:100;padding:4px 0 env(safe-area-inset-bottom,4px)}
.mnav-row{display:flex;justify-content:space-around;max-width:500px;margin:0 auto}
.mnav button{background:none;border:none;color:var(--dim);font:500 9px 'Instrument Sans',sans-serif;padding:6px 4px;cursor:pointer;display:flex;flex-direction:column;align-items:center;gap:2px;min-width:44px}
.mnav button.on{color:var(--ac)}
.mnav button em{font-style:normal;font-size:16px;line-height:1}
@media(max-width:768px){.tabs{display:none}.mnav{display:block}.app{padding:12px 12px 90px}}

/* Cards */
.card{background:var(--s1);border:1px solid var(--bdr);border-radius:var(--r);padding:14px;margin-bottom:10px}
.card-flush{padding:0}
.card-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}
.card-label{font:700 10px 'JetBrains Mono',monospace;text-transform:uppercase;letter-spacing:1px;color:var(--dim)}
.badge{font:500 9px 'JetBrains Mono',monospace;padding:2px 6px;border-radius:99px}
.b-ac{background:var(--acd);color:var(--ac)}.b-rd{background:var(--rdd);color:var(--rd)}.b-yl{background:var(--yld);color:var(--yl)}.b-pp{background:var(--ppd);color:var(--pp)}.b-bl{background:var(--bld);color:var(--bl)}

/* Grid */
.g2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.g4{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
@media(max-width:768px){.g2,.g4{grid-template-columns:1fr 1fr}}
@media(max-width:400px){.g2,.g4{grid-template-columns:1fr}}

/* Stats */
.stat-n{font:700 26px 'JetBrains Mono',monospace;color:var(--wh);line-height:1}
.stat-l{font:500 9px 'JetBrains Mono',monospace;color:var(--dim);text-transform:uppercase;letter-spacing:.5px;margin-top:4px}
.pbar{height:5px;background:var(--s3);border-radius:3px;margin:8px 0;overflow:hidden}
.pfill{height:100%;border-radius:3px;background:linear-gradient(90deg,var(--ac),var(--pp));transition:width .4s}

/* Tasks */
.task{display:flex;gap:8px;padding:4px 0;font-size:12px;line-height:1.5;align-items:flex-start}
.task-ck{width:15px;height:15px;border-radius:4px;flex-shrink:0;border:1.5px solid var(--bdr2);display:grid;place-items:center;font-size:9px;margin-top:2px}
.task-ck.done{background:var(--ac);border-color:var(--ac);color:var(--bg)}
.task-tx{color:var(--tx)}.task-tx.done{color:var(--dim);text-decoration:line-through}

/* Terminal */
.term{background:#020208;border:1px solid var(--bdr);border-radius:8px;overflow:hidden}
.term-bar{display:flex;justify-content:space-between;align-items:center;padding:7px 12px;background:var(--s2);border-bottom:1px solid var(--bdr)}
.term-dots{display:flex;gap:5px}
.term-dot{width:8px;height:8px;border-radius:50%}
.dot-r{background:#ff5f57}.dot-y{background:#febc2e}.dot-g{background:#28c840}
.term-title{font:500 10px 'JetBrains Mono',monospace;color:var(--dim)}
.term-body{padding:12px;max-height:72vh;overflow-y:auto;overflow-x:hidden;font:400 11px/1.7 'JetBrains Mono',monospace;color:#9898b0;white-space:pre-wrap;word-break:break-word;scroll-behavior:smooth}
.term-body .c-err{color:var(--rd)}.term-body .c-warn{color:var(--yl)}.term-body .c-ok{color:var(--ac)}.term-body .c-head{color:var(--pp);font-weight:600}.term-body .c-info{color:var(--bl)}

/* Log list items */
.log-item{border-bottom:1px solid var(--bdr)}
.log-item:last-child{border-bottom:none}
.log-hdr{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;cursor:pointer;transition:.1s}
.log-hdr:hover{background:var(--s2)}
.log-name{font:600 12px 'Instrument Sans',sans-serif;color:var(--wh)}
.log-meta{display:flex;gap:6px;align-items:center}
.log-time{font:400 10px 'JetBrains Mono',monospace;color:var(--dim)}
.log-dur{font:500 10px 'JetBrains Mono',monospace;color:var(--pp)}
.log-chev{color:var(--dim);font-size:10px;transition:transform .2s;margin-left:4px}
.log-chev.open{transform:rotate(90deg)}
.log-body{display:none;padding:0 14px 14px}
.log-body.open{display:block}

/* Issues */
.issue{padding:8px 12px;border-bottom:1px solid var(--bdr);font-size:12px;line-height:1.6}
.issue:last-child{border-bottom:none}
.issue-crit{border-left:3px solid var(--rd)}.issue-med{border-left:3px solid var(--yl)}.issue-low{border-left:3px solid var(--bl)}.issue-done{opacity:.4}

/* Banner */
.banner{border-radius:var(--r);padding:12px 16px;margin-bottom:14px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px}
.banner-active{background:var(--acd);border:1px solid var(--acb)}
.banner-idle{background:var(--s1);border:1px solid var(--bdr)}
.banner h3{font:600 13px 'Instrument Sans',sans-serif;margin:0}
.banner-active h3{color:var(--ac)}.banner-idle h3{color:var(--dim)}
.banner p{font:400 11px 'JetBrains Mono',monospace;margin:2px 0 0}
.banner-active p{color:var(--tx)}.banner-idle p{color:var(--dim)}
.banner .timer{font:700 14px 'JetBrains Mono',monospace;color:var(--ac)}

/* Search */
.search{width:100%;padding:8px 12px;border-radius:8px;border:1px solid var(--bdr);background:var(--s2);color:var(--tx);font:400 12px 'Instrument Sans',sans-serif;margin-bottom:12px;outline:none}
.search:focus{border-color:var(--ac)}.search::placeholder{color:var(--dim)}

/* Toast */
.toast{position:fixed;top:16px;right:16px;background:var(--ac);color:var(--bg);padding:10px 16px;border-radius:8px;font:600 12px 'Instrument Sans',sans-serif;z-index:999;transform:translateY(-60px);opacity:0;transition:.3s;pointer-events:none}
.toast.show{transform:translateY(0);opacity:1}

/* Status bar */
.status-bar{position:fixed;bottom:0;left:0;right:0;background:var(--s1);border-top:1px solid var(--bdr);padding:3px 12px;font:400 9px 'JetBrains Mono',monospace;color:var(--dim);display:flex;justify-content:space-between;z-index:50}
@media(max-width:768px){.status-bar{bottom:52px}}

/* Loading */
.loading{color:var(--dim);padding:20px;text-align:center;font:400 12px 'JetBrains Mono',monospace}
.spin{display:inline-block;animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}

::-webkit-scrollbar{width:4px;height:4px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:var(--s3);border-radius:2px}
</style>
</head>
<body>
<div id="toast" class="toast"></div>

<div class="app">
<div class="hdr">
<div class="logo"><div class="logo-icon">T</div><div class="logo-title"><h1>Timmy</h1><span>LEVER Protocol</span></div></div>
<div class="hdr-r">
<div class="pill" id="status-pill"><div class="dot dot-off"></div><span>—</span></div>
<div class="clock" id="clock"></div>
<button class="btn btn-go" onclick="triggerRun()">&#9654; Run</button>
<button class="btn" onclick="refresh()">&#8635;</button>
</div>
</div>

<div class="tabs">
<button class="tab on" data-v="v-live">&#9889; Live</button>
<button class="tab" data-v="v-overview">&#9632; Overview</button>
<button class="tab" data-v="v-worker">&#128295; Worker</button>
<button class="tab" data-v="v-nightly">&#127769; Nightly</button>
<button class="tab" data-v="v-issues">&#9888; Issues</button>
<button class="tab" data-v="v-git">&#128200; Git</button>
<button class="tab" data-v="v-models">&#129504; Models</button>
</div>

<!-- LIVE -->
<div id="v-live" class="view on">
<div id="live-banner"></div>
<div class="term">
<div class="term-bar"><div class="term-dots"><div class="term-dot dot-r"></div><div class="term-dot dot-y"></div><div class="term-dot dot-g"></div></div><div class="term-title" id="live-title">Connecting...</div></div>
<div class="term-body" id="live-term"><span class="c-info">Loading live feed...</span></div>
</div>
<div style="margin-top:6px;display:flex;justify-content:space-between;align-items:center">
<span class="mono" style="font-size:10px;color:var(--dim)" id="live-meta"></span>
<label class="mono" style="font-size:10px;color:var(--dim);cursor:pointer"><input type="checkbox" id="autoscroll" checked> Auto-scroll</label>
</div>
</div>

<!-- OVERVIEW -->
<div id="v-overview" class="view">
<div id="ov-banner"></div>
<div class="g4" id="ov-stats"></div>
<div id="ov-phases" style="margin-top:10px"></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Shift Reports</span></div><div id="ov-reports"></div></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Completion Timeline</span></div><div id="ov-timeline" class="mono" style="font-size:11px;line-height:1.8;padding:0 4px"></div></div>
</div>

<!-- WORKER -->
<div id="v-worker" class="view">
<input class="search" placeholder="Filter worker logs..." oninput="filterItems('worker-list',this.value)">
<div id="worker-list"></div>
</div>

<!-- NIGHTLY -->
<div id="v-nightly" class="view">
<input class="search" placeholder="Filter nightly logs..." oninput="filterItems('nightly-list',this.value)">
<div id="nightly-list"></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Summaries</span></div><div id="nightly-sums"></div></div>
</div>

<!-- ISSUES -->
<div id="v-issues" class="view"><div class="card card-flush" id="issues-box"></div></div>

<!-- GIT -->
<div id="v-git" class="view">
<div class="g2">
<div class="card"><div class="card-head"><span class="card-label">Commits</span></div><div class="term"><div class="term-body" id="git-log" style="max-height:400px"></div></div></div>
<div class="card"><div class="card-head"><span class="card-label">Working Tree</span></div><div class="term"><div class="term-body" id="git-st" style="max-height:400px"></div></div></div>
</div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Last Commit Changes</span></div><div class="term"><div class="term-body" id="git-d1" style="max-height:300px"></div></div></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Uncommitted Diff</span></div><div class="term"><div class="term-body" id="git-d2" style="max-height:300px"></div></div></div>
</div>

<!-- MODELS -->
<div id="v-models" class="view">
<div class="card"><div class="card-head"><span class="card-label">Model Router</span></div><div class="term"><div class="term-body" id="model-log" style="max-height:500px"></div></div></div>
</div>
</div>

<!-- Mobile nav -->
<nav class="mnav"><div class="mnav-row">
<button class="on" data-v="v-live"><em>&#9889;</em>Live</button>
<button data-v="v-overview"><em>&#9632;</em>Plan</button>
<button data-v="v-worker"><em>&#128295;</em>Work</button>
<button data-v="v-issues"><em>&#9888;</em>Issues</button>
<button data-v="v-git"><em>&#128200;</em>Git</button>
</div></nav>

<div class="status-bar"><span id="sb-left">—</span><span id="sb-right">—</span></div>

<script>
// ========== State ==========
let DATA = {};
let liveTimer = null;
let prevLogLen = -1;
let wasRunning = false;
let lastRefresh = 0;

// ========== Utils ==========
function esc(s) { return s ? s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') : '' }

function colorize(text) {
  if (!text) return '';
  return text.split('\n').map(function(line) {
    var cls = '';
    if (/error|fail|FAIL|panic|revert|CRITICAL/i.test(line)) cls = 'c-err';
    else if (/warn|WARN|WARNING|MEDIUM/i.test(line)) cls = 'c-warn';
    else if (/PASS|pass|success|FINISHED|Done|FIXED|COMPLETE/i.test(line)) cls = 'c-ok';
    else if (/^={3,}|^#{1,3} |PHASE|STEP:|Phase |---/i.test(line)) cls = 'c-head';
    else if (/INFO|info|Note/i.test(line)) cls = 'c-info';
    return cls ? '<span class="' + cls + '">' + esc(line) + '</span>' : esc(line);
  }).join('\n');
}

function toast(msg) {
  var t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(function() { t.classList.remove('show') }, 3500);
}

function statusBar(left, right) {
  document.getElementById('sb-left').textContent = left || '';
  document.getElementById('sb-right').textContent = right || '';
}

// ========== Clock ==========
function tickClock() {
  var n = new Date();
  var utc = n.getTime() + n.getTimezoneOffset() * 60000;
  var ict = new Date(utc + 7 * 3600000);
  var time = ict.toLocaleTimeString('en-GB');
  var date = ict.toLocaleDateString('en-GB', {weekday:'short', day:'numeric', month:'short'});
  document.getElementById('clock').innerHTML = time + ' ICT<br>' + date;
}
tickClock();
setInterval(tickClock, 1000);

// ========== Tabs ==========
function switchView(id) {
  document.querySelectorAll('.tab,.mnav button').forEach(function(x) { x.classList.remove('on') });
  document.querySelectorAll('.view').forEach(function(x) { x.classList.remove('on') });
  document.querySelectorAll('[data-v="' + id + '"]').forEach(function(x) { x.classList.add('on') });
  var el = document.getElementById(id);
  if (el) el.classList.add('on');
  if (id === 'v-live') startLive(); else stopLive();
}

document.querySelectorAll('.tab,.mnav button').forEach(function(t) {
  t.addEventListener('click', function() { switchView(t.getAttribute('data-v')) });
});

// ========== Live Feed ==========
function startLive() {
  if (liveTimer) return;
  fetchLive();
  liveTimer = setInterval(fetchLive, 3000);
}

function stopLive() {
  if (liveTimer) { clearInterval(liveTimer); liveTimer = null; }
}

function fetchLive() {
  fetch('/api/live?n=250')
    .then(function(r) { return r.json() })
    .then(function(d) {
      var el = document.getElementById('live-term');
      var newLen = d.log ? d.log.length : 0;

      // Only re-render if content changed
      if (newLen !== prevLogLen || prevLogLen === -1) {
        el.innerHTML = colorize(d.log || 'Claude Code is thinking... output appears when it starts writing.');
        prevLogLen = newLen;
        if (document.getElementById('autoscroll').checked) {
          el.scrollTop = el.scrollHeight;
        }
      }

      // Title
      var title = d.file || 'No active log';
      if (d.stale && d.file) title += ' (stale)';
      document.getElementById('live-title').textContent = title;

      // Meta
      var meta = [];
      if (d.file) meta.push(d.file);
      if (d.size) meta.push((d.size / 1024).toFixed(1) + 'KB');
      if (d.elapsed) meta.push(d.elapsed);
      document.getElementById('live-meta').textContent = meta.join(' · ') || '—';

      // Banner
      var ban = document.getElementById('live-banner');
      if (d.running) {
        ban.innerHTML = '<div class="banner banner-active"><div><h3>&#9889; Working</h3><p>' + esc(d.next_task || '—') + '</p></div><div class="timer">' + esc(d.elapsed || '0m 0s') + '</div></div>';
      } else {
        ban.innerHTML = '<div class="banner banner-idle"><div><h3>Idle</h3><p>Next: ' + esc(d.next_task || '—') + '</p></div></div>';
      }

      updateStatusPill(d.running, d.elapsed);

      // Completion toast
      if (!d.running && wasRunning) toast('Worker shift complete!');
      wasRunning = d.running;

      statusBar(d.running ? 'Worker active' : 'Worker idle', 'Live feed OK');
    })
    .catch(function(err) {
      statusBar('Live feed error', err.message || 'fetch failed');
    });
}

startLive();

function updateStatusPill(running, elapsed) {
  var p = document.getElementById('status-pill');
  if (running) {
    p.innerHTML = '<div class="dot dot-on"></div><span>' + (elapsed || 'Active') + '</span>';
  } else {
    p.innerHTML = '<div class="dot dot-off"></div><span>Idle</span>';
  }
}

// ========== Trigger ==========
function triggerRun() {
  if (!confirm('Start a worker shift now?')) return;
  fetch('/api/trigger')
    .then(function(r) { return r.json() })
    .then(function(d) { toast(d.msg) })
    .catch(function() { toast('Failed to trigger') });
}

// ========== Lazy Log Loading ==========
var loadedLogs = {};

function lazyLoad(path, elemId) {
  if (loadedLogs[elemId]) return;
  var el = document.getElementById(elemId);
  if (!el) return;
  el.innerHTML = '<span class="c-info"><span class="spin">&#8635;</span> Loading full log...</span>';
  fetch('/api/log?path=' + encodeURIComponent(path))
    .then(function(r) { return r.text() })
    .then(function(text) {
      el.innerHTML = colorize(text);
      loadedLogs[elemId] = true;
    })
    .catch(function(err) {
      el.innerHTML = '<span class="c-err">Failed to load: ' + esc(err.message) + '</span>';
    });
}

function toggleLog(itemEl) {
  var body = itemEl.querySelector('.log-body');
  var chev = itemEl.querySelector('.log-chev');
  var path = itemEl.getAttribute('data-path');
  var tid = itemEl.getAttribute('data-tid');

  if (body.classList.contains('open')) {
    body.classList.remove('open');
    if (chev) chev.classList.remove('open');
  } else {
    body.classList.add('open');
    if (chev) chev.classList.add('open');
    if (path && tid) lazyLoad(path, tid);
  }
}

// ========== Search ==========
function filterItems(containerId, query) {
  var el = document.getElementById(containerId);
  if (!el) return;
  var q = query.toLowerCase();
  el.querySelectorAll('.log-item').forEach(function(item) {
    var name = item.querySelector('.log-name');
    var match = !q || (name && name.textContent.toLowerCase().indexOf(q) >= 0);
    item.style.display = match ? '' : 'none';
  });
}

// ========== Render: Overview ==========
function renderOverview(d) {
  var done = 0, total = 0;
  (d.build_plan || []).forEach(function(p) { done += p.done; total += p.total });
  var pct = total ? Math.round(done / total * 100) : 0;
  var issues = (d.known_issues || '').match(/-\s*\[\s*\]/g);
  var openIssues = issues ? issues.length : 0;
  var h = d.health || {};

  document.getElementById('ov-stats').innerHTML =
    '<div class="card"><div class="stat-n">' + pct + '%</div><div class="stat-l">Build Progress</div><div class="pbar"><div class="pfill" style="width:' + pct + '%"></div></div></div>' +
    '<div class="card"><div class="stat-n">' + openIssues + '</div><div class="stat-l">Open Issues</div></div>' +
    '<div class="card"><div class="stat-n">' + (h.contracts || 0) + '</div><div class="stat-l">Contracts</div></div>' +
    '<div class="card"><div class="stat-n">' + (h.tests || 0) + '</div><div class="stat-l">Test Files</div></div>';

  // Banner
  var ban = document.getElementById('ov-banner');
  if (d.running) {
    ban.innerHTML = '<div class="banner banner-active"><div><h3>&#9889; Worker Active</h3><p>' + esc(d.next_task) + '</p></div><div class="timer">' + esc(d.elapsed || '—') + '</div></div>';
  } else {
    ban.innerHTML = '<div class="banner banner-idle"><div><h3>Next Task</h3><p>' + esc(d.next_task) + '</p></div></div>';
  }

  // Phases
  var ph = '';
  (d.build_plan || []).forEach(function(p, pi) {
    var pp = p.total ? Math.round(p.done / p.total * 100) : 0;
    var isCurrent = p.done < p.total;
    // Check if previous phases are all done
    if (pi > 0) {
      for (var k = 0; k < pi; k++) {
        if (d.build_plan[k].done < d.build_plan[k].total) { isCurrent = false; break }
      }
    }
    var tasks = p.tasks.map(function(t) {
      return '<div class="task"><div class="task-ck' + (t.done ? ' done' : '') + '">' + (t.done ? '\u2713' : '') + '</div><span class="task-tx' + (t.done ? ' done' : '') + '">' + esc(t.task) + '</span></div>';
    }).join('');
    ph += '<div class="card" style="' + (isCurrent ? 'border-color:var(--acb)' : '') + '"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font:600 13px Instrument Sans;color:var(--wh)">' + esc(p.name) + (isCurrent ? ' <span class="badge b-ac">CURRENT</span>' : '') + '</span><span class="mono" style="font-size:11px;color:var(--ac)">' + p.done + '/' + p.total + '</span></div><div class="pbar"><div class="pfill" style="width:' + pp + '%"></div></div>' + tasks + '</div>';
  });
  document.getElementById('ov-phases').innerHTML = ph;

  // Reports
  var rh = '';
  (d.reports || []).forEach(function(r, i) {
    var cid = 'rpt-' + i;
    rh += '<div class="log-item" data-tid="' + cid + '" onclick="toggleLog(this)"><div class="log-hdr"><span class="log-name">' + esc(r.name) + '</span><div class="log-meta"><span class="log-time">' + esc(r.time) + '</span><span class="log-chev">&#9654;</span></div></div><div class="log-body"><div class="term"><div class="term-body" id="' + cid + '" style="max-height:350px">' + colorize(r.content) + '</div></div></div></div>';
  });
  document.getElementById('ov-reports').innerHTML = rh || '<div class="loading">No reports yet</div>';

  // Timeline
  var tl = (d.completion_log || []).map(function(l) { return esc(l) }).join('\n');
  document.getElementById('ov-timeline').innerHTML = tl || '<span style="color:var(--dim)">No entries yet</span>';
}

// ========== Render: Log Lists ==========
function renderLogList(containerId, logs, prefix) {
  var html = '';
  (logs || []).forEach(function(l, i) {
    var tid = prefix + '-' + i;
    html += '<div class="log-item" data-path="' + esc(l.path) + '" data-tid="' + tid + '" onclick="toggleLog(this)">' +
      '<div class="log-hdr"><div><span class="log-name">' + esc(l.name) + '</span></div>' +
      '<div class="log-meta">' +
      (l.duration ? '<span class="log-dur">' + esc(l.duration) + '</span>' : '') +
      '<span class="log-time">' + esc(l.time) + '</span>' +
      '<span class="badge b-bl">' + (l.size / 1024).toFixed(1) + 'KB</span>' +
      '<span class="log-chev">&#9654;</span></div></div>' +
      '<div class="log-body"><div class="term"><div class="term-body" id="' + tid + '" style="max-height:60vh"><span class="c-info">Click to load...</span></div></div></div></div>';
  });
  document.getElementById(containerId).innerHTML = html || '<div class="loading">No logs yet</div>';
}

// ========== Render: Issues ==========
function renderIssues(d) {
  var lines = (d.known_issues || '').split('\n');
  var html = '<div style="padding:14px"><div class="card-head"><span class="card-label">Known Issues</span></div></div>';
  var sev = '';
  lines.forEach(function(line) {
    if (/^## CRITICAL/i.test(line)) sev = 'issue-crit';
    else if (/^## MEDIUM/i.test(line)) sev = 'issue-med';
    else if (/^## LOW/i.test(line)) sev = 'issue-low';
    else if (/^## AUDIT/i.test(line)) sev = '';
    else if (line.trim().indexOf('- [') === 0) {
      var isDone = line.indexOf('[x]') >= 0;
      var text = line.replace(/-\s*\[.\]\s*/, '');
      html += '<div class="issue ' + sev + (isDone ? ' issue-done' : '') + '">' + (isDone ? '\u2705' : '\u2b1c') + ' ' + esc(text) + '</div>';
    }
  });
  document.getElementById('issues-box').innerHTML = html;
}

// ========== Render: Models ==========
function renderModels(d) {
  var c = esc(d.model_decisions || 'No model decisions logged yet.');
  c = c.replace(/opus/gi, '<span class="badge b-pp">opus</span>');
  c = c.replace(/sonnet/gi, '<span class="badge b-ac">sonnet</span>');
  document.getElementById('model-log').innerHTML = c;
}

// ========== Main Render ==========
function render(d) {
  DATA = d;
  renderOverview(d);
  renderLogList('worker-list', d.worker_logs, 'wl');
  renderLogList('nightly-list', d.nightly_logs, 'nl');

  // Summaries
  var sh = '';
  (d.summaries || []).forEach(function(s, i) {
    var cid = 'sum-' + i;
    sh += '<div class="log-item" data-tid="' + cid + '" onclick="toggleLog(this)"><div class="log-hdr"><span class="log-name">' + esc(s.name) + '</span><div class="log-meta"><span class="log-time">' + esc(s.time) + '</span><span class="log-chev">&#9654;</span></div></div><div class="log-body"><div class="term"><div class="term-body" id="' + cid + '" style="max-height:300px">' + colorize(s.content) + '</div></div></div></div>';
  });
  document.getElementById('nightly-sums').innerHTML = sh || '<div class="loading">No summaries yet</div>';

  renderIssues(d);
  document.getElementById('git-log').innerHTML = colorize(d.git_log || '');
  document.getElementById('git-st').innerHTML = colorize(d.git_status || 'Clean');
  document.getElementById('git-d1').innerHTML = colorize(d.git_last_diff || 'No data');
  document.getElementById('git-d2').innerHTML = colorize(d.git_diff || 'Clean');
  renderModels(d);
  updateStatusPill(d.running, d.elapsed);
  lastRefresh = Date.now();
}

function refresh() {
  statusBar('Refreshing...', '');
  // Reset lazy-loaded state so logs can be re-fetched
  loadedLogs = {};
  fetch('/api/status')
    .then(function(r) { return r.json() })
    .then(function(d) { render(d); statusBar('Refreshed', d.now) })
    .catch(function(err) { statusBar('Refresh failed', err.message) });
}

// Initial load + periodic refresh
refresh();
setInterval(function() {
  fetch('/api/status')
    .then(function(r) { return r.json() })
    .then(function(d) {
      render(d);
      var ago = Math.round((Date.now() - lastRefresh) / 1000);
      statusBar(d.running ? 'Worker active' : 'Idle', 'Updated ' + ago + 's ago · ' + d.now);
    })
    .catch(function() {});
}, 30000);

// Update "last refreshed" display every 5s
setInterval(function() {
  if (lastRefresh) {
    var ago = Math.round((Date.now() - lastRefresh) / 1000);
    var right = document.getElementById('sb-right').textContent;
    if (right.indexOf('Updated') >= 0) {
      document.getElementById('sb-right').textContent = right.replace(/Updated \d+s/, 'Updated ' + ago + 's');
    }
  }
}, 5000);
</script>
</body>
</html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        try:
            p = urllib.parse.urlparse(self.path)
            q = urllib.parse.parse_qs(p.query)
            if p.path == '/api/status':
                self._json(api_status())
            elif p.path == '/api/live':
                self._json(api_live(int(q.get('n', [200])[0])))
            elif p.path == '/api/log':
                self._text(api_log(q.get('path', [''])[0]))
            elif p.path == '/api/trigger':
                self._json(api_trigger())
            elif p.path == '/api/debug':
                self._json(api_debug())
            else:
                self._html(HTML)
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e), "trace": traceback.format_exc()}).encode())

    def _json(self, d):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(d).encode())

    def _text(self, t):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(t.encode())

    def _html(self, h):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(h.encode())


if __name__ == '__main__':
    print(f"Timmy Dashboard v3 — http://0.0.0.0:{PORT}")
    print(f"All times ICT (UTC+7) | Debug: http://0.0.0.0:{PORT}/api/debug")
    http.server.HTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
