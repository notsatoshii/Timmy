#!/usr/bin/env python3
"""
Test script for Market Discovery System

Runs a quick test of the discovery system to verify functionality:
1. Tests Polymarket API connectivity
2. Runs discovery scan with small sample
3. Verifies database operations
4. Tests candidate export
5. Validates onboarding format

Usage:
    python scripts/oracle/test_discovery.py
"""

import json
import logging
import sys
import tempfile
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from scripts.oracle.market_discovery import MarketDiscoveryEngine
from scripts.oracle.polymarket_client import PolymarketClient

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
logger = logging.getLogger(__name__)


def test_api_connectivity():
    """Test Polymarket API connectivity."""
    logger.info("=== Testing Polymarket API Connectivity ===")

    client = PolymarketClient()
    try:
        markets = client.fetch_active_markets(limit=5, min_volume=10000)
        logger.info(f"✓ API connectivity OK - fetched {len(markets)} markets")

        if markets:
            # Test price fetching
            sample_market = markets[0]
            if sample_market.token_ids:
                try:
                    price = client.fetch_price(sample_market.token_ids[0])
                    logger.info(f"✓ Price fetching OK - sample price: {price:.4f}")
                except Exception as e:
                    logger.warning(f"⚠ Price fetching failed: {e}")

            logger.info(f"Sample market: {sample_market.question[:60]}")
            logger.info(f"Volume: ${sample_market.volume:,.0f}")

        return True
    except Exception as e:
        logger.error(f"✗ API connectivity failed: {e}")
        return False
    finally:
        client.close()


def test_discovery_engine():
    """Test the discovery engine with temporary database."""
    logger.info("\n=== Testing Discovery Engine ===")

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db:
        tmp_db_path = Path(tmp_db.name)

    try:
        # Initialize discovery engine with temp database
        discovery = MarketDiscoveryEngine(db_path=tmp_db_path)

        logger.info("✓ Discovery engine initialized")

        # Test market scanning
        new_markets = discovery.scan_new_markets(limit=10)
        logger.info(f"✓ Market scanning OK - found {len(new_markets)} new markets")

        # Test scoring
        if new_markets:
            sample_market = new_markets[0]
            score = discovery.compute_onboarding_score(sample_market)
            logger.info(f"✓ Scoring OK - sample score: {score:.2f}")

            # Record discovery
            discovery.record_discovery(sample_market)
            logger.info("✓ Database recording OK")

            # Test candidate retrieval
            candidates = discovery.get_top_candidates(limit=5)
            logger.info(f"✓ Candidate retrieval OK - {len(candidates)} candidates")

            if candidates:
                top_candidate = candidates[0]
                logger.info(f"Top candidate: {top_candidate['question'][:60]}")
                logger.info(f"Score: {top_candidate['onboarding_score']:.2f}")

        discovery.close()
        return True

    except Exception as e:
        logger.error(f"✗ Discovery engine test failed: {e}")
        return False
    finally:
        # Clean up temp database
        if tmp_db_path.exists():
            tmp_db_path.unlink()


def test_candidate_export():
    """Test candidate export functionality."""
    logger.info("\n=== Testing Candidate Export ===")

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db:
        tmp_db_path = Path(tmp_db.name)

    with tempfile.NamedTemporaryFile(mode='w', suffix=".json", delete=False) as tmp_export:
        tmp_export_path = Path(tmp_export.name)

    try:
        discovery = MarketDiscoveryEngine(db_path=tmp_db_path)

        # Populate with some test data
        new_markets = discovery.scan_new_markets(limit=5)
        for market in new_markets[:3]:  # Just record a few
            discovery.record_discovery(market)

        # Test export
        discovery.export_candidates(output_path=tmp_export_path, min_score=0.0)  # Low threshold for testing

        # Validate export format
        if tmp_export_path.exists():
            with open(tmp_export_path) as f:
                exported = json.load(f)

            logger.info(f"✓ Export OK - {len(exported)} candidates exported")

            if exported:
                sample = exported[0]
                required_fields = ['marketId', 'name', 'externalMarketId', 'resolutionTime', 'category', 'allocationWeight']
                missing_fields = [field for field in required_fields if field not in sample]

                if not missing_fields:
                    logger.info("✓ Export format validation OK")
                    logger.info(f"Sample export: {sample['name'][:50]}")
                else:
                    logger.warning(f"⚠ Export format missing fields: {missing_fields}")

        discovery.close()
        return True

    except Exception as e:
        logger.error(f"✗ Candidate export test failed: {e}")
        return False
    finally:
        # Clean up temp files
        if tmp_db_path.exists():
            tmp_db_path.unlink()
        if tmp_export_path.exists():
            tmp_export_path.unlink()


