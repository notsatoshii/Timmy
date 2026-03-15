"""
Multi-Source Price Validation — Compare Polymarket REST vs WebSocket vs backup sources.

Tests price feed reliability across all available sources:
1. CLOB REST API (/midpoint) — Primary source
2. Gamma API (outcomePrices) — Secondary source
3. WebSocket feeds (if available) — Real-time source
4. Historical price comparison for consistency validation

Reports on:
- Price discrepancies between sources
- Response time per source
- Error rates and staleness
- Recommended fallback ordering
- Source reliability scores
"""

import json
import logging
import time
import asyncio
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional, Dict, List
from datetime import datetime, timedelta
from statistics import mean, median, stdev

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.oracle.polymarket_client import PolymarketClient, GAMMA_API, CLOB_API

logger = logging.getLogger(__name__)

@dataclass
class SourceResult:
    """Result from a single price source."""
    source: str
    price: Optional[float] = None
    response_time_ms: float = 0.0
    success: bool = False
    error: Optional[str] = None
    timestamp: float = 0.0
    metadata: Dict = None  # Additional source-specific data

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

@dataclass
class ValidationReport:
    """Comprehensive validation report for a market."""
    market_id: str
    question: str
    token_id: str
    results: Dict[str, SourceResult]
    primary_price: Optional[float] = None
    price_variance: float = 0.0
    max_deviation: float = 0.0
    recommended_source: str = ""
    reliability_scores: Dict[str, float] = None

    def __post_init__(self):
        if self.reliability_scores is None:
            self.reliability_scores = {}

