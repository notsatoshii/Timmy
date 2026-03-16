#!/bin/bash
# LEVER Frontend Sanity Check v2
# STRICT: fails if it can't extract values OR if values are wrong
# Run after every frontend change. Exit 1 = broken, do NOT mark done.
source /home/lever/lever-protocol/control-plane/deploy-env.sh

echo "=== FRONTEND SANITY CHECK v2 ==="

# 1. Compute expected values from chain
TVL_RAW=$(cast call $LEVER_VAULT 'totalAssets()(uint256)' --rpc-url $RPC_URL 2>/dev/null | head -1 | tr -d ' ')
OI_RAW=$(cast call $OI_LIMITS 'getGlobalOI()(uint256)' --rpc-url $RPC_URL 2>/dev/null | head -1 | tr -d ' ')
INS_RAW=$(cast call $INSURANCE_FUND 'getBalance()(uint256)' --rpc-url $RPC_URL 2>/dev/null | head -1 | tr -d ' ')

EXPECTED=$(python3 << PYEOF
import json

def parse_val(s):
    s = s.strip().split('[')[0].strip()
    if s.startswith('0x'):
        return int(s, 16)
    return int(s)

tvl_raw = parse_val("$TVL_RAW")
oi_raw = parse_val("$OI_RAW")
ins_raw = parse_val("$INS_RAW")

tvl = tvl_raw / 1e6
oi = oi_raw / 1e6
ins = ins_raw / 1e18

utilization = oi / tvl if tvl > 0 else 0
expected_apy = utilization * 0.0002 * 8760 * 0.50 * 100

result = {
    "tvl": round(tvl, 2),
    "oi": round(oi, 2),
    "insurance": round(ins, 2),
    "apy": round(expected_apy, 4),
    "utilization": round(utilization * 100, 4)
}
print(json.dumps(result))
PYEOF
)

echo "Expected from chain: $EXPECTED"

# 2. Extract what frontend actually shows
echo ""
echo "Extracting frontend values..."

FRONTEND_VALUES=$(node -e '
const puppeteer = require("puppeteer");
(async () => {
    const browser = await puppeteer.launch({
        headless: "new",
        executablePath: "/usr/bin/chromium-browser",
        args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
    });
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    await page.goto("http://localhost:3000", { waitUntil: "networkidle2", timeout: 30000 });
    await new Promise(r => setTimeout(r, 5000));

    await page.screenshot({
        path: "/home/lever/lever-protocol/control-plane/screenshots/sanity-check.png",
        fullPage: true
    });

    const values = await page.evaluate(() => {
        const result = { tvl: null, volume: null, oi: null, apy: null, insurance: null };
        const body = document.body.innerText;

        const tvlMatch = body.match(/Total TVL[\s\S]{0,50}?\$([\d,.]+)/);
        if (tvlMatch) result.tvl = tvlMatch[1].replace(/,/g, "");

        const oiMatch = body.match(/Total OI[\s\S]{0,50}?\$([\d,.]+)/);
        if (oiMatch) result.oi = oiMatch[1].replace(/,/g, "");

        const volMatch = body.match(/24h Volume[\s\S]{0,50}?\$([\d,.]+)/);
        if (volMatch) result.volume = volMatch[1].replace(/,/g, "");

        const apyMatch = body.match(/LP APY[\s\S]{0,100}?([\d,.]+)/);
        if (apyMatch) result.apy = apyMatch[1].replace(/,/g, "");

        const insMatch = body.match(/Insurance Fund[\s\S]{0,50}?\$([\d,.]+)/);
        if (insMatch) result.insurance = insMatch[1].replace(/,/g, "");

        return result;
    });

    console.log(JSON.stringify(values));
    await browser.close();
})().catch(e => {
    console.log(JSON.stringify({ error: e.message }));
    process.exit(1);
});
' 2>/dev/null)

echo "Frontend values: $FRONTEND_VALUES"

# 3. Compare expected vs actual
echo ""
python3 << PYEOF
import json, sys

expected = json.loads('$EXPECTED')
try:
    actual = json.loads('$FRONTEND_VALUES')
except:
    print("FAIL: Could not parse frontend values")
    sys.exit(1)

if "error" in actual:
    print(f"FAIL: Frontend error: {actual['error']}")
    sys.exit(1)

problems = []

# Check TVL
if actual.get("tvl"):
    fe_tvl = float(actual["tvl"])
    ratio = fe_tvl / expected["tvl"] if expected["tvl"] > 0 else 999
    print(f"TVL:       expected=\${expected['tvl']:,.2f}  displayed=\${fe_tvl:,.2f}  ratio={ratio:.2f}")
    if ratio > 10 or ratio < 0.1:
        problems.append(f"TVL off by {ratio:.0f}x")
else:
    problems.append("Could not extract TVL from frontend")

# Check OI
if actual.get("oi"):
    fe_oi = float(actual["oi"])
    ratio = fe_oi / expected["oi"] if expected["oi"] > 0 else 999
    print(f"OI:        expected=\${expected['oi']:,.2f}  displayed=\${fe_oi:,.2f}  ratio={ratio:.2f}")
    if ratio > 10 or ratio < 0.1:
        problems.append(f"OI off by {ratio:.0f}x")
else:
    problems.append("Could not extract OI from frontend")

# Check APY
if actual.get("apy"):
    fe_apy_str = actual["apy"]
    fe_apy = float(fe_apy_str)
    print(f"APY:       expected={expected['apy']:.4f}%  displayed={fe_apy}  (raw: {fe_apy_str})")
    
    if len(fe_apy_str.replace(".", "")) > 15:
        problems.append(f"APY is raw BigInt dumped to screen: {fe_apy_str[:30]}...")
    elif fe_apy > 1000:
        problems.append(f"APY is {fe_apy}% - decimal bug (expected {expected['apy']:.4f}%)")
    elif expected["apy"] < 1 and fe_apy > 100:
        problems.append(f"APY expected {expected['apy']:.4f}% but shows {fe_apy}% - off by {fe_apy/max(expected['apy'],0.0001):.0f}x")
else:
    problems.append("Could not extract APY from frontend - may be raw number without % sign")

# Check Insurance
if actual.get("insurance"):
    fe_ins = float(actual["insurance"])
    ratio = fe_ins / expected["insurance"] if expected["insurance"] > 0 else 999
    print(f"Insurance: expected=\${expected['insurance']:,.2f}  displayed=\${fe_ins:,.2f}  ratio={ratio:.2f}")
    if ratio > 100 or ratio < 0.01:
        problems.append(f"Insurance off by {ratio:.0f}x - WAD/USDT format mismatch")
else:
    problems.append("Could not extract Insurance from frontend")

print()
if problems:
    print(f"FAILED: {len(problems)} problems found:")
    for p in problems:
        print(f"  FAIL: {p}")
    print()
    print("DO NOT mark this task as done. Fix the calculation, rebuild, and re-run this check.")
    sys.exit(1)
else:
    print("ALL CHECKS PASSED - frontend values match on-chain expectations")
    sys.exit(0)
PYEOF

EXIT=$?
if [ $EXIT -ne 0 ]; then
    echo "=== SANITY CHECK FAILED ==="
    exit 1
else
    echo "=== SANITY CHECK PASSED ==="
    exit 0
fi
