# How to re-run the Instruments CPU Counters PMU profiling
# ===========================================================
# ------------------------------------
# The original PMU traces (results/fib_mac.trace, results/matmul_mac.trace,
# summarized in results/trace_summaries/) used a custom counter set inside
# the Instruments "CPU Counters" template: Cycles, Instructions,
# BRANCH_MISPRED_NONSPEC, L1D_CACHE_MISS_LD, INST_INT_LD, INST_BRANCH, plus
# derived formulas (IPC, branch misprediction rate, L1D miss/load rate).
# `xctrace record` can launch a template from the CLI, but adding specific
# hardware PMU events to a template's recording options is an Instruments
# GUI action -- there is no CLI equivalent. Run the steps below by hand.
#
# BEFORE YOU START
# ------------------
# Run this first and fix anything it flags -- the original session that
# produced ~1.7 GHz average cycles/sec (vs. ~3.6-4.0 GHz seen at full power
# in the July 2026 powermetrics logs) is suspected to have run under Low
# Power Mode on battery:
#
#   ../scripts/check_measurement_conditions.sh
#
# STEP 1: Rebuild the profiling targets
# ---------------------------------------
cd "$(dirname "$0")"
../scripts/build_c_profiles.sh
# (builds fib_profile_O0, fib_profile_O2, matmul_profile_O0, matmul_profile_O2
#  in this directory)

# STEP 2: Open Instruments
# ---------------------------------------
# open -a Instruments
#
# File > New > choose the "CPU Counters" template.

# STEP 3: Configure the target
# ---------------------------------------
# In the top-left target picker, choose "Choose Target..." > "Choose
# Executable..." and pick:
#   fib_profile_O0     with arguments: 40 50
#     (or matmul_profile_O0  with arguments: 256 1000, as a separate recording)
#
# These match the original defaults baked into fib_profile.c / matmul_profile.c
# and what the trace_summaries describe (fib_profile_O0 run 2, matmul_profile_O0
# run 3, both ~40s, ended by SIGKILL at the Instruments time limit).

# STEP 4: Configure the counters
# ---------------------------------------
# Click the "i" / Recording Options button on the CPU Counters instrument row
# and add exactly these events (search by name in the counter picker):
#   - FIXED_CYCLES            (labeled "Cycles")
#   - FIXED_INSTRUCTIONS      (labeled "Instructions")
#   - BRANCH_MISPRED_NONSPEC
#   - L1D_CACHE_MISS_LD
#   - INST_INT_LD
#   - INST_BRANCH
#
# Add these derived formulas (Instruments lets you define formula rows):
#   - IPC                        = Instructions / Cycles
#   - branch misprediction rate  = BRANCH_MISPRED_NONSPEC / INST_BRANCH * 100
#   - L1D miss/load rate         = L1D_CACHE_MISS_LD / INST_INT_LD * 100

# STEP 5: Set a time limit and record
# ---------------------------------------
# Recording Options > set a time limit around 40s (matches the original
# protocol -- the profiling target intentionally runs longer than this so
# Instruments captures a steady-state window rather than a full-process
# lifetime). Click Record.
#
# Let it run to the time limit (it will SIGKILL the target, which is
# expected and matches "End reason: Time limit reached" in the original
# trace_inventory.txt).

# STEP 6: Export and save the trace
# ---------------------------------------
# File > Save As... > save into:
#   results/fib_mac_rerun.trace       (for the fib_profile_O0 recording)
#   results/matmul_mac_rerun.trace    (for the matmul_profile_O0 recording)
#
# Do NOT overwrite results/fib_mac.trace / results/matmul_mac.trace -- keep
# the original (suspected-throttled) traces for the paper's before/after
# comparison, same as the energy_windows_*_low_energy.csv files were kept
# rather than deleted.

# STEP 7: Read off the aggregated counters
# ---------------------------------------
# In the counters track, select the steady-state region (exclude the first
# ~2-3s startup, same as "First included sample time" in the original
# fib_mac_trace_summary.txt) and read the summed/aggregated values for each
# counter from the Instruments inspector panel.
#
# Report back (or fill directly into new
# results/trace_summaries/*_rerun_summary.txt files, following the format of
# the existing fib_mac_trace_summary.txt / matmul_mac_trace_summary.txt):
#   - Cycles, Instructions, BRANCH_MISPRED_NONSPEC, L1D_CACHE_MISS_LD,
#     INST_INT_LD, INST_BRANCH (raw totals)
#   - Included time span (s)
#   - Derived: IPC, instructions/s, cycles/s, branch miss rate, L1D miss rate
#
# The key number to sanity-check against the throttling hypothesis is
# cycles/s: it was ~1.73-1.77e9 (i.e. ~1.7 GHz) in both original traces. If
# the re-run lands close to the ~3.6-3.9 GHz seen in the corrected July 2026
# powermetrics captures, that confirms the original session was throttled.
