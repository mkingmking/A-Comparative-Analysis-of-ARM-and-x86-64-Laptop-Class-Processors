# How to capture Instruments CPU Counters PMU data on the actual hand-written
# assembly kernels (not the portable-C proxy)
# ===========================================================================
# Table tab:uarch in the paper only profiles fib_profile.c / matmul_profile.c
# (a portable-C proxy), and sec:limitations item 5 ("Incomplete pipeline
# characterization") discloses that no PMU data exists for the hand-written
# fib_arm.s / matmul_arm.s binaries themselves. fib_arm_profile.s /
# matmul_arm_profile.s close that gap on the Apple side: they wrap the
# byte-for-byte-unmodified _fib / _matmul from fib_arm.s / matmul_arm.s in a
# repeat loop, purely so the process runs long enough (~33-35s) for
# Instruments to sample a steady-state PMU window.
#
# As with the C-portable profiling targets, there is no CLI way to attach
# custom PMU events to an Instruments template -- run the steps below by
# hand.
#
# BEFORE YOU START
# ------------------
# Run this first and fix anything it flags:
#   ../scripts/check_measurement_conditions.sh
#
# STEP 1: Build the profiling targets
# ---------------------------------------
# ../scripts/build_asm_profiles.sh
# (builds fib_arm_profile, matmul_arm_profile in this directory and prints a
#  checksum sanity check: 10233415500 and 1336272000)
#
# STEP 2: Open Instruments
# ---------------------------------------
# open -a Instruments
#
# File > New > choose the "CPU Counters" template.
#
# STEP 3: Configure the target
# ---------------------------------------
# In the top-left target picker, choose "Choose Target..." > "Choose
# Executable..." and pick:
#   fib_arm_profile       (no arguments -- reps are baked in via REPETITIONS)
#     (or matmul_arm_profile, as a separate recording)
#
# STEP 4: Configure the counters
# ---------------------------------------
# Click the "i" / Recording Options button on the CPU Counters instrument row
# and add exactly the same events used for the C-portable proxy in
# results/trace_summaries/, so the two datasets are directly comparable:
#   - FIXED_CYCLES            (labeled "Cycles")
#   - FIXED_INSTRUCTIONS      (labeled "Instructions")
#   - BRANCH_MISPRED_NONSPEC
#   - L1D_CACHE_MISS_LD
#   - INST_INT_LD
#   - INST_BRANCH
#
# Add the same derived formulas:
#   - IPC                        = Instructions / Cycles
#   - branch misprediction rate  = BRANCH_MISPRED_NONSPEC / INST_BRANCH * 100
#   - L1D miss/load rate         = L1D_CACHE_MISS_LD / INST_INT_LD * 100
#
# STEP 5: Set a time limit and record
# ---------------------------------------
# Recording Options > set a time limit around 40s (fib_arm_profile runs
# ~33s, matmul_arm_profile ~35s single-threaded; the time limit just needs
# to be comfortably above that so the process exits/gets sampled to
# completion rather than being cut off mid-run). Click Record.
#
# STEP 6: Export and save the trace
# ---------------------------------------
# File > Save As... > save into:
#   results/fib_arm_asm.trace       (for the fib_arm_profile recording)
#   results/matmul_arm_asm.trace    (for the matmul_arm_profile recording)
#
# Keep these separate from results/fib_mac.trace / results/matmul_mac.trace
# (the original C-portable-proxy traces) -- both datasets are meant to be
# reported side by side, not merged.
#
# STEP 7: Read off the aggregated counters
# ---------------------------------------
# In the counters track, select the steady-state region (exclude the first
# ~2-3s startup, same convention as "First included sample time" in
# results/trace_summaries/fib_mac_trace_summary.txt) and read the
# summed/aggregated values for each counter from the Instruments inspector
# panel.
#
# Report back (or fill directly into new
# results/trace_summaries/*_asm_summary.txt files, following the format of
# the existing fib_mac_trace_summary.txt / matmul_mac_trace_summary.txt):
#   - Cycles, Instructions, BRANCH_MISPRED_NONSPEC, L1D_CACHE_MISS_LD,
#     INST_INT_LD, INST_BRANCH (raw totals)
#   - Included time span (s)
#   - Derived: IPC, instructions/s, cycles/s, branch miss rate, L1D miss rate
#
# The interesting comparison once this is in hand is asm-IPC vs. proxy-IPC
# (apple_m3_counter_summary.txt) on the same platform: if they diverge, that
# is direct evidence that ISA-specific hand-written instruction selection
# (not just algorithmic work) drives part of the microarchitectural
# difference sec:limitations item 5 currently leaves open.
