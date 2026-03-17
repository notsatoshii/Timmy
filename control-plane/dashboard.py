#!/usr/bin/env python3
"""
LEVER Protocol — Timmy Dashboard v5
Supports: parallel dispatcher lanes, old worker logs, execution plan, live progress.
All timestamps ICT (UTC+7). Run: python3 dashboard.py — Access: http://SERVER_IP:8080
"""

import http.server, json, os, subprocess, glob, urllib.parse, re, time, traceback, logging
from datetime import datetime, timezone, timedelta

PORT = 8080
PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
ICT = timezone(timedelta(hours=7))
TRIGGER_COOLDOWN = 60
_last_trigger = 0


# ── Helpers ─────────────────────────────────────────────────────────────────

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
    except:
        return ""

def fsize(path):
    try: return os.path.getsize(path)
    except: return 0

def run_cmd(cmd, cwd=PROJECT, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, timeout=timeout).stdout.strip()
    except:
        return ""


# ── Log parsing ─────────────────────────────────────────────────────────────

def parse_stream_json(raw_text):
    """Parse Claude Code stream-json log into readable text."""
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
                output.append(f'[Session started — model: {chunk.get("model", "?")}]')
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
                output.append('\n=== RESULT ===')
                output.append(chunk.get('result', ''))
                cost = chunk.get('total_cost_usd', 0)
                dur = chunk.get('duration_ms', 0)
                output.append(f'Cost: ${round(cost, 4)} | Duration: {dur // 1000}s')
        except:
            output.append(line)
    return '\n'.join(output)


# ── Dispatcher-aware state ──────────────────────────────────────────────────

