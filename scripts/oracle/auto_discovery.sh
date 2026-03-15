#!/bin/bash
#
# Auto Discovery Pipeline — Automated market discovery and candidate generation
#
# This script integrates market discovery with the existing onboarding pipeline:
# 1. Runs market discovery scan
# 2. Exports qualified candidates
# 3. Optionally generates onboarding config
# 4. Logs results for review
#
# Usage:
#   ./scripts/oracle/auto_discovery.sh                    # discover + export candidates
#   ./scripts/oracle/auto_discovery.sh --auto-onboard    # generate full onboarding config
#   ./scripts/oracle/auto_discovery.sh --daemon          # continuous discovery daemon
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
MIN_SCORE=${MIN_SCORE:-65.0}  # Minimum onboarding score for auto-consideration
MAX_CANDIDATES=${MAX_CANDIDATES:-15}  # Max markets to include in auto-onboard
DISCOVERY_LOG="$SCRIPT_DIR/discovery.log"
CANDIDATES_FILE="$SCRIPT_DIR/candidates.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_dependencies() {
    if ! command -v python3 &> /dev/null; then
        error "python3 is required"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/market_discovery.py" ]; then
        error "market_discovery.py not found in $SCRIPT_DIR"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/polymarket_client.py" ]; then
        error "polymarket_client.py not found in $SCRIPT_DIR"
        exit 1
    fi
}

run_discovery() {
    log "Running market discovery scan..."

    cd "$PROJECT_ROOT"
    python3 scripts/oracle/market_discovery.py --verbose

    if [ $? -eq 0 ]; then
        success "Discovery scan completed"
    else
        error "Discovery scan failed"
        exit 1
    fi
}

export_candidates() {
    log "Exporting qualified candidates (min score: $MIN_SCORE)..."

    cd "$PROJECT_ROOT"
    python3 scripts/oracle/market_discovery.py --export-candidates --min-score "$MIN_SCORE"

    if [ $? -eq 0 ] && [ -f "$CANDIDATES_FILE" ]; then
        local count=$(jq length "$CANDIDATES_FILE")
        success "Exported $count candidates to candidates.json"

        if [ "$count" -gt 0 ]; then
            log "Top candidates:"
            jq -r '.[:5][] | "  - [\(._discovery.onboardingScore)] \(.name[:60])"' "$CANDIDATES_FILE"

            if [ "$count" -gt 5 ]; then
                log "  ... and $((count - 5)) more"
            fi
        else
            warn "No candidates met the minimum score threshold of $MIN_SCORE"
        fi
    else
        error "Failed to export candidates"
        exit 1
    fi
}

generate_onboarding_config() {
    log "Generating onboarding configuration from candidates..."

    if [ ! -f "$CANDIDATES_FILE" ]; then
        error "No candidates.json found. Run discovery first."
        exit 1
    fi

    local candidate_count=$(jq length "$CANDIDATES_FILE")
    local onboard_count=$(( candidate_count < MAX_CANDIDATES ? candidate_count : MAX_CANDIDATES ))

    if [ "$onboard_count" -eq 0 ]; then
        warn "No candidates available for onboarding"
        return
    fi

    log "Selecting top $onboard_count candidates for onboarding config..."

    # Take top N candidates and format them properly for onboarding
    jq ".[:$onboard_count]" "$CANDIDATES_FILE" > "$SCRIPT_DIR/market_config.json"

    success "Generated market_config.json with $onboard_count markets"
    log "Next steps:"
    log "  1. Review: cat scripts/oracle/market_config.json"
    log "  2. Deploy: forge script script/OnboardMarkets.s.sol --rpc-url \$RPC --broadcast"
}

show_status() {
    log "Market Discovery Status"
    echo "======================"

    if [ -f "$SCRIPT_DIR/discovery.db" ]; then
        local db_size=$(du -h "$SCRIPT_DIR/discovery.db" | cut -f1)
        log "Discovery database: $db_size"

        # Show stats via Python
        cd "$PROJECT_ROOT"
        python3 -c "
import sqlite3
with sqlite3.connect('scripts/oracle/discovery.db') as conn:
    cursor = conn.cursor()
    cursor.execute('SELECT status, COUNT(*) FROM discovered_markets GROUP BY status')
    stats = cursor.fetchall()
    cursor.execute('SELECT AVG(onboarding_score) FROM discovered_markets WHERE status IN (\"discovered\", \"candidate\")')
    avg_score = cursor.fetchone()[0] or 0

    print('  Markets by status:')
    for status, count in stats:
        print(f'    {status}: {count}')
    print(f'  Average onboarding score: {avg_score:.1f}')
"
    else
        warn "No discovery database found. Run discovery first."
    fi

    if [ -f "$CANDIDATES_FILE" ]; then
        local candidate_count=$(jq length "$CANDIDATES_FILE")
        log "Current candidates: $candidate_count"
    else
        log "No candidates file found"
    fi

    if [ -f "$DISCOVERY_LOG" ]; then
        local last_scan=$(tail -n 1 "$DISCOVERY_LOG" | cut -d'|' -f1 | xargs)
        log "Last scan: $last_scan"
    fi
}

# Parse arguments
AUTO_ONBOARD=false
DAEMON_MODE=false
STATUS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-onboard)
            AUTO_ONBOARD=true
            shift
            ;;
        --daemon)
            DAEMON_MODE=true
            shift
            ;;
        --status)
            STATUS_ONLY=true
            shift
            ;;
        --min-score)
            MIN_SCORE="$2"
            shift 2
            ;;
        --max-candidates)
            MAX_CANDIDATES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-onboard     Generate market_config.json from candidates"
            echo "  --daemon           Run continuous discovery (every hour)"
            echo "  --status           Show discovery system status"
            echo "  --min-score N      Minimum onboarding score (default: 65.0)"
            echo "  --max-candidates N Max candidates for auto-onboard (default: 15)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log "LEVER Market Discovery Pipeline"

    check_dependencies

    if [ "$STATUS_ONLY" = true ]; then
        show_status
        return
    fi

    if [ "$DAEMON_MODE" = true ]; then
        log "Starting discovery daemon..."
        cd "$PROJECT_ROOT"
        exec python3 scripts/oracle/market_discovery.py --daemon --interval 3600
    fi

    # Standard discovery pipeline
    run_discovery
    export_candidates

    if [ "$AUTO_ONBOARD" = true ]; then
        generate_onboarding_config
    fi

    success "Discovery pipeline completed"

    # Show quick summary
    if [ -f "$CANDIDATES_FILE" ]; then
        local count=$(jq length "$CANDIDATES_FILE")
        if [ "$count" -gt 0 ]; then
            log "Found $count qualified candidates. Next steps:"
            if [ "$AUTO_ONBOARD" = true ]; then
                log "  Review: cat scripts/oracle/market_config.json"
                log "  Deploy: forge script script/OnboardMarkets.s.sol --rpc-url \$RPC --broadcast"
            else
                log "  Generate config: $0 --auto-onboard"
                log "  Manual review: cat scripts/oracle/candidates.json"
            fi
        fi
    fi
}

main "$@"