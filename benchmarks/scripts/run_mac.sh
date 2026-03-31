#!/bin/bash
# run_mac.sh - Benchmark runner for macOS (Apple Silicon M3)
#
# Usage: sudo ./run_mac.sh
# (sudo required for powermetrics)
#
# Outputs results to results_mac.csv

RUNS=30
WARMUP=5
RESULTS="results_mac.csv"

echo "=== ARM (AArch64) Benchmark Suite - macOS ==="
echo "Platform: $(uname -m), $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
echo "Runs: $RUNS (+ $WARMUP warmup)"
echo ""

# Header
echo "benchmark,run,time_seconds,checksum" > "$RESULTS"

run_benchmark() {
    local name="$1"
    local cmd="$2"

    echo "--- $name ---"

    # Warmup runs (discard)
    echo "  Warming up ($WARMUP runs)..."
    for ((w=1; w<=WARMUP; w++)); do
        $cmd > /dev/null 2>&1
    done

    # Measured runs
    echo "  Measuring ($RUNS runs)..."
    for ((r=1; r<=RUNS; r++)); do
        # Use gtime (GNU time) if available, otherwise use built-in
        start_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")
        output=$($cmd 2>&1)
        end_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")

        elapsed=$(python3 -c "print(($end_ns - $start_ns) / 1e9)")
        echo "$name,$r,$elapsed" >> "$RESULTS"

        if [ "$r" -eq 1 ]; then
            echo "  Sample output: $(echo "$output" | head -1)"
        fi
    done

    # Quick stats
    python3 -c "
import csv, statistics
times = []
with open('$RESULTS') as f:
    for row in csv.DictReader(f):
        if row['benchmark'] == '$name':
            times.append(float(row['time_seconds']))
if times:
    print(f'  Mean: {statistics.mean(times):.6f}s')
    print(f'  Stdev: {statistics.stdev(times):.6f}s')
    print(f'  Min: {min(times):.6f}s, Max: {max(times):.6f}s')
"
    echo ""
}

# ---- Build benchmarks ----
echo "Building benchmarks..."

# C versions
clang -O0 -o fib_c_O0 c_portable/fib.c 2>/dev/null
clang -O2 -o fib_c_O2 c_portable/fib.c 2>/dev/null
clang -O0 -o matmul_c_O0 c_portable/matmul.c 2>/dev/null
clang -O2 -o matmul_c_O2 c_portable/matmul.c 2>/dev/null
clang -O2 -o memwalk c_portable/memwalk.c 2>/dev/null

# Assembly versions (may need adjustment for your SDK path)
SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)
if [ -n "$SDK" ]; then
    as -o fib_arm.o asm_aarch64/fib_arm.s 2>/dev/null && \
    ld -o fib_asm fib_arm.o -lSystem -syslibroot "$SDK" -e _main 2>/dev/null

    as -o matmul_arm.o asm_aarch64/matmul_arm.s 2>/dev/null && \
    ld -o matmul_asm matmul_arm.o -lSystem -syslibroot "$SDK" -e _main 2>/dev/null
fi

echo "Build complete."
echo ""

# ---- Run benchmarks ----
echo "=== Starting benchmarks ==="
echo ""

# Fibonacci
[ -f ./fib_c_O0 ]  && run_benchmark "fib_c_O0" "./fib_c_O0"
[ -f ./fib_c_O2 ]  && run_benchmark "fib_c_O2" "./fib_c_O2"
[ -f ./fib_asm ]   && run_benchmark "fib_asm"   "./fib_asm"

# Matrix multiply
[ -f ./matmul_c_O0 ] && run_benchmark "matmul_c_O0" "./matmul_c_O0"
[ -f ./matmul_c_O2 ] && run_benchmark "matmul_c_O2" "./matmul_c_O2"
[ -f ./matmul_asm ]  && run_benchmark "matmul_asm"   "./matmul_asm"

# Memory walk
[ -f ./memwalk ] && run_benchmark "memwalk" "./memwalk"

echo "=== All benchmarks complete ==="
echo "Results saved to $RESULTS"
echo ""
echo "=== Power measurement ==="
echo "To measure power, run in a separate terminal:"
echo "  sudo powermetrics --samplers cpu_power -i 500 -n 20"
echo "while running a benchmark in this terminal."