def get_dispatcher_running():
    """Check if dispatcher service is active."""
    try:
        r = subprocess.run(['systemctl', 'is-active', 'lever-dispatcher'],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() == 'active'
    except:
        return False

def get_running_agents():
    """Get currently running agent tasks from lock files."""
    agents = []
    for lock in glob.glob(f"{CONTROL}/locks/running-*"):
        try:
            meta = json.loads(open(lock).read())
            meta['age_s'] = int(time.time() - os.path.getmtime(lock))
            agents.append(meta)
        except:
            tid = os.path.basename(lock).replace('running-', '')
            agents.append({'task_id': tid, 'lane': '?', 'age_s': 0})
    return agents

def get_completed_tasks():
    """Get completed task IDs from done- lock files."""
    done = []
    for f in glob.glob(f"{CONTROL}/locks/done-*"):
        tid = os.path.basename(f).replace('done-', '')
        done.append({'task_id': tid, 'time': mtime_ict(f)})
    return done

def get_failed_tasks():
    """Get failed task IDs and reasons."""
    failed = []
    for f in glob.glob(f"{CONTROL}/locks/fail-*"):
        tid = os.path.basename(f).replace('fail-', '')
        reason = read_file(f, head=3).strip()
        failed.append({'task_id': tid, 'reason': reason, 'time': mtime_ict(f)})
    return failed

def get_execution_plan():
    """Read the planner's cached execution plan."""
    path = f"{CONTROL}/locks/current-plan.json"
    try:
        return json.loads(open(path).read())
    except:
        return None

def worker_running():
    """Check if any build agent is actively working."""
    # Dispatcher agents
    if glob.glob(f"{CONTROL}/locks/running-*"):
        return True
    # Old worker lock
    if os.path.exists("/tmp/lever-worker.lock"):
        if time.time() - os.path.getmtime("/tmp/lever-worker.lock") < 3600:
            return True
    return False

def worker_elapsed():
    if not worker_running():
        return None
    # Dispatcher: time since oldest running agent started
    running = glob.glob(f"{CONTROL}/locks/running-*")
    if running:
        try:
            oldest = min(os.path.getmtime(l) for l in running)
            return int(time.time() - oldest)
        except:
            pass
    try:
        return int(time.time() - os.path.getmtime("/tmp/lever-worker.lock"))
    except:
        return None


# ── Data functions ──────────────────────────────────────────────────────────

def find_latest_log():
    logs = (glob.glob(f"{CONTROL}/worker-logs/worker-*.log") +
            glob.glob(f"{CONTROL}/nightly-logs/cycle-*.log") +
            glob.glob(f"{CONTROL}/dispatcher-logs/dispatcher.log"))
    if not logs:
        return None, None
    newest = max(logs, key=os.path.getmtime)
    age = time.time() - os.path.getmtime(newest)
    return newest, age

def list_logs(subdir, pattern, n=30):
    logs = sorted(glob.glob(f"{CONTROL}/{subdir}/{pattern}"), key=os.path.getmtime, reverse=True)[:n]
    result = []
    for l in logs:
        name = os.path.basename(l)
        size = fsize(l)
        mt = mtime_ict(l)
        ep = mtime_epoch(l)
        dur = None
        m = re.search(r'(\d{8})-?(\d{6})', name)
        if m:
            try:
                start = datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S')
                start = start.replace(tzinfo=timezone.utc).timestamp()
                dur = max(0, int(ep - start))
            except:
                pass
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

def git_log(n=25):
    return run_cmd(['git', 'log', '--oneline', '--format=%h %s (%ar)', f'-{n}'])

def git_status():
    return run_cmd(['git', 'status', '--short']) or "Clean"

def git_diff_stat():
    return run_cmd(['git', 'diff', '--stat']) or "No uncommitted changes"

def git_last_diff():
    return run_cmd(['git', 'diff', 'HEAD~1', '--stat'])

def parse_plan(content):
    """Parse build-plan.md — handles both old and new format.
    Old: ## Phase X header + - [x] **P0** description
    New: ### id. Title [PRIORITY] + - [x] id. description
    """
    phases = []
    cur = None
    for line in content.split('\n'):
        # Phase headers: ## Phase ... or ## Completed Phases
        if line.startswith('## '):
            if cur:
                phases.append(cur)
            name = line.replace('## ', '').strip()
            if name.endswith('\u2705'):
                name = name[:-1].strip()
            cur = {"name": name, "tasks": [], "done": 0, "total": 0}
            continue
        # New format task: - [x] 1a. description
        m = re.match(r'\s*-\s*\[([ x])\]\s*(\w+)\.\s*(.*)', line)
        if m:
            if not cur:
                cur = {"name": "Phase 0-FINAL: Ship Investor Demo", "tasks": [], "done": 0, "total": 0}
            done = m.group(1) == 'x'
            tid = m.group(2)
            desc = m.group(3).strip()
            if len(desc) > 120:
                desc = desc[:117] + '...'
            cur["tasks"].append({"task": f"{tid}. {desc}", "done": done, "id": tid})
            cur["total"] += 1
            if done:
                cur["done"] += 1
            continue
        # Old format task: - [x] **P0** description  OR  - [x] description
        m2 = re.match(r'\s*-\s*\[([ x])\]\s*(.*)', line)
        if m2 and cur is not None:
            done = m2.group(1) == 'x'
            desc = m2.group(2).strip()
            if not desc:
                continue
            if len(desc) > 120:
                desc = desc[:117] + '...'
            cur["tasks"].append({"task": desc, "done": done, "id": ""})
            cur["total"] += 1
            if done:
                cur["done"] += 1
            continue
    if cur:
        phases.append(cur)
    return phases

def next_task_label():
    """Summary of what's currently being worked on."""
    agents = get_running_agents()
    if agents:
        parts = []
        for a in agents:
            lane = a.get('lane', '?')
            tid = a.get('task_id', '?')
            title = a.get('title', '')
            short = title[:40] + '...' if len(title) > 40 else title
            parts.append(f"[{lane[0] if lane else '?'}] {tid}: {short}")
        return " | ".join(parts)
    content = read_file(f"{CONTROL}/build-plan.md")
    for line in content.split('\n'):
        m = re.match(r'\s*-\s*\[\s*\]\s*(\w+)\.\s*(.*)', line)
        if m:
            return f"{m.group(1)}. {m.group(2)[:80]}"
    return "All tasks complete"

def contract_health():
    contracts = [c for c in glob.glob(f"{PROJECT}/src/**/*.sol", recursive=True)]
    tests = glob.glob(f"{PROJECT}/test/*.t.sol") + glob.glob(f"{PROJECT}/test/**/*.t.sol", recursive=True)
    return {"contracts": len(contracts), "tests": len(tests)}

# ── Contract Data Fetching with Error Handling ─────────────────────────────

# Setup logging for contract calls
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(f"{CONTROL}/dashboard-contract-calls.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def retry_with_backoff(func, max_retries=3, base_delay=1.0, max_delay=8.0):
    """Execute function with exponential backoff retry logic."""
    for attempt in range(max_retries):
        try:
            result = func()
            if attempt > 0:
                logger.info(f"Retry successful on attempt {attempt + 1}")
            return result
        except Exception as e:
            wait_time = min(base_delay * (2 ** attempt), max_delay)
            logger.warning(f"Attempt {attempt + 1}/{max_retries} failed: {str(e)}")
            if attempt == max_retries - 1:
                logger.error(f"All {max_retries} attempts failed. Final error: {str(e)}")
                raise e
            logger.info(f"Retrying in {wait_time:.1f}s...")
            time.sleep(wait_time)

def load_deployment_config():
    """Load contract addresses and RPC config from deploy-env.sh."""
    config = {}
    try:
        env_path = f"{CONTROL}/deploy-env.sh"
        if not os.path.exists(env_path):
            logger.error(f"deploy-env.sh not found at {env_path}")
            return config

        # Read the deploy-env.sh file and extract environment variables
        with open(env_path, 'r') as f:
            content = f.read()

        # Extract RPC_URL
        rpc_match = re.search(r'export RPC_URL="([^"]+)"', content)
        config['RPC_URL'] = rpc_match.group(1) if rpc_match else "https://sepolia.base.org"

        # Extract contract addresses
        address_patterns = [
            'USDT_ADDRESS', 'MARKET_REGISTRY', 'ORACLE_ADAPTER', 'ACCOUNT_MANAGER',
            'POSITION_MANAGER', 'LEVER_VAULT', 'REWARDS_DISTRIBUTOR', 'INSURANCE_FUND',
            'FEE_ROUTER', 'LEVERAGE_MODEL', 'OI_LIMITS', 'BORROW_FEE_ENGINE',
            'FUNDING_RATE_ENGINE', 'MARGIN_ENGINE', 'EXECUTION_ENGINE',
            'LIQUIDATION_ENGINE', 'SETTLEMENT_ENGINE', 'DEPLOYER'
        ]

        for pattern in address_patterns:
            match = re.search(rf'export {pattern}=([0-9xa-fA-F]+)', content)
            if match:
                config[pattern] = match.group(1)

        logger.info(f"Loaded {len(config)} config values from deploy-env.sh")
        return config

    except Exception as e:
        logger.error(f"Failed to load deployment config: {str(e)}")
        return config

def call_contract(contract_address, function_signature, rpc_url, additional_args=""):
    """Make a contract call using cast with comprehensive error logging."""
    if not contract_address or not function_signature or not rpc_url:
        raise ValueError(f"Missing required parameters: contract={contract_address}, func={function_signature}, rpc={rpc_url}")

    cast_path = "/home/lever/.foundry/bin/cast"
    if not os.path.exists(cast_path):
        raise FileNotFoundError(f"Cast binary not found at {cast_path}")

    cmd = [cast_path, "call", contract_address, function_signature, "--rpc-url", rpc_url]
    if additional_args:
        cmd.extend(additional_args.split())

    logger.debug(f"Executing cast call: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

    if result.returncode != 0:
        error_msg = result.stderr.strip() if result.stderr else "Unknown error"
        logger.error(f"Cast call failed - Contract: {contract_address}, Function: {function_signature}, Error: {error_msg}")
        raise RuntimeError(f"Cast call failed: {error_msg}")

    output = result.stdout.strip()
    logger.debug(f"Cast call successful - Contract: {contract_address}, Function: {function_signature}, Result: {output}")
    return output

def get_contract_data():
    """Fetch all contract data with fallback values and comprehensive error logging."""
    config = load_deployment_config()
    rpc_url = config.get('RPC_URL', 'https://sepolia.base.org')

    # Fallback values for when calls fail
    fallback_data = {
        "tvl": {"value": "0", "display": "N/A", "error": None},
        "global_oi": {"value": "0", "display": "N/A", "error": None},
        "insurance_balance": {"value": "0", "display": "N/A", "error": None},
        "platform_ceiling": {"value": "0", "display": "N/A", "error": None},
        "global_utilization": {"value": "0", "display": "N/A", "error": None},
        "usdt_decimals": {"value": "6", "display": "6", "error": None},
        "deployer_balance": {"value": "0", "display": "N/A", "error": None},
        "market_count": {"value": "0", "display": "0", "error": None},
        "rpc_status": {"status": "unknown", "url": rpc_url}
    }

    def safe_format_wei(wei_str, decimals=18):
        """Safely format wei to readable format with error handling."""
        try:
            if not wei_str or wei_str == "0":
                return "0"
            # Convert wei string to float and format
            wei_val = int(wei_str)
            formatted = wei_val / (10 ** decimals)
            if formatted >= 1e6:
                return f"{formatted/1e6:.2f}M"
            elif formatted >= 1e3:
                return f"{formatted/1e3:.2f}K"
            else:
                return f"{formatted:.4f}"
        except Exception as e:
            logger.warning(f"Failed to format wei value '{wei_str}': {str(e)}")
            return "N/A"

    # Test RPC connectivity
    try:
        def test_rpc():
            return call_contract(config.get('USDT_ADDRESS', ''), 'decimals()(uint8)', rpc_url)
        retry_with_backoff(test_rpc, max_retries=2)
        fallback_data["rpc_status"]["status"] = "connected"
        logger.info("RPC connection test successful")
    except Exception as e:
        fallback_data["rpc_status"]["status"] = "failed"
        logger.error(f"RPC connection test failed: {str(e)}")
        # Return fallback data early if RPC is not working
        return fallback_data

    # Fetch TVL from LeverVault
    try:
        def get_tvl():
            return call_contract(config.get('LEVER_VAULT', ''), 'totalAssets()(uint256)', rpc_url)
        tvl_wei = retry_with_backoff(get_tvl)
        fallback_data["tvl"]["value"] = tvl_wei
        fallback_data["tvl"]["display"] = safe_format_wei(tvl_wei, 6)  # USDT has 6 decimals
        logger.info(f"TVL fetched successfully: {tvl_wei} wei = {fallback_data['tvl']['display']}")
    except Exception as e:
        fallback_data["tvl"]["error"] = str(e)
        logger.error(f"Failed to fetch TVL: {str(e)}")

    # Fetch Global OI
    try:
        def get_global_oi():
            return call_contract(config.get('OI_LIMITS', ''), 'getGlobalOI()(uint256)', rpc_url)
        oi_wei = retry_with_backoff(get_global_oi)
        fallback_data["global_oi"]["value"] = oi_wei
        fallback_data["global_oi"]["display"] = safe_format_wei(oi_wei, 6)
        logger.info(f"Global OI fetched successfully: {oi_wei} wei = {fallback_data['global_oi']['display']}")
    except Exception as e:
        fallback_data["global_oi"]["error"] = str(e)
        logger.error(f"Failed to fetch Global OI: {str(e)}")

    # Fetch Insurance Fund Balance
    try:
        def get_insurance_balance():
            return call_contract(config.get('INSURANCE_FUND', ''), 'getBalance()(uint256)', rpc_url)
        ins_wei = retry_with_backoff(get_insurance_balance)
        fallback_data["insurance_balance"]["value"] = ins_wei
        fallback_data["insurance_balance"]["display"] = safe_format_wei(ins_wei, 6)
        logger.info(f"Insurance balance fetched successfully: {ins_wei} wei = {fallback_data['insurance_balance']['display']}")
    except Exception as e:
        fallback_data["insurance_balance"]["error"] = str(e)
        logger.error(f"Failed to fetch Insurance Fund balance: {str(e)}")

    # Fetch Platform Ceiling
    try:
        def get_platform_ceiling():
            return call_contract(config.get('LEVERAGE_MODEL', ''), 'getPlatformCeiling()(uint256)', rpc_url)
        ceiling_wei = retry_with_backoff(get_platform_ceiling)
        fallback_data["platform_ceiling"]["value"] = ceiling_wei
        fallback_data["platform_ceiling"]["display"] = safe_format_wei(ceiling_wei, 18)
        logger.info(f"Platform ceiling fetched successfully: {ceiling_wei} wei = {fallback_data['platform_ceiling']['display']}")
    except Exception as e:
        fallback_data["platform_ceiling"]["error"] = str(e)
        logger.error(f"Failed to fetch Platform Ceiling: {str(e)}")

    # Fetch Global Utilization
    try:
        def get_global_utilization():
            return call_contract(config.get('OI_LIMITS', ''), 'getGlobalUtilization()(uint256)', rpc_url)
        util_wei = retry_with_backoff(get_global_utilization)
        fallback_data["global_utilization"]["value"] = util_wei
        # Utilization is in basis points (10000 = 100%)
        try:
            util_percent = int(util_wei) / 10000 * 100
            fallback_data["global_utilization"]["display"] = f"{util_percent:.2f}%"
        except:
            fallback_data["global_utilization"]["display"] = "N/A"
        logger.info(f"Global utilization fetched successfully: {util_wei} bps = {fallback_data['global_utilization']['display']}")
    except Exception as e:
        fallback_data["global_utilization"]["error"] = str(e)
        logger.error(f"Failed to fetch Global Utilization: {str(e)}")

    # Fetch Deployer Balance
    try:
        def get_deployer_balance():
            cast_path = "/home/lever/.foundry/bin/cast"
            cmd = [cast_path, "balance", config.get('DEPLOYER', ''), "--rpc-url", rpc_url, "--raw"]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                raise RuntimeError(f"Balance check failed: {result.stderr}")
            return result.stdout.strip()

        balance_wei = retry_with_backoff(get_deployer_balance)
        fallback_data["deployer_balance"]["value"] = balance_wei
        fallback_data["deployer_balance"]["display"] = safe_format_wei(balance_wei, 18)
        logger.info(f"Deployer balance fetched successfully: {balance_wei} wei = {fallback_data['deployer_balance']['display']} ETH")
    except Exception as e:
        fallback_data["deployer_balance"]["error"] = str(e)
        logger.error(f"Failed to fetch Deployer balance: {str(e)}")

    # Count markets (if MarketRegistry available)
    try:
        def get_market_count():
            # This is a placeholder - actual implementation depends on MarketRegistry interface
            # For now, we'll use a basic check that the contract exists
            call_contract(config.get('MARKET_REGISTRY', ''), 'hasRole(bytes32,address)(bool)', rpc_url, "0x0000000000000000000000000000000000000000000000000000000000000000 " + config.get('DEPLOYER', ''))
            return "1"  # If call succeeds, assume at least 1 market exists

        market_count = retry_with_backoff(get_market_count)
        fallback_data["market_count"]["value"] = "1"
        fallback_data["market_count"]["display"] = "≥1"
        logger.info(f"Market registry check successful - markets available")
    except Exception as e:
        fallback_data["market_count"]["error"] = str(e)
        logger.error(f"Failed to check market count: {str(e)}")

    return fallback_data



def get_loop_data():
    """Get autonomous loop state for dashboard."""
    import glob as _glob
    logs_dir = f"{CONTROL}/dispatcher-logs"
    result = {
        "cycle": 0,
        "phase": "unknown",
        "qa_score": None,
        "qa_checks": [],
        "plan_text": "",
        "critique_text": "",
        "critic_verdict": "",
        "cycle_history": [],
        "loop_log": "",
        "loop_running": False,
    }

    # Check if loop service is running
    try:
        import subprocess as _sp
        r = _sp.run(['systemctl', 'is-active', 'lever-loop'], capture_output=True, text=True, timeout=5)
        result["loop_running"] = r.stdout.strip() == 'active'
    except:
        pass

    # Read loop log (last 50 lines)
    loop_log = f"{logs_dir}/loop.log"
    try:
        with open(loop_log) as f:
            lines = f.readlines()
        result["loop_log"] = ''.join(lines[-50:])
        # Parse current phase from last lines
        for line in reversed(lines[-20:]):
            if 'CYCLE' in line:
                import re as _re
                m = _re.search(r'CYCLE\s+(\d+)', line)
                if m:
                    result["cycle"] = int(m.group(1))
            if 'QA PHASE' in line:
                result["phase"] = "qa"
            elif 'PLANNER PHASE' in line or 'PLANNER REVISION' in line:
                result["phase"] = "planning"
            elif 'CRITIC PHASE' in line:
                result["phase"] = "critic"
            elif 'DISPATCH PHASE' in line or 'Dispatcher running' in line:
                result["phase"] = "dispatching"
            elif 'QA Score' in line:
                m2 = _re.search(r'QA Score:\s*(\d+)', line)
                if m2:
                    result["qa_score"] = int(m2.group(1))
            elif 'APPROVED' in line:
                result["critic_verdict"] = "approved"
            elif 'REJECTED' in line:
                result["critic_verdict"] = "rejected"
    except:
        pass

    # Read latest QA report
    qa_reports = sorted(_glob.glob(f"{logs_dir}/qa-report-*.json"), reverse=True)
    if qa_reports:
        try:
            import json as _json
            with open(qa_reports[0]) as f:
                qa = _json.load(f)
            result["qa_score"] = qa.get("score", result["qa_score"])
            result["qa_checks"] = qa.get("checks", [])
        except:
            pass

    # Read latest plan
    plans = sorted(_glob.glob(f"{logs_dir}/plan-*.md"), reverse=True)
    if plans:
        try:
            with open(plans[0]) as f:
                result["plan_text"] = f.read()[:3000]
        except:
            pass

    # Read latest critique
    critiques = sorted(_glob.glob(f"{logs_dir}/critique-*.md"), reverse=True)
    if critiques:
        try:
            with open(critiques[0]) as f:
                result["critique_text"] = f.read()[:2000]
        except:
            pass

    # Build cycle history from QA reports
    for qr in sorted(qa_reports)[-10:]:
        try:
            import json as _json
            with open(qr) as f:
                q = _json.load(f)
            import os as _os
            fname = _os.path.basename(qr)
            # Extract cycle number from filename: qa-report-1.json
            m3 = _re.search(r'qa-report-(\d+)', fname)
            cnum = int(m3.group(1)) if m3 else 0
            result["cycle_history"].append({
                "cycle": cnum,
                "score": q.get("score", 0),
                "critical": len(q.get("critical_issues", [])),
                "timestamp": q.get("timestamp", ""),
            })
        except:
            pass

    # Read loop state file
    state_file = f"{logs_dir}/loop-state.json"
    try:
        import json as _json
        with open(state_file) as f:
            state = _json.load(f)
        result["cycle"] = max(result["cycle"], state.get("next_cycle", 1) - 1)
    except:
        pass

    return result


# ── API ─────────────────────────────────────────────────────────────────────


def build_timeline():
    events = []
    dlog = f"{CONTROL}/dispatcher-logs/dispatcher.log"
    if os.path.exists(dlog):
        for line in open(dlog).readlines():
            line = line.strip()
            m = re.match(r'\[(\d+:\d+:\d+)\]\s*(.*)', line)
            if not m: continue
            ts, txt = m.group(1), m.group(2)
            if '🚀 LAUNCH' in txt:
                events.append({"time": ts, "type": "launch", "msg": txt})
            elif '✅' in txt and 'DONE' in txt:
                events.append({"time": ts, "type": "done", "msg": txt})
            elif '❌' in txt or '💀' in txt:
                events.append({"time": ts, "type": "fail", "msg": txt})
            elif '🧠 Analyzing' in txt:
                events.append({"time": ts, "type": "plan", "msg": txt})
    return events

def api_status():
    bp = read_file(f"{CONTROL}/build-plan.md")
    log_path, log_age = find_latest_log()
    el = worker_elapsed()
    return {
        "now": fmt_ict(),
        "build_plan": parse_plan(bp),
        "known_issues": read_file(f"{CONTROL}/known-issues.md"),
        "git_log": git_log(),
        "git_status": git_status(),
        "git_diff": git_diff_stat(),
        "git_last_diff": git_last_diff(),
        "running": worker_running(),
        "dispatcher_active": get_dispatcher_running(),
        "agents": get_running_agents(),
        "completed": get_completed_tasks(),
        "failed": get_failed_tasks(),
        "execution_plan": get_execution_plan(),
        "elapsed_s": el,
        "elapsed": f"{el // 60}m {el % 60}s" if el else None,
        "next_task": next_task_label(),
        "active_log": os.path.basename(log_path) if log_path else None,
        "active_log_age": int(log_age) if log_age is not None else None,
        "worker_logs": list_logs("worker-logs", "worker-*.log"),
        "dispatcher_logs": list_logs("dispatcher-logs", "task-*.log"),
        "nightly_logs": list_logs("nightly-logs", "cycle-*.log"),
        "reports": list_reports(),
        "summaries": list_summaries(),
        "model_decisions": read_file(f"{CONTROL}/worker-logs/model-decisions.log", tail=40),
        "health": contract_health(),
        "contract_data": get_contract_data(),
        "timeline": build_timeline(),
        "qa_log": read_file(f"{CONTROL}/dispatcher-logs/qa-agent.log", tail=30),
        "watchdog_log": read_file(f"{CONTROL}/dispatcher-logs/watchdog.log", tail=15),
    }

def api_live(n=250):
    # Prefer dispatcher log
    dlog = f"{CONTROL}/dispatcher-logs/dispatcher.log"
    log_path, log_age = find_latest_log()
    el = worker_elapsed()
    running = worker_running()

    # Use dispatcher log if it exists and is fresh
    if os.path.exists(dlog) and (time.time() - mtime_epoch(dlog)) < 120:
        content = read_file(dlog, tail=n)
        return {
            "log": content,  # dispatcher log is plain text, not stream-json
            "file": "dispatcher.log",
            "size": fsize(dlog),
            "running": running,
            "stale": False,
            "elapsed_s": el,
            "elapsed": f"{el // 60}m {el % 60}s" if el else None,
            "next_task": next_task_label(),
            "agents": get_running_agents(),
        }

    if not log_path:
        return {
            "log": "No log files found.\nDispatcher and worker logs appear in control-plane/",
            "file": None, "size": 0, "running": running, "stale": True,
            "elapsed": None, "next_task": next_task_label(), "agents": [],
        }

    return {
        "log": parse_stream_json(read_file(log_path, tail=n)),
        "file": os.path.basename(log_path),
        "size": fsize(log_path),
        "running": running,
        "stale": log_age is not None and log_age > 300,
        "elapsed_s": el,
        "elapsed": f"{el // 60}m {el % 60}s" if el else None,
        "next_task": next_task_label(),
        "agents": get_running_agents(),
    }

def api_log(path):
    if not path:
        return "[No path specified]"
    real = os.path.realpath(path)
    ok = real.startswith(os.path.realpath(CONTROL)) or real.startswith(os.path.realpath(PROJECT))
    if not ok:
        return f"[Access denied: {path}]"
    if not os.path.exists(real):
        return f"[File not found: {path}]"
    content = read_file(path)
    if path.endswith(".log") and content.strip().startswith('{'):
        return parse_stream_json(content)
    return content

def api_trigger():
    global _last_trigger
    now = time.time()
    if now - _last_trigger < TRIGGER_COOLDOWN:
        return {"ok": False, "msg": f"Cooldown — wait {int(TRIGGER_COOLDOWN - (now - _last_trigger))}s"}
    if worker_running():
        return {"ok": False, "msg": "Agents already running."}
    try:
        subprocess.Popen(
            ['systemctl', 'restart', 'lever-dispatcher'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        _last_trigger = now
        return {"ok": True, "msg": "Dispatcher restarted. Watch the Live tab."}
    except Exception as e:
        return {"ok": False, "msg": str(e)}


# ── HTML ────────────────────────────────────────────────────────────────────

HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Timmy — LEVER Protocol</title>
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
--or:#ff8c42;--ord:rgba(255,140,66,.1);
--r:10px}
*{margin:0;padding:0;box-sizing:border-box}
html{font-size:14px}
body{background:var(--bg);color:var(--tx);font-family:'Instrument Sans',sans-serif;-webkit-font-smoothing:antialiased}
.mono{font-family:'JetBrains Mono',monospace}
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
.badge{font:500 9px 'JetBrains Mono',monospace;padding:2px 6px;border-radius:99px;display:inline-block}
.b-ac{background:var(--acd);color:var(--ac)}.b-rd{background:var(--rdd);color:var(--rd)}.b-yl{background:var(--yld);color:var(--yl)}.b-pp{background:var(--ppd);color:var(--pp)}.b-bl{background:var(--bld);color:var(--bl)}.b-or{background:var(--ord);color:var(--or)}

/* Stats grid */
.g2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.g3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}
.g4{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
@media(max-width:768px){.g2,.g3,.g4{grid-template-columns:1fr 1fr}}
@media(max-width:400px){.g2,.g3,.g4{grid-template-columns:1fr}}
.stat-n{font:700 26px 'JetBrains Mono',monospace;color:var(--wh);line-height:1}
.stat-l{font:500 9px 'JetBrains Mono',monospace;color:var(--dim);text-transform:uppercase;letter-spacing:.5px;margin-top:4px}
.pbar{height:5px;background:var(--s3);border-radius:3px;margin:8px 0;overflow:hidden}
.pfill{height:100%;border-radius:3px;background:linear-gradient(90deg,var(--ac),var(--pp));transition:width .4s}

/* Lane cards */
.lane{border-radius:var(--r);padding:14px;border:1px solid var(--bdr);background:var(--s1);position:relative;overflow:hidden}
.lane-active{border-color:var(--acb);background:linear-gradient(135deg,var(--acd),transparent)}
.lane-idle{opacity:.5}
.lane-hdr{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.lane-name{font:700 11px 'JetBrains Mono',monospace;text-transform:uppercase;letter-spacing:1px}
.lane-c{color:var(--pp)}.lane-f{color:var(--bl)}.lane-i{color:var(--or)}
.lane-task{font:500 12px 'Instrument Sans',sans-serif;color:var(--wh);margin-bottom:4px}
.lane-meta{font:400 10px 'JetBrains Mono',monospace;color:var(--dim)}
.lane-bar{position:absolute;bottom:0;left:0;right:0;height:2px}
.lane-bar-active{background:linear-gradient(90deg,var(--ac),var(--pp));animation:lanePulse 2s infinite}
@keyframes lanePulse{0%,100%{opacity:.5}50%{opacity:1}}

/* Tasks */
.task{display:flex;gap:8px;padding:5px 0;font-size:12px;line-height:1.5;align-items:flex-start}
.task-ck{width:16px;height:16px;border-radius:4px;flex-shrink:0;border:1.5px solid var(--bdr2);display:grid;place-items:center;font-size:9px;margin-top:1px}
.task-ck.done{background:var(--ac);border-color:var(--ac);color:var(--bg)}
.task-ck.running{background:var(--ppd);border-color:var(--pp);animation:pulse 1.5s infinite}
.task-ck.failed{background:var(--rdd);border-color:var(--rd)}
.task-tx{color:var(--tx)}.task-tx.done{color:var(--dim);text-decoration:line-through}.task-tx.running{color:var(--wh);font-weight:600}.task-tx.failed{color:var(--rd)}
.task-badge{margin-left:6px}

/* Terminal */
.term{background:#020208;border:1px solid var(--bdr);border-radius:8px;overflow:hidden}
.term-bar{display:flex;justify-content:space-between;align-items:center;padding:7px 12px;background:var(--s2);border-bottom:1px solid var(--bdr)}
.term-dots{display:flex;gap:5px}
.term-dot{width:8px;height:8px;border-radius:50%}
.dot-r{background:#ff5f57}.dot-y{background:#febc2e}.dot-g{background:#28c840}
.term-title{font:500 10px 'JetBrains Mono',monospace;color:var(--dim)}
.term-body{padding:12px;max-height:72vh;overflow-y:auto;overflow-x:hidden;font:400 11px/1.7 'JetBrains Mono',monospace;color:#9898b0;white-space:pre-wrap;word-break:break-word;scroll-behavior:smooth}
.term-body .c-err{color:var(--rd)}.term-body .c-warn{color:var(--yl)}.term-body .c-ok{color:var(--ac)}.term-body .c-head{color:var(--pp);font-weight:600}.term-body .c-info{color:var(--bl)}

/* Log list */
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
.banner{border-radius:var(--r);padding:14px 18px;margin-bottom:14px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px}
.banner-active{background:var(--acd);border:1px solid var(--acb)}
.banner-idle{background:var(--s1);border:1px solid var(--bdr)}
.banner h3{font:600 13px 'Instrument Sans',sans-serif;margin:0}
.banner-active h3{color:var(--ac)}.banner-idle h3{color:var(--dim)}
.banner p{font:400 11px 'JetBrains Mono',monospace;margin:2px 0 0}
.banner-active p{color:var(--tx)}.banner-idle p{color:var(--dim)}
.banner .timer{font:700 14px 'JetBrains Mono',monospace;color:var(--ac)}

/* Dep graph */
.dep-row{display:flex;gap:8px;padding:4px 0;font:400 11px 'JetBrains Mono',monospace;align-items:center}
.dep-id{color:var(--wh);font-weight:600;min-width:30px}
.dep-lane{min-width:70px}
.dep-arrow{color:var(--dim)}
.dep-deps{color:var(--dim)}

.search{width:100%;padding:8px 12px;border-radius:8px;border:1px solid var(--bdr);background:var(--s2);color:var(--tx);font:400 12px 'Instrument Sans',sans-serif;margin-bottom:12px;outline:none}
.search:focus{border-color:var(--ac)}.search::placeholder{color:var(--dim)}
.toast{position:fixed;top:16px;right:16px;background:var(--ac);color:var(--bg);padding:10px 16px;border-radius:8px;font:600 12px 'Instrument Sans',sans-serif;z-index:999;transform:translateY(-60px);opacity:0;transition:.3s;pointer-events:none}
.toast.show{transform:translateY(0);opacity:1}
.status-bar{position:fixed;bottom:0;left:0;right:0;background:var(--s1);border-top:1px solid var(--bdr);padding:3px 12px;font:400 9px 'JetBrains Mono',monospace;color:var(--dim);display:flex;justify-content:space-between;z-index:50}
@media(max-width:768px){.status-bar{bottom:52px}}
.spin{display:inline-block;animation:spin 1s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
::-webkit-scrollbar{width:4px;height:4px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:var(--s3);border-radius:2px}
</style>
</head>
<body>
<div id="toast" class="toast"></div>
<div class="app">
<div class="hdr">
<div class="logo"><div class="logo-icon">T</div><div class="logo-title"><h1>Timmy</h1><span>LEVER Protocol — Autonomous Loop</span></div></div>
<div class="hdr-r">
<div class="pill" id="status-pill"><div class="dot dot-off"></div><span>—</span></div>
<div class="clock" id="clock"></div>
<button class="btn btn-go" onclick="triggerRun()">&#9654; Run</button>
<button class="btn" onclick="refresh()">&#8635;</button>
</div>
</div>

<div class="tabs">
<button class="tab on" data-v="v-loop">&#x1F504; Loop</button>
<button class="tab" data-v="v-live">&#9889; Live</button>
<button class="tab" data-v="v-plan">&#9632; Plan</button>
<button class="tab" data-v="v-contracts">&#128202; Contracts</button>
<button class="tab" data-v="v-work">&#128295; Work</button>
<button class="tab" data-v="v-issues">&#9888; Issues</button>
<button class="tab" data-v="v-git">&#128200; Git</button>
</div>

<!-- LOOP -->
<div id="v-loop" class="view on">
<div class="g4" id="loop-stats"></div>
<div class="g2" style="margin-top:10px">
<div class="card"><div class="card-head"><span class="card-label">Cycle Phase</span><span class="badge b-ac" id="loop-phase">-</span></div><div id="loop-pipeline" style="padding:8px 0"></div></div>
<div class="card"><div class="card-head"><span class="card-label">QA Checks</span><span class="badge b-bl" id="loop-qa-badge">-</span></div><div id="loop-qa-checks" style="max-height:300px;overflow-y:auto"></div></div>
</div>
<div class="g2" style="margin-top:10px">
<div class="card"><div class="card-head"><span class="card-label">Latest Plan</span></div><div class="term"><div class="term-body" id="loop-plan" style="max-height:350px">Waiting for first cycle...</div></div></div>
<div class="card"><div class="card-head"><span class="card-label">Critic Feedback</span><span class="badge" id="loop-verdict">-</span></div><div class="term"><div class="term-body" id="loop-critique" style="max-height:350px">Waiting for first cycle...</div></div></div>
</div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Loop Log</span></div><div class="term"><div class="term-body" id="loop-log" style="max-height:400px">Starting...</div></div></div>
</div>

<!-- LIVE -->
<div id="v-live" class="view">
<div id="live-banner"></div>
<div class="g3" id="lane-cards" style="margin-bottom:14px"></div>
<div class="term">
<div class="term-bar"><div class="term-dots"><div class="term-dot dot-r"></div><div class="term-dot dot-y"></div><div class="term-dot dot-g"></div></div><div class="term-title" id="live-title">Connecting...</div></div>
<div class="term-body" id="live-term"><span class="c-info">Loading live feed...</span></div>
</div>
<div style="margin-top:6px;display:flex;justify-content:space-between;align-items:center">
<span class="mono" style="font-size:10px;color:var(--dim)" id="live-meta"></span>
<label class="mono" style="font-size:10px;color:var(--dim);cursor:pointer"><input type="checkbox" id="autoscroll" checked> Auto-scroll</label>
</div>
</div>

<!-- PLAN -->
<div id="v-plan" class="view">
<div id="plan-banner"></div>
<div class="g4" id="plan-stats"></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Execution Plan</span><span class="badge b-pp" id="plan-mode">—</span></div><div id="dep-graph"></div></div>
<div id="plan-phases" style="margin-top:10px"></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Shift Reports</span></div><div id="plan-reports"></div></div>
</div>

<!-- CONTRACTS -->
<div id="v-contracts" class="view">
<div class="card">
<div class="card-head">
<span class="card-label">Protocol Health</span>
<span class="badge" id="contract-rpc-status">RPC</span>
</div>
<div class="g4" id="contract-stats"></div>
</div>
<div class="g2" style="margin-top:10px">
<div class="card">
<div class="card-head"><span class="card-label">Pool Metrics</span></div>
<div id="contract-pool-stats"></div>
</div>
<div class="card">
<div class="card-head"><span class="card-label">Risk Metrics</span></div>
<div id="contract-risk-stats"></div>
</div>
</div>
<div class="card" style="margin-top:10px">
<div class="card-head"><span class="card-label">Contract Status</span></div>
<div id="contract-health-details"></div>
</div>
<div class="card" style="margin-top:10px">
<div class="card-head"><span class="card-label">Error Log</span></div>
<div class="term">
<div class="term-body" id="contract-errors" style="max-height:200px">No contract call errors...</div>
</div>
</div>
</div>

<!-- WORK (logs) -->
<div id="v-work" class="view">
<input class="search" placeholder="Filter logs..." oninput="filterItems('work-list',this.value)">
<div class="card" style="margin-bottom:10px"><div class="card-head"><span class="card-label">Dispatcher Task Logs</span></div><div id="disp-list" class="card-flush"></div></div>
<div class="card"><div class="card-head"><span class="card-label">Worker Logs (Legacy)</span></div><div id="work-list" class="card-flush"></div></div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Nightly Logs</span></div><div id="nightly-list" class="card-flush"></div></div>
</div>

<!-- ISSUES -->
<div id="v-issues" class="view"><div class="card card-flush" id="issues-box"></div></div>

<!-- GIT -->
<div id="v-git" class="view">
<div class="g2">
<div class="card"><div class="card-head"><span class="card-label">Commits</span></div><div class="term"><div class="term-body" id="git-log" style="max-height:400px"></div></div></div>
<div class="card"><div class="card-head"><span class="card-label">Working Tree</span></div><div class="term"><div class="term-body" id="git-st" style="max-height:400px"></div></div></div>
</div>
<div class="card" style="margin-top:10px"><div class="card-head"><span class="card-label">Last Commit</span></div><div class="term"><div class="term-body" id="git-d1" style="max-height:300px"></div></div></div>
</div>

<nav class="mnav"><div class="mnav-row">
<button class="on" data-v="v-loop"><em>&#x1F504;</em>Loop</button>
<button data-v="v-live"><em>&#9889;</em>Live</button>
<button data-v="v-plan"><em>&#9632;</em>Plan</button>
<button data-v="v-contracts"><em>&#128202;</em>Contracts</button>
<button data-v="v-work"><em>&#128295;</em>Work</button>
<button data-v="v-issues"><em>&#9888;</em>Issues</button>
<button data-v="v-git"><em>&#128200;</em>Git</button>
</div></nav>
<div class="status-bar"><span id="sb-left">—</span><span id="sb-right">—</span></div>
</div>

<script>
let DATA={},liveTimer=null,prevLogLen=-1,wasRunning=false,lastRefresh=0;
const loadedLogs={};

function esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'):''}
function colorize(t){if(!t)return'';return t.split('\n').map(l=>{let c='';if(/error|fail|FAIL|panic|revert|CRITICAL|❌|💀/i.test(l))c='c-err';else if(/warn|WARN|⚠/i.test(l))c='c-warn';else if(/PASS|pass|success|DONE|✅|🎉|COMPLETE/i.test(l))c='c-ok';else if(/^={3,}|^#{1,3} |PHASE|🚀|LAUNCH|📋/i.test(l))c='c-head';else if(/INFO|🧠|⚡/i.test(l))c='c-info';return c?'<span class="'+c+'">'+esc(l)+'</span>':esc(l)}).join('\n')}
function toast(m){const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),3500)}
function statusBar(l,r){document.getElementById('sb-left').textContent=l||'';document.getElementById('sb-right').textContent=r||''}

// Clock
function tickClock(){const n=new Date(),utc=n.getTime()+n.getTimezoneOffset()*60000,ict=new Date(utc+7*3600000);document.getElementById('clock').innerHTML=ict.toLocaleTimeString('en-GB')+' ICT<br>'+ict.toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'})}
tickClock();setInterval(tickClock,1000);

// Tabs
function switchView(id){document.querySelectorAll('.tab,.mnav button').forEach(x=>x.classList.remove('on'));document.querySelectorAll('.view').forEach(x=>x.classList.remove('on'));document.querySelectorAll('[data-v="'+id+'"]').forEach(x=>x.classList.add('on'));const el=document.getElementById(id);if(el)el.classList.add('on');if(id==='v-live')startLive();else stopLive()}
document.querySelectorAll('.tab,.mnav button').forEach(t=>t.addEventListener('click',()=>switchView(t.getAttribute('data-v'))));

// Live
function startLive(){if(liveTimer)return;fetchLive();liveTimer=setInterval(fetchLive,3000)}
function stopLive(){if(liveTimer){clearInterval(liveTimer);liveTimer=null}}
function fetchLive(){
  fetch('/api/live?n=300').then(r=>r.json()).then(d=>{
    const el=document.getElementById('live-term');
    const newLen=d.log?d.log.length:0;
    if(newLen!==prevLogLen||prevLogLen===-1){
      el.innerHTML=colorize(d.log||'Waiting for output...');
      prevLogLen=newLen;
      if(document.getElementById('autoscroll').checked)el.scrollTop=el.scrollHeight;
    }
    document.getElementById('live-title').textContent=(d.file||'No log')+(d.stale?' (stale)':'');
    const meta=[];if(d.file)meta.push(d.file);if(d.size)meta.push((d.size/1024).toFixed(1)+'KB');if(d.elapsed)meta.push(d.elapsed);
    document.getElementById('live-meta').textContent=meta.join(' · ')||'—';

    // Banner
    const ban=document.getElementById('live-banner');
    const agents=d.agents||[];
    if(d.running&&agents.length>0){
      ban.innerHTML='<div class="banner banner-active"><div><h3>&#9889; '+agents.length+' Agent'+(agents.length>1?'s':'')+' Working</h3><p>'+esc(d.next_task||'—')+'</p></div><div class="timer">'+esc(d.elapsed||'0m 0s')+'</div></div>';
    } else if(d.running){
      ban.innerHTML='<div class="banner banner-active"><div><h3>&#9889; Working</h3><p>'+esc(d.next_task||'—')+'</p></div><div class="timer">'+esc(d.elapsed||'0m 0s')+'</div></div>';
    } else {
      ban.innerHTML='<div class="banner banner-idle"><div><h3>Idle</h3><p>'+esc(d.next_task||'All complete')+'</p></div></div>';
    }

    // Lane cards
    renderLaneCards(agents);
    updateStatusPill(d.running,d.elapsed,agents.length);
    if(!d.running&&wasRunning)toast('Build shift complete!');
    wasRunning=d.running;
    statusBar(d.running?agents.length+' agent'+(agents.length>1?'s':'')+' active':'Idle','Live feed OK');
  }).catch(err=>statusBar('Live error',err.message));
}
startLive();

function renderLaneCards(agents){
  const lanes={CONTRACT:null,FRONTEND:null,INFRA:null};
  agents.forEach(a=>{const l=a.lane||'?';if(lanes.hasOwnProperty(l))lanes[l]=a;});
  let h='';
  const colors={CONTRACT:'lane-c',FRONTEND:'lane-f',INFRA:'lane-i'};
  Object.entries(lanes).forEach(([name,agent])=>{
    const active=!!agent;
    const cls=active?'lane lane-active':'lane lane-idle';
    const colCls=colors[name]||'';
    h+='<div class="'+cls+'">';
    h+='<div class="lane-hdr"><span class="lane-name '+colCls+'">'+name+'</span>';
    if(active)h+='<span class="badge b-ac">ACTIVE</span>';
    else h+='<span class="badge" style="background:var(--s3);color:var(--dim)">IDLE</span>';
    h+='</div>';
    if(agent){
      const title=agent.title||agent.task_id||'';
      const age=agent.age_s||0;
      h+='<div class="lane-task">'+esc(agent.task_id+': '+(title.length>50?title.slice(0,47)+'...':title))+'</div>';
      h+='<div class="lane-meta">'+Math.floor(age/60)+'m '+age%60+'s</div>';
      h+='<div class="lane-bar lane-bar-active"></div>';
    } else {
      h+='<div class="lane-task" style="color:var(--dim)">Waiting for task...</div>';
      h+='<div class="lane-bar"></div>';
    }
    h+='</div>';
  });
  document.getElementById('lane-cards').innerHTML=h;
}

function updateStatusPill(running,elapsed,count){
  const p=document.getElementById('status-pill');
  if(running){p.innerHTML='<div class="dot dot-on"></div><span>'+(count||'')+'× '+(elapsed||'Active')+'</span>';}
  else{p.innerHTML='<div class="dot dot-off"></div><span>Idle</span>';}
}

function triggerRun(){if(!confirm('Restart the dispatcher?'))return;fetch('/api/trigger').then(r=>r.json()).then(d=>toast(d.msg)).catch(()=>toast('Failed'))}

// Lazy log loading
function lazyLoad(path,elemId){
  if(loadedLogs[elemId])return;const el=document.getElementById(elemId);if(!el)return;
  el.innerHTML='<span class="c-info"><span class="spin">&#8635;</span> Loading...</span>';
  fetch('/api/log?path='+encodeURIComponent(path)).then(r=>r.text()).then(t=>{el.innerHTML=colorize(t);loadedLogs[elemId]=true;}).catch(e=>{el.innerHTML='<span class="c-err">'+esc(e.message)+'</span>';});
}
function toggleLog(el){
  const body=el.querySelector('.log-body'),chev=el.querySelector('.log-chev'),path=el.getAttribute('data-path'),tid=el.getAttribute('data-tid');
  if(body.classList.contains('open')){body.classList.remove('open');if(chev)chev.classList.remove('open');}
  else{body.classList.add('open');if(chev)chev.classList.add('open');if(path&&tid)lazyLoad(path,tid);}
}
function filterItems(cid,q){const el=document.getElementById(cid);if(!el)return;q=q.toLowerCase();el.querySelectorAll('.log-item').forEach(i=>{const n=i.querySelector('.log-name');i.style.display=(!q||(n&&n.textContent.toLowerCase().includes(q)))?'':'none';})}

// Plan view
function renderPlan(d){
  const agents=d.agents||[];const completed=d.completed||[];const failed=d.failed||[];
  const plan=d.execution_plan;
  let done=0,total=0;
  (d.build_plan||[]).forEach(p=>{done+=p.done;total+=p.total});
  const pct=total?Math.round(done/total*100):0;
  const issues=(d.known_issues||'').match(/-\s*\[\s*\]/g);const openIssues=issues?issues.length:0;
  const h=d.health||{};

  document.getElementById('plan-stats').innerHTML=
    '<div class="card"><div class="stat-n">'+pct+'%</div><div class="stat-l">Progress</div><div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div></div>'+
    '<div class="card"><div class="stat-n">'+agents.length+'/3</div><div class="stat-l">Active Agents</div></div>'+
    '<div class="card"><div class="stat-n">'+done+'/'+total+'</div><div class="stat-l">Tasks Done</div></div>'+
    '<div class="card"><div class="stat-n">'+openIssues+'</div><div class="stat-l">Open Issues</div></div>';

  const ban=document.getElementById('plan-banner');
  if(d.running){ban.innerHTML='<div class="banner banner-active"><div><h3>&#9889; Parallel Build Active</h3><p>'+esc(d.next_task)+'</p></div><div class="timer">'+esc(d.elapsed||'—')+'</div></div>';}
  else{ban.innerHTML='<div class="banner banner-idle"><div><h3>Idle</h3><p>'+esc(d.next_task||'All complete')+'</p></div></div>';}

  document.getElementById('plan-mode').textContent=d.dispatcher_active?'Dispatcher':'Legacy Worker';

  // Dep graph
  const runIds=new Set(agents.map(a=>a.task_id));
  const doneIds=new Set(completed.map(c=>c.task_id));
  const failIds=new Set(failed.map(f=>f.task_id));
  let dg='';
  if(plan&&plan.tasks){
    plan.tasks.forEach(t=>{
      const laneCls=t.lane==='CONTRACT'?'lane-c':t.lane==='FRONTEND'?'lane-f':'lane-i';
      const badgeCls=t.lane==='CONTRACT'?'b-pp':t.lane==='FRONTEND'?'b-bl':'b-or';
      let status='';
      if(doneIds.has(t.id))status='<span class="badge b-ac">DONE</span>';
      else if(runIds.has(t.id))status='<span class="badge b-yl">RUNNING</span>';
      else if(failIds.has(t.id))status='<span class="badge b-rd">FAILED</span>';
      else status='<span class="badge" style="background:var(--s3);color:var(--dim)">QUEUED</span>';
      const deps=t.depends_on&&t.depends_on.length?'← '+t.depends_on.join(', '):'';
      dg+='<div class="dep-row"><span class="dep-id">'+esc(t.id)+'</span><span class="dep-lane badge '+badgeCls+'">'+esc(t.lane)+'</span>'+status+'<span class="dep-arrow">'+esc(deps)+'</span></div>';
    });
  } else {
    dg='<div style="padding:8px;color:var(--dim);font-size:12px">No execution plan cached yet. Dispatcher will generate one on next cycle.</div>';
  }
  document.getElementById('dep-graph').innerHTML=dg;

  // Phases with task status
  let ph='';
  (d.build_plan||[]).forEach(p=>{
    const pp=p.total?Math.round(p.done/p.total*100):0;
    const tasks=p.tasks.map(t=>{
      const tid=(t.id||'').toUpperCase();
      let ckCls='',txCls='',badge='';
      if(t.done){ckCls='done';txCls='done';}
      else if(runIds.has(t.id)){ckCls='running';txCls='running';badge='<span class="badge b-yl task-badge">RUNNING</span>';}
      else if(failIds.has(t.id)){ckCls='failed';txCls='failed';badge='<span class="badge b-rd task-badge">FAILED</span>';}
      return '<div class="task"><div class="task-ck '+ckCls+'">'+(t.done?'✓':ckCls==='running'?'⚡':'')+'</div><span class="task-tx '+txCls+'">'+esc(t.task)+'</span>'+badge+'</div>';
    }).join('');
    ph+='<div class="card"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font:600 13px Instrument Sans;color:var(--wh)">'+esc(p.name)+'</span><span class="mono" style="font-size:11px;color:var(--ac)">'+p.done+'/'+p.total+'</span></div><div class="pbar"><div class="pfill" style="width:'+pp+'%"></div></div>'+tasks+'</div>';
  });
  document.getElementById('plan-phases').innerHTML=ph;

  // Reports
  let rh='';
  (d.reports||[]).forEach((r,i)=>{
    const cid='rpt-'+i;
    rh+='<div class="log-item" data-tid="'+cid+'" onclick="toggleLog(this)"><div class="log-hdr"><span class="log-name">'+esc(r.name)+'</span><div class="log-meta"><span class="log-time">'+esc(r.time)+'</span><span class="log-chev">&#9654;</span></div></div><div class="log-body"><div class="term"><div class="term-body" id="'+cid+'" style="max-height:350px">'+colorize(r.content)+'</div></div></div></div>';
  });
  let tl='';(d.timeline||[]).forEach(e=>{let cls='';if(e.type==='done')cls='c-ok';else if(e.type==='fail')cls='c-err';else if(e.type==='launch')cls='c-head';else if(e.type==='plan')cls='c-info';tl+='<div><span style="color:var(--dim);min-width:60px;display:inline-block">'+esc(e.time||'')+'</span> <span class="'+cls+'">'+esc(e.msg||'')+'</span></div>';});document.getElementById('timeline').innerHTML=tl||'<span style="color:var(--dim)">No events yet</span>';const tlEl=document.getElementById('timeline');tlEl.scrollTop=tlEl.scrollHeight;if(d.qa_log)document.getElementById('qa-log').innerHTML=colorize(d.qa_log);if(d.watchdog_log)document.getElementById('wd-log').innerHTML=colorize(d.watchdog_log);document.getElementById('plan-reports').innerHTML=rh||'<div style="padding:14px;color:var(--dim);font-size:12px">No reports yet</div>';
}

// Log lists
function renderLogList(cid,logs,prefix){
  let h='';
  (logs||[]).forEach((l,i)=>{
    const tid=prefix+'-'+i;
    h+='<div class="log-item" data-path="'+esc(l.path)+'" data-tid="'+tid+'" onclick="toggleLog(this)"><div class="log-hdr"><div><span class="log-name">'+esc(l.name)+'</span></div><div class="log-meta">'+(l.duration?'<span class="log-dur">'+esc(l.duration)+'</span>':'')+'<span class="log-time">'+esc(l.time)+'</span><span class="badge b-bl">'+(l.size/1024).toFixed(1)+'KB</span><span class="log-chev">&#9654;</span></div></div><div class="log-body"><div class="term"><div class="term-body" id="'+tid+'" style="max-height:60vh"><span class="c-info">Click to load...</span></div></div></div></div>';
  });
  const el=document.getElementById(cid);
  if(el)el.innerHTML=h||'<div style="padding:14px;color:var(--dim);font-size:12px">No logs yet</div>';
}

// Issues
function renderIssues(d){
  const lines=(d.known_issues||'').split('\n');let h='<div style="padding:14px"><div class="card-head"><span class="card-label">Known Issues</span></div></div>';let sev='';
  lines.forEach(line=>{
    if(/^## CRITICAL/i.test(line))sev='issue-crit';else if(/^## MEDIUM/i.test(line))sev='issue-med';else if(/^## LOW/i.test(line))sev='issue-low';else if(/^## AUDIT/i.test(line))sev='';
    else if(line.trim().startsWith('- [')){const isDone=line.includes('[x]');const text=line.replace(/-\s*\[.\]\s*/,'');h+='<div class="issue '+sev+(isDone?' issue-done':'')+'">'+( isDone?'✅':'⬜')+' '+esc(text)+'</div>';}
  });
  document.getElementById('issues-box').innerHTML=h;
}


// Loop view
function renderLoop(d){
  const loop=d.loop||{};
  const score=loop.qa_score!==null?loop.qa_score:'--';
  const scoreColor=score>=80?'var(--ac)':score>=50?'var(--yl)':'var(--rd)';
  const cycle=loop.cycle||0;
  const phase=loop.phase||'idle';
  const verdict=loop.critic_verdict||'pending';
  const history=loop.cycle_history||[];

  // Stats cards
  document.getElementById('loop-stats').innerHTML=
    '<div class="card"><div class="stat-n" style="color:'+scoreColor+'">'+score+'</div><div class="stat-l">QA Score</div></div>'+
    '<div class="card"><div class="stat-n">'+cycle+'</div><div class="stat-l">Cycle #</div></div>'+
    '<div class="card"><div class="stat-n" style="font-size:16px;text-transform:capitalize">'+phase+'</div><div class="stat-l">Current Phase</div></div>'+
    '<div class="card"><div class="stat-n">'+(loop.loop_running?'<span style="color:var(--ac)">ON</span>':'<span style="color:var(--rd)">OFF</span>')+'</div><div class="stat-l">Loop Status</div></div>';

  // Phase badge
  const phaseEl=document.getElementById('loop-phase');
  phaseEl.textContent=phase.toUpperCase();
  phaseEl.className='badge '+(phase==='dispatching'?'b-ac':phase==='qa'?'b-bl':phase==='planning'?'b-pp':phase==='critic'?'b-yl':'b-or');

  // Pipeline visualization
  const phases=['qa','planning','critic','dispatching'];
  const phaseLabels={'qa':'QA Test','planning':'Planner','critic':'Critic','dispatching':'Dispatch'};
  const phaseIcons={'qa':'&#128269;','planning':'&#128203;','critic':'&#128270;','dispatching':'&#9889;'};
  let pipe='<div style="display:flex;gap:4px;align-items:center;flex-wrap:wrap">';
  phases.forEach((p,i)=>{
    const active=p===phase;
    const done=phases.indexOf(phase)>i;
    const bg=active?'var(--acd)':done?'var(--s3)':'var(--s2)';
    const bdr=active?'var(--acb)':done?'var(--bdr2)':'var(--bdr)';
    const col=active?'var(--ac)':done?'var(--dim)':'var(--dim)';
    pipe+='<div style="flex:1;padding:10px;border-radius:8px;border:1px solid '+bdr+';background:'+bg+';text-align:center">';
    pipe+='<div style="font-size:18px;margin-bottom:4px">'+phaseIcons[p]+'</div>';
    pipe+='<div style="font:600 10px JetBrains Mono,monospace;color:'+col+';text-transform:uppercase">'+phaseLabels[p]+'</div>';
    if(active)pipe+='<div style="margin-top:4px"><div class="dot dot-on" style="display:inline-block"></div></div>';
    if(done)pipe+='<div style="font-size:10px;color:var(--ac);margin-top:2px">&#10003;</div>';
    pipe+='</div>';
    if(i<phases.length-1)pipe+='<div style="color:var(--dim);font-size:12px">&#9654;</div>';
  });
  pipe+='</div>';

  // History sparkline
  if(history.length>1){
    pipe+='<div style="margin-top:12px;display:flex;align-items:end;gap:2px;height:40px">';
    history.forEach(h=>{
      const pct=Math.max(5,h.score||0);
      const c=pct>=80?'var(--ac)':pct>=50?'var(--yl)':'var(--rd)';
      pipe+='<div title="Cycle '+h.cycle+': '+pct+'%" style="flex:1;height:'+pct+'%;background:'+c+';border-radius:2px;min-width:8px;cursor:help"></div>';
    });
    pipe+='</div>';
    pipe+='<div style="display:flex;justify-content:space-between;font:400 9px JetBrains Mono,monospace;color:var(--dim);margin-top:2px"><span>Cycle '+(history[0].cycle||1)+'</span><span>Cycle '+(history[history.length-1].cycle||cycle)+'</span></div>';
  }
  document.getElementById('loop-pipeline').innerHTML=pipe;

  // QA Checks
  const checks=loop.qa_checks||[];
  document.getElementById('loop-qa-badge').textContent=checks.filter(c=>c.pass).length+'/'+checks.length+' pass';
  let qh='';
  checks.forEach(c=>{
    const icon=c.pass?'<span style="color:var(--ac)">&#10003;</span>':'<span style="color:var(--rd)">&#10007;</span>';
    qh+='<div style="display:flex;justify-content:space-between;padding:6px 8px;border-bottom:1px solid var(--bdr);font-size:12px"><span>'+icon+' '+esc(c.name||'')+'</span><span class="mono" style="font-size:10px;color:var(--dim)">'+esc(c.detail||'')+'</span></div>';
  });
  document.getElementById('loop-qa-checks').innerHTML=qh||'<div style="padding:12px;color:var(--dim);font-size:12px">No QA data yet</div>';

  // Plan text
  document.getElementById('loop-plan').innerHTML=colorize(loop.plan_text||'No plan generated yet');

  // Critique
  const verdictEl=document.getElementById('loop-verdict');
  if(verdict==='approved'){verdictEl.textContent='APPROVED';verdictEl.className='badge b-ac';}
  else if(verdict==='rejected'){verdictEl.textContent='REJECTED';verdictEl.className='badge b-rd';}
  else{verdictEl.textContent='PENDING';verdictEl.className='badge b-yl';}
  document.getElementById('loop-critique').innerHTML=colorize(loop.critique_text||'No critique yet');

  // Loop log
  document.getElementById('loop-log').innerHTML=colorize(loop.loop_log||'Loop not started yet');
}

function renderContracts(d){
  const cd = d.contract_data || {};

  // Update RPC status badge
  const rpcBadge = document.getElementById('contract-rpc-status');
  if (rpcBadge) {
    const status = cd.rpc_status?.status || 'unknown';
    rpcBadge.textContent = status.toUpperCase();
    rpcBadge.className = status === 'connected' ? 'badge b-ac' : 'badge b-rd';
  }

  // Main contract stats cards
  const statsHtml = `
    <div class="card">
      <div class="stat-n">${cd.tvl?.display || 'N/A'}</div>
      <div class="stat-l">Total Value Locked</div>
      ${cd.tvl?.error ? '<div style="font-size:9px;color:var(--rd);margin-top:4px">Error: ' + cd.tvl.error.substring(0,40) + '...</div>' : ''}
    </div>
    <div class="card">
      <div class="stat-n">${cd.global_oi?.display || 'N/A'}</div>
      <div class="stat-l">Global Open Interest</div>
      ${cd.global_oi?.error ? '<div style="font-size:9px;color:var(--rd);margin-top:4px">Error: ' + cd.global_oi.error.substring(0,40) + '...</div>' : ''}
    </div>
    <div class="card">
      <div class="stat-n">${cd.insurance_balance?.display || 'N/A'}</div>
      <div class="stat-l">Insurance Fund</div>
      ${cd.insurance_balance?.error ? '<div style="font-size:9px;color:var(--rd);margin-top:4px">Error: ' + cd.insurance_balance.error.substring(0,40) + '...</div>' : ''}
    </div>
    <div class="card">
      <div class="stat-n">${cd.deployer_balance?.display || 'N/A'} ETH</div>
      <div class="stat-l">Deployer Balance</div>
      ${cd.deployer_balance?.error ? '<div style="font-size:9px;color:var(--rd);margin-top:4px">Error: ' + cd.deployer_balance.error.substring(0,40) + '...</div>' : ''}
    </div>
  `;
  document.getElementById('contract-stats').innerHTML = statsHtml;

  // Pool metrics
  const poolHtml = `
    <div style="padding:8px 0">
      <div style="display:flex;justify-content:space-between;margin-bottom:6px">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">TVL</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${cd.tvl?.display || 'N/A'}</span>
      </div>
      <div style="display:flex;justify-content:space-between;margin-bottom:6px">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Global Utilization</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${cd.global_utilization?.display || 'N/A'}</span>
      </div>
      <div style="display:flex;justify-content:space-between">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Markets</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${cd.market_count?.display || '0'}</span>
      </div>
    </div>
  `;
  document.getElementById('contract-pool-stats').innerHTML = poolHtml;

  // Risk metrics
  const riskHtml = `
    <div style="padding:8px 0">
      <div style="display:flex;justify-content:space-between;margin-bottom:6px">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Platform Ceiling</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${cd.platform_ceiling?.display || 'N/A'}</span>
      </div>
      <div style="display:flex;justify-content:space-between;margin-bottom:6px">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Insurance Balance</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${cd.insurance_balance?.display || 'N/A'}</span>
      </div>
      <div style="display:flex;justify-content:space-between">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">RPC Status</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:${cd.rpc_status?.status === 'connected' ? 'var(--ac)' : 'var(--rd)'}">
          ${cd.rpc_status?.status || 'unknown'}
        </span>
      </div>
    </div>
  `;
  document.getElementById('contract-risk-stats').innerHTML = riskHtml;

  // Contract health details
  const healthData = d.health || {};
  const healthHtml = `
    <div style="padding:8px 0">
      <div style="display:flex;justify-content:space-between;margin-bottom:6px">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Smart Contracts</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${healthData.contracts || 0}</span>
      </div>
      <div style="display:flex;justify-content:space-between;">
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--dim)">Test Files</span>
        <span style="font:500 11px 'JetBrains Mono',monospace;color:var(--wh)">${healthData.tests || 0}</span>
      </div>
    </div>
  `;
  document.getElementById('contract-health-details').innerHTML = healthHtml;

  // Error log - collect all errors from contract data
  let errors = [];
  Object.keys(cd).forEach(key => {
    if (cd[key] && cd[key].error) {
      errors.push(`[${key}] ${cd[key].error}`);
    }
  });

  const errorHtml = errors.length > 0
    ? errors.map(err => `<div style="margin-bottom:4px;font:400 10px 'JetBrains Mono',monospace;color:var(--rd)">${err}</div>`).join('')
    : '<div style="font:400 10px \'JetBrains Mono\',monospace;color:var(--dim)">No contract call errors...</div>';

  document.getElementById('contract-errors').innerHTML = errorHtml;
}

// Main render
function render(d){
  DATA=d;
  renderLoop(d);
  renderPlan(d);
  renderContracts(d);
  renderLogList('disp-list',d.dispatcher_logs,'dl');
  renderLogList('work-list',d.worker_logs,'wl');
  renderLogList('nightly-list',d.nightly_logs,'nl');
  renderIssues(d);
  document.getElementById('git-log').innerHTML=colorize(d.git_log||'');
  document.getElementById('git-st').innerHTML=colorize(d.git_status||'Clean');
  document.getElementById('git-d1').innerHTML=colorize(d.git_last_diff||'No data');
  lastRefresh=Date.now();
}

function refresh(){
  statusBar('Refreshing...','');
  Object.keys(loadedLogs).forEach(k=>delete loadedLogs[k]);
  fetch('/api/status').then(r=>r.json()).then(d=>{render(d);statusBar('Refreshed',d.now)}).catch(e=>statusBar('Failed',e.message));
}

refresh();
setInterval(()=>{fetch('/api/status').then(r=>r.json()).then(d=>{render(d);statusBar(d.running?'Building':'Idle',d.now)}).catch(()=>{})},10000);
setInterval(()=>{if(lastRefresh){const ago=Math.round((Date.now()-lastRefresh)/1000);const r=document.getElementById('sb-right').textContent;if(r.includes('Updated'))document.getElementById('sb-right').textContent=r.replace(/Updated \d+s/,'Updated '+ago+'s');}},5000);
</script>
</body>
</html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        try:
            p = urllib.parse.urlparse(self.path)
            q = urllib.parse.parse_qs(p.query)
            if p.path == '/api/status':
                self._json(api_status())
            elif p.path == '/api/live':
                self._json(api_live(int(q.get('n', [250])[0])))
            elif p.path == '/api/log':
                self._text(api_log(q.get('path', [''])[0]))
            elif p.path == '/api/trigger':
                self._json(api_trigger())
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
    print(f"Timmy Dashboard v5 — http://0.0.0.0:{PORT}")
    http.server.HTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
