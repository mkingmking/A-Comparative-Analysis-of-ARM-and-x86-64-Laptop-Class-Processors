# PMU Trace Summaries (Superseded Capture)

Readable summaries extracted from the **original** Apple Instruments CPU Counters
capture. That capture is superseded: its IPC values agree with the ones reported in
the article, but its time spans and derived rates do not. The raw `.trace` bundles
it came from are no longer retained — these text summaries are the surviving
record.

The captures behind the article's reported PMU values are the bundles one level up:
`../pmu_fib_rerun.trace` and `../pmu_matmul_rerun.trace`.

## Files

| File | Contents |
| --- | --- |
| `trace_inventory.txt` | Run inventory for each original trace bundle |
| `counter_summary_fib.txt` | Counter summary for `fib_profile_O0` |
| `counter_summary_matmul.txt` | Counter summary for `matmul_profile_O0` |
| `counter_summary_combined.txt` | Compact cross-workload counter table |

## Artifact handling

Exploratory all-process runs and duplicated runs inside the original bundles are
documented in `trace_inventory.txt` but excluded from the workload summaries.
Startup and runtime samples before the first target workload frame are excluded
from the aggregated counters.
