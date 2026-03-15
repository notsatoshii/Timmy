# Multi-Source Price Validation Analysis — Critical Findings

**Date:** 2026-03-15
**Task:** P1 Multi-source price validation
**Status:** CRITICAL ISSUES IDENTIFIED

## Executive Summary

The multi-source validation has uncovered **critical reliability issues** in the current oracle fallback system. Only 1 out of 3 price sources is providing accurate data, creating a single point of failure that could compromise the entire protocol.

## Key Findings

### 🟢 CLOB Midpoint (Primary Source) — HEALTHY
- **Success Rate:** 100%
- **Response Time:** ~264ms average
- **Status:** ✅ **RELIABLE** — Only source providing accurate real-time prices
- **Sample Prices:** 0.0245, 0.285, 0.075 (realistic market values)

### 🔴 Gamma API Embedded (Fallback Source) — BROKEN
- **Success Rate:** 100% (connects successfully)
- **Data Quality:** ❌ **CRITICAL FAILURE** — Returns 0.0 for ALL markets
- **Response Time:** ~406ms (slower than primary)
- **Root Cause:** Price parsing issue — embedded `outcomePrices` array contains zeros instead of actual prices
- **Impact:** Fallback mechanism is completely non-functional

### 🔴 CLOB Orderbook (Secondary Source) — UNRELIABLE
- **Success Rate:** 100% (connects successfully)
- **Data Quality:** ❌ **STATIC PRICES** — Returns exactly 0.5 (50%) for ALL markets
- **Response Time:** ~197ms (fastest)
- **Root Cause:** Empty orderbooks causing midpoint calculation to default to 0.5
- **Impact:** Cannot be used as reliable price source

## Price Deviation Analysis

- **Maximum Deviation:** 50.00% between sources
- **Average Variance:** 0.267 across all markets
- **Markets Affected:** 3/3 (100% of tested markets)

The extreme deviations are caused by:
1. Real prices from CLOB midpoint
2. Zero prices from Gamma API
3. Static 0.5 from empty orderbooks

## WebSocket Investigation Results

**Status:** Potential endpoints identified but not confirmed functional

**Tested Endpoints:**
- ✅ `wss://clob.polymarket.com/ws` — HTTP base available
- ✅ `wss://gamma-api.polymarket.com/ws` — HTTP base available
- ❌ `wss://ws-subscriptions-clob.polymarket.com` — Invalid URL format
- ❌ `wss://api.polymarket.com/ws` — 404 Not Found
- ❌ `wss://ws.polymarket.com` — Invalid URL format

**Recommendation:** Investigate WebSocket authentication and subscription methods for real-time feeds.

## Impact Assessment

### Current Risk Level: 🚨 **HIGH**

1. **Single Point of Failure:** Only CLOB midpoint is functional
2. **Broken Fallback Chain:** If primary source fails, oracle will provide invalid prices (0.0 or 0.5)
3. **Feed Monitor Ineffective:** The current feed_monitor.py fallback logic would fail in production
4. **Liquidation Risk:** Invalid prices could trigger false liquidations or prevent necessary liquidations

## Immediate Action Required

### Priority 1: Fix Gamma API Integration
```python
# Current broken logic in feed_monitor.py line ~119-133:
resp = requests.get(
    f"{GAMMA_API}/markets",
    params={"id": condition_id},
    timeout=10
)

# ISSUE: Using 'condition_id' instead of searching all markets
# Gamma API embedded prices appear to be stale/zero for these specific markets
```

**Fix:** Update feed_monitor.py to use the multi-source validator's improved Gamma API logic that fetches all markets and filters locally.

### Priority 2: Investigate Orderbook Emptiness
The consistent 0.5 pricing suggests these markets have no active liquidity:

**Root Cause Analysis Needed:**
1. Are these markets too illiquid for meaningful orderbooks?
2. Is the CLOB API returning empty books for low-volume markets?
3. Should we exclude markets below a minimum liquidity threshold?

### Priority 3: Implement WebSocket Feeds
Current REST polling introduces latency and rate limits. WebSocket feeds would provide:
- Real-time price updates
- Reduced API overhead
- Lower latency for oracle updates

## Recommended Source Priority (Based on Evidence)

1. **PRIMARY:** CLOB Midpoint API (/midpoint endpoint)
   - Most reliable and accurate
   - Consistent real-time pricing

2. **SECONDARY:** WebSocket feeds (after implementation)
   - Real-time updates
   - Lower latency

3. **TERTIARY:** Fixed Gamma API (after debugging)
   - Currently broken but potentially valuable as backup

4. **EXCLUDED:** CLOB Orderbook midpoint calculation
   - Unreliable due to empty books
   - Should only be used for spread/depth analysis, not pricing

## Next Steps

### Technical Tasks
1. **Deploy fixed feed_monitor.py** with improved Gamma API logic
2. **Investigate WebSocket authentication** for real-time feeds
3. **Add liquidity filters** to exclude empty orderbook markets
4. **Update keeper.py** to only use validated sources
5. **Add monitoring alerts** for source failure detection

### Monitoring Improvements
1. **Price deviation alerts** when sources differ by >5%
2. **Source health dashboard** tracking success rates
3. **Automated fallback testing** to ensure backup sources work
4. **Liquidity threshold monitoring** for market quality

## Conclusion

The current oracle system has a **single point of failure**. While CLOB midpoint is reliable, the backup sources are completely non-functional. This creates significant risk for a protocol handling real money.

**Priority:** Implement fixes for Gamma API and add WebSocket feeds before mainnet deployment.

---

**Generated by:** Multi-Source Price Validator
**Report:** validation_report.json
**Test Duration:** 5 minutes
**Markets Tested:** 3 representative markets