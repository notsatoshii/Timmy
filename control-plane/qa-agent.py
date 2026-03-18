#!/usr/bin/env python3
"""
LEVER Protocol — QA Agent v2 (Human-Perspective Testing)

Three test layers run every 10 minutes:
  LAYER 1: Visual — screenshot + Claude Vision with LEVER-specific investor context
  LAYER 2: Data — extract DOM values, compare to on-chain, cross-tab consistency
  LAYER 3: Flow — click Demo button, navigate to market, check position form works

Also: verifies leverage cap fix, checks positions have high leverage visible.
"""

import subprocess, json, os, time, glob, re
from datetime import datetime
from pathlib import Path

PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
SCREENSHOTS = f"{CONTROL}/screenshots"
QA_LOG = f"{CONTROL}/dispatcher-logs/qa-agent.log"
QA_RESULTS = f"{CONTROL}/qa-results.json"
DEPLOY_ENV = f"{CONTROL}/deploy-env.sh"
CYCLE_INTERVAL = 600
MODEL = "claude-sonnet-4-20250514"
RPC_URL = "https://sepolia.base.org"

EXPECTED = {"tvl_min":50000000,"tvl_max":200000000,"apy_min":0.01,"apy_max":100,"share_price_min":0.95,"share_price_max":1.10,"oi_min":10000,"oi_max":50000000,"position_count_min":10}

def log(msg):
    ts = datetime.utcnow().strftime('%H:%M:%S')
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(QA_LOG, 'a') as f: f.write(line + '\n')

def notify(msg):
    try:
        tf = f"{PROJECT}/.telegram-token"
        token = Path(tf).read_text().strip() if os.path.exists(tf) else os.environ.get('TELEGRAM_BOT_TOKEN', '')
        if not token: return
        import urllib.request
        data = json.dumps({'chat_id': '422985839', 'text': f"🔍 QA: {msg}"}).encode()
        urllib.request.urlopen(urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data, headers={'Content-Type': 'application/json'}), timeout=5)
    except: pass

def run(cmd, cwd=PROJECT, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout, executable='/bin/bash')
        return r.stdout.strip(), r.returncode
    except: return "", 1

def source_env():
    out, _ = run(f"bash -c 'source {DEPLOY_ENV} && env'")
    env = {}
    for line in out.split('\n'):
        if '=' in line:
            k, _, v = line.partition('=')
            if k.startswith('LEVER_') or k.startswith('RPC_') or k in ('DEPLOYER_KEY', 'TEST_WALLET_KEY', 'LEVER_VAULT', 'INSURANCE_FUND', 'OI_LIMITS'):
                env[k] = v
    return env

def cast_call(addr, sig, env, args=""):
    rpc = env.get('RPC_URL', RPC_URL)
    cast_path = "/home/lever/.foundry/bin/cast"
    out, code = run(f"{cast_path} call {addr} '{sig}' {args} --rpc-url {rpc}")
    return out if code == 0 else None

def get_on_chain_truth(env):
    truth = {}
    vault = env.get('LEVER_VAULT', '')
    if vault:
        r = cast_call(vault, "totalAssets()(uint256)", env)
        if r:
            try: truth['tvl'] = int(r, 16 if r.startswith('0x') else 10) / 1e6
            except: pass
        r = cast_call(vault, "convertToAssets(uint256)(uint256)", env, "1000000000000000000")
        if r:
            try: truth['share_price'] = int(r, 16 if r.startswith('0x') else 10) / 1e6
            except: pass
    ins = env.get('INSURANCE_FUND', '')
    if ins:
        r = cast_call(ins, "getBalance()(uint256)", env)
        if r:
            try: truth['insurance'] = int(r, 16 if r.startswith('0x') else 10) / 1e18
            except: pass
    oi = env.get('OI_LIMITS', '')
    if oi:
        r = cast_call(oi, "getGlobalOI()(uint256)", env)
        if r:
            try: truth['global_oi'] = int(r, 16 if r.startswith('0x') else 10) / 1e6
            except: pass
    return truth

