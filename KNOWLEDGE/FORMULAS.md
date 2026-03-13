# KNOWLEDGE/FORMULAS.md — Complete Formula Reference

All values are WAD (1e18 fixed-point) unless noted. All rates are per-hour unless noted.

---

## 1. RiskCurves Library

### Effective Time-to-Resolution
```
τ_effective = τ × (1 - live_compression × is_live)
```
- τ: hours to resolution
- live_compression: 0.70 (default)
- is_live: 0 or 1
- When live: τ_effective = τ × 0.30

### Risk Curve R(τ) — Mechanical Constraints
```
R(τ) = 1 - e^(-λ × τ_effective / τ_ref)
```
- λ = 2.0
- τ_ref = 24 hours
- R → 1 when far from resolution (full flexibility)
- R → 0 at resolution (maximum tightening)

### Borrow Curve R_borrow(τ) — Economic Pressure
```
R_borrow(τ) = 1 - e^(-λ × τ_effective / τ_ref_borrow)
```
- λ = 2.0
- τ_ref_borrow = 168 hours (1 week)
- Starts tightening a full week before resolution

### Market-Specific Adjustment
```
M_market = min(1.0, Vol_Factor × Depth_Factor × Concentration_Factor)
R_adjusted = R(τ) × M_market
R_borrow_adjusted = R_borrow(τ) × M_market
```

### Vol_Factor
```
Vol_Factor = 1 / (1 + max(0, σ_current - σ_baseline))
```

### Depth_Factor
```
Depth_Factor = min(1.0, external_depth / depth_threshold)
```

### Concentration_Factor
```
C = market_OI / global_OI
Concentration_Factor = max(0.5, 1 - 2 × max(0, C - 0.15))
```
- Activates when market holds >15% of global OI
- Floor at 0.5 (halves available leverage at worst)

### Parameter Mappings (all from R_adjusted unless noted)
```
Leverage_Compression    = R_adjusted
OI_Cap_Multiplier       = 0.20 + R_adjusted × 0.80
MM_Multiplier           = 3.0 - R_adjusted × 2.0
IM_Multiplier           = 3.0 - R_adjusted × 2.0
Execution_Depth_Mult    = 0.30 + R_adjusted × 0.70
Oracle_Frequency        = 30 + R_adjusted × 270        (seconds)
Liquidation_SLA         = 15 + R_adjusted × 75          (seconds)
Borrow_M_ttR            = 1.0 + (25.0 - 1.0) × (1 - R_borrow_adjusted)
```

---

## 2. OracleAdapter (includes Smoothing Engine)

### Volatility Dampening
```
w_vol = 1 / (1 + σ)
```
- σ: rolling stdev of recent P_raw changes

### Smoothed Price Update
```
P_smooth(t) = P_smooth(t-1) + α × w_vol × (P_raw(t) - P_smooth(t-1))
```
- α: base smoothing coefficient (0.1 – 0.5)

### Time-Weighted Smoothing
```
w_time = sqrt(τ / τ_max)
```
- τ_max: total duration listing → resolution

### Combined Smoothing Weight
```
w = α × w_vol × w_time
```

### Max Tick Movement Filter
```
If |P_raw(t) - P_raw(t-1)| > δ_max → REJECT update entirely
```
- δ_max: 0.02 – 0.10, condition-dependent

### Rate-of-Change Clamp
```
If |P_smooth(t) - P_smooth(t-1)| > ε:
  P_smooth(t) = P_smooth(t-1) + sign(change) × ε
```
- ε: max per-tick change (0.005 – 0.02)

### Spread Filter
```
If Spread > Spread_limit → REJECT update
```

### Depth Filter
```
If Depth < Depth_min → REJECT update
```

### Terminal Snap (at resolution only)
```
PI_final = Outcome ∈ {0, 1}
```

---

## 3. LeverageModel

### Step 1: Platform Ceiling
```
Platform_Ceiling = Base_Max × TVL_Multiplier × IFR_Multiplier × Utilization_Multiplier
```
- Base_Max = 30×

### TVL_Multiplier
```
TVL_Multiplier = min(1.0, max(0.10, (TVL / TVL_maturity)^0.5))
```
- TVL_maturity = $50M

### IFR_Multiplier
```
IFR = Insurance_Fund / TVL
IFR_Multiplier = min(1.0, max(0.40, 0.40 + 0.60 × (IFR / IFR_target)))
```
- IFR_target = 0.20 (20%)
- Floor at 0.40 (even with empty insurance, 40% capacity remains)

