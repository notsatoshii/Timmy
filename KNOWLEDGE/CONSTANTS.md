# KNOWLEDGE/CONSTANTS.md — All Protocol Constants

All monetary values stored as WAD (1e18). All rates are per-hour unless noted.

---

## Risk Curves (RiskCurves.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| LAMBDA | 2.0 | `2e18` | Controls steepness of risk tightening. Keeps markets flexible >24h out, aggressive in final hours. |
| TAU_REF | 24 hours | `24` (hours, not WAD) | Reference horizon for mechanical risk curve. Tightening concentrated in final day. |
| TAU_REF_BORROW | 168 hours | `168` (hours) | Reference horizon for borrow curve. Starts tightening a full week before resolution. |
| LIVE_COMPRESSION | 0.70 | `7e17` | Going live compresses remaining time to 30% of actual. Instant risk tightening. |
| CONCENTRATION_THRESHOLD | 15% | `15e16` | Market OI above 15% of global OI triggers concentration penalty. |
| CONCENTRATION_FLOOR | 0.50 | `5e17` | Minimum Concentration_Factor. At worst, halves available leverage. |

---

## Leverage Model (LeverageModel.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| BASE_MAX_LEVERAGE | 30× | `30e18` | Absolute max at full platform maturity under ideal conditions. |
| TVL_MATURITY | $50M | `50_000_000e18` | TVL at which TVL_Multiplier reaches 1.0. Square root scaling. |
| TVL_MULTIPLIER_FLOOR | 0.10 | `1e17` | Even tiny platforms get 10% of ceiling (3× min leverage). |
| IFR_TARGET | 20% | `2e17` | Insurance fund target as fraction of TVL. |
| IFR_MULTIPLIER_FLOOR | 0.40 | `4e17` | Even with empty insurance, 40% of ceiling available. |
| UTIL_THRESHOLD | 30% | `3e17` | Utilization above this starts reducing leverage. (WP 9.5) |
| UTIL_MULTIPLIER_FLOOR | 0.30 | `3e17` | Floor at 100% utilization. (WP 9.5) |
| UTIL_SLOPE | 0.70 | `7e17` | Slope of linear decrease from threshold to 100%. (WP 9.5) |
| UTIL_RANGE | 0.70 | `7e17` | Range over which utilization decreases (100% - 30% = 70%). (WP 9.5) |

**Utilization_Multiplier formula (WP Section 9.5):**
```
Utilization_Multiplier = max(0.30, 1.0 - 0.70 × max(0, (U_global - 0.30) / 0.70))
```

---

## OI Limits (OILimits.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| GLOBAL_OI_RATIO | 60% | `6e17` | Max total OI = 60% of TVL. 40% buffer for settlements, PnL swings, withdrawals. |
| OI_CAP_FLOOR | 0.20 | `2e17` | Per-market cap never drops below 20% of base allocation (even at resolution). |
| SIDE_OI_RATIO | 70% | `7e17` | Per-side cap = 70% of per-market cap. |
| USER_OI_RATIO | 20% | `2e17` | Per-user cap = 20% of per-market cap. |

---

## Execution Engine (ExecutionEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| IMBALANCE_MULTIPLIER | 2.0 | `2e18` | How strongly imbalance_delta penalizes balance-worsening trades. |
| MAX_IMPACT | 5% | `5e16` | Circuit breaker. No trade pays more than 5% execution impact. (WP 10.7) |

---

## Liquidation Engine (LiquidationEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| LIQUIDATION_FEE_RATE | 1.0% | `1e16` | 100 bps of position notional. Penalty for forced close. (WP 13.5) |
| LIQUIDATOR_BOUNTY_SHARE | 10% | `1e17` | External liquidator (Path C) gets 10% of liq fee. Rest through 50/30/20. (WP 13.5) |
| PARTIAL_LIQ_THRESHOLD | 10% | `1e17` | Positions >10% of market depth use partial liquidation. (WP 13.7) |
| PARTIAL_LIQ_CHUNK | 5% | `5e16` | Each partial liq chunk = 5% of market depth. (WP 13.7) |

---

## Margin Engine (MarginEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| BASE_MM_RATE | 2.5% | `25e15` | Base maintenance margin as % of notional. |
| MM_MULTIPLIER_MAX | 3.0× | `3e18` | MM scales up to 3× near resolution. |
| IM_MULTIPLIER_MAX | 3.0× | `3e18` | IM scales up to 3× near resolution. |
| VOL_SENSITIVITY_IM | 0.5 | `5e17` | α_IM: how much excess volatility increases IM. |
| UTIL_SENSITIVITY_IM | 1.0 | `1e18` | β: how much excess utilization increases IM. |
| UTIL_THRESHOLD_IM | 50% | `5e17` | OI utilization above which IM increases. |
| LIQUIDATION_BUFFER | 0.5% | `5e15` | Buffer (δ) above MM to prevent threshold oscillation. |
| COLLATERAL_WITHDRAWAL_BUFFER | 2.0% | `2e16` | Additional MR buffer required after collateral removal. |

---

