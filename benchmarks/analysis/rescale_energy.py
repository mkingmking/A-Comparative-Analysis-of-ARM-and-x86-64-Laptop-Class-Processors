#!/usr/bin/env python3
"""Recompute energy_j for an existing measure_power_mac_repeated.sh CSV
using a corrected MEAN_RUNTIME_S, without re-sampling power.

WHY THIS EXISTS
---------------
energy_j = delta_cpu_w * MEAN_RUNTIME_S, where MEAN_RUNTIME_S is a fixed
external constant baked in at measurement time (see the "DESIGN CHOICE"
comment in measure_power_mac_repeated.sh). The power sampling (idle/load/
delta, in Watts) is independent of that constant -- it's measured from a
continuous run-in-a-loop window, not a single invocation -- so if a CSV's
power columns are already known-good (verified full-clock, not Low Power
Mode), a corrected MEAN_RUNTIME_S can be applied after the fact instead of
re-running powermetrics.

Usage:
    python3 rescale_energy.py <input_csv> <new_mean_runtime_s> <output_csv>

Reads columns positionally (window, idle, load, delta, ...) same as
analyze_energy_windows.py, and ignores any existing mean_runtime_s/energy_j
columns rather than trusting their header names.
"""
import csv
import sys


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input_csv> <new_mean_runtime_s> <output_csv>")
        sys.exit(1)

    in_path, new_runtime_s, out_path = sys.argv[1], float(sys.argv[2]), sys.argv[3]

    with open(in_path, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = [row for row in reader if row]

    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["window", "idle_cpu_w", "load_cpu_w", "delta_cpu_w", "energy_j"])
        for row in rows:
            window, idle, load, delta = row[0], float(row[1]), float(row[2]), float(row[3])
            energy_j = delta * new_runtime_s
            writer.writerow([window, f"{idle:.4f}", f"{load:.4f}", f"{delta:.4f}", f"{energy_j:.6f}"])

    print(f"Rescaled {len(rows)} windows from {in_path}")
    print(f"  old runtime multiplier implied by row 1: {float(rows[0][-1]) / float(rows[0][3]):.6f} s")
    print(f"  new runtime multiplier applied:          {new_runtime_s:.6f} s")
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
