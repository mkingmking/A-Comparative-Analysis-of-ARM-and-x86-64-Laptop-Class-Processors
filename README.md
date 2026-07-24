# A Comparative Analysis of ARM and x86-64 Laptop-Class Processors

This repository contains the supporting benchmark artifact for the article:

**A Comparative Analysis of ARM and x86-64 Laptop-Class Processors: Architecture, Assembly-Level Performance, and Energy Efficiency**

The study compares an Apple M3 platform running AArch64 code with an AMD Ryzen 7 3750H platform running x86-64 code. It combines architectural analysis with native assembly benchmarks and energy measurements to examine the runtime and energy tradeoffs of the two tested laptop-class systems.

## Article Scope

The article focuses on two hand-written assembly workloads:

| Workload | Input | Main stress point |
| --- | --- | --- |
| Recursive Fibonacci | `fib(40)` | Branching, function calls, recursion overhead |
| Integer matrix multiplication | `256x256` matrices | Arithmetic throughput and memory hierarchy behavior |

The results are interpreted as a platform-level comparison, not as a pure ISA-only verdict. The systems differ in generation, operating system, power-management policy, measurement tooling, and broader platform integration.

## Main Findings

- The Apple M3 is faster on the branch-heavy Fibonacci benchmark: `330.7 ms` versus `474.8 ms` on the Ryzen 7 3750H (a 30.3% lower runtime).
- The Apple M3 is also faster on matrix multiplication: `16.1 ms` versus `26.4 ms` on Ryzen 7 3750H (a 39.0% lower runtime).
- The Apple M3 uses substantially less processor energy per completed run: about `2.13x` lower energy on both Fibonacci and matrix multiplication.
- Matched portable-C counter runs show higher IPC on the Apple M3, while the Ryzen system retires more instructions per second because of its higher measured cycle rate.

## Repository Layout

```text
.
|-- benchmarks/
|   |-- asm_aarch64/           # Apple Silicon / AArch64 assembly benchmarks
|   |-- asm_x86_64/            # x86-64 assembly benchmarks
|   |-- c_portable/            # Portable C profiling versions
|   `-- scripts/               # Benchmark helper scripts
|-- figures/
|   |-- generate_figures.py    # Figure generator
|   `-- *.png, *.svg           # Article figures
|-- results_mac.txt            # Apple M3 timing and power summaries
|-- results_linux.txt          # Ryzen 7 3750H timing and energy summaries
`-- benchmark_ci_check.py      # Parser/checker for timing and energy summaries
```

## Regenerating Figures

Regenerate article figures if needed:

```bash
python3 figures/generate_figures.py
```

## Reproducing the Benchmarks

The article reports 5 warm-up runs and 100 measured runs per benchmark. The helper scripts under `benchmarks/scripts/` are useful starting points, but their `RUNS` value should be set to `100` when reproducing the article protocol exactly.

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

Result summaries are under `results/`:

- `results/results_mac.txt` (and `macos_timing.txt`, `macos_power.txt`, `summary.txt`): the original Apple M3 timing/power session. This session is superseded — it was later found to be affected by Low Power Mode and is kept only for comparison, not as the article's reported numbers.
- `results/rerun_20260722_223106/`: the corrected Apple M3 timing re-run (`hyperfine`, 5 warm-up + 100 measured runs) behind the runtime figures reported in the article.
- `benchmarks/asm_aarch64/energy_windows_*_rescaled_20260722.csv`: Apple M3 `powermetrics` power-sampling windows rescaled to the corrected mean runtime; run through `benchmarks/analysis/analyze_energy_windows.py` to reproduce the article's energy statistics.
- `results/results_linux.txt` (and `linux_energy.txt`, `linux_timing_new.txt`): `perf stat` package-energy results and `hyperfine` timing results for the Ryzen 7 3750H, unaffected by the Apple-side correction.
- `results/trace_summaries/` (original Apple Instruments CPU Counters capture): superseded. `results/fib_mac_rerun.trace` and `results/matmul_mac_rerun.trace` are the rerun captures behind the article's reported Apple PMU/IPC statistics. Both captures are affected by an Instruments-tooling limitation documented in `benchmarks/c_portable/diagnose_profile_clock.sh`: the traced process is scheduled onto efficiency cores (Fibonacci) or otherwise subject to counter-sampling overhead (matrix multiplication), which suppresses the implied instructions/s and clock-rate figures well below the platform's true operating frequency (confirmed separately via direct `powermetrics` sampling in `powermetrics_*_direct_*.txt`). IPC is stable and reliable across both captures; instructions/s and implied GHz should be read as characterizing the instrumented run, not full-speed execution.

The generated figures in `figures/` visualize runtime, energy per run, and the runtime-energy tradeoff reported in the article.

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
