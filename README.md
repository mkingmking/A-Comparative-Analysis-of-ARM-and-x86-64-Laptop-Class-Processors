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

- The Ryzen 7 3750H is faster on the branch-heavy Fibonacci benchmark: `474.8 ms` versus `583.6 ms` on the Apple M3.
- Matrix multiplication shows no decisive runtime winner in the reported measurements: `26.0 ms` on Apple M3 and `26.4 ms` on Ryzen 7 3750H.
- The Apple M3 uses substantially less processor energy per completed run: about `5.82x` lower energy on Fibonacci and `6.38x` lower energy on matrix multiplication.
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

The root-level result summaries contain the measurements used in the article:

- `results_mac.txt`: `hyperfine` timing results and `powermetrics` CPU-power estimates for the Apple M3.
- `results_linux.txt`: `perf stat` package-energy results and `hyperfine` timing results for the Ryzen 7 3750H.

The generated figures in `figures/` visualize runtime, energy per run, and the runtime-energy tradeoff reported in the article.

## License

This repository is distributed under the license provided in `LICENSE`.
