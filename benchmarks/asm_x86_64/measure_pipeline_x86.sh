#!/bin/bash
# measure_pipeline_x86.sh - direct PMU/pipeline measurement on the
# hand-written x86-64 assembly binaries (fib_x86, matmul_x86).
#
# Unlike the Apple side (where Instruments' CPU Counters template can only
# attach custom PMU events through its GUI, and reads best over one
# long-lived process, requiring fib_arm_profile.s / matmul_arm_profile.s
# repeat-loop wrappers), `perf stat -r N` already averages hardware counters
# cleanly over many short process launches -- so this measures the *actual*
# hand-written binaries directly, no wrapper needed. This closes
# sec:limitations item 5 ("Incomplete pipeline characterization") on the
# x86-64 side.
#
# Run this on the Ryzen 5 5600, since the original Ryzen 7 3750H used for
# the paper's archival timing/energy tables is no longer accessible
# (see experiments/next_steps.md). Because the 5600 is a different
# microarchitecture generation (Zen 3 / TSMC N7) from the 3750H (Zen+ / GF
# 12nm), report this as new Apple-M3-vs-Ryzen-5600 pipeline data -- do not
# retroactively attribute these numbers to the archival 3750H dataset.
#
# Usage (on the Ryzen 5 5600, Linux):
#   sudo sysctl kernel.perf_event_paranoid=0   # if perf stat refuses to run
#   ./measure_pipeline_x86.sh
#
# Requires: nasm, gcc, linux-tools (perf) matching the running kernel.
# Output: results/pipeline_x86_<timestamp>/fib_x86.txt, matmul_x86.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS=30
EVENTS="cycles,instructions,branch-instructions,branch-misses,L1-dcache-loads,L1-dcache-load-misses"

echo "=== Building fib_x86 / matmul_x86 from source ==="
cd "$SCRIPT_DIR"
nasm -f elf64 -o fib_x86.o fib_x86.asm
gcc -o fib_x86 fib_x86.o -no-pie
nasm -f elf64 -o matmul_x86.o matmul_x86.asm
gcc -o matmul_x86 matmul_x86.o -no-pie
rm -f fib_x86.o matmul_x86.o

echo ""
echo "=== Sanity check: correctness ==="
./fib_x86
./matmul_x86

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$REPO_ROOT/results/pipeline_x86_$TS"
mkdir -p "$OUTDIR"

echo ""
echo "=== perf stat: fib_x86 ($RUNS runs) ==="
perf stat -r "$RUNS" -e "$EVENTS" ./fib_x86 > "$OUTDIR/fib_x86.txt" 2>&1 || true
cat "$OUTDIR/fib_x86.txt"

echo ""
echo "=== perf stat: matmul_x86 ($RUNS runs) ==="
perf stat -r "$RUNS" -e "$EVENTS" ./matmul_x86 > "$OUTDIR/matmul_x86.txt" 2>&1 || true
cat "$OUTDIR/matmul_x86.txt"

echo ""
echo "Results written to $OUTDIR"
echo ""
echo "perf's own -r N report already derives 'insn per cycle' (IPC) and"
echo "'% of all branches' (branch miss rate) when both counters in a pair"
echo "are present -- no separate parsing step needed, same as the numbers"
echo "already used for results/linux_energy.txt."
echo ""
echo "If L1-dcache-loads / L1-dcache-load-misses show <not supported> on"
echo "this kernel/PMU, run 'perf list' for the closest available AMD raw"
echo "L1D-fill event and substitute it in EVENTS above."