## Borrow Fee Engine (BorrowFeeEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| BASE_BORROW_RATE | 0.02%/hr | `2e14` (WAD per hour) | Rate under ideal conditions. 0.48%/day annualizing to ~175%. |
| M_TTR_MAX | 25.0× | `25e18` | Max borrow multiplier at resolution. Produces 0.50%/hr (438% ann). |
| SURCHARGE_FACTOR | 1.0 | `1e18` | Imbalance surcharge scaling. Heavy side pays up to 2× base rate at full imbalance. |

---

## Funding Rate Engine (FundingRateEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| BASE_FUNDING_RATE | 0.01%/hr | `1e14` (WAD per hour) | Rate at 100% imbalance with no escalation. |
| MAX_FUNDING_RATE | 0.05%/hr | `5e14` (WAD per hour) | Hard cap. 43.8% annualized at cap. |
| FUNDING_ESCALATION_MAX | 4.0 | `4e18` | Multiplier increase near resolution. Effective range 1×→5×. |

---

## Fee Router (FeeRouter.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| LP_FEE_SHARE | 50% | `5e17` | LP always gets 50%. Never reduced. |
| PROTOCOL_FEE_SHARE_T1 | 30% | `3e17` | Protocol share when IFR < 20%. |
| INSURANCE_FEE_SHARE_T1 | 20% | `2e17` | Insurance share when IFR < 20%. |
| PROTOCOL_FEE_SHARE_T2 | 50% | `5e17` | Protocol share when IFR ≥ 20%. |
| INSURANCE_FEE_SHARE_T2 | 0% | `0` | Insurance share when IFR ≥ 20% (fully funded). |
| TX_FEE_RATE | 0.10% | `1e15` | Transaction fee on notional at open and close. |

---

## Settlement Engine (SettlementEngine.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| SETTLEMENT_FEE_RATE | 0.20% | `2e15` | Charged on notional to winners only. |
| PENDING_RESOLUTION_MM_MULT | 2.0× | `2e18` | Elevated MM during oracle gap. |

---

## Insurance Fund (InsuranceFund.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| INSURANCE_BOOTSTRAP | $10,000 | `10_000e18` | Initial seed. Non-zero IFR at launch. |
| INSURANCE_DAILY_CAP | 25% | `25e16` | Max drawdown per rolling 24h window. |
| INSURANCE_FLOOR_IFR | 5% | `5e16` | Fund never depleted below 5% of TVL. |
| ADL_TIER_1_THRESHOLD | 15% IFR | `15e16` | Above: 100% insurance / 0% ADL. |
| ADL_TIER_2_THRESHOLD | 10% IFR | `1e17` | 10-15%: 70% insurance / 30% ADL. |
| ADL_TIER_3_THRESHOLD | 5% IFR | `5e16` | 5-10%: 40% insurance / 60% ADL. |
| ADL_TIER_4 | Below 5% | — | <5%: 10% insurance / 90% ADL. |

---

## LeverVault (LeverVault.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| DEPOSIT_ASSET | USDT | — | Single-asset pool. Stablecoin only. |
| SHARE_TOKEN | lvUSDT | — | ERC-4626 share token. ERC-20 compatible with tranche ledger. |
| MAX_TRANCHES_PER_ADDRESS | 10 | `10` | Gas-bounded tranche list. Oldest two merge on overflow. |
| WITHDRAWAL_COOLDOWN | 48 hours | `172800` (seconds) | Time from request to execute. NAV computed at execution. |
| CANCEL_RE_REQUEST_COOLDOWN | 24 hours | `86400` (seconds) | After cancelling, wait 24h before new request. |
| MAX_UTILIZATION_FOR_WITHDRAWAL | 80% | `8e17` | Post-withdrawal utilization must stay ≤ 80%. |

---

## Oracle / Smoothing (OracleAdapter.sol)

| Constant | Value | Solidity | Rationale |
|----------|-------|----------|-----------|
| CONSISTENCY_TOLERANCE | 0.02 | `2e16` | Max |P_YES + P_NO - 1| deviation for source validation. (WP 5.2) |

## Oracle/SLA Thresholds

| Condition | Update Frequency | Staleness Threshold |
|-----------|-----------------|-------------------|
| Event weeks away | 5 min | 10 min |
| Event days away | 2 min | 5 min |
| Event hours away | 1 min | 2 min |
| Event live | 30 sec | 1 min |
| First 30 min of live | 30 sec | 45 sec |

---

## Smoothing Engine Tuning Parameters (NOT constants — governance/admin tunable)

| Parameter | Typical Range | Notes |
|-----------|--------------|-------|
| α (base smoothing) | 0.1 – 0.5 | Higher = faster tracking |
| δ_max (max tick filter) | 0.02 – 0.10 | Condition-dependent |
| ε (max P_smooth change/tick) | 0.005 – 0.02 | Function of update frequency |
| Spread_limit | 0.03 – 0.10 | Source-dependent |
| Depth_min | Market-dependent | Function of allowed OI |
| τ_threshold (convergence trigger) | 2 – 4 hours | Event category dependent |

