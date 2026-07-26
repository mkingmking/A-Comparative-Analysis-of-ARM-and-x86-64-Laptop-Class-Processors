# Measurement Artifacts

Provenance map for the measurements reported in the article. Files are grouped by
platform; superseded material is kept in clearly marked subdirectories so that it
is never mistaken for a reported result.

## Apple M3 (`apple_m3/`)

| Artifact | Backs | Notes |
| --- | --- | --- |
| `timing_rerun_20260722/` | Reported Apple runtimes | `hyperfine`, 5 warm-up + 100 measured runs. Preconditions verified (Low Power Mode off, no stray load). |
| `energy_windows_fib.csv`, `energy_windows_matmul.csv` | Reported Apple energy per run | 25 `powermetrics` power-sampling windows per benchmark, taken at the corrected mean runtime. All recorded windows are used. |
| `pmu_fib_rerun.trace`, `pmu_matmul_rerun.trace` | Reported Apple PMU/IPC values | Apple Instruments CPU Counters captures of the portable-C `-O0` profiling programs. Open with Instruments; these bundles are the raw record and have no text summary. |
| `powermetrics_direct_fib.txt`, `powermetrics_direct_matmul.txt` | Clock-rate cross-check | Direct `powermetrics` sampling, used to show that the instrumented runs above under-report frequency. |
| `pmu_trace_summaries/` | **Superseded** | Text summaries extracted from the original PMU capture. The IPC values agree with the reported ones; the time spans and derived rates do not. The raw bundles are no longer retained — these summaries are the surviving record. |
| `superseded_session/` | **Superseded** | The original Apple timing/power session, later found to have run under Low Power Mode. Kept only for the before/after comparison discussed in the article. |

To reproduce the reported energy statistics from the sampling windows:

```bash
python3 benchmarks/analysis/analyze_energy_windows.py \
    results/apple_m3/energy_windows_fib.csv fib
```

### Reading the PMU captures

Both Instruments captures are affected by a tooling limitation documented in
`benchmarks/c_portable/diagnose_profile_clock.sh`: the traced process is
scheduled onto efficiency cores (Fibonacci) or otherwise subject to
counter-sampling overhead (matrix multiplication). This suppresses the implied
instructions/s and clock-rate figures well below the platform's true operating
frequency. **IPC is stable and reliable across both captures; instructions/s and
implied GHz characterize the instrumented run, not full-speed execution.**

## AMD Ryzen 7 3750H (`ryzen7_3750h/`)

| Artifact | Contents |
| --- | --- |
| `timing.txt` | `hyperfine`, 5 warm-up + 100 measured runs |
| `energy.txt` | `perf stat` package energy via `power/energy-pkg/`, 100 runs |
| `results.txt` | Combined platform, timing, and energy summary |

The Ryzen measurements are unaffected by the Apple-side correction and were not
re-run.

## Cross-platform

`cross_platform_summary.txt` — side-by-side timing and energy summary across both
platforms, using the corrected Apple numbers.