TEST_SCRIPT = r"""
const puppeteer = require('puppeteer');
const SSDIR = process.argv[1];
const EXPECTED = JSON.parse(process.argv[2]);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const parseNum = t => { if(!t)return null; const c=t.replace(/[$,%×x,]/g,'').trim(); const n=parseFloat(c); return isNaN(n)?null:n; };
(async () => {
    const browser = await puppeteer.launch({headless:'new',args:['--no-sandbox','--disable-setuid-sandbox']});
    const R = {timestamp:new Date().toISOString(),tabs:{},flows:{},cross_tab:{},issues:[],overall_pass:true};
    const extracted = {};
    const tabs = [{name:'Trade',path:'/'},{name:'Vault',path:'/vault'},{name:'Positions',path:'/positions'},{name:'MarketDetail',path:'/market/spacex'}];
    for (const tab of tabs) {
        const page = await browser.newPage();
        await page.setViewport({width:1440,height:900});
        const tr = {pass:true,issues:[],values:{},screenshot:null};
        try {
            await page.goto('http://localhost:3000'+tab.path,{waitUntil:'networkidle2',timeout:20000});
            await sleep(4000);
            const fn = tab.name.toLowerCase()+'-'+Date.now()+'.png';
            const fp = SSDIR+'/'+fn;
            await page.screenshot({path:fp,fullPage:true});
            tr.screenshot = fp;
            const bodyText = await page.evaluate(()=>document.body.innerText);
            tr.textContent = bodyText.substring(0,2000);
            if(/Something went wrong|Error boundary/i.test(bodyText)){tr.pass=false;tr.issues.push('Error boundary visible');}
            if(/\$NaN|NaN%|undefined/.test(bodyText)){tr.pass=false;tr.issues.push('$NaN or undefined detected');}
            // Extract values
            const m = (pat) => { const x=bodyText.match(pat); return x?x[1]:null; };
            const tvlRaw=m(/TVL[\s:]*\$([\d,.]+[KMB]?)/i);
            if(tvlRaw){let v=parseNum(tvlRaw);if(tvlRaw.includes('M'))v*=1e6;if(tvlRaw.includes('B'))v*=1e9;if(tvlRaw.includes('K'))v*=1e3;tr.values.tvl=v;}
            const apyRaw=m(/APY[\s:]*([\d.]+)%/i); if(apyRaw)tr.values.apy=parseFloat(apyRaw);
            const spRaw=m(/Share\s*Price[\s:]*\$([\d.]+)/i); if(spRaw)tr.values.sharePrice=parseFloat(spRaw);
            const oiRaw=m(/(?:Open\s*Interest|OI)[\s:]*\$([\d,.]+[KMB]?)/i);
            if(oiRaw){let v=parseNum(oiRaw);if(oiRaw.includes('M'))v*=1e6;if(oiRaw.includes('B'))v*=1e9;if(oiRaw.includes('K'))v*=1e3;tr.values.oi=v;}
            tr.values.hasChart = await page.evaluate(()=>document.querySelectorAll('canvas,svg.recharts-surface,.chart-container').length>0);
            // Tab-specific
            if(tab.name==='Vault'){
                if(tr.values.tvl&&tr.values.tvl<EXPECTED.tvl_min){tr.pass=false;tr.issues.push('TVL below expected: $'+tr.values.tvl);}
                if(tr.values.sharePrice&&(tr.values.sharePrice<EXPECTED.share_price_min||tr.values.sharePrice>EXPECTED.share_price_max)){tr.pass=false;tr.issues.push('Share price out of range: $'+tr.values.sharePrice);}
            }
            if(tab.name==='Positions'){
                const levTexts = await page.evaluate(()=>Array.from(document.querySelectorAll('*')).map(e=>e.textContent).filter(t=>/\d+(\.\d+)?[x×]/.test(t)).slice(0,20));
                const maxLev = Math.max(0,...levTexts.map(t=>parseFloat(t.replace(/[x×]/g,''))||0));
                tr.values.maxLeverageSeen = maxLev;
                if(maxLev<5)tr.issues.push('Max leverage seen: '+maxLev+'x (expected 10x+ after fix)');
            }
            if(tab.name==='MarketDetail'){
                if(tr.values.oi&&tr.values.oi>EXPECTED.oi_max){tr.pass=false;tr.issues.push('OI too high: $'+tr.values.oi+' (decimal bug?)');}
                if(!tr.values.hasChart)tr.issues.push('No chart rendering on MarketDetail');
            }
            extracted[tab.name]=tr.values;
        } catch(e) {tr.pass=false;tr.issues.push('Load failed: '+e.message);}
        if(!tr.pass)R.overall_pass=false;
        R.tabs[tab.name]=tr;
        await page.close();
    }
    // Cross-tab TVL
    if(extracted.Trade?.tvl && extracted.Vault?.tvl){
        const diff=Math.abs(extracted.Trade.tvl-extracted.Vault.tvl)/Math.max(extracted.Trade.tvl,extracted.Vault.tvl);
        if(diff>0.05)R.issues.push('TVL mismatch: Trade=$'+extracted.Trade.tvl+' Vault=$'+extracted.Vault.tvl);
    }
    // Demo flow
    try {
        const page = await browser.newPage();
        await page.setViewport({width:1440,height:900});
        await page.goto('http://localhost:3000',{waitUntil:'networkidle2',timeout:20000});
        await sleep(2000);
        const demoFound = await page.evaluate(()=>{const b=Array.from(document.querySelectorAll('button,a')).find(b=>/demo|try demo/i.test(b.textContent));if(b){b.click();return true;}return false;});
        R.flows.demo_button_found = demoFound;
        if(demoFound){
            await sleep(2000);
            await page.screenshot({path:SSDIR+'/flow-demo-'+Date.now()+'.png',fullPage:true});
            R.flows.demo_connected = await page.evaluate(()=>/0x[a-fA-F0-9]{4,}|Connected|Demo/i.test(document.body.innerText));
            const clicked = await page.evaluate(()=>{const l=Array.from(document.querySelectorAll('a,[class*=card],[class*=market]')).find(e=>/spacex|trump|bitcoin/i.test(e.textContent));if(l){l.click();return true;}return false;});
            if(clicked){
                await sleep(3000);
                await page.screenshot({path:SSDIR+'/flow-market-'+Date.now()+'.png',fullPage:true});
                R.flows.has_trading_form = await page.evaluate(()=>{const btns=Array.from(document.querySelectorAll('button'));return btns.some(b=>/open|long|short|trade/i.test(b.textContent));});
            }
        } else { R.issues.push('Demo button not found'); }
        await page.close();
    } catch(e){R.flows.error=e.message;R.issues.push('Demo flow failed: '+e.message);}
    console.log(JSON.stringify(R));
    await browser.close();
})();
"""

