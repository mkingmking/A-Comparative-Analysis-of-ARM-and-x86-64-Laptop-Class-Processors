#!/bin/bash
# rerun_timing.sh - clean re-run of the M3 wall-clock timing protocol
#
# Rebuilds fib_arm/matmul_arm from source and re-runs the exact protocol
# already reported in results/results_mac.txt (hyperfine, 5 warm-up runs,
# 100 measured runs), gated on check_measurement_conditions.sh so this can't
# repeat the Low-Power-Mode contamination found in the original session.
#
# Usage:
#   ./rerun_timing.sh
#
# Output:
#   results/rerun_<timestamp>/fib_arm.json, fib_arm.csv
#   results/rerun_<timestamp>/matmul_arm.json, matmul_arm.csv
#   results/rerun_<timestamp>/summary.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

"$REPO_ROOT/benchmarks/scripts/check_measurement_conditions.sh" || {
    echo ""
    echo "Refusing to run the timing re-measurement until the above is fixed."
    exit 1
}

cd "$SCRIPT_DIR"

echo ""
echo "=== Rebuilding fib_arm / matmul_arm from source ==="
SDK=$(xcrun --sdk macosx --show-sdk-path)
as -o fib_arm.o fib_arm.s
ld -o fib_arm fib_arm.o -lSystem -syslibroot "$SDK" -e _main
as -o matmul_arm.o matmul_arm.s
ld -o matmul_arm matmul_arm.o -lSystem -syslibroot "$SDK" -e _main
rm -f fib_arm.o matmul_arm.o
echo "Rebuilt fib_arm and matmul_arm."

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$REPO_ROOT/results/rerun_$TS"
mkdir -p "$OUTDIR"

echo ""
echo "=== Sanity check: correctness ==="
./fib_arm
./matmul_arm

echo ""
echo "=== hyperfine: fib_arm (5 warmup, 100 runs) ==="
hyperfine --warmup 5 --runs 100 \
    --export-json "$OUTDIR/fib_arm.json" \
    --export-csv "$OUTDIR/fib_arm.csv" \
    './fib_arm'

echo ""
echo "=== hyperfine: matmul_arm (5 warmup, 100 runs) ==="
hyperfine --warmup 5 --runs 100 \
    --export-json "$OUTDIR/matmul_arm.json" \
    --export-csv "$OUTDIR/matmul_arm.csv" \
    './matmul_arm'

FIB_MEAN=$(python3 -c "import json; print(json.load(open('$OUTDIR/fib_arm.json'))['results'][0]['mean'])")
MATMUL_MEAN=$(python3 -c "import json; print(json.load(open('$OUTDIR/matmul_arm.json'))['results'][0]['mean'])")

{
    echo "M3 timing re-run - $TS"
    echo "======================================"
    echo "Preconditions verified: AC power, Low Power Mode off (see"
    echo "check_measurement_conditions.sh output printed above)."
    echo ""
    echo "fib(40)    mean runtime (s): $FIB_MEAN"
    echo "matmul     mean runtime (s): $MATMUL_MEAN"
    echo ""
    echo "Compare against the original (possibly throttled) session:"
    echo "  fib(40)    583.6 ms  (results/results_mac.txt)"
    echo "  matmul      26.0 ms  (results/results_mac.txt)"
    echo ""
    echo "Compare against Ryzen (results/linux_timing.txt):"
    echo "  fib(40)    474.8 ms"
    echo "  matmul      26.4 ms"
    echo ""
    echo "Next step: feed \$FIB_MEAN / \$MATMUL_MEAN into rerun_energy.sh as"
    echo "the MEAN_RUNTIME_S argument, e.g.:"
    echo "  sudo ./rerun_energy.sh ./fib_arm    $FIB_MEAN 25"
    echo "  sudo ./rerun_energy.sh ./matmul_arm $MATMUL_MEAN 25"
} | tee "$OUTDIR/summary.txt"

echo ""
echo "Results written to $OUTDIR"