### Utilization_Multiplier (WP Section 9.5)
```
Utilization_Multiplier = max(0.30, 1.0 - 0.70 × max(0, (U_global - 0.30) / 0.70))
```
- U_global = Global_OI / Global_OI_Cap
- Starts reducing at 30% utilization
- Linear decrease from 1.0 at 30% to 0.30 at 100%
- Floor at 0.30 (never shuts down leverage completely)

| U_global | Util_Mult | Effect |
|----------|-----------|--------|
| < 30%    | 1.00      | No reduction |
| 40%      | 0.90      | Slight |
| 50%      | 0.80      | Moderate |
| 60%      | 0.70      | Meaningful |
| 70%      | 0.60      | Significant |
| 80%      | 0.50      | Halved |
| 90%      | 0.40      | Severe |
| 100%     | 0.30      | Floor |

### Step 2: Risk Factor Compression
```
Compressed_Leverage = Platform_Ceiling × R_adjusted
```
- R_adjusted already includes M_market from RiskCurves

### Step 3: Market-Specific Adjustment (SECOND application of M_market)
```
Market_Adjustment = min(1.0, Vol_Factor × Depth_Factor × Concentration_Factor)
Effective_Max_Leverage = max(1.0, Compressed_Leverage × Market_Adjustment)
```
- **CRITICAL:** M_market is applied TWICE for leverage — once inside R_adjusted (Section 8.11)
  and once here as Market_Adjustment (Section 9.9). This is intentional compounding because
  leverage is the single most dangerous parameter. Market stress has double impact on leverage.
- Never below 1× (spot equivalent)

---

## 4. OILimits (Four-Tier System)

### Tier 1: Global OI Cap
```
Global_OI_Cap = TVL × 0.60
```
- Does NOT compress with R(τ)

### Tier 2: Per-Market OI Cap
```
Base_Market_Cap = Global_OI_Cap × Market_Allocation_Weight
Market_OI_Cap = Base_Market_Cap × OI_Cap_Multiplier(R_adjusted)
OI_Cap_Multiplier = 0.20 + R_adjusted × 0.80
```
- Allocation weights: 15-20% (high liq), 8-12% (mid), 3-5% (low), 2-3% (new)
- Floor at 20% of base cap

### Tier 3: Per-Side OI Cap
```
Side_OI_Cap = Market_OI_Cap × 0.70
```
- 70% of per-market cap per side

### Tier 4: Per-User OI Cap
```
User_OI_Cap = Market_OI_Cap × 0.20
```
- 20% of per-market cap per user

---

## 5. ExecutionEngine (WP Section 10)

### Market Depth
```
market_depth = Market_OI_Cap × Execution_Depth_Mult(R_adjusted)
Execution_Depth_Mult = 0.30 + R_adjusted × 0.70
```
- At R=1 (far): depth = full OI cap
- At R=0 (resolution): depth = 30% of cap (execution more expensive)

### Base Impact
```
base_impact = trade_size / (market_depth × 2)
```
- A trade equal to full market depth = 50% base impact (before cap)

### Imbalance Delta (WP Section 10.2 — the core innovation)
```
imbalance_before = (longOI - shortOI) / totalOI
```
For a LONG trade of size S:
```
imbalance_after = ((longOI + S) - shortOI) / (totalOI + S)
```
For a SHORT trade of size S:
```
imbalance_after = (longOI - (shortOI + S)) / (totalOI + S)
```
Then:
```
imbalance_delta = |imbalance_after| - |imbalance_before|
```
- Positive imbalance_delta: trade WORSENS balance (increases LP directional risk) → more impact
- Negative imbalance_delta: trade IMPROVES balance (reduces LP directional risk) → less impact
- Near-zero: trade has minimal effect on balance → standard impact

### Impact Calculation
```
impact = base_impact × (1 + imbalance_delta × imbalance_multiplier)
```
- imbalance_multiplier = 2.0

### Impact Cap
```
impact = min(impact, MAX_IMPACT)
```
- MAX_IMPACT = 0.05 (5%). Circuit breaker for extreme conditions.

### Entry Price
```
Long:  entry_price = PI × (1 + impact)
Short: entry_price = PI × (1 - impact)
```

### Exit Price (reverse direction)
```
Closing Long:  exit_price = PI × (1 - impact)
Closing Short: exit_price = PI × (1 + impact)
```
- Closing recalculates imbalance_delta using the post-close OI values
- Closing usually improves balance → better pricing (reward for reducing exposure)

### PI Independence
The impact percentage is independent of PI level. A $10K trade at PI=0.95 has the same
percentage impact as at PI=0.50. This is why linear impact works at boundaries where vAMMs break.

