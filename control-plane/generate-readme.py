#!/usr/bin/env python3
"""
LEVER Protocol — README Generator
Reads project state and generates an up-to-date README.md
Called by nightly cycle or manually: python3 generate-readme.py
"""

import os, glob, re, subprocess
from datetime import datetime, timezone, timedelta

PROJECT = "/home/lever/lever-protocol"
CONTROL = f"{PROJECT}/control-plane"
ICT = timezone(timedelta(hours=7))

def read_file(path):
    try:
        with open(path, 'r', errors='replace') as f: return f.read()
    except: return ""

def run_cmd(cmd, cwd=PROJECT):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, timeout=30).stdout.strip()
    except: return ""

def get_contracts():
    core = sorted(glob.glob(f"{PROJECT}/contracts/core/*.sol"))
    main = sorted(glob.glob(f"{PROJECT}/contracts/*.sol"))
    libs = sorted(glob.glob(f"{PROJECT}/contracts/libraries/*.sol"))
    interfaces = sorted(glob.glob(f"{PROJECT}/contracts/interfaces/*.sol"))
    return core, main, libs, interfaces

def get_test_files():
    unit = sorted(glob.glob(f"{PROJECT}/test/*.t.sol"))
    integration = sorted(glob.glob(f"{PROJECT}/test/integration/*.t.sol"))
    return unit, integration

def count_tests():
    r = run_cmd(['grep', '-rc', 'function test', 'test/'])
    total = 0
    for line in r.strip().split('\n'):
        if ':' in line:
            try: total += int(line.split(':')[-1])
            except: pass
    return total

def parse_plan():
    content = read_file(f"{CONTROL}/build-plan.md")
    phases = []
    cur = None
    for line in content.split('\n'):
        if line.startswith('## Phase'):
            if cur: phases.append(cur)
            cur = {"name": line.replace('## ', ''), "done": 0, "total": 0}
        elif cur and line.strip().startswith('- ['):
            cur["total"] += 1
            if line.strip().startswith('- [x]'): cur["done"] += 1
    if cur: phases.append(cur)
    return phases

def count_issues():
    content = read_file(f"{CONTROL}/known-issues.md")
    crit = med = low = fixed = 0
    sev = ""
    for line in content.split('\n'):
        if '## CRITICAL' in line: sev = 'c'
        elif '## MEDIUM' in line: sev = 'm'
        elif '## LOW' in line: sev = 'l'
        elif line.strip().startswith('- [x]'): fixed += 1
        elif line.strip().startswith('- [ ]'):
            if sev == 'c': crit += 1
            elif sev == 'm': med += 1
            elif sev == 'l': low += 1
    return crit, med, low, fixed

