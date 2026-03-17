#!/usr/bin/env bash
# profile.sh — flamegraph + massif for slow and optimized variants.
# Runs inside Docker (perf + valgrind not available on Windows/macOS).
#
# Usage:
#   bash scripts/profile.sh [slow|optimized|both]   (default: both)
#
# Output: broken-app/artifacts/
#   flamegraph_<variant>.svg
#   massif_<variant>.out
#   massif_<variant>.txt   (ms_print summary)

set -euo pipefail

VARIANT="${1:-both}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$PROJECT_DIR/artifacts"
IMAGE="broken-app-profile"
VOLUME="broken-app-profile-vol"

mkdir -p "$ARTIFACTS_DIR"

# ── helpers ────────────────────────────────────────────────────────────────────

build_image() {
    echo "==> Building Docker image: $IMAGE"
    docker build -t "$IMAGE" "$PROJECT_DIR"
}

ensure_volume() {
    docker volume inspect "$VOLUME" > /dev/null 2>&1 \
        || docker volume create "$VOLUME" > /dev/null
}

# Run a command inside Docker with perf/valgrind access.
# $1 = feature flag ("" for slow, "--features optimized" for optimized)
# $2 = variant label (slow | optimized)
run_profile() {
    local features="$1"
    local label="$2"

    echo ""
    echo "══════════════════════════════════════════"
    echo "  Profiling variant: $label"
    echo "══════════════════════════════════════════"

    # Build release binary for this variant inside a fresh container.
    # We use a named volume so the compiled binary persists for both tools.
    docker run --rm \
        --privileged \
        -v "$VOLUME:/app/target" \
        "$IMAGE" \
        bash -c "
            set -euo pipefail
            cargo build --release $features
        "

    # ── flamegraph ──────────────────────────────────────────────────────────
    echo "--> flamegraph ($label)"
    docker run --rm \
        --privileged \
        -v "$VOLUME:/app/target" \
        "$IMAGE" \
        bash -c "
            set -euo pipefail
            # perf requires kernel.perf_event_paranoid <= 1
            echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
            cargo flamegraph --release $features \
                --bin demo \
                --output /tmp/flamegraph_${label}.svg
            cp /tmp/flamegraph_${label}.svg /app/target/flamegraph_${label}.svg
        "

    # ── massif ──────────────────────────────────────────────────────────────
    echo "--> massif ($label)"
    docker run --rm \
        --privileged \
        -v "$VOLUME:/app/target" \
        "$IMAGE" \
        bash -c "
            set -euo pipefail
            valgrind --tool=massif \
                --massif-out-file=/app/target/massif_${label}.out \
                ./target/release/demo
            ms_print /app/target/massif_${label}.out \
                > /app/target/massif_${label}.txt
        "

    # ── extract artifacts ───────────────────────────────────────────────────
    echo "--> extracting artifacts"
    local tmp_ctr
    tmp_ctr=$(docker create -v "$VOLUME:/app/target" "$IMAGE" true)
    docker cp "$tmp_ctr:/app/target/flamegraph_${label}.svg" \
        "$ARTIFACTS_DIR/flamegraph_${label}.svg"
    docker cp "$tmp_ctr:/app/target/massif_${label}.out" \
        "$ARTIFACTS_DIR/massif_${label}.out"
    docker cp "$tmp_ctr:/app/target/massif_${label}.txt" \
        "$ARTIFACTS_DIR/massif_${label}.txt"
    docker rm "$tmp_ctr" > /dev/null

    echo "    flamegraph -> artifacts/flamegraph_${label}.svg"
    echo "    massif     -> artifacts/massif_${label}.out"
    echo "    ms_print   -> artifacts/massif_${label}.txt"
}

# ── main ───────────────────────────────────────────────────────────────────────

build_image
ensure_volume

case "$VARIANT" in
    slow)
        run_profile "" "slow"
        ;;
    optimized)
        run_profile "--features optimized" "optimized"
        ;;
    both)
        run_profile "" "slow"
        run_profile "--features optimized" "optimized"
        ;;
    *)
        echo "Usage: $0 [slow|optimized|both]"
        exit 1
        ;;
esac

echo ""
echo "==> Done. Artifacts in: $ARTIFACTS_DIR"
ls -lh "$ARTIFACTS_DIR"/flamegraph_*.svg "$ARTIFACTS_DIR"/massif_*.txt 2>/dev/null || true