VISION_PROMPT = """You are a senior investor reviewing LEVER Protocol's live demo in a pitch meeting.

EXPECTED: TVL ~$60M, 10 markets, positions at 1x-30x leverage, APY 0.1-50%, share price ~$1, OI $100K-$10M range, professional dark trading UI.

This screenshot shows the actual React application rendered in a browser (not HTML shell). Tab: {tab_name}. Page text: {text_snippet}

Evaluate:
1. Do numbers match expected ranges?
2. Any $0, $NaN, undefined, errors, blank sections?
3. Charts rendering with real data?
4. Professional quality (Hyperliquid-tier) or hackathon-tier?
5. Deal-breakers that would make you pass on investing?

IMPORTANT: This is actual browser-rendered content from the React SPA, not curl HTML shell.

JSON only: {{"pass":true/false,"score":1-10,"issues":["specific"],"investor_impression":"one sentence","deal_breakers":["if any"]}}"""

def vision_review(ss, tab, text):
    if not ss or not os.path.exists(ss): return {"pass":False,"score":0,"issues":["No screenshot"]}
    prompt = VISION_PROMPT.format(tab_name=tab, text_snippet=text[:400])
    out, code = run(f'claude -p --dangerously-skip-permissions --model {MODEL} "{prompt}" --image {ss}', timeout=90)
    if code != 0: return {"pass":False,"score":0,"issues":["Vision failed"]}
    try:
        c = re.sub(r'^```(?:json)?\s*\n?','',out.strip()); c = re.sub(r'\n?\s*```$','',c)
        return json.loads(c)
    except: return {"pass":False,"score":0,"issues":["Parse error"],"investor_impression":out[:200]}

def report_issues(issues):
    if not issues: return
    path = f"{CONTROL}/known-issues.md"
    existing = Path(path).read_text() if os.path.exists(path) else ""
    new = [i for i in issues if i[:40] not in existing]
    if new:
        with open(path, 'a') as f:
            f.write(f"\n## QA v2 ({datetime.utcnow().strftime('%Y-%m-%d %H:%M')})\n")
            for i in new: f.write(f"- [ ] {i}\n")
        log(f"📝 {len(new)} new issues")
        notify(f"{len(new)} issues: {new[0][:60]}...")

