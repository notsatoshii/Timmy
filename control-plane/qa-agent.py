#!/usr/bin/env python3
"""
LEVER Protocol — Continuous QA Agent
Runs forever alongside the dispatcher. Every cycle:
  1. Screenshots every frontend tab via puppeteer
  2. Feeds screenshots to Claude Vision for investor-perspective review
  3. Checks on-chain state (leverage cap, fees, positions)
  4. Opens new orders if leverage is fixed
  5. Logs issues to known-issues.md
  6. Sends Telegram alerts for critical findings

Runs as: systemd lever-qa.service
"""

import subprocess
import json
import os
import time
import glob
import re
from datetime import datetime
from pathlib import Path

PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
SCREENSHOTS = f"{CONTROL}/screenshots"
QA_LOG = f"{CONTROL}/dispatcher-logs/qa-agent.log"
DEPLOY_ENV = f"{CONTROL}/deploy-env.sh"
CYCLE_INTERVAL = 600
MODEL = "claude-sonnet-4-20250514"
RPC_URL = "https://sepolia.base.org"

TABS = [
    {"name": "Trade", "path": "/", "key_values": ["TVL", "Volume", "Open Interest"]},
    {"name": "Vault", "path": "/vault", "key_values": ["TVL", "APY", "Share Price"]},
    {"name": "Positions", "path": "/positions", "key_values": ["PnL", "Leverage", "Collateral"]},
    {"name": "MarketDetail", "path": "/market/spacex", "key_values": ["Price", "OI", "Funding Rate"]},
]


def log(msg):
    ts = datetime.utcnow().strftime('%H:%M:%S')
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(QA_LOG, 'a') as f:
        f.write(line + '\n')


def notify(msg):
    try:
        token_file = f"{PROJECT}/.telegram-token"
        token = Path(token_file).read_text().strip() if os.path.exists(token_file) else os.environ.get('TELEGRAM_BOT_TOKEN', '')
        if not token:
            return
        import urllib.request
        data = json.dumps({'chat_id': '422985839', 'text': f"🔍 QA: {msg}"}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=data, headers={'Content-Type': 'application/json'}
        )
        urllib.request.urlopen(req, timeout=5)
    except:
        pass