---

## 6. MarginEngine

### PnL
```
PnL = direction × (PI_current - PI_entry) × position_size
```
- direction: +1 (long), -1 (short)

### Equity
```
Equity = Collateral + PnL(PI) - Accrued_Borrow_Fees + Accrued_Funding
```
- Accrued_Borrow_Fees: always positive (uint256), always reduces equity
- Accrued_Funding: SIGNED (int256). Positive = you received. Negative = you paid.
  So "+ Accrued_Funding" increases equity if you received, decreases if you paid.

### Margin Ratio
```
MR = Equity / Position_Notional
```

### Base Maintenance Margin
```
MM_base = m × Position_Notional
```
- m = 2.5% (base MM rate)

### Scaled Maintenance Margin
```
MM = MM_base × MM_Multiplier(R_adjusted)
MM_Multiplier = 3.0 - R_adjusted × 2.0
```
- Range: 1.0× (far) to 3.0× (at resolution)

### Initial Margin (with adjustments)
```
IM_base = Position_Notional / leverage_requested
IM_adjusted = IM_base × IM_Multiplier(R_adjusted) × (1 + vol_adj + util_adj)

vol_adj = α_IM × max(0, σ_current - σ_baseline)      // α_IM = 0.5
util_adj = β × max(0, market_utilization - 0.50)       // β = 1.0
```

### Liquidation Threshold
```
Liquidation when: Equity < MM + δ × Position_Notional
```
- δ = 0.5% (50 bps) liquidation buffer

### Collateral Removal Constraint
```
After removal: MR ≥ (MM / Position_Notional) + withdrawal_buffer
```
- withdrawal_buffer = 2.0%

---

## 7. BorrowFeeEngine

### Borrow Fee Accrual
```
borrow_fee = borrow_rate × position_notional × Δt
```
- Only on leveraged positions (leverage > 1×)
- 1× positions exempt

### Borrow Rate
```
borrow_rate = base_borrow_rate × M_ttR × (1 + imbalance_surcharge)
```
- base_borrow_rate = 0.0002 per hour (0.02%)

### Time-to-Resolution Multiplier
```
M_ttR = 1.0 + (M_ttR_max - 1.0) × (1 - R_borrow_adjusted)
```
- M_ttR_max = 25.0
- Range: 1.0× (far) → 25.0× (at resolution)

### Imbalance Surcharge (heavy side only)
```
imbalance_surcharge = max(0, imbalance_ratio) × surcharge_factor
```
- surcharge_factor = 1.0
- imbalance_ratio = (longOI - shortOI) / (longOI + shortOI)
- Light side always has surcharge = 0
- Note: for shorts on a long-heavy book, imbalance_ratio is positive but the SHORT
  is on the light side, so surcharge = 0. For longs, surcharge = 0.4286 × 1.0 = 0.4286.

### Fee Distribution
```
50% → LP Pool (via RewardsDistributor)
30% → Protocol Treasury
20% → Insurance Fund
```
When IFR ≥ 20%: 50% LP / 50% Protocol / 0% Insurance

---

## 8. FundingRateEngine

### Imbalance Ratio
```
imbalance_ratio = (longOI - shortOI) / (longOI + shortOI)
```

### Funding Rate
```
funding_rate_calc = base_funding_rate × |imbalance_ratio| × funding_multiplier
funding_rate = min(funding_rate_calc, max_funding_rate)
```
- base_funding_rate = 0.0001 per hour (0.01%)
- max_funding_rate = 0.0005 per hour (0.05%)

### Funding Multiplier (escalates near resolution)
```
funding_multiplier = 1.0 + (funding_escalation_max - 1.0) × (1 - R_adjusted)
```
- funding_escalation_max = 4.0 (so range 1.0× → 5.0×)

### OI Split
```
Matched_OI = min(longOI, shortOI)
Unmatched_OI = |longOI - shortOI|
```

### Payment Routing
```
Matched portion: heavy side pays → light side receives (trader↔trader, zero-sum)
Unmatched portion: heavy side pays → LP pool directly (risk compensation)
```
- Funding does NOT go through 50/30/20 split
- Funding does NOT involve protocol treasury or insurance

### Index-Based Accrual (single index per market)
```
_fundingIndex[marketId] += funding_rate × Δt
```
- funding_rate is SIGNED: positive when longs pay (long-heavy), negative when shorts pay
- Single cumulative index. Not two indices.

