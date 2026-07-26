#!/usr/bin/env python3
"""Analyze repeated-window Apple energy samples from
measure_power_mac_repeated.sh, and compare against the existing Ryzen
package-energy measurements (results/ryzen7_3750h/results.txt) with a real
two-sample Welch's t-test -- the statistical test that was previously
impossible because the Apple side had no repeated-run variance.

Usage:
    python3 analyze_energy_windows.py <csv_file> <fib|matmul> [--skip-warmup N]
        [--runtime-json PATH]

Every recorded window is used as measured. The only window a run discards is
an explicit --skip-warmup, a fixed protocol step applied by position.

--skip-warmup N (default 0): discard the first N windows before computing
statistics. measure_power_mac_repeated.sh now runs and discards its own
warm-up window before recording any of the N requested windows, so CSVs it
produces need no further skipping. CSVs collected before that fix (window 1
still present as the first data row) need --skip-warmup 1.

--runtime-json PATH: read a hyperfine JSON result and additionally report a
delta-method confidence interval for mean energy that propagates uncertainty
from both the retained power-window mean and the runtime mean.

Columns are read positionally (window, idle, load, delta, ..., energy=last
column), not by header name, so this works whether or not a given CSV
includes the retired mean_runtime_s column.

Ryzen reference stats (from results/ryzen7_3750h/results.txt / Table tab:energy in
the paper) are hardcoded below per benchmark: mean package energy (J) and
the relative standard error (%) reported by `perf stat -r 100`, n=100.
"""
import csv
import json
import math
import statistics
import sys

RYZEN_REF = {
    "fib":    {"mean_j": 3.04, "relse_pct": 2.52, "n": 100},
    "matmul": {"mean_j": 0.179, "relse_pct": 0.77, "n": 100},
}


def betacf(a, b, x):
    MAXIT, EPS, FPMIN = 200, 3e-14, 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < FPMIN:
        d = FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        de = d * c
        h *= de
        if abs(de - 1.0) < EPS:
            break
    return h


def betai(a, b, x):
    if x <= 0 or x >= 1:
        return float(x <= 0)
    bt = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log(1 - x)
    )
    if x < (a + 1) / (a + b + 2):
        return bt * betacf(a, b, x) / a
    return 1.0 - bt * betacf(b, a, 1 - x) / b


def t_two_sided_p(t, df):
    x = df / (df + t * t)
    return betai(df / 2.0, 0.5, x)


def t_crit_95(df):
    # bisection on the same betai-based CDF; good to ~1e-4
    lo, hi = 0.0, 50.0
    for _ in range(100):
        mid = (lo + hi) / 2
        p = t_two_sided_p(mid, df)
        if p > 0.05:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def welch(mean1, sd1, n1, mean2, sd2, n2):
    se = math.sqrt(sd1**2 / n1 + sd2**2 / n2)
    t = (mean1 - mean2) / se
    df = (sd1**2 / n1 + sd2**2 / n2) ** 2 / (
        (sd1**2 / n1) ** 2 / (n1 - 1) + (sd2**2 / n2) ** 2 / (n2 - 1)
    )
    p = t_two_sided_p(abs(t), df)
    return t, df, p


def cohens_d(m1, s1, n1, m2, s2, n2):
    sp = math.sqrt(((n1 - 1) * s1**2 + (n2 - 1) * s2**2) / (n1 + n2 - 2))
    return (m1 - m2) / sp


def load_windows(csv_path):
    """Returns a list of (window, idle_w, load_w, delta_w, energy_j) tuples,
    read positionally: idx0=window, idx1=idle, idx2=load, idx3=delta,
    idx[-1]=energy. Robust to whether mean_runtime_s is present as a middle
    column."""
    rows = []
    with open(csv_path, newline="") as f:
        reader = csv.reader(f)
        next(reader)  # header
        for parts in reader:
            if not parts:
                continue
            window = int(parts[0])
            idle_w, load_w, delta_w = float(parts[1]), float(parts[2]), float(parts[3])
            energy_j = float(parts[-1])
            rows.append((window, idle_w, load_w, delta_w, energy_j))
    return rows


def parse_args(argv):
    """Manual parser: two required positionals (csv_path, bench), plus
    optional --skip-warmup N and --runtime-json PATH in any order."""
    positional = []
    skip = 0
    runtime_json = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--skip-warmup":
            if i + 1 >= len(argv):
                return None
            skip = int(argv[i + 1])
            i += 2
        elif arg == "--runtime-json":
            if i + 1 >= len(argv):
                return None
            runtime_json = argv[i + 1]
            i += 2
        elif arg.startswith("--"):
            return None
        else:
            positional.append(arg)
            i += 1
    if len(positional) != 2 or positional[1] not in RYZEN_REF:
        return None
    return positional[0], positional[1], skip, runtime_json


