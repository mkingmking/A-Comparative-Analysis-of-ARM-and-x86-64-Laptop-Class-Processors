#!/bin/bash
# diagnose_profile_clock.sh - is Instruments landing the profile target on E-cores?
#
# The Instruments PMU rerun showed cycles/s ~2.0-2.1 GHz for
# fib_profile_O0/matmul_profile_O0 -- a real improvement over the throttled
# ~1.7 GHz baseline, but well short of the ~3.6-3.9 GHz this same machine
# hits at full power (confirmed via the assembly binaries' hyperfine timing
# AND direct powermetrics P-cluster frequency logs). IPC was unchanged
# between the throttled and rerun traces, which rules out a workload/data
# problem -- so the leading suspect is that Instruments is scheduling the
# traced process onto E-cores (or a reduced QoS class) rather than P-cores,
# a different mechanism from Low Power Mode.
#
# This script runs the SAME profiling binary directly (no Instruments in the
# loop) while sampling P-cluster/E-cluster active frequency with
# powermetrics, so you can see which cluster actually carries the load.
#
# Usage:
#   sudo ./diagnose_profile_clock.sh fib     (runs fib_profile_O0 40 50)
#   sudo ./diagnose_profile_clock.sh matmul  (runs matmul_profile_O0 256 1000)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: powermetrics requires root. Run with sudo."
    exit 1
fi

"$SCRIPT_DIR/../scripts/check_measurement_conditions.sh" || {
    echo "Refusing to run until the above is fixed."
    exit 1
}

case "${1:-}" in
    fib)
        BIN=./fib_profile_O0
        ARGS="40 50"
        ;;
    matmul)
        BIN=./matmul_profile_O0
        ARGS="256 1000"
        ;;
    *)
        echo "Usage: sudo $0 <fib|matmul>"
        exit 1
        ;;
esac

[ -x "$BIN" ] || { echo "ERROR: $BIN not found -- run ../scripts/build_c_profiles.sh first."; exit 1; }

OUT="powermetrics_${1}_direct_$(date +%Y%m%d_%H%M%S).txt"

echo "=== Launching $BIN $ARGS directly (no Instruments), sampling powermetrics in parallel ==="
( $BIN $ARGS > /tmp/diagnose_out.txt 2>&1 ) &
BENCH_PID=$!

powermetrics --samplers cpu_power -i 500 -n 60 > "$OUT" 2>/dev/null &
PM_PID=$!

wait "$BENCH_PID" 2>/dev/null || true
kill "$PM_PID" 2>/dev/null || true
wait "$PM_PID" 2>/dev/null || true

echo ""
echo "=== Benchmark output ==="
cat /tmp/diagnose_out.txt

echo ""
echo "=== P-Cluster vs E-Cluster active frequency (non-zero samples) ==="
grep -E "^(E|P)-Cluster HW active frequency" "$OUT" | grep -v " 0 MHz" | sort | uniq -c | sort -rn | head -20

echo ""
echo "Full log: $OUT"
echo "If P-Cluster shows sustained 3000+ MHz here but the Instruments trace"
echo "showed ~2000-2100 MHz cycles/s, that confirms Instruments itself is"
echo "the source of the discrepancy (likely E-core scheduling of the traced"
echo "process), not a property of the binary or the machine's power state."
