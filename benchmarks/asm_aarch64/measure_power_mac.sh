#!/bin/bash
# measure_power_mac.sh - macOS CPU/SoC power measurement via powermetrics
#
# Self-contained: starts powermetrics in background, runs benchmark in a loop,
# parses the output for averages.
#
# Requires: sudo (powermetrics needs root)
#
# Usage:
#   sudo ./measure_power_mac.sh ./fib_arm
#   sudo ./measure_power_mac.sh ./matmul_arm

BENCHMARK=$1
if [ -z "$BENCHMARK" ]; then
    echo "Usage: sudo $0 <benchmark_executable>"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: powermetrics requires root."
    echo "Run with: sudo $0 $BENCHMARK"
    exit 1
fi

if [ ! -x "$BENCHMARK" ]; then
    echo "ERROR: $BENCHMARK not found or not executable."
    exit 1
fi

WORKDIR=$(mktemp -d /tmp/pm_XXXXXX)
IDLE_FILE="$WORKDIR/idle.txt"
LOAD_FILE="$WORKDIR/load.txt"
SAMPLES=40        # 40 samples × 500ms = 20s window
INTERVAL=500      # ms

# -------- IDLE phase --------
echo "=== Power Measurement: $BENCHMARK ==="
echo ""
echo "[1/2] Measuring IDLE for $((SAMPLES * INTERVAL / 1000))s — please don't touch the Mac..."
powermetrics --samplers cpu_power -i $INTERVAL -n $SAMPLES > "$IDLE_FILE" 2>/dev/null

# -------- LOAD phase --------
echo "[2/2] Running benchmark in a loop while measuring for $((SAMPLES * INTERVAL / 1000))s..."

# Start benchmark in a tight loop in the background
(while true; do "$BENCHMARK" > /dev/null 2>&1; done) &
LOOP_PID=$!

sleep 2  # let load establish

# Run powermetrics in foreground while loop runs
powermetrics --samplers cpu_power -i $INTERVAL -n $SAMPLES > "$LOAD_FILE" 2>/dev/null

# Stop the benchmark loop
kill -9 $LOOP_PID 2>/dev/null
pkill -9 -P $LOOP_PID 2>/dev/null
wait 2>/dev/null

# -------- Parse results --------
parse_avg() {
    local file=$1
    local pattern=$2
    grep "$pattern" "$file" | awk -F: '{print $2}' | awk '{print $1}' | \
        awk '{s+=$1; n++} END {if (n>0) printf "%.3f", s/n/1000; else print "0.000"}'
}

parse_max() {
    local file=$1
    local pattern=$2
    grep "$pattern" "$file" | awk -F: '{print $2}' | awk '{print $1}' | \
        awk 'BEGIN{m=0} {if ($1>m) m=$1} END {printf "%.3f", m/1000}'
}

IDLE_CPU=$(parse_avg "$IDLE_FILE" "^CPU Power")
IDLE_COMBINED=$(parse_avg "$IDLE_FILE" "Combined Power")
LOAD_CPU=$(parse_avg "$LOAD_FILE" "^CPU Power")
LOAD_CPU_MAX=$(parse_max "$LOAD_FILE" "^CPU Power")
LOAD_COMBINED=$(parse_avg "$LOAD_FILE" "Combined Power")
LOAD_COMBINED_MAX=$(parse_max "$LOAD_FILE" "Combined Power")

DELTA_CPU=$(awk "BEGIN { printf \"%.3f\", $LOAD_CPU - $IDLE_CPU }")
DELTA_COMBINED=$(awk "BEGIN { printf \"%.3f\", $LOAD_COMBINED - $IDLE_COMBINED }")

# Count samples for sanity
N_IDLE=$(grep -c "^CPU Power" "$IDLE_FILE")
N_LOAD=$(grep -c "^CPU Power" "$LOAD_FILE")

echo ""
echo "=== Results ==="
echo ""
printf "  %-22s %12s %12s %12s\n" "Metric" "Idle" "Load" "Delta"
printf "  %-22s %12s %12s %12s\n" "----------------------" "------------" "------------" "------------"
printf "  %-22s %10.3f W %10.3f W %10.3f W\n" "CPU Power"      "$IDLE_CPU"      "$LOAD_CPU"      "$DELTA_CPU"
printf "  %-22s %10.3f W %10.3f W %10.3f W\n" "Combined (CPU+GPU+ANE)" "$IDLE_COMBINED" "$LOAD_COMBINED" "$DELTA_COMBINED"
echo ""
echo "  Peak CPU Power during load:      $LOAD_CPU_MAX W"
echo "  Peak Combined during load:       $LOAD_COMBINED_MAX W"
echo "  Samples (idle/load):             $N_IDLE / $N_LOAD"
echo ""
echo "  Logs saved to: $WORKDIR/"
echo ""
echo "Notes:"
echo "  • CPU Power is comparable to Linux 'perf energy-pkg' on x86."
echo "  • Combined Power adds GPU + Neural Engine, capturing full SoC."
echo "  • Energy per run = Delta × benchmark execution time."