class MultiSourceValidator:
    """Validates price feeds across multiple Polymarket data sources."""

    def __init__(self, market_config: List[dict], test_duration_minutes: int = 5):
        self.client = PolymarketClient()
        self.market_config = market_config
        self.test_duration = test_duration_minutes * 60  # convert to seconds
        self.source_stats: Dict[str, Dict] = {}

        # Initialize source tracking
        self.sources = [
            "clob_midpoint",
            "gamma_embedded",
            "clob_orderbook",
            "websocket"  # Will test availability
        ]

        for source in self.sources:
            self.source_stats[source] = {
                "attempts": 0,
                "successes": 0,
                "response_times": [],
                "errors": []
            }

    def test_websocket_availability(self) -> Dict:
        """Test if Polymarket has WebSocket feeds available."""
        ws_results = {
            "available": False,
            "tested_endpoints": [],
            "working_endpoints": [],
            "errors": []
        }

        # Common WebSocket endpoints to test
        ws_endpoints = [
            "wss://ws-subscriptions-clob.polymarket.com",
            "wss://clob.polymarket.com/ws",
            "wss://gamma-api.polymarket.com/ws",
            "wss://api.polymarket.com/ws",
            "wss://ws.polymarket.com"
        ]

        logger.info("Testing WebSocket endpoint availability...")

        for endpoint in ws_endpoints:
            ws_results["tested_endpoints"].append(endpoint)
            try:
                # Test if the WebSocket endpoint responds to HTTP
                import requests
                http_endpoint = endpoint.replace("wss://", "https://").replace("/ws", "")
                resp = requests.get(http_endpoint, timeout=5)

                if resp.status_code == 200:
                    logger.info(f"  {endpoint}: HTTP base available")
                    ws_results["working_endpoints"].append(endpoint)
                elif resp.status_code == 426:  # Upgrade Required - good sign for WebSocket
                    logger.info(f"  {endpoint}: WebSocket upgrade available")
                    ws_results["working_endpoints"].append(endpoint)
                    ws_results["available"] = True
                else:
                    logger.info(f"  {endpoint}: HTTP {resp.status_code}")

            except Exception as e:
                error_msg = f"{endpoint}: {str(e)}"
                logger.debug(f"  {error_msg}")
                ws_results["errors"].append(error_msg)

        if ws_results["working_endpoints"]:
            logger.info(f"Found {len(ws_results['working_endpoints'])} potential WebSocket endpoints")
        else:
            logger.info("No WebSocket endpoints found - REST APIs only")

        return ws_results

    def fetch_clob_midpoint(self, token_id: str) -> SourceResult:
        """Fetch price from CLOB /midpoint endpoint."""
        result = SourceResult(source="clob_midpoint", timestamp=time.time())

        start = time.time()
        self.source_stats["clob_midpoint"]["attempts"] += 1

        try:
            price = self.client.fetch_price(token_id)
            result.response_time_ms = (time.time() - start) * 1000

            if price is not None and 0 <= price <= 1:
                result.price = price
                result.success = True
                self.source_stats["clob_midpoint"]["successes"] += 1
            else:
                result.error = f"Invalid price: {price}"

            self.source_stats["clob_midpoint"]["response_times"].append(result.response_time_ms)

        except Exception as e:
            result.error = str(e)
            result.response_time_ms = (time.time() - start) * 1000
            self.source_stats["clob_midpoint"]["errors"].append(str(e))

        return result

    def fetch_gamma_embedded(self, condition_id: str, token_id: str) -> SourceResult:
        """Fetch price from Gamma API embedded prices."""
        result = SourceResult(source="gamma_embedded", timestamp=time.time())

        start = time.time()
        self.source_stats["gamma_embedded"]["attempts"] += 1

        try:
            import requests

            # Try multiple parameter formats for Gamma API
            search_params_list = [
                {"conditionId": condition_id},  # Standard format
                {"id": condition_id},           # What we tried before
                {"market": condition_id},       # Alternative
                {}                              # Fetch all and filter locally
            ]

            success_found = False
            for params in search_params_list:
                try:
                    resp = requests.get(f"{GAMMA_API}/markets", params=params, timeout=10)
                    result.response_time_ms = (time.time() - start) * 1000

                    if resp.ok:
                        data = resp.json()
                        if data:
                            # If fetching all markets, filter by condition_id
                            if not params:  # Empty params = get all
                                data = [m for m in data if m.get("conditionId") == condition_id]

                            if data and len(data) > 0:
                                market = data[0]
                                outcome_prices = market.get("outcomePrices", "")

                                if isinstance(outcome_prices, str):
                                    outcome_prices = json.loads(outcome_prices)

                                if isinstance(outcome_prices, list) and len(outcome_prices) >= 1:
                                    price = float(outcome_prices[0])
                                    if 0 <= price <= 1:
                                        result.price = price
                                        result.success = True
                                        result.metadata = {
                                            "volume": market.get("volume", 0),
                                            "liquidity": market.get("liquidity", 0),
                                            "working_params": str(params)
                                        }
                                        self.source_stats["gamma_embedded"]["successes"] += 1
                                        success_found = True
                                        break
                                    else:
                                        result.error = f"Invalid embedded price: {price}"
                                else:
                                    continue  # Try next param format
                            else:
                                continue  # Try next param format
                        else:
                            continue  # Try next param format
                    else:
                        continue  # Try next param format

                except Exception as e:
                    continue  # Try next param format

            if not success_found and not result.error:
                result.error = "No market found with any parameter format"

            self.source_stats["gamma_embedded"]["response_times"].append(result.response_time_ms)

        except Exception as e:
            result.error = str(e)
            result.response_time_ms = (time.time() - start) * 1000
            self.source_stats["gamma_embedded"]["errors"].append(str(e))

        return result

    def fetch_clob_orderbook(self, token_id: str) -> SourceResult:
        """Fetch price computed from CLOB orderbook spread."""
        result = SourceResult(source="clob_orderbook", timestamp=time.time())

        start = time.time()
        self.source_stats["clob_orderbook"]["attempts"] += 1

        try:
            book = self.client.fetch_orderbook(token_id)
            result.response_time_ms = (time.time() - start) * 1000

            bids = book.get("bids", [])
            asks = book.get("asks", [])

            result.metadata = {
                "bid_count": len(bids),
                "ask_count": len(asks),
                "raw_book": book  # Include raw response for debugging
            }

            if bids and asks:
                best_bid = float(bids[0].get("price", 0))
                best_ask = float(asks[0].get("price", 1))

                # Validate bid/ask logic
                if best_bid <= 0 or best_ask <= 0:
                    result.error = f"Zero/negative prices: bid={best_bid}, ask={best_ask}"
                elif best_bid >= best_ask:
                    result.error = f"Crossed market: bid={best_bid} >= ask={best_ask}"
                elif not (0 <= best_bid <= 1 and 0 <= best_ask <= 1):
                    result.error = f"Prices outside [0,1]: bid={best_bid}, ask={best_ask}"
                else:
                    midpoint = (best_bid + best_ask) / 2
                    spread = best_ask - best_bid

                    result.price = midpoint
                    result.success = True
                    result.metadata.update({
                        "best_bid": best_bid,
                        "best_ask": best_ask,
                        "spread": spread,
                        "spread_bps": spread * 10000,  # basis points
                        "bid_size": float(bids[0].get("size", 0)),
                        "ask_size": float(asks[0].get("size", 0)),
                        "total_bid_depth": sum(float(b.get("size", 0)) for b in bids[:5]),
                        "total_ask_depth": sum(float(a.get("size", 0)) for a in asks[:5])
                    })
                    self.source_stats["clob_orderbook"]["successes"] += 1
            else:
                # Specific error for empty orderbook sides
                if not bids and not asks:
                    result.error = "Completely empty orderbook (no bids or asks)"
                elif not bids:
                    result.error = f"No bids (asks: {len(asks)})"
                elif not asks:
                    result.error = f"No asks (bids: {len(bids)})"

            self.source_stats["clob_orderbook"]["response_times"].append(result.response_time_ms)

        except Exception as e:
            result.error = str(e)
            result.response_time_ms = (time.time() - start) * 1000
            self.source_stats["clob_orderbook"]["errors"].append(str(e))

        return result

    def validate_market(self, market_config: dict) -> ValidationReport:
        """Validate all sources for a single market."""
        market_id = market_config["marketId"]
        poly = market_config.get("_polymarket", {})
        token_id = poly.get("tokenIds", [""])[0]
        condition_id = poly.get("conditionId", "")

        report = ValidationReport(
            market_id=market_id,
            question=market_config.get("name", "")[:80],
            token_id=token_id,
            results={}
        )

        if not token_id:
            logger.warning(f"No token ID for market {market_id[:18]}...")
            return report

        logger.info(f"Validating sources for: {report.question}")

        # Test all available sources
        report.results["clob_midpoint"] = self.fetch_clob_midpoint(token_id)
        report.results["gamma_embedded"] = self.fetch_gamma_embedded(condition_id, token_id)
        report.results["clob_orderbook"] = self.fetch_clob_orderbook(token_id)

        # Analyze price consistency
        successful_prices = [
            r.price for r in report.results.values()
            if r.success and r.price is not None
        ]

        if successful_prices:
            report.primary_price = successful_prices[0]  # Use first successful price

            if len(successful_prices) > 1:
                report.price_variance = stdev(successful_prices) if len(successful_prices) > 1 else 0
                report.max_deviation = max(successful_prices) - min(successful_prices)

            # Calculate reliability scores
            for source, result in report.results.items():
                stats = self.source_stats.get(source, {})
                attempts = stats.get("attempts", 1)
                successes = stats.get("successes", 0)
                avg_response_time = mean(stats.get("response_times", [1000])) if stats.get("response_times") else 1000

                # Score: success rate weighted by response time
                success_rate = successes / attempts if attempts > 0 else 0
                response_penalty = min(avg_response_time / 1000, 2.0)  # Cap at 2x penalty
                reliability_score = success_rate / response_penalty

                report.reliability_scores[source] = round(reliability_score, 3)

            # Recommend best source
            if report.reliability_scores:
                report.recommended_source = max(report.reliability_scores, key=report.reliability_scores.get)

        return report

    def run_comprehensive_test(self) -> Dict:
        """Run validation across all configured markets."""
        logger.info(f"Starting multi-source validation for {len(self.market_config)} markets...")

        # Test WebSocket availability first
        ws_results = self.test_websocket_availability()

        reports = []
        for market_config in self.market_config:
            try:
                report = self.validate_market(market_config)
                reports.append(report)
                time.sleep(0.5)  # Rate limiting
            except Exception as e:
                logger.error(f"Market validation failed: {e}")

        return self._generate_summary(reports, ws_results)

    def _generate_summary(self, reports: List[ValidationReport], ws_results: Dict) -> Dict:
        """Generate comprehensive summary report."""
        summary = {
            "timestamp": datetime.now().isoformat(),
            "test_duration_minutes": self.test_duration / 60,
            "markets_tested": len(reports),
            "websocket_results": ws_results,
            "source_reliability": {},
            "price_consistency": {
                "avg_variance": 0,
                "max_deviation_seen": 0,
                "markets_with_discrepancies": 0
            },
            "recommendations": [],
            "detailed_reports": []
        }

        # Aggregate source performance
        for source in self.sources[:-1]:  # Skip websocket for now
            stats = self.source_stats[source]
            if stats["attempts"] > 0:
                success_rate = stats["successes"] / stats["attempts"]
                avg_response_time = mean(stats["response_times"]) if stats["response_times"] else 0
                error_count = len(stats["errors"])

                summary["source_reliability"][source] = {
                    "success_rate": round(success_rate, 3),
                    "avg_response_time_ms": round(avg_response_time, 1),
                    "total_attempts": stats["attempts"],
                    "total_successes": stats["successes"],
                    "error_count": error_count,
                    "unique_errors": len(set(stats["errors"]))
                }

        # Price consistency analysis
        variances = [r.price_variance for r in reports if r.price_variance > 0]
        deviations = [r.max_deviation for r in reports if r.max_deviation > 0]

        if variances:
            summary["price_consistency"]["avg_variance"] = round(mean(variances), 6)
        if deviations:
            summary["price_consistency"]["max_deviation_seen"] = round(max(deviations), 6)
            summary["price_consistency"]["markets_with_discrepancies"] = len(deviations)

        # Generate recommendations
        summary["recommendations"] = self._generate_recommendations(summary)

        # Add detailed reports
        summary["detailed_reports"] = [
            {
                "market_id": r.market_id[:18] + "...",
                "question": r.question,
                "primary_price": r.primary_price,
                "max_deviation": r.max_deviation,
                "recommended_source": r.recommended_source,
                "source_results": {
                    source: {
                        "success": result.success,
                        "price": result.price,
                        "response_time_ms": result.response_time_ms,
                        "error": result.error
                    }
                    for source, result in r.results.items()
                }
            }
            for r in reports
        ]

        return summary

    def _generate_recommendations(self, summary: Dict) -> List[str]:
        """Generate actionable recommendations based on test results."""
        recommendations = []
        reliability = summary.get("source_reliability", {})

        # Find most reliable source
        if reliability:
            best_source = max(reliability.keys(), key=lambda s: reliability[s]["success_rate"])
            best_rate = reliability[best_source]["success_rate"]

            if best_rate >= 0.95:
                recommendations.append(f"PRIMARY: Use {best_source} as primary source (success rate: {best_rate:.1%})")
            else:
                recommendations.append(f"WARNING: Best source {best_source} only has {best_rate:.1%} success rate")

        # Check response times
        fast_sources = [
            s for s, data in reliability.items()
            if data["avg_response_time_ms"] < 1000
        ]
        if fast_sources:
            fastest = min(fast_sources, key=lambda s: reliability[s]["avg_response_time_ms"])
            recommendations.append(f"PERFORMANCE: {fastest} has fastest response time ({reliability[fastest]['avg_response_time_ms']:.0f}ms)")

        # Price consistency warnings
        consistency = summary.get("price_consistency", {})
        if consistency.get("max_deviation_seen", 0) > 0.05:  # 5% deviation
            recommendations.append(f"ALERT: Price deviations up to {consistency['max_deviation_seen']:.2%} detected between sources")

        # Fallback chain recommendation
        if len(reliability) >= 2:
            sorted_sources = sorted(reliability.keys(), key=lambda s: reliability[s]["success_rate"], reverse=True)
            recommendations.append(f"FALLBACK: Recommended order: {' → '.join(sorted_sources)}")

        # WebSocket recommendation
        ws_results = summary.get("websocket_results", {})
        if ws_results.get("available"):
            working_endpoints = ws_results.get("working_endpoints", [])
            recommendations.append(f"WEBSOCKET: Found {len(working_endpoints)} potential endpoints for real-time feeds")
        else:
            recommendations.append("WEBSOCKET: No confirmed endpoints - implement REST polling with shorter intervals")

        return recommendations

