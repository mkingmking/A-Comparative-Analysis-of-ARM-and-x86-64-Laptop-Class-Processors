#!/usr/bin/env python3
"""Analyze repeated-window Apple energy samples from
measure_power_mac_repeated.sh, and compare against the existing Ryzen
package-energy measurements (results/linux_energy.txt) with a real
two-sample Welch's t-test -- the statistical test that was previously
impossible because the Apple side had no repeated-run variance.

Usage:
    python3 analyze_energy_windows.py <csv_file> <fib|matmul>

The CSV is produced by measure_power_mac_repeated.sh and has columns:
    window,idle_cpu_w,load_cpu_w,delta_cpu_w,mean_runtime_s,energy_j

Ryzen reference stats (from results/linux_energy.txt / Table tab:energy in
the paper) are hardcoded below per benchmark: mean package energy (J) and
the relative standard error (%) reported by `perf stat -r 100`, n=100.
"""
import csv
import math
import statistics
import sys

RYZEN_REF = {
    "fib":    {"mean_j": 3.05, "relse_pct": 2.53, "n": 100},
    "matmul": {"mean_j": 0.18, "relse_pct": 0.78, "n": 100},
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


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in RYZEN_REF:
        print(f"Usage: {sys.argv[0]} <csv_file> <fib|matmul>")
        sys.exit(1)

    csv_path, bench = sys.argv[1], sys.argv[2]

    energies = []
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            energies.append(float(row["energy_j"]))

    n = len(energies)
    if n < 3:
        print(f"Only {n} window(s) in {csv_path} -- need at least a few to compute sd/CI.")
        sys.exit(1)

    mean = statistics.mean(energies)
    sd = statistics.stdev(energies)  # sample sd, n-1
    sem = sd / math.sqrt(n)
    tcrit = t_crit_95(n - 1)
    ci_lo, ci_hi = mean - tcrit * sem, mean + tcrit * sem
    cv_pct = 100 * sd / mean

    print(f"=== Apple M3 repeated-window energy: {bench} ===")
    print(f"  windows (n)        : {n}")
    print(f"  mean energy        : {mean:.4f} J")
    print(f"  sample sd          : {sd:.4f} J")
    print(f"  CV                 : {cv_pct:.2f}%")
    print(f"  95% CI (t, df={n-1}): [{ci_lo:.4f}, {ci_hi:.4f}] J")
    print()

    ref = RYZEN_REF[bench]
    ryzen_mean = ref["mean_j"]
    ryzen_n = ref["n"]
    ryzen_sem = ryzen_mean * ref["relse_pct"] / 100
    ryzen_sd = ryzen_sem * math.sqrt(ryzen_n)

    print(f"=== Ryzen reference (from results/linux_energy.txt): {bench} ===")
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
    print(
        f"  Apple M3: ${mean:.4f} \\pm {sd:.4f}$ J, 95\\% CI $[{ci_lo:.4f}, {ci_hi:.4f}]$ J, $n={n}$."
    )
    print(
        f"  Welch's $t({df:.1f})={t:.2f}$, $p{'<.001' if p < 0.001 else '='+format(p,'.3f')}$, $d={d:.2f}$."
    )


if __name__ == "__main__":
    main()
