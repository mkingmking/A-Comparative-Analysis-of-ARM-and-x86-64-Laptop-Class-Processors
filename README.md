# A Comparative Analysis of ARM and x86-64 Laptop-Class Processors

This repository contains the supporting benchmark artifact for the article:

**A Platform-Level Comparison of Apple M3 (ARM) and AMD Ryzen 7 3750H (x86-64) Laptop Platforms: Architecture, Assembly-Level Performance, and Energy Efficiency**

The study compares an Apple M3 platform running AArch64 code with an AMD Ryzen 7 3750H platform running x86-64 code. It combines architectural analysis with native assembly benchmarks and energy measurements to examine the runtime and energy tradeoffs of the two tested laptop-class systems.

## Article Scope

The article focuses on two hand-written assembly workloads:

| Workload | Input | Main stress point |
| --- | --- | --- |
| Recursive Fibonacci | `fib(40)` | Branching, function calls, recursion overhead |
| Integer matrix multiplication | `256x256` matrices | Arithmetic throughput and memory hierarchy behavior |

The results are interpreted as a platform-level comparison, not as a pure ISA-only verdict. The systems differ in generation, operating system, power-management policy, measurement tooling, and broader platform integration.

## Main Findings

- The Apple M3 is faster on the branch-heavy Fibonacci benchmark: `330.7 ms` versus `475.9 ms` on the Ryzen 7 3750H (a 30.5% lower runtime).
- The Apple M3 is also faster on matrix multiplication: `16.1 ms` versus `26.3 ms` on Ryzen 7 3750H (a 38.8% lower runtime).
- The Apple M3 uses substantially less processor energy per completed run: about `2.16x` lower energy on Fibonacci and `2.13x` lower on matrix multiplication (all 25 recorded power-sampling windows used).
- Matched portable-C counter runs show higher IPC on the Apple M3, while the Ryzen system's higher cycle rate lets it retire about `1.19x` more instructions per second on the Fibonacci proxy, with near-parity on matrix multiplication.

## Repository Layout

```text
.
├── benchmarks/
│   ├── asm_aarch64/          # Apple Silicon / AArch64 assembly kernels + measurement scripts
│   ├── asm_x86_64/           # x86-64 assembly kernels + measurement scripts
│   ├── c_portable/           # Portable C benchmarks and PMU profiling variants
│   ├── scripts/              # Build, run, and precondition-check scripts
│   ├── validation/           # Functional-equivalence runner + machine-readable reports
│   └── analysis/             # Energy-window analysis, confidence intervals, bias
│                             #   sensitivity, compiler-baseline audit
├── figures/
│   ├── generate_figures.py   # Figure generator
│   └── *.pdf, *.png, *.svg   # Generated figures
└── results/                  # Measurement artifacts — see results/README.md
    ├── apple_m3/             # Apple M3 timing, energy, and PMU data
    ├── ryzen7_3750h/         # AMD Ryzen 7 3750H timing and energy data
    └── cross_platform_summary.txt
```

Binaries are not committed; they are rebuilt from source with the scripts under
`benchmarks/scripts/`.

## Regenerating Figures

```bash
python3 figures/generate_figures.py
```

This writes `runtime_comparison`, `energy_per_run`, and `runtime_energy_tradeoff`
in PDF, PNG, and SVG. The article includes the runtime comparison and the
runtime-energy tradeoff; `energy_per_run` is supplementary.

## Reproducing the Benchmarks

The article reports 5 warm-up runs and 100 measured runs per benchmark. The helper scripts under `benchmarks/scripts/` are useful starting points, but their `RUNS` value should be set to `100` when reproducing the article protocol exactly.

Before any measurement on the Apple system, run `benchmarks/scripts/check_measurement_conditions.sh` and fix anything it flags — it refuses to proceed if Low Power Mode is on or stray benchmark processes are running (the failure mode that contaminated the original session). The gated re-run scripts `benchmarks/asm_aarch64/rerun_timing.sh` and `rerun_energy.sh` reproduce the corrected article protocol end to end.

On Apple Silicon / macOS:

```bash
cd benchmarks
bash scripts/run_mac.sh
```

For power sampling on macOS, use the included `powermetrics`-based helper in `benchmarks/asm_aarch64/` with administrator privileges.

On Linux / x86-64:

```bash
cd benchmarks
bash scripts/run_linux.sh
```

Linux energy measurements use `perf` package-energy counters and may require administrator privileges, a supported RAPL interface, and access to `power/energy-pkg/`.

## Measurement Artifacts

All measurement data is under `results/`, grouped by platform.
**[`results/README.md`](results/README.md) is the provenance map** — it records
which artifact backs which reported number and which material is superseded.

| Path | Contents |
| --- | --- |
| `results/apple_m3/timing_rerun_20260722/` | Apple M3 timing behind the reported runtimes (`hyperfine`, 5 warm-up + 100 measured runs) |
| `results/apple_m3/energy_windows_*.csv` | The 25 `powermetrics` power-sampling windows per benchmark behind the reported energy |
| `results/apple_m3/pmu_*_rerun.trace` | Instruments CPU Counters captures behind the reported Apple PMU/IPC values |
| `results/apple_m3/pmu_trace_summaries/` | Text summaries of the superseded original PMU capture |
| `results/apple_m3/superseded_session/` | The original Apple session, later found to have run under Low Power Mode |
| `results/ryzen7_3750h/` | Ryzen timing (`hyperfine`) and package energy (`perf stat`) |
| `results/cross_platform_summary.txt` | Side-by-side summary using the corrected Apple numbers |

To reproduce the reported energy statistics from the raw sampling windows:

```bash
python3 benchmarks/analysis/analyze_energy_windows.py \
    results/apple_m3/energy_windows_fib.csv fib
```

Two caveats are documented in full in `results/README.md`: the Apple session in
`superseded_session/` is kept only for the before/after comparison and is not the
article's reported data, and the Instruments captures under-report clock rate for
the reasons set out in `benchmarks/c_portable/diagnose_profile_clock.sh` (IPC is
reliable; instructions/s and implied GHz characterize the instrumented run).

## Functional Validation

The assembly kernels can be checked against platform-independent reference
implementations with the reproducible validation runner. It tests Fibonacci at
multiple inputs and compares every matrix element across multiple dimensions and
input patterns, including the complete measured 256×256 case. Validation builds
are temporary and do not alter the benchmark binaries used for timing or energy.

On macOS/AArch64:

```bash
python3 benchmarks/validation/validate_functional_equivalence.py arm64-macos
```

On Linux/x86-64 (requires Python 3, NASM, and GCC):

```bash
python3 benchmarks/validation/validate_functional_equivalence.py x86_64-linux
```

Machine-readable reports from the manuscript validation run are stored in
`benchmarks/validation/results_arm64_macos.json` and
`benchmarks/validation/results_x86_64_linux.json`.

## License

This repository is distributed under the license provided in `LICENSE`.
