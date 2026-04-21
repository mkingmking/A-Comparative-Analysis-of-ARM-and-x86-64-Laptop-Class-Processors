Trace Summaries
===============

This folder contains readable summaries extracted from Apple Instruments .trace bundles.
The raw .trace bundles remain unchanged in the results/ directory.

Files
-----
- trace_inventory.txt: run inventory for each trace bundle.
- fib_mac_trace_summary.txt: cleaned counter summary for fib_profile_O0.
- matmul_mac_trace_summary.txt: cleaned counter summary for matmul_profile_O0.
- apple_m3_counter_summary.txt: compact cross-workload counter table.

Artifact handling
-----------------
Exploratory all-process runs and duplicated runs inside the trace bundles are documented in trace_inventory.txt but excluded from the workload summaries.
Startup/runtime samples before the first target workload frame are excluded from the aggregated counters.