def run_cycle(n):
    log(f"═══ QA Cycle #{n} — 3 Layers ═══════════")
    env = source_env()
    # Test React SPA with proper browser testing (replaces curl)
    react_out, react_code = run("node scripts/react-spa-verification.js --quick", timeout=30)
    if react_code != 0:
        # Fallback to curl for basic connectivity
        fallback_out, _ = run("curl -s -o /dev/null -w '%{http_code}' http://localhost:3000")
        if fallback_out != '200':
            log(f"❌ Frontend React SPA failed AND HTTP {fallback_out}"); notify(f"Frontend down - both React and HTTP failed"); return
        else:
            log(f"⚠️  React SPA verification failed but HTTP works - continuing with degraded testing"); notify(f"React SPA testing failed, using fallback")
    else:
        log("✅ React SPA verified with browser testing")

    log("⛓  On-chain truth...")
    truth = get_on_chain_truth(env)
    for k, v in truth.items(): log(f"  {k}: {'${:,.0f}'.format(v) if v > 100 else v}")
    if truth.get('tvl'): EXPECTED['tvl_min'] = truth['tvl'] * 0.8

    log("🧪 Layer 1+2: Screenshots + DOM extraction + flows...")
    os.makedirs(SCREENSHOTS, exist_ok=True)
    Path("/tmp/qa-test-v2.js").write_text(TEST_SCRIPT)
    out, code = run(f"node /tmp/qa-test-v2.js '{SCREENSHOTS}' '{json.dumps(EXPECTED)}'", timeout=120)
    if code != 0: log(f"❌ Test suite failed: {out[:300]}"); return
    try: results = json.loads(out)
    except: log("❌ Parse failed"); return

    Path(QA_RESULTS).write_text(json.dumps(results, indent=2))
    all_issues = list(results.get('issues', []))

    for tab, td in results.get('tabs', {}).items():
        s = '✅' if td.get('pass') else '❌'
        vals = ', '.join(f"{k}={v}" for k,v in td.get('values',{}).items() if v is not None)
        log(f"  {s} {tab}: {vals[:80]}")
        for i in td.get('issues',[]): log(f"    ⚠️  {i}"); all_issues.append(f"[{tab}] {i}")

    # Vision review
    log("👁  Layer 1: Claude Vision investor review...")
    scores = []
    for tab, td in results.get('tabs', {}).items():
        if td.get('screenshot'):
            v = vision_review(td['screenshot'], tab, td.get('textContent',''))
            score = v.get('score', 0)
            scores.append(score)
            log(f"  {tab}: {score}/10 — {v.get('investor_impression','?')}")
            for db in v.get('deal_breakers', []): log(f"    🚨 DEAL BREAKER: {db}"); all_issues.append(f"[DEALBREAKER-{tab}] {db}")

    # Flows
    flows = results.get('flows', {})
    log(f"  🔄 Demo: button={'✅' if flows.get('demo_button_found') else '❌'} connect={'✅' if flows.get('demo_connected') else '❌'} form={'✅' if flows.get('has_trading_form') else '❌'}")

    # Frontend vs chain
    for tab, td in results.get('tabs', {}).items():
        v = td.get('values', {})
        if v.get('tvl') and truth.get('tvl'):
            ratio = v['tvl'] / truth['tvl']
            if ratio < 0.5 or ratio > 2.0:
                all_issues.append(f"[CHAIN-{tab}] TVL mismatch: UI ${v['tvl']:,.0f} vs chain ${truth['tvl']:,.0f}")

    report_issues(all_issues)
    tabs = results.get('tabs', {})
    passed = sum(1 for t in tabs.values() if t.get('pass'))
    avg_score = sum(scores)/len(scores) if scores else 0
    log(f"═══ #{n}: {passed}/{len(tabs)} tabs | Avg score: {avg_score:.1f}/10 | {'✅' if results.get('overall_pass') else '❌'} ═══")

def main():
    os.makedirs(SCREENSHOTS, exist_ok=True)
    log("═══════════════════════════════════════"); log("  LEVER QA v2 — Human Perspective"); log("═══════════════════════════════════════")
    notify("QA v2 started")
    cycle = 0
    while True:
        cycle += 1
        try: run_cycle(cycle)
        except Exception as e: log(f"❌ Error: {e}")
        log(f"💤 Next in {CYCLE_INTERVAL//60}min")
        time.sleep(CYCLE_INTERVAL)

if __name__ == '__main__': main()