def main():
    parsed = parse_args(sys.argv[1:])
    if parsed is None:
        print(
            f"Usage: {sys.argv[0]} <csv_file> <fib|matmul> "
            "[--skip-warmup N] [--runtime-json PATH]"
        )
        sys.exit(1)
    csv_path, bench, skip, runtime_json = parsed

    all_rows = load_windows(csv_path)
    warmup, kept = all_rows[:skip], all_rows[skip:]
    if warmup:
        print(f"Discarded {len(warmup)} warm-up window(s): {[('%.4f J' % r[4]) for r in warmup]}")

    energies = [r[4] for r in kept]
    n = len(energies)
    if n < 3:
        print(f"Only {n} window(s) left in {csv_path} after warm-up skip -- need at least a few to compute sd/CI.")
        sys.exit(1)

    mean = statistics.mean(energies)
    sd = statistics.stdev(energies)  # sample sd, n-1
    sem = sd / math.sqrt(n)
    tcrit = t_crit_95(n - 1)
    ci_lo, ci_hi = mean - tcrit * sem, mean + tcrit * sem
    cv_pct = 100 * sd / mean

    print(f"=== Apple M3 repeated-window energy: {bench} ===")
    print(f"  windows (n)        : {n}  (all recorded windows used, {len(warmup)} warm-up discarded)")
    print(f"  mean energy        : {mean:.4f} J")
    print(f"  sample sd          : {sd:.4f} J")
    print(f"  CV                 : {cv_pct:.2f}%")
    print(f"  95% CI (t, df={n-1}): [{ci_lo:.4f}, {ci_hi:.4f}] J")
    print()

    if runtime_json:
        with open(runtime_json) as f:
            timing = json.load(f)["results"][0]
        runtime_mean = float(timing["mean"])
        runtime_sd = float(timing["stddev"])
        runtime_n = len(timing["times"])
        powers = [r[3] for r in kept]
        power_mean = statistics.mean(powers)
        power_sd = statistics.stdev(powers)
        propagated_mean = power_mean * runtime_mean
        power_component = runtime_mean**2 * power_sd**2 / n
        runtime_component = power_mean**2 * runtime_sd**2 / runtime_n
        propagated_sem = math.sqrt(power_component + runtime_component)
        propagated_df = (power_component + runtime_component) ** 2 / (
            power_component**2 / (n - 1)
            + runtime_component**2 / (runtime_n - 1)
        )
        propagated_tcrit = t_crit_95(propagated_df)
        propagated_lo = propagated_mean - propagated_tcrit * propagated_sem
        propagated_hi = propagated_mean + propagated_tcrit * propagated_sem
        print("=== Delta-method CI including runtime-mean uncertainty ===")
        print(f"  power windows (n_P): {n}")
        print(f"  timing runs (n_T)  : {runtime_n}")
        print(f"  mean energy        : {propagated_mean:.4f} J")
        print(f"  propagated SE      : {propagated_sem:.4f} J")
        print(f"  effective df       : {propagated_df:.1f}")
        print(f"  95% CI             : [{propagated_lo:.4f}, {propagated_hi:.4f}] J")
        print()

    ref = RYZEN_REF[bench]
    ryzen_mean = ref["mean_j"]
    ryzen_n = ref["n"]
    ryzen_sem = ryzen_mean * ref["relse_pct"] / 100
    ryzen_sd = ryzen_sem * math.sqrt(ryzen_n)

    print(f"=== Ryzen reference (from results/ryzen7_3750h/results.txt): {bench} ===")
    print(f"  n                  : {ryzen_n}")
    print(f"  mean energy        : {ryzen_mean:.4f} J")
    print(f"  implied sd         : {ryzen_sd:.4f} J  (from {ref['relse_pct']}% relative std. error)")
    print()

    t, df, p = welch(mean, sd, n, ryzen_mean, ryzen_sd, ryzen_n)
    d = cohens_d(mean, sd, n, ryzen_mean, ryzen_sd, ryzen_n)

    print("=== Welch's t-test: Apple (new, repeated-window) vs. Ryzen (perf stat) ===")
    print(f"  t({df:.1f}) = {t:.3f}, p = {p:.3e}, Cohen's d = {d:.3f}")
    print()
    print("LaTeX-ready snippet:")
    if runtime_json:
        print(
            f"  Apple M3: ${propagated_mean:.4f}$ J, delta-method 95\\% CI "
            f"$[{propagated_lo:.4f}, {propagated_hi:.4f}]$ J, "
            f"$n_P={n}$, $n_T={runtime_n}$."
        )
    else:
        print(
            f"  Apple M3: ${mean:.4f} \\pm {sd:.4f}$ J, "
            f"95\\% CI $[{ci_lo:.4f}, {ci_hi:.4f}]$ J, $n={n}$."
        )
    print(
        f"  Welch's $t({df:.1f})={t:.2f}$, $p{'<.001' if p < 0.001 else '='+format(p,'.3f')}$, $d={d:.2f}$."
    )


if __name__ == "__main__":
    main()
