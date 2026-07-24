#!/bin/bash
# measure_power_mac_repeated.sh - repeated-window Apple CPU-energy sampling
#
# WHY THIS SCRIPT EXISTS
# -----------------------
# measure_power_mac.sh runs ONE idle window + ONE load window and turns the
# single resulting power delta into a single point-estimate for energy per
# run. That point estimate has no repeated-run variance, so no confidence
# interval or significance test can be computed for it -- a limitation
# called out explicitly in the paper (sec:stats, sec:limitations item 3).
#
# This script repeats that same idle/load protocol N independent times and
# writes one row per window to a CSV, giving a real sample of N energy
# estimates. From that you get an actual mean, sd, and 95% CI for Apple
# energy, and -- for the first time -- a legitimate two-sample statistical
# test against the Ryzen energy measurements (see analyze_energy_windows.py).
#
# DESIGN CHOICE: mean runtime is held FIXED across windows
# ----------------------------------------------------------
# energy_i = (load_cpu_power_i - idle_cpu_power_i) * MEAN_RUNTIME_S
#
# MEAN_RUNTIME_S is a single fixed value you pass in: the mean runtime from
# a same-session, same-power-conditions 100-run hyperfine timing experiment
# (see rerun_timing.sh, which produces this number directly -- do not reuse
# the old 0.5836 s / 0.0260 s values from results/results_mac.txt, which
# came from a session later found to plausibly have run under Low Power
# Mode). Only the power measurement varies window-to-window.
# This isolates exactly the missing piece -- power-measurement repeatability
# -- without reconflating it with runtime variance that is already
# separately measured and reported. If you want combined power+runtime
# variance instead, re-run hyperfine per window and adapt accordingly, but
# that is a different experiment from the one this script runs.
#
# Requires sudo (powermetrics needs root).
#
# Usage:
#   sudo ./measure_power_mac_repeated.sh <benchmark_executable> <mean_runtime_s> [N] [outfile.csv]
#
# Examples:
#   sudo ./measure_power_mac_repeated.sh ./fib_arm    0.5836 20
#   sudo ./measure_power_mac_repeated.sh ./matmul_arm 0.0260 20
#
# Each window is ~20s idle + ~20s load (matches the original single-window
# protocol's SAMPLES/INTERVAL), so N=20 takes roughly 20*(20+20+2)/60 ~= 14
# minutes per benchmark. Run fib and matmul as two separate invocations.
# Progress and partial results are written incrementally, so Ctrl-C after
# window k still leaves you a usable k-row CSV.

set -u

BENCHMARK=${1:-}
MEAN_RUNTIME_S=${2:-}
N=${3:-20}
OUTFILE=${4:-}

usage() {
    echo "Usage: sudo $0 <benchmark_executable> <mean_runtime_s> [N=20] [outfile.csv]"
    echo ""
    echo "  mean_runtime_s: fixed mean runtime (seconds) from the existing"
    echo "                  100-run hyperfine timing experiment, e.g.:"
    echo "                    fib_arm    -> 0.5836"
    echo "                    matmul_arm -> 0.0260"
    exit 1
}

[ -z "$BENCHMARK" ] && usage
[ -z "$MEAN_RUNTIME_S" ] && usage

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: powermetrics requires root."
    echo "Run with: sudo $0 $BENCHMARK $MEAN_RUNTIME_S $N"
    exit 1
fi

if [ ! -x "$BENCHMARK" ]; then
    echo "ERROR: $BENCHMARK not found or not executable."
    exit 1
fi

if ! awk "BEGIN{exit !($MEAN_RUNTIME_S > 0)}"; then
    echo "ERROR: mean_runtime_s must be a positive number (got: $MEAN_RUNTIME_S)"
    exit 1
fi

BASE=$(basename "$BENCHMARK")
if [ -z "$OUTFILE" ]; then
    OUTFILE="energy_windows_${BASE}_$(date +%Y%m%d_%H%M%S).csv"
fi

SCRIPT_NAME=$(basename "$0")
STRAY_SCRIPT=$(pgrep -f "$SCRIPT_NAME" | grep -v "^$$\$" || true)
STRAY_BENCH=$(pgrep -x "$BASE" || true)
if [ -n "$STRAY_SCRIPT" ] || [ -n "$STRAY_BENCH" ]; then
    echo "ERROR: a previous measurement run (or an orphaned $BASE loop) is still active."
    echo "This will silently contaminate the idle/load windows -- refusing to start."
    [ -n "$STRAY_SCRIPT" ] && echo "  $SCRIPT_NAME PIDs: $STRAY_SCRIPT"
    [ -n "$STRAY_BENCH" ]  && echo "  $BASE PIDs: $STRAY_BENCH"
    echo "Kill them (sudo kill -9 <pid>), confirm 'ps aux | egrep \"$SCRIPT_NAME|$BASE\"' is clean, then re-run."
    exit 1
fi

SAMPLES=40      # 40 x 500ms = 20s window (matches measure_power_mac.sh)
INTERVAL=500    # ms

WORKDIR=$(mktemp -d /tmp/pm_rep_XXXXXX)
LOOP_PID=""
cleanup_and_exit() {
    echo ""
    echo "Interrupted. Cleaning up background loop..."
    if [ -n "$LOOP_PID" ]; then
        kill -9 "$LOOP_PID" 2>/dev/null
        pkill -9 -P "$LOOP_PID" 2>/dev/null
    fi
    pkill -9 -x "$BASE" 2>/dev/null
    echo "Partial results in $OUTFILE ($WORKDIR kept for inspection)."
    exit 130
}
trap cleanup_and_exit INT TERM

echo "window,idle_cpu_w,load_cpu_w,delta_cpu_w,energy_j" > "$OUTFILE"

TOTAL_S=$(( N * (SAMPLES*INTERVAL/1000*2 + 4) ))
echo "=== Repeated-window energy sampling: $BENCHMARK ==="
echo "Windows: $N, each ~$((SAMPLES*INTERVAL/1000))s idle + $((SAMPLES*INTERVAL/1000))s load"
echo "Fixed mean runtime: ${MEAN_RUNTIME_S}s"
echo "Estimated total time: ~$(( TOTAL_S / 60 )) min"
echo "Output: $OUTFILE"
echo ""

# Runs one idle/load window pair and prints "idle,load,delta,energy".
# A first invocation of this (discarded, not written to $OUTFILE) was found
# empirically to be a startup transient: idle and load power both land far
# outside the range of every subsequent window, in both the fib and matmul
# sequences, which is the same rationale as hyperfine's discarded warm-up
# runs for timing. Do not skip the warm-up call below.
measure_one_window() {
    local tag=$1
    local idle_file="$WORKDIR/idle_$tag.txt"
    local load_file="$WORKDIR/load_$tag.txt"

    powermetrics --samplers cpu_power -i $INTERVAL -n $SAMPLES > "$idle_file" 2>/dev/null

    ( while true; do "$BENCHMARK" > /dev/null 2>&1; done ) &
    LOOP_PID=$!
    sleep 2  # let load establish
    powermetrics --samplers cpu_power -i $INTERVAL -n $SAMPLES > "$load_file" 2>/dev/null
    kill -9 "$LOOP_PID" 2>/dev/null
    pkill -9 -P "$LOOP_PID" 2>/dev/null
    wait 2>/dev/null
    pkill -9 -x "$BASE" 2>/dev/null  # belt-and-suspenders: nothing should survive to the next window

    local idle_cpu load_cpu delta_cpu energy
    idle_cpu=$(grep "^CPU Power" "$idle_file" | awk -F: '{print $2}' | awk '{print $1}' | \
        awk '{s+=$1; n++} END {if (n>0) printf "%.4f", s/n/1000; else print "0.0000"}')
    load_cpu=$(grep "^CPU Power" "$load_file" | awk -F: '{print $2}' | awk '{print $1}' | \
        awk '{s+=$1; n++} END {if (n>0) printf "%.4f", s/n/1000; else print "0.0000"}')
    delta_cpu=$(awk "BEGIN { printf \"%.4f\", $load_cpu - $idle_cpu }")
    energy=$(awk "BEGIN { printf \"%.6f\", $delta_cpu * $MEAN_RUNTIME_S }")
    echo "$idle_cpu,$load_cpu,$delta_cpu,$energy"
}

echo "[warm-up] discarded idle+load window..."
WARMUP_RESULT=$(measure_one_window "warmup")
echo "  (discarded) $WARMUP_RESULT"

for i in $(seq 1 "$N"); do
    echo "[$i/$N] idle+load phase..."
    RESULT=$(measure_one_window "$i")
    echo "$i,$RESULT" >> "$OUTFILE"
    echo "  $RESULT"
done

echo ""
echo "Done. $N windows written to $OUTFILE (plus 1 discarded warm-up window)"
echo "Next: python3 ../analysis/analyze_energy_windows.py $OUTFILE fib   (or matmul)"