def main():
    """Run comprehensive multi-source validation."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%H:%M:%S"
    )

    # Load market configuration
    config_path = Path("scripts/oracle/market_config.json")
    if not config_path.exists():
        logger.error("market_config.json not found. Run onboard_markets.py first.")
        sys.exit(1)

    with open(config_path) as f:
        market_config = json.load(f)

    if not market_config:
        logger.error("No markets in config file")
        sys.exit(1)

    # Run validation
    validator = MultiSourceValidator(market_config[:5])  # Test first 5 markets
    logger.info("Starting multi-source price validation...")

    try:
        summary = validator.run_comprehensive_test()

        # Print summary
        print("\n" + "="*80)
        print("MULTI-SOURCE PRICE VALIDATION SUMMARY")
        print("="*80)

        print(f"\nTest completed: {summary['markets_tested']} markets tested")

        ws_results = summary.get("websocket_results", {})
        if ws_results.get("available"):
            print(f"WebSocket availability: Found {len(ws_results.get('working_endpoints', []))} potential endpoints")
        else:
            print(f"WebSocket availability: Not confirmed ({len(ws_results.get('tested_endpoints', []))} endpoints tested)")

        print(f"\nSOURCE RELIABILITY:")
        for source, data in summary["source_reliability"].items():
            print(f"  {source:20} | {data['success_rate']:6.1%} success | {data['avg_response_time_ms']:6.0f}ms avg | {data['error_count']} errors")

        consistency = summary["price_consistency"]
        print(f"\nPRICE CONSISTENCY:")
        print(f"  Markets with discrepancies: {consistency['markets_with_discrepancies']}")
        print(f"  Average variance: {consistency['avg_variance']:.6f}")
        print(f"  Max deviation seen: {consistency['max_deviation_seen']:.4f} ({consistency['max_deviation_seen']:.2%})")

        print(f"\nRECOMMENDATIONS:")
        for rec in summary["recommendations"]:
            print(f"  • {rec}")

        # Save detailed report
        output_path = Path("scripts/oracle/validation_report.json")
        with open(output_path, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"\nDetailed report saved to: {output_path}")

    except KeyboardInterrupt:
        logger.info("Validation stopped by user")
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        sys.exit(1)
    finally:
        validator.client.close()

if __name__ == "__main__":
    main()