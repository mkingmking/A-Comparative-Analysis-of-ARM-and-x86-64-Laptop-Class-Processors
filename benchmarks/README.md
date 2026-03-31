# ARM vs x86-64 Benchmark Suite
## For: Comparative Analysis of Mobile and Desktop Microprocessors

---

## Overview

This benchmark suite contains three workload types implemented in:
- **AArch64 assembly** (for Apple Silicon M3 / ARM-based systems)
- **x86-64 assembly** (for AMD Ryzen 5 / Intel-based systems)
- **Portable C** (compiles natively on both — used for cross-validation)

Each workload targets a different processor subsystem to reveal architectural
differences between RISC (ARM) and CISC (x86-64) designs.

---

## Workloads

| # | Workload | What it tests | Why it matters |
|---|----------|---------------|----------------|
| 1 | **Matrix Multiplication** (256×256 integers) | Compute intensity, register usage, ILP | Shows how each ISA handles nested loops and multiply-accumulate patterns |
| 2 | **Array Sum / Memory Sweep** (64 MB) | Memory bandwidth and cache hierarchy | Reveals L1/L2/L3 cache behavior and memory access efficiency |
| 3 | **Recursive Fibonacci** (fib(40)) | Branch prediction, call stack overhead | Exposes RISC vs CISC differences in function call conventions |

---

## How to Handle the "Different Hardware" Concern

Your M3 and Ryzen 5 are at different price/performance tiers. This is NOT
a flaw — handle it with these normalized metrics:

### Raw Metrics (collect these):
- Wall-clock execution time (seconds)
- CPU energy consumed (joules)
- Instructions retired (from perf counters)
- CPU cycles consumed
- Clock frequency during test

### Normalized Metrics (derive and REPORT these):
- **IPC** = Instructions / Cycles — architectural efficiency
- **Energy per Operation** = Joules / Operations — energy efficiency
- **Performance per Watt** = Operations / (Joules/second) — perf/W
- **Energy-Delay Product** = Energy × Time — holistic efficiency
- **Ops per Cycle** = useful operations / cycles — ISA efficiency

These metrics are INDEPENDENT of clock speed and core count, so they
fairly compare an M3 at 4.05 GHz against a Ryzen 5 at 4.6 GHz.

---

## Directory Structure

```
benchmarks/
├── README.md                  # This file
├── asm_aarch64/               # AArch64 assembly (run on Mac M3)
│   ├── matmul_arm.s
│   ├── memwalk_arm.s
│   └── fib_arm.s
├── asm_x86_64/                # x86-64 assembly (run on Ryzen 5 Linux)
│   ├── matmul_x86.asm
│   ├── memwalk_x86.asm
│   └── fib_x86.asm
├── c_portable/                # C versions (compile on BOTH platforms)
│   ├── matmul.c
│   ├── memwalk.c
│   └── fib.c
├── scripts/
│   ├── run_mac.sh             # Profiling script for macOS (powermetrics)
│   └── run_linux.sh           # Profiling script for Linux (perf + RAPL)
└── analysis/
    └── compare.py             # Results comparison and normalization
```

---

## Build & Run Instructions

### On Mac (M3 — AArch64):

```bash
# Assembly benchmarks
as -o matmul_arm.o asm_aarch64/matmul_arm.s
ld -o matmul_arm matmul_arm.o -lSystem -syslibroot $(xcrun --sdk macosx --show-sdk-path) -e _main

# C benchmarks
clang -O0 -o matmul_c_O0 c_portable/matmul.c
clang -O2 -o matmul_c_O2 c_portable/matmul.c

# Run with timing
time ./matmul_arm

# Run with power measurement (requires sudo)
sudo powermetrics --samplers cpu_power -i 100 -n 50 &
./matmul_arm
kill %1
```

### On Linux (Ryzen 5 — x86-64):

```bash
# Assembly benchmarks
nasm -f elf64 -o matmul_x86.o asm_x86_64/matmul_x86.asm
ld -o matmul_x86 matmul_x86.o

# C benchmarks
gcc -O0 -o matmul_c_O0 c_portable/matmul.c
gcc -O2 -o matmul_c_O2 c_portable/matmul.c

# Run with perf (IPC, cache misses, energy)
perf stat -e cycles,instructions,cache-misses,cache-references,\
energy-cores,energy-pkg ./matmul_x86

# Alternative: use 'perf stat -r 30' for 30 repetitions with stats
perf stat -r 30 ./matmul_x86
```

---

## Experimental Protocol

1. **Warm-up**: Run each benchmark 5 times before recording (discard results)
2. **Repetitions**: 30 measured runs per benchmark per platform
3. **Environment**: Close all other applications, disable Wi-Fi/Bluetooth
4. **CPU governor**: Set to 'performance' on Linux (`cpupower frequency-set -g performance`)
5. **Turbo**: Disable turbo/boost for consistent results
   - Linux: `echo 0 > /sys/devices/system/cpu/cpufreq/boost`
   - Mac: Not directly controllable, but powermetrics reports actual frequency
6. **Core pinning**:
   - Linux: `taskset -c 0 ./benchmark`
   - Mac: Use QoS to target P-cores (set in code or via `taskpolicy`)
7. **Reporting**: Mean, standard deviation, 95% confidence interval, min, max

---

## Iso-Power Experiment (Optional but Recommended)

To fairly compare architectures at the same power budget:

1. Find the M3's average power during benchmarks (e.g., ~12W)
2. Throttle the Ryzen 5 to a similar power draw:
   ```bash
   # Set max frequency to reduce power to ~12W
   cpupower frequency-set -u 2.0GHz
   ```
3. Run the same benchmarks and compare performance at equal power
4. This reveals which *architecture* extracts more work per watt

---

## Citation

If you use this benchmark suite in your article, describe it as:
"A custom benchmark suite consisting of three workload types (compute-intensive,
memory-intensive, and branch-intensive) implemented in both AArch64 and x86-64
assembly, designed to isolate architectural differences between ARM and x86
processors."
