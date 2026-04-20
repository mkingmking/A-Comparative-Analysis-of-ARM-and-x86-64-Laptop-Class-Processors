#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/../c_portable" && pwd)"

CC="${CC:-clang}"
CFLAGS_BASE=(-Wall -Wextra -std=c11)

echo "Building single-process C profiling targets in:"
echo "  $BENCH_DIR"
echo

cd "$BENCH_DIR"

"$CC" "${CFLAGS_BASE[@]}" -O0 -o fib_profile_O0 fib_profile.c
"$CC" "${CFLAGS_BASE[@]}" -O2 -o fib_profile_O2 fib_profile.c

"$CC" "${CFLAGS_BASE[@]}" -O0 -o matmul_profile_O0 matmul_profile.c
"$CC" "${CFLAGS_BASE[@]}" -O2 -o matmul_profile_O2 matmul_profile.c

echo "Built:"
echo "  $BENCH_DIR/fib_profile_O0"
echo "  $BENCH_DIR/fib_profile_O2"
echo "  $BENCH_DIR/matmul_profile_O0"
echo "  $BENCH_DIR/matmul_profile_O2"
echo
echo "Suggested Instruments targets:"
echo "  $BENCH_DIR/fib_profile_O0 40 50"
echo "  $BENCH_DIR/matmul_profile_O0 256 1000"
echo
echo "If a target runs too long or too short, adjust the last argument:"
echo "  ./fib_profile_O0 40 25"
echo "  ./matmul_profile_O0 256 500"
