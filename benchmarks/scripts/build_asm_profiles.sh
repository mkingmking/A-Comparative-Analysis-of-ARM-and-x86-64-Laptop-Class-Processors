#!/bin/zsh
# build_asm_profiles.sh - build the long-running assembly-binary profiling
# targets for direct Instruments CPU Counters PMU measurement.
#
# Unlike build_c_profiles.sh (which builds a portable-C proxy), these wrap
# the *unmodified* hand-written _fib / _matmul from fib_arm.s / matmul_arm.s
# in a repeat loop, so the PMU counters characterize the actual assembly
# kernels used for Tables tab:asm_time-tab:energy, not a proxy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/../asm_aarch64" && pwd)"
SDK=$(xcrun --sdk macosx --show-sdk-path)

echo "Building assembly profiling targets in:"
echo "  $BENCH_DIR"
echo

cd "$BENCH_DIR"

as -o fib_arm_profile.o fib_arm_profile.s
ld -o fib_arm_profile fib_arm_profile.o -lSystem -syslibroot "$SDK" -e _main

as -o matmul_arm_profile.o matmul_arm_profile.s
ld -o matmul_arm_profile matmul_arm_profile.o -lSystem -syslibroot "$SDK" -e _main

rm -f fib_arm_profile.o matmul_arm_profile.o

echo "Built:"
echo "  $BENCH_DIR/fib_arm_profile     (fib(40) x 100 reps, ~33s)"
echo "  $BENCH_DIR/matmul_arm_profile  (256x256 matmul x 2400 reps, ~35s)"
echo
echo "Sanity check (checksums should be 10233415500 and 1336272000):"
./fib_arm_profile
./matmul_arm_profile
echo
echo "Instruments targets: run these with no arguments -- reps are baked"
echo "into the .s source (REPETITIONS equ). To change the run length, edit"
echo "REPETITIONS in fib_arm_profile.s / matmul_arm_profile.s and rebuild."
