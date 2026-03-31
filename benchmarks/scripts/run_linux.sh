#!/bin/bash
# run_linux.sh - Benchmark runner for Linux (AMD Ryzen 5 / x86-64)
#
# Usage: ./run_linux.sh
# (some perf features may need sudo or perf_event_paranoid=0)
#
# Prerequisites:
#   sudo sysctl kernel.perf_event_paranoid=0
#   sudo apt install linux-tools-common linux-tools-generic nasm gcc
#
# Outputs results to results_linux.csv

RUNS=30
WARMUP=5
RESULTS="results_linux.csv"
PERF_RESULTS="perf_results.csv"

echo "=== x86-64 Benchmark Suite - Linux ==="
echo "Platform: $(uname -m), $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | xargs)"
echo "Kernel: $(uname -r)"
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"
echo "Runs: $RUNS (+ $WARMUP warmup)"
echo ""

# Headers
echo "benchmark,run,time_seconds" > "$RESULTS"
echo "benchmark,cycles,instructions,ipc,cache_refs,cache_misses,miss_rate,energy_pkg_J" > "$PERF_RESULTS"

run_benchmark() {
    local name="$1"
    local cmd="$2"

    echo "--- $name ---"

    # Warmup
    echo "  Warming up ($WARMUP runs)..."
    for ((w=1; w<=WARMUP; w++)); do
        taskset -c 0 $cmd > /dev/null 2>&1
    done

    # Measured runs (timing)
    echo "  Measuring timing ($RUNS runs)..."
    for ((r=1; r<=RUNS; r++)); do
        start_ns=$(date +%s%N)
        taskset -c 0 $cmd > /dev/null 2>&1
        end_ns=$(date +%s%N)

        elapsed=$(python3 -c "print(($end_ns - $start_ns) / 1e9)")
        echo "$name,$r,$elapsed" >> "$RESULTS"
    done

    # Perf stat run (single detailed run for microarchitectural data)
    echo "  Collecting perf counters..."
    perf_output=$(taskset -c 0 perf stat -e \
        cycles,instructions,cache-references,cache-misses,\
        power/energy-pkg/ \
        $cmd 2>&1 >/dev/null)

    # Parse perf output
    cycles=$(echo "$perf_output" | grep "cycles" | head -1 | awk '{gsub(/,/,""); print $1}')
    instructions=$(echo "$perf_output" | grep "instructions" | awk '{gsub(/,/,""); print $1}')
    ipc=$(echo "$perf_output" | grep "instructions" | grep -oP '[\d.]+\s+insn per cycle' | awk '{print $1}')
    cache_refs=$(echo "$perf_output" | grep "cache-references" | awk '{gsub(/,/,""); print $1}')
    cache_misses=$(echo "$perf_output" | grep "cache-misses" | awk '{gsub(/,/,""); print $1}')
    miss_rate=$(echo "$perf_output" | grep "cache-misses" | grep -oP '[\d.]+%' | tr -d '%')
    energy=$(echo "$perf_output" | grep "energy-pkg" | awk '{print $1}')

    echo "$name,$cycles,$instructions,$ipc,$cache_refs,$cache_misses,$miss_rate,$energy" >> "$PERF_RESULTS"

    # Print stats
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
    print(f'  95% CI: ±{1.96 * statistics.stdev(times) / len(times)**0.5:.6f}s')
"
    if [ -n "$ipc" ]; then
        echo "  IPC: $ipc"
    fi
    if [ -n "$energy" ]; then
        echo "  Energy: ${energy} J"
    fi
    echo ""
}

# ---- Build ----
echo "Building benchmarks..."

# C versions
gcc -O0 -o fib_c_O0 c_portable/fib.c -lm 2>/dev/null
gcc -O2 -o fib_c_O2 c_portable/fib.c -lm 2>/dev/null
gcc -O0 -o matmul_c_O0 c_portable/matmul.c -lm 2>/dev/null
gcc -O2 -o matmul_c_O2 c_portable/matmul.c -lm 2>/dev/null
gcc -O2 -o memwalk c_portable/memwalk.c -lm 2>/dev/null

# Assembly versions
nasm -f elf64 -o fib_x86.o asm_x86_64/fib_x86.asm 2>/dev/null && \
    gcc -o fib_asm fib_x86.o -no-pie 2>/dev/null

nasm -f elf64 -o matmul_x86.o asm_x86_64/matmul_x86.asm 2>/dev/null && \
    gcc -o matmul_asm matmul_x86.o -no-pie 2>/dev/null

echo "Build complete."
echo ""

# ---- Prepare system ----
echo "=== System preparation ==="
echo "Setting CPU governor to 'performance'..."
sudo cpupower frequency-set -g performance 2>/dev/null || \
    echo "  (Could not set governor — run with sudo or set manually)"

echo "Disabling turbo boost..."
echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || \
    echo "  (Could not disable boost)"
echo ""

# ---- Run ----
echo "=== Starting benchmarks ==="
echo ""

[ -f ./fib_c_O0 ]    && run_benchmark "fib_c_O0" "./fib_c_O0"
[ -f ./fib_c_O2 ]    && run_benchmark "fib_c_O2" "./fib_c_O2"
[ -f ./fib_asm ]     && run_benchmark "fib_asm"   "./fib_asm"

[ -f ./matmul_c_O0 ] && run_benchmark "matmul_c_O0" "./matmul_c_O0"
[ -f ./matmul_c_O2 ] && run_benchmark "matmul_c_O2" "./matmul_c_O2"
[ -f ./matmul_asm ]  && run_benchmark "matmul_asm"   "./matmul_asm"

[ -f ./memwalk ]     && run_benchmark "memwalk" "./memwalk"

echo "=== All benchmarks complete ==="
echo "Timing results:   $RESULTS"
echo "Perf counters:    $PERF_RESULTS"
echo ""

# ---- Restore system ----
echo "Restoring CPU governor..."
sudo cpupower frequency-set -g schedutil 2>/dev/null
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost 2>/dev/null
