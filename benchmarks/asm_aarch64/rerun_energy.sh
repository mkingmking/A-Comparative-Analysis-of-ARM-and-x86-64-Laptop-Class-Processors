#!/bin/bash
# rerun_energy.sh - energy re-run wrapper: measure + analyze in one step
#
# Thin wrapper around measure_power_mac_repeated.sh (which now refuses to
# start unless check_measurement_conditions.sh passes) that also runs
# analyze_energy_windows.py automatically afterward, so the CSV and the
# mean/CI/Welch's-t-test output are produced in one call.
#
# Usage:
#   sudo ./rerun_energy.sh <fib_arm|matmul_arm> <mean_runtime_s> [N=25]
#
# mean_runtime_s should come from the fresh hyperfine numbers in
# rerun_timing.sh's output (results/rerun_<timestamp>/summary.txt), NOT the
# old 0.5836 / 0.0260 values -- those were from the same session suspected
# of running under Low Power Mode.
#
# Examples:
#   sudo ./rerun_energy.sh ./fib_arm    0.4123 25
#   sudo ./rerun_energy.sh ./matmul_arm 0.0198 25

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BENCHMARK=${1:?"Usage: sudo $0 <./fib_arm|./matmul_arm> <mean_runtime_s> [N=25]"}
MEAN_RUNTIME_S=${2:?"Usage: sudo $0 <./fib_arm|./matmul_arm> <mean_runtime_s> [N=25]"}
N=${3:-25}

BASE=$(basename "$BENCHMARK")
case "$BASE" in
    fib_arm)    TAG=fib ;;
    matmul_arm) TAG=matmul ;;
    *)
        echo "ERROR: expected ./fib_arm or ./matmul_arm, got $BENCHMARK"
        exit 1
        ;;
esac

TS=$(date +%Y%m%d_%H%M%S)
CSV="$SCRIPT_DIR/energy_windows_${BASE}_${TS}.csv"

"$SCRIPT_DIR/measure_power_mac_repeated.sh" "$BENCHMARK" "$MEAN_RUNTIME_S" "$N" "$CSV"

echo ""
echo "=== Analyzing $CSV ==="
python3 "$REPO_ROOT/benchmarks/analysis/analyze_energy_windows.py" "$CSV" "$TAG"