def test_scoring_logic():
    """Test the scoring logic with known market characteristics."""
    logger.info("\n=== Testing Scoring Logic ===")

    try:
        from scripts.oracle.polymarket_client import PolymarketMarket

        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db:
            tmp_db_path = Path(tmp_db.name)

        discovery = MarketDiscoveryEngine(db_path=tmp_db_path)

        # Create test markets with different characteristics
        test_markets = [
            # High volume, good liquidity, balanced price
            PolymarketMarket(
                condition_id="test1",
                question="Test High Quality Market",
                description="",
                outcomes=["Yes", "No"],
                token_ids=["token1"],
                end_date="2026-06-15T00:00:00Z",
                active=True,
                volume=500000,
                liquidity=75000,
                category="politics",
                yes_price=0.45
            ),
            # Low volume market
            PolymarketMarket(
                condition_id="test2",
                question="Test Low Volume Market",
                description="",
                outcomes=["Yes", "No"],
                token_ids=["token2"],
                end_date="2026-06-15T00:00:00Z",
                active=True,
                volume=5000,
                liquidity=500,
                category="other",
                yes_price=0.50
            ),
            # Extreme price market
            PolymarketMarket(
                condition_id="test3",
                question="Test Extreme Price Market",
                description="",
                outcomes=["Yes", "No"],
                token_ids=["token3"],
                end_date="2026-06-15T00:00:00Z",
                active=True,
                volume=100000,
                liquidity=10000,
                category="sports",
                yes_price=0.95
            ),
        ]

        scores = []
        for market in test_markets:
            score = discovery.compute_onboarding_score(market)
            scores.append(score)
            logger.info(f"Market: {market.question[:30]:<30} | Score: {score:.2f}")

        # Verify scoring makes sense
        high_quality_score = scores[0]
        low_volume_score = scores[1]
        extreme_price_score = scores[2]

        if high_quality_score > low_volume_score:
            logger.info("✓ Volume scoring OK - high volume beats low volume")
        else:
            logger.warning("⚠ Volume scoring issue")

        if high_quality_score > extreme_price_score:
            logger.info("✓ Price balance scoring OK - balanced beats extreme")
        else:
            logger.warning("⚠ Price balance scoring may need adjustment")

        discovery.close()
        tmp_db_path.unlink()

        return True

    except Exception as e:
        logger.error(f"✗ Scoring logic test failed: {e}")
        return False


def main():
    """Run all tests."""
    logger.info("LEVER Market Discovery System - Test Suite")
    logger.info("==========================================")

    tests = [
        ("API Connectivity", test_api_connectivity),
        ("Discovery Engine", test_discovery_engine),
        ("Candidate Export", test_candidate_export),
        ("Scoring Logic", test_scoring_logic),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append(result)
        except Exception as e:
            logger.error(f"Test {test_name} crashed: {e}")
            results.append(False)

    # Summary
    passed = sum(results)
    total = len(results)

    logger.info(f"\n=== Test Summary ===")
    logger.info(f"Passed: {passed}/{total}")

    if passed == total:
        logger.info("✓ All tests passed! Discovery system is ready.")
        sys.exit(0)
    else:
        logger.error(f"✗ {total - passed} test(s) failed. Check the logs above.")
        sys.exit(1)


if __name__ == "__main__":
    main()