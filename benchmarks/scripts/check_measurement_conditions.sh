#!/bin/bash
# check_measurement_conditions.sh - refuse to measure under throttled conditions
#
# WHY THIS SCRIPT EXISTS
# -----------------------
# The original April 2026 M3 session (hyperfine timing, the single-window
# power estimate, and the Instruments CPU Counters PMU traces) was run with
# Low Power Mode enabled.
#
# Low Power Mode caps CPU clocks well below the M3's boost ceiling (observed:
# ~1.7 GHz average in the contaminated runs vs. ~3.6-4.0 GHz at full power).
# That suppressed BOTH the single-window energy estimate AND, almost
# certainly, the hyperfine wall-clock timing numbers and the PMU IPC trace --
# i.e. it can plausibly explain "Ryzen wins Fibonacci" as a throttling
# artifact rather than a real result. The July 2026 energy re-measurement
# caught the same failure mode again (see energy_windows_*_low_energy.csv
# vs. the corrected same-day files), which is what prompted this guard.
#
# This script is meant to be sourced or run as a gate before ANY timing,
# energy, or profiling measurement: source it and check its exit code, or
# just run it directly and stop if it prints FAIL.
#
# Usage:
#   ./check_measurement_conditions.sh
#   (exit 0 = safe to measure, exit 1 = fix the printed issue first)

set -u

FAIL=0

echo "=== Measurement precondition check ($(date)) ==="

# --- Low Power Mode: must be off in the ACTIVE profile ---
LPM=$(pmset -g | awk '/lowpowermode/ {print $2; exit}')
if [ "$LPM" = "0" ]; then
    echo "[OK]   Low Power Mode is off"
else
    echo "[FAIL] Low Power Mode is ON (lowpowermode=$LPM)"
    echo "       Disable it: System Settings > Battery > (uncheck) Low Power Mode,"
    echo "       or use 'sudo pmset -b lowpowermode 0' while on battery."
    FAIL=1
fi

# --- Battery level: informational, but flag if critically low ---
BATT_PCT=$(pmset -g ps | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
if [ -n "${BATT_PCT:-}" ] && [ "$BATT_PCT" -lt 20 ]; then
    echo "[WARN] Battery at ${BATT_PCT}% -- some firmware/power policies behave"
    echo "       differently near critical battery levels even on AC. Let it"
    echo "       charge past ~50% before a long measurement session if possible."
fi

# --- Thermal pressure: informational (macOS only reports after an event fires) ---
THERM=$(pmset -g therm 2>/dev/null)
if echo "$THERM" | grep -qi "No thermal warning level"; then
    echo "[OK]   No thermal warning logged"
else
    echo "[WARN] Thermal state: $THERM"
    echo "       Let the machine cool and re-check before measuring."
fi

# --- Stray processes from a previous run ---
STRAY=$(pgrep -f "fib_arm|matmul_arm|fib_profile_O0|matmul_profile_O0|powermetrics|hyperfine" | grep -v "^$$\$" || true)
if [ -z "$STRAY" ]; then
    echo "[OK]   No stray benchmark/profiling processes"
else
    echo "[FAIL] Stray processes still running (PIDs: $STRAY)"
    echo "       Kill them first: kill -9 $STRAY"
    FAIL=1
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "=== READY: conditions are safe to measure ==="
    exit 0
else
    echo "=== NOT READY: fix the [FAIL] items above before measuring ==="
    exit 1
fi