def generate():
    now = datetime.now(ICT).strftime('%Y-%m-%d %H:%M:%S ICT')
    core, main, libs, interfaces = get_contracts()
    unit_tests, integration_tests = get_test_files()
    test_count = count_tests()
    phases = parse_plan()
    crit, med, low, fixed = count_issues()
    commit = run_cmd(['git', 'log', '--oneline', '-1'])
    branch = run_cmd(['git', 'branch', '--show-current'])

    total_done = sum(p['done'] for p in phases)
    total_all = sum(p['total'] for p in phases)
    pct = round(total_done / total_all * 100) if total_all else 0

    # Contract table
    rows = []
    for c in core:
        n = os.path.basename(c).replace('.sol', '')
        rows.append(f"| {n} | `contracts/core/` | Core Infrastructure |")
    for c in main:
        n = os.path.basename(c).replace('.sol', '')
        cat = "Protocol"
        if 'Fee' in n or 'Funding' in n: cat = "Fee Engine"
        elif 'Vault' in n or 'Rewards' in n or 'Insurance' in n: cat = "Vault & Settlement"
        elif 'Leverage' in n or 'OI' in n or 'Execution' in n or 'Margin' in n: cat = "Risk & Execution"
        elif 'Liquidation' in n or 'Settlement' in n: cat = "Vault & Settlement"
        rows.append(f"| {n} | `contracts/` | {cat} |")
    for c in libs:
        n = os.path.basename(c).replace('.sol', '')
        rows.append(f"| {n} | `contracts/libraries/` | Library |")
    contract_table = '\n'.join(rows)

    # Test list
    test_list = ""
    for t in unit_tests:
        test_list += f"  - `{os.path.basename(t)}`\n"
    if integration_tests:
        test_list += "\n  **Integration:**\n"
        for t in integration_tests:
            test_list += f"  - `{os.path.basename(t)}`\n"

    # Phase progress
    phase_lines = ""
    for p in phases:
        filled = round(p['done'] / p['total'] * 20) if p['total'] else 0
        bar = '\u2588' * filled + '\u2591' * (20 - filled)
        phase_lines += f"  {p['name']}: {bar} {p['done']}/{p['total']}\n"

    readme = f"""# LEVER Protocol

> Synthetic leveraged perpetuals on binary prediction market outcomes.

LEVER brings leveraged long/short trading to prediction markets. Instead of binary yes/no positions, traders take 2-50x leveraged positions on probability movements, backed by a unified LP vault that earns yield from borrow fees across all markets simultaneously.

---

## Build Status

| Metric | Value |
|--------|-------|
| Overall Progress | **{pct}%** ({total_done}/{total_all} tasks) |
| Contracts | **{len(core) + len(main)}** implementations + **{len(libs)}** libraries |
| Interfaces | **{len(interfaces)}** |
| Test Files | **{len(unit_tests) + len(integration_tests)}** files (~{test_count} test functions) |
| Open Issues | {crit} critical, {med} medium, {low} low |
| Resolved Issues | {fixed} |
| Latest Commit | `{commit}` |
| Branch | `{branch}` |
| Last Updated | {now} |

### Phase Progress

```
{phase_lines}```

---

## Architecture

**Chain:** Base (Sepolia testnet > mainnet)
**Solidity:** 0.8.24
**Framework:** Foundry
**Deposit Asset:** USDT / lvUSDT (ERC-4626 vault shares)

### Contract Overview

| Contract | Location | Category |
|----------|----------|----------|
{contract_table}

### Key Design Decisions

- **Oracle:** References external prediction market prices — no proprietary price discovery
- **Vault:** Unified ERC-4626 LeverVault (lvUSDT) backs all markets. LPs earn yield from borrow fees
- **Funding:** Single funding index per market. `accrued = -direction * posSize * (currentIndex - entryIndex)`
- **Liquidation:** 1.0% fee (100 bps). Bad debt socialized to LPs. ADL only at settlement
- **Withdrawal Gate:** 80% utilization threshold with blocking mechanism
- **Equity:** `Collateral + PnL - BorrowFees + Funding` (signed int256)
- **Settlement:** Fees frozen at external resolution timestamp

---

## Project Structure

```
lever-protocol/
  contracts/
    core/           OracleAdapter, MarketRegistry, AccountManager, PositionManager
    interfaces/     All contract interfaces (I*.sol)
    libraries/      FixedPointMath, RiskCurves, ProbabilityIndex
    *.sol           ExecutionEngine, LeverVault, fee engines, settlement
  test/
    *.t.sol         Unit tests + math verification
    integration/    Full lifecycle, liquidation, settlement, multi-market
  control-plane/    Build agent (Timmy), dashboard, automation
  CLAUDE.md         Protocol specification
  SPEC/             Per-contract specifications
  foundry.toml
```

---

## Testing

### Test Files

{test_list}

### Running Tests

```bash
forge test --summary            # Full suite
forge test --match-contract X   # Specific contract
forge test --gas-report         # With gas
forge test --match-path test/integration/*  # Integration only
```

---

## Build Agent (Timmy)

Automated build agent that works autonomously:

- **Every 4 hours:** picks the next task, executes with QA gate, commits and pushes
- **Nightly at 2 AM UTC:** deep maintenance — fixes issues, runs full test suite
- **Model routing:** Opus for spec audits and complex bugs, Sonnet for routine tasks
- **Reports via Telegram** and a **web dashboard** at `http://SERVER_IP:8080`

---

## Development

```bash
git clone git@github.com:notsatoshii/Timmy.git lever-protocol
cd lever-protocol
forge install
forge build
forge test
```

---

## Roadmap

1. ~~Contract implementation~~ Done
2. ~~Math verification~~ Done
3. Spec audit (all contracts) — in progress
4. Integration testing — in progress
5. Base Sepolia deployment
6. Seed bots + monitoring
7. Frontend dashboard
8. Security audit
9. Mainnet launch

---

*Auto-generated by build agent. Last updated: {now}*
"""
    return readme.strip()


if __name__ == '__main__':
    readme = generate()
    path = f"{PROJECT}/README.md"
    with open(path, 'w') as f:
        f.write(readme)
    print(f"README.md generated ({len(readme)} bytes)")

    now = datetime.now(ICT).strftime('%Y-%m-%d %H:%M:%S ICT')
    contributing = f"""# Contributing to LEVER Protocol

## Build Agent

This repo is maintained by an automated build agent (Timmy) that:
- Commits as `LEVER Bot <eric@diiant.com>`
- Runs spec audits, fixes bugs, writes tests autonomously
- Updates `control-plane/build-plan.md` as tasks complete
- Logs issues to `control-plane/known-issues.md`

## Manual Changes

1. Check `control-plane/build-plan.md` for current priorities
2. Check `control-plane/known-issues.md` for known problems
3. Run `forge build && forge test` before committing
4. The build agent will audit your changes in its next cycle

## Specification

- `CLAUDE.md` is the canonical protocol spec
- `SPEC/` contains per-contract specifications
- Deviations from spec must be logged in `known-issues.md`

*Last updated: {now}*"""

    cpath = f"{PROJECT}/CONTRIBUTING.md"
    with open(cpath, 'w') as f:
        f.write(contributing.strip())
    print(f"CONTRIBUTING.md generated")