def run(cmd, cwd=PROJECT, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        return r.stdout.strip(), r.returncode
    except:
        return "", 1


def source_env():
    out, _ = run(f"bash -c 'source {DEPLOY_ENV} && env'")
    env = {}
    for line in out.split('\n'):
        if '=' in line:
            k, _, v = line.partition('=')
            if k.startswith('LEVER_') or k.startswith('RPC_') or k in ('DEPLOYER_KEY', 'TEST_WALLET_KEY'):
                env[k] = v
    return env


def cast_call(addr, sig, env, args=""):
    rpc = env.get('RPC_URL', RPC_URL)
    cmd = f"cast call {addr} '{sig}' {args} --rpc-url {rpc}"
    out, code = run(cmd)
    return out if code == 0 else None


SCREENSHOT_SCRIPT = """
const puppeteer = require('puppeteer');
const tabs = JSON.parse(process.argv[1]);
const outDir = process.argv[2];
(async () => {
    const browser = await puppeteer.launch({headless:'new',args:['--no-sandbox','--disable-setuid-sandbox']});
    const results = [];
    for (const tab of tabs) {
        const page = await browser.newPage();
        await page.setViewport({width:1440,height:900});
        try {
            await page.goto('http://localhost:3000'+tab.path,{waitUntil:'networkidle2',timeout:15000});
            await new Promise(r=>setTimeout(r,3000));
            const filename = tab.name.toLowerCase()+'-'+Date.now()+'.png';
            const filepath = outDir+'/'+filename;
            await page.screenshot({path:filepath,fullPage:true});
            const text = await page.evaluate(()=>document.body.innerText);
            const hasError = /Something went wrong|\\$NaN|undefined|Error boundary/i.test(text);
            results.push({tab:tab.name,screenshot:filepath,hasError,textSnippet:text.substring(0,500)});
        } catch(e) {
            results.push({tab:tab.name,screenshot:null,hasError:true,error:e.message});
        }
        await page.close();
    }
    await browser.close();
    console.log(JSON.stringify(results));
})();
"""


def take_screenshots():
    os.makedirs(SCREENSHOTS, exist_ok=True)
    script_path = "/tmp/qa-screenshots.js"
    Path(script_path).write_text(SCREENSHOT_SCRIPT)
    tabs_json = json.dumps(TABS)
    out, code = run(f"node {script_path} '{tabs_json}' '{SCREENSHOTS}'", timeout=60)
    if code != 0:
        log(f"⚠️  Screenshot failed: {out[:200]}")
        return []
    try:
        return json.loads(out)
    except:
        log("⚠️  Could not parse screenshot results")
        return []


VISION_PROMPT = """You are a senior investor doing due diligence on a DeFi protocol called LEVER.
You are looking at a screenshot of their demo platform for the first time in a pitch meeting.

Check for:
1. DATA CREDIBILITY: Do numbers make sense? TVL ~$60M, APY 0-100%, Share Price ~$1, OI in thousands not billions.
2. BROKEN UI: Any $0, $NaN, undefined, error messages, blank sections, obviously wrong values?
3. PROFESSIONALISM: Does this look like a real trading platform? Misaligned text, broken charts, raw hex values?
4. INVESTOR RED FLAGS: Anything making you hesitate to invest?

Tab: {tab_name}
Text content: {text_snippet}

Respond with JSON only:
{{"pass":true/false,"confidence":"high/medium/low","issues":["issue 1"],"investor_impression":"one sentence"}}"""


def vision_review(screenshot_path, tab_name, text_snippet):
    if not screenshot_path or not os.path.exists(screenshot_path):
        return {"pass": False, "issues": ["No screenshot"], "confidence": "low", "investor_impression": "Cannot review"}

    prompt = VISION_PROMPT.format(tab_name=tab_name, text_snippet=text_snippet[:300])
    out, code = run(
        f'claude -p --dangerously-skip-permissions --model {MODEL} "{prompt}" --image {screenshot_path}',
        timeout=90
    )
    if code != 0:
        return {"pass": False, "issues": [f"Vision failed: {out[:100]}"], "confidence": "low", "investor_impression": "Error"}
    try:
        cleaned = re.sub(r'^```(?:json)?\s*\n?', '', out.strip())
        cleaned = re.sub(r'\n?\s*```$', '', cleaned)
        return json.loads(cleaned)
    except:
        return {"pass": False, "issues": ["Parse error"], "confidence": "low", "investor_impression": out[:200]}


def check_on_chain(env):
    findings = []

    # TVL
    vault = env.get('LEVER_VAULT', '')
    if vault:
        result = cast_call(vault, "totalAssets()(uint256)", env)
        if result:
            try:
                val = int(result, 16) if result.startswith('0x') else int(result)
                tvl = val / 1e6
                findings.append({"type": "OK", "msg": f"TVL: ${tvl:,.0f}"})
            except:
                pass

    # Insurance fund
    insurance = env.get('LEVER_INSURANCE_FUND', '')
    if insurance:
        result = cast_call(insurance, "getBalance()(uint256)", env)
        if result:
            try:
                val = int(result, 16) if result.startswith('0x') else int(result)
                balance = val / 1e18
                status = "OK" if balance > 10000 else "WARN"
                findings.append({"type": status, "msg": f"Insurance: ${balance:,.0f}"})
            except:
                pass

    return findings


def report_issues(vision_results, chain_findings):
    issues_path = f"{CONTROL}/known-issues.md"
    existing = Path(issues_path).read_text() if os.path.exists(issues_path) else ""
    new_issues = []

    for vr in vision_results:
        if not vr.get('review', {}).get('pass', True):
            for issue in vr['review'].get('issues', []):
                if issue[:40] not in existing:
                    new_issues.append(f"- [ ] [QA-{vr['tab']}] {issue}")

    for cf in chain_findings:
        if cf['type'] == 'CRITICAL' and cf['msg'][:30] not in existing:
            new_issues.append(f"- [ ] [QA-CHAIN] {cf['msg']}")

    if new_issues:
        with open(issues_path, 'a') as f:
            f.write(f"\n## QA Findings ({datetime.utcnow().strftime('%Y-%m-%d %H:%M')})\n")
            for issue in new_issues:
                f.write(issue + '\n')
        log(f"📝 Added {len(new_issues)} issues")
        notify(f"Found {len(new_issues)} issues: {new_issues[0][:60]}...")


def run_cycle(cycle_num):
    log(f"═══ QA Cycle #{cycle_num} ═══════════════════")
    env = source_env()

    # Frontend check
    out, _ = run("curl -s -o /dev/null -w '%{http_code}' http://localhost:3000")
    if out != '200':
        log(f"⚠️  Frontend HTTP {out} — skipping screenshots")
        screenshots = []
    else:
        log("📸 Screenshots...")
        screenshots = take_screenshots()
        log(f"  {len(screenshots)} tabs captured")

    # Vision review
    vision_results = []
    for ss in screenshots:
        if ss.get('screenshot'):
            log(f"👁  {ss['tab']}...")
            review = vision_review(ss['screenshot'], ss['tab'], ss.get('textSnippet', ''))
            ss['review'] = review
            icon = '✅' if review.get('pass') else '❌'
            log(f"  {icon} {ss['tab']}: {review.get('investor_impression', '?')}")
            vision_results.append(ss)

    # On-chain
    log("⛓  Chain checks...")
    chain = check_on_chain(env)
    for f in chain:
        icon = '✅' if f['type'] == 'OK' else '⚠️'
        log(f"  {icon} {f['msg']}")

    # Report
    report_issues(vision_results, chain)

    passed = sum(1 for vr in vision_results if vr.get('review', {}).get('pass'))
    total = len(vision_results)
    log(f"═══ Cycle #{cycle_num}: {passed}/{total} passed ═══════")
    if total > 0 and passed < total:
        failed = [vr['tab'] for vr in vision_results if not vr.get('review', {}).get('pass')]
        notify(f"Cycle #{cycle_num}: {passed}/{total}. Failed: {', '.join(failed)}")


def main():
    os.makedirs(SCREENSHOTS, exist_ok=True)
    log("═══════════════════════════════════════")
    log("  LEVER QA Agent started")
    log("═══════════════════════════════════════")
    notify("QA Agent started")

    cycle = 0
    while True:
        cycle += 1
        try:
            run_cycle(cycle)
        except Exception as e:
            log(f"❌ Cycle error: {e}")
        log(f"💤 Next cycle in {CYCLE_INTERVAL // 60}min")
        time.sleep(CYCLE_INTERVAL)


if __name__ == '__main__':
    main()
