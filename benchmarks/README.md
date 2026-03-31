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

| # | Workload | What it tests | Why |
|---|----------|---------------|----------------|
| 1 | **Matrix Multiplication** (256×256 integers) | Compute intensity, register usage, ILP | Shows how each ISA handles nested loops and multiply-accumulate patterns |
| 2 | **Array Sum / Memory Sweep** (64 MB) | Memory bandwidth and cache hierarchy | Reveals L1/L2/L3 cache behavior and memory access efficiency |
| 3 | **Recursive Fibonacci** (fib(40)) | Branch prediction, call stack overhead | Exposes RISC vs CISC differences in function call conventions |

---





### Raw Metrics:
- Wall-clock execution time (seconds)
- CPU energy consumed (joules)
- Instructions retired (from perf counters)
- CPU cycles consumed
- Clock frequency during test

### Normalized Metrics:
- **IPC** = Instructions / Cycles — architectural efficiency
- **Energy per Operation** = Joules / Operations — energy efficiency
- **Performance per Watt** = Operations / (Joules/second) — perf/W
- **Energy-Delay Product** = Energy × Time — holistic efficiency
- **Ops per Cycle** = useful operations / cycles — ISA efficiency

These metrics are INDEPENDENT of clock speed and core count.

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

### On Mac:

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

### On Linux:

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



