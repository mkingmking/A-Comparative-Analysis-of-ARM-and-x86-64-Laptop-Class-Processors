# How to Collect Benchmark Data for Your Article
# ================================================

# STEP 1: Build the fixed programs
# ---------------------------------
as -o fib_arm.o fib_arm.s
ld -o fib_arm fib_arm.o -lSystem -syslibroot $(xcrun --sdk macosx --show-sdk-path) -e _main

as -o matmul_arm.o matmul_arm.s
ld -o matmul_arm matmul_arm.o -lSystem -syslibroot $(xcrun --sdk macosx --show-sdk-path) -e _main

# STEP 2: Quick test (should now show correct values)
# ---------------------------------------------------
./fib_arm
# Expected: fib(40) = 102334155, Time: ~XXX ms

./matmul_arm
# Expected: C[0] = some integer, Time: ~XXX ms


# =============================================
#  THREE WAYS TO COLLECT DATA
# =============================================

# METHOD A: Built-in timing (already in the programs now)
# -------------------------------------------------------
# Just run the program — it prints its own time in milliseconds.
# Do this 30 times and record the "Time:" values:
for i in $(seq 1 30); do ./fib_arm 2>&1 | grep "Time:"; done

# To save to a file:
for i in $(seq 1 30); do ./fib_arm 2>&1 | grep "Time:"; done > fib_times.txt


# METHOD B: hyperfine (RECOMMENDED — best for your paper)
# -------------------------------------------------------
# Install: brew install hyperfine
#
# This automates warmup + repetitions + gives you mean, stddev, min, max:

hyperfine --warmup 5 --runs 30 './fib_arm'
hyperfine --warmup 5 --runs 30 './matmul_arm'

# For side-by-side comparison of assembly vs C:
# First compile C version:
clang -O0 -o fib_c fib.c
hyperfine --warmup 5 --runs 30 './fib_arm' './fib_c'

# Export to CSV for your paper:
hyperfine --warmup 5 --runs 30 --export-csv fib_results.csv './fib_arm' './fib_c'

# Export to markdown table (paste directly into paper):
hyperfine --warmup 5 --runs 30 --export-markdown fib_table.md './fib_arm' './fib_c'


# METHOD C: powermetrics (for ENERGY measurement)
# ------------------------------------------------
# This is what Hübner et al. used in their Apple Silicon HPC paper.
# Requires sudo. Run in two terminals:

# Terminal 1 — start power monitoring:
sudo powermetrics --samplers cpu_power -i 500 -n 40 > power_fib.txt

# Terminal 2 — run the benchmark while monitoring:
./fib_arm

# Then look at power_fib.txt for lines like:
#   CPU Power: 5.2 W
#   Package Power: 7.1 W
#
# To calculate energy:
#   Energy (J) = Average Power (W) × Time (s)
#   e.g., 5.2 W × 0.45 s = 2.34 J


# =============================================
#  WHAT TO PUT IN YOUR PAPER
# =============================================
#
# For each benchmark, report a table like:
#
# | Metric              | ARM (M3)  | x86-64 (Ryzen 5) |
# |---------------------|-----------|-------------------|
# | Execution time (ms) | 450 ± 12  | 380 ± 8           |
# | Avg CPU power (W)   | 5.2       | 28.4              |
# | Energy consumed (J) | 2.34      | 10.79             |
# | Energy per op (nJ)  | 0.070     | 0.322             |
# | Perf per watt       | ...       | ...               |
#
# The energy metrics are where ARM shines even if raw time is slower.
# That's the key finding of your architectural comparison.


# =============================================
#  ON YOUR LINUX PC (Ryzen 5)
# =============================================
#
# Build x86 assembly:
#   nasm -f elf64 -o fib_x86.o fib_x86.asm
#   gcc -o fib_x86 fib_x86.o -no-pie
#
# Measure with perf (gives IPC, cache misses, AND energy):
#   perf stat -r 30 -e cycles,instructions,cache-misses,power/energy-pkg/ ./fib_x86
#
# Or use hyperfine for timing:
#   hyperfine --warmup 5 --runs 30 './fib_x86'
