#!/usr/bin/env bash
# compare.sh — run baseline bench for slow and optimized variants, save results.
#
# Usage:
#   bash scripts/compare.sh [slow|optimized|both]   (default: both)
#
# Output: broken-app/artifacts/
#   baseline_slow.txt
#   baseline_optimized.txt

set -euo pipefail

VARIANT="${1:-both}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$PROJECT_DIR/artifacts"

mkdir -p "$ARTIFACTS_DIR"

run_bench() {
    local features="$1"
    local label="$2"
    local outfile="$ARTIFACTS_DIR/baseline_${label}.txt"

    echo "--> cargo bench --bench baseline $features"
    (cd "$PROJECT_DIR" && cargo bench --bench baseline $features) | tee "$outfile"
    echo "    saved -> artifacts/baseline_${label}.txt"
}

case "$VARIANT" in
    slow)
        run_bench "" "slow"
        ;;
    optimized)
        run_bench "--features optimized" "optimized"
        ;;
    both)
        run_bench "" "slow"
        run_bench "--features optimized" "optimized"
        ;;
    *)
        echo "Usage: $0 [slow|optimized|both]"
        exit 1
        ;;
esac

# ── side-by-side diff if both files exist ─────────────────────────────────────
SLOW_FILE="$ARTIFACTS_DIR/baseline_slow.txt"
OPT_FILE="$ARTIFACTS_DIR/baseline_optimized.txt"

if [[ -f "$SLOW_FILE" && -f "$OPT_FILE" ]]; then
    echo ""
    echo "==> Comparison (slow vs optimized):"

    COL=55
    printf "%-${COL}s  %s\n" "SLOW" "OPTIMIZED"
    printf "%-${COL}s  %s\n" "$(printf '─%.0s' $(seq 1 $COL))" "$(printf '─%.0s' $(seq 1 $COL))"

    paste \
        <(grep -E '(slow|optimized|sum|dedup|fib)' "$SLOW_FILE") \
        <(grep -E '(slow|optimized|sum|dedup|fib)' "$OPT_FILE") |
    while IFS=$'\t' read -r left right; do
        printf "%-${COL}s  %s\n" "$left" "$right"
    done
fi

echo ""
echo "==> Done. Artifacts in: $ARTIFACTS_DIR"