### Accrued Funding Per Position (direction-aware)
```
indexDelta = current_fundingIndex - position_entry_fundingIndex

For longs:  accrued_funding = -(position_size × indexDelta / WAD)
For shorts: accrued_funding = +(position_size × indexDelta / WAD)

Equivalently: accrued_funding = -direction × position_size × indexDelta / WAD
  where direction = +1 (long), -1 (short)
```
- Result is SIGNED: positive = received, negative = paid
- When longs pay (rate > 0): index rises → indexDelta positive → 
  long accrued = -(pos × positive) = NEGATIVE → "paid" ✓
  short accrued = +(pos × positive) = POSITIVE → "received" ✓

---

## 9. SettlementEngine

### Settlement Payout (Winners)
```
outcome_pnl = position_notional × |PI_final - entry_PI|
final_equity = collateral + outcome_pnl - accrued_borrow + accrued_funding
  // accrued_funding is SIGNED (+ = received, - = paid). Same convention as equity equation.
settlement_fee = position_notional × 0.0020     // 20 bps
payout = max(0, final_equity - settlement_fee)
```

### Settlement Payout (Losers)
```
outcome_pnl = -(position_notional × |PI_final - entry_PI|)
final_equity = collateral + outcome_pnl - accrued_borrow + accrued_funding
payout = max(0, final_equity)                    // no settlement fee for losers
```

### Bad Debt (when loser equity < 0)
```
bad_debt = |final_equity|                        // the negative amount
```

### Bad Debt Waterfall
```
1. Position equity absorbs first
2. Insurance Fund (subject to three constraints)
3. ADL (Auto-Deleveraging) — pro-rata haircut on winners
4. LP socialization (absolute last resort)
```

### Insurance Fund Constraints
```
Constraint 1 — Daily cap:    max 25% of insurance balance per rolling 24h
Constraint 2 — Tiered split:
  IFR > 15%:  100% insurance / 0% ADL
  IFR 10-15%: 70% insurance / 30% ADL
  IFR 5-10%:  40% insurance / 60% ADL
  IFR < 5%:   10% insurance / 90% ADL
Constraint 3 — Floor:        Insurance never drops below 5% of TVL
```

### ADL Distribution
```
haircut_per_winner = bad_debt_after_insurance / total_winner_payouts
adjusted_payout = original_payout × (1 - haircut_per_winner)
```
- Pro-rata by payout amount (equal percentage haircut)

### Void Settlement
```
All positions: PnL = 0
Accrued fees NOT refunded
No settlement fee charged
Equity refund = collateral - accrued_borrow - accrued_funding
```

---

## 10. LeverVault (LP Pool)

### Share Minting
```
shares_minted = deposit_amount × total_shares / NAV
```
- If first deposit: shares = deposit_amount

### NAV Calculation
```
NAV = USDT_balance - total_unrealized_trader_pnl
```
- Includes unrealized PnL (mark-to-market against current PI)
- Does NOT include pending rewards in RewardsDistributor

### Share Redemption (at withdrawal execution)
```
withdrawal_amount = shares_burned × NAV / total_shares
```
- Computed at EXECUTION time, not request time

### Utilization
```
utilization = Global_OI / TVL
```
- Target: 40-70%
- Withdrawals blocked above 80%

### Insurance Fund Revenue
```
Insurance_Accrual = 0.20 × (Borrow_Fees + TX_Fees + Liquidation_Fees + Settlement_Fees)
```

---

## 11. Tranche Ledger (inside LeverVault)

### Tranche Struct
```solidity
struct Tranche {
    uint128 shares;
    uint128 rewardSnapshot;  // cumulative index at acquisition
}
```

### Yield Per Tranche
```
yield = tranche.shares × (current_reward_index - tranche.rewardSnapshot)
```

### Total Pending Yield
```
total_yield = Σ(yield per tranche) for all tranches of address
```

### Transfer (Proportional Split)
```
fraction = transfer_amount / sender_total_shares
For each sender tranche:
  shares_to_move = tranche.shares × fraction
  sender tranche.shares -= shares_to_move
  append to receiver: Tranche(shares_to_move, tranche.rewardSnapshot)
```
- NOT FIFO, NOT LIFO — proportional from ALL tranches
- Receiver gets new tranches appended (not blended)

### Consolidation (when receiver hits max 10 tranches)
```
Merge two oldest tranches:
  merged.shares = tranche_a.shares + tranche_b.shares
  merged.snapshot = weighted_average(tranche_a.snapshot, tranche_b.snapshot,
                                      tranche_a.shares, tranche_b.shares)
```

### Total Value at Address
```
total_value = shares × NAV_per_share + total_pending_yield
```

