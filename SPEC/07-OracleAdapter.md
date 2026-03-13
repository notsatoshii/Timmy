# SPEC: OracleAdapter

## Purpose
Full price pipeline: ingests P_raw from external prediction markets, validates sources, applies smoothing (volatility dampening, time-weighted smoothing, anti-manipulation filters, convergence enforcement), outputs PI. This is a SINGLE contract — smoothing is internal, not a separate contract.

PI is the single most important value in the system. Every dollar of PnL, every margin check, every liquidation depends on the quality of this signal. Get this right.

## Dependencies
- MarketRegistry (τ, τ_max, is_live)
- RiskCurves (for condition-dependent parameter scaling)
- ProbabilityIndex (validation)
- FixedPointMath

## Build Priority
Phase 2 — Oracle & Price Pipeline. All PI consumers depend on this.

## Access Control
- ORACLE role: pushPrice
- SETTLEMENT_ENGINE role: snapToOutcome
- ADMIN role: registerSource, removeSource, updateSourceWeight, freezeMarket, unfreezeMarket, updateSmoothingParams

## State Per Market
```solidity
struct SmoothingState {
    uint256 pSmooth;        // Current PI (WAD)
    uint256 lastPRaw;       // Last accepted P_raw (WAD)
    uint256 sigma;          // Rolling volatility of P_raw (WAD)
    uint256 lastUpdateTime; // Timestamp of last accepted update
    bool initialized;       // Has first valid PI been set
}

struct SmoothingParams {
    uint256 alpha;          // Base smoothing coefficient (WAD, 0.1-0.5)
    uint256 deltaMax;       // Max tick movement filter (WAD, 0.02-0.10)
    uint256 epsilon;        // Max P_smooth change per tick (WAD, 0.005-0.02)
    uint256 spreadLimit;    // Max spread for acceptance (WAD)
    uint256 depthMin;       // Min depth for acceptance (WAD)
}

mapping(bytes32 => SmoothingState) private _states;
mapping(bytes32 => SmoothingParams) private _params;
mapping(bytes32 => bool) private _frozen;
```

## pushPrice — The Core Function

This is the most complex function in the contract. It runs four stages sequentially:

### Stage 0: Validation
```
1. Check market exists and is ACTIVE
2. Check market not frozen
3. Check source is registered and active
4. Validate: |pYes + pNo - WAD| <= CONSISTENCY_TOLERANCE (e.g., 0.02)
5. Compute pRaw = pYes (YES probability is the canonical value)
6. Validate: 0 <= pRaw <= WAD
```

### Stage 1: Anti-Manipulation Filters
```
A. Max Tick Filter:
   If |pRaw - lastPRaw| > deltaMax → REJECT, emit UpdateRejected, return

B. Spread Filter:
   If spread > spreadLimit → REJECT

C. Depth Filter:
   If depth < depthMin → REJECT
```

### Stage 2: Volatility Dampening
```
Update rolling sigma:
   sigma = (sigma × (N-1) + |pRaw - lastPRaw|) / N    // exponential moving average
   where N = lookback window (e.g., 20 updates)

Compute volatility weight:
   w_vol = WAD / (WAD + sigma)
```

### Stage 3: Time-Weighted Smoothing
```
tau = MarketRegistry.getTau(marketId)
tauMax = MarketRegistry.getTauMax(marketId)

w_time = wadSqrt(tau × WAD / tauMax)
   // When far: w_time ≈ WAD (light smoothing)
   // Near resolution: w_time → 0 (heavy smoothing)

Combined weight:
   w = alpha × w_vol / WAD × w_time / WAD
```

### Stage 4: Apply Smoothing + Rate Clamp
```
delta = int256(pRaw) - int256(pSmooth)
newPSmooth = pSmooth + w × delta / WAD

// Rate-of-change clamp:
actualChange = |newPSmooth - pSmooth|
if actualChange > epsilon:
    newPSmooth = pSmooth + sign(delta) × epsilon

// Bounds clamp:
newPSmooth = clamp(newPSmooth, 0, WAD)
```

### Finalize
```
state.pSmooth = newPSmooth  // This IS the new PI
state.lastPRaw = pRaw
state.lastUpdateTime = block.timestamp
emit PIUpdated(marketId, newPSmooth, pRaw, w, block.timestamp)
```

### Initialization (first update for a market)
If !state.initialized:
```
state.pSmooth = pRaw  // First PI = first valid P_raw
state.lastPRaw = pRaw
state.sigma = 0
state.initialized = true
```

## snapToOutcome(bytes32 marketId, uint256 outcome)
```
require outcome == 0 || outcome == WAD
state.pSmooth = outcome
emit PIUpdated(...)
```
- Only callable by SettlementEngine
- Only discontinuous PI movement in the entire system
- No smoothing applied. Direct override.

## getPI(bytes32 marketId) → uint256
```
return _states[marketId].pSmooth;
```
- This is what every other contract calls. Must be gas-cheap.

## Edge Cases
- First pushPrice for a market → initialize, don't smooth
- All sources go stale → market should be frozen, PI stays at last value
- pRaw = 0 or pRaw = WAD from oracle → valid (near-certain outcome). Do NOT reject.
- sigma starts at 0, first few updates will have no dampening until sigma builds up
- Convergence near resolution: when τ < threshold (2-4h), consider enforcing monotonicity (if PI has been consistently moving one direction, restrict reversals). This is a SHOULD, not a MUST for v1.
- Market frozen → pushPrice reverts. PI stays at last value. Borrow fees continue at last rate.
- Very rapid updates (same block) → use block.timestamp, not a tick counter. Multiple updates in same block are fine.

## Smoothing Parameter Defaults
| Market Category | α | δ_max | ε | spreadLimit | depthMin |
|----------------|---|-------|---|-------------|----------|
| HIGH_LIQUIDITY | 0.3 | 0.05 | 0.01 | 0.05 | 50K USDT |
| MEDIUM_LIQUIDITY | 0.2 | 0.04 | 0.008 | 0.08 | 20K USDT |
| LOW_LIQUIDITY | 0.15 | 0.03 | 0.005 | 0.10 | 5K USDT |
| NEW_UNPROVEN | 0.1 | 0.02 | 0.005 | 0.10 | 5K USDT |

These are set at market creation and can be updated by admin.

## Testing Strategy
- Feed a known sequence of P_raw values, verify PI trajectory matches expected smoothed curve
- Verify anti-manipulation: spike P_raw by 20% → should be rejected by deltaMax filter
- Verify time-weighted: same P_raw movement near resolution should produce smaller PI change than far from resolution
- Verify sigma builds up correctly over N updates
- Verify snapToOutcome overrides PI to exactly 0 or WAD
- Fuzz: PI always stays in [0, WAD]
- Fuzz: PI change per update never exceeds epsilon

