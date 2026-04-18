#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, Optional, Tuple

try:
    from scipy import stats
except Exception:  # pragma: no cover
    stats = None


@dataclass
class TimingStats:
    bench: str
    mean_s: float
    sd_s: float
    n: int
    min_s: float
    max_s: float
    source: str

    @property
    def se_s(self) -> float:
        return self.sd_s / math.sqrt(self.n)

    @property
    def ci95(self) -> Tuple[float, float]:
        crit = t_critical_975(self.n - 1)
        half = crit * self.se_s
        return self.mean_s - half, self.mean_s + half


@dataclass
class EnergyStats:
    bench: str
    mean_j: float
    sd_j: Optional[float]
    n: Optional[int]
    source: str
    note: str = ""

    @property
    def ci95(self) -> Optional[Tuple[float, float]]:
        if self.sd_j is None or self.n is None or self.n < 2:
            return None
        crit = t_critical_975(self.n - 1)
        half = crit * (self.sd_j / math.sqrt(self.n))
        return self.mean_j - half, self.mean_j + half


def t_critical_975(df: int) -> float:
    if stats is not None:
        return float(stats.t.ppf(0.975, df))
    # fallback: normal approximation for large n
    return 1.96


def seconds_from_value(value: float, unit: str) -> float:
    unit = unit.lower()
    if unit == "s":
        return value
    if unit == "ms":
        return value / 1000.0
    if unit in ("us", "µs"):
        return value / 1_000_000.0
    raise ValueError(f"Unsupported time unit: {unit}")


def normalize_bench(name: str) -> str:
    raw = name.strip().lower()
    raw = raw.split("/")[-1]
    raw = raw.replace("./", "")
    if "fib" in raw:
        return "fib"
    if "matmul" in raw:
        return "matmul"
    return re.sub(r"[^a-z0-9]+", "_", raw).strip("_")


def parse_hyperfine(text: str, source: str) -> Dict[str, TimingStats]:
    results: Dict[str, TimingStats] = {}
    pat = re.compile(
        r"Benchmark\s+\d+:\s+(?P<cmd>.+?)\n"
        r"\s*Time \(mean ± σ\):\s+(?P<mean>[0-9.,]+)\s*(?P<unit>ms|s|us|µs)\s*±\s*(?P<sd>[0-9.,]+)\s*(?P=unit).*?\n"
        r"\s*Range \(min … max\):\s+(?P<min>[0-9.,]+)\s*(?P=unit)\s*…\s*(?P<max>[0-9.,]+)\s*(?P=unit)\s+(?P<n>\d+)\s+runs",
        re.S,
    )
    for m in pat.finditer(text):
        cmd = m.group("cmd").strip().strip("'")
        bench = normalize_bench(cmd)
        mean = float(m.group("mean").replace(",", "."))
        sd = float(m.group("sd").replace(",", "."))
        mn = float(m.group("min").replace(",", "."))
        mx = float(m.group("max").replace(",", "."))
        unit = m.group("unit")
        n = int(m.group("n"))
        results[bench] = TimingStats(
            bench=bench,
            mean_s=seconds_from_value(mean, unit),
            sd_s=seconds_from_value(sd, unit),
            n=n,
            min_s=seconds_from_value(mn, unit),
            max_s=seconds_from_value(mx, unit),
            source=source,
        )
    return results


def parse_linux_perf(text: str, source: str) -> Dict[str, EnergyStats]:
    results: Dict[str, EnergyStats] = {}
    cmd_pat = re.compile(r"^.*?sudo perf stat -r\s+(?P<n>\d+)\s+-e\s+power/energy-pkg/\s+\./(?P<cmd>[A-Za-z0-9_\-]+).*$", re.M)
    blocks = []
    for m in cmd_pat.finditer(text):
        blocks.append((m.start(), int(m.group("n")), normalize_bench(m.group("cmd"))))
    blocks.append((len(text), None, None))
    for (start, n, bench), (next_start, _, _) in zip(blocks, blocks[1:]):
        chunk = text[start:next_start]
        em = re.search(r"([0-9.,]+)\s+Joules\s+power/energy-pkg/\s+\( \+\-\s*([0-9.,]+)% \)", chunk)
        if not em:
            continue
        mean_j = float(em.group(1).replace(",", "."))
        rel_pct = float(em.group(2).replace(",", "."))
        sd_j = mean_j * rel_pct / 100.0
        results[bench] = EnergyStats(bench=bench, mean_j=mean_j, sd_j=sd_j, n=n, source=source, note="Derived from perf repeated-run relative spread.")
    return results


def parse_mac_power(text: str, timing: Dict[str, TimingStats], source: str) -> Dict[str, EnergyStats]:
    results: Dict[str, EnergyStats] = {}
    # Split per benchmark block
    pat = re.compile(r"=== Power Measurement: (?P<cmd>\./[^=\n]+) ===(?P<body>.*?)(?=(?:=== Power Measurement:|\Z))", re.S)
    for m in pat.finditer(text):
        bench = normalize_bench(m.group("cmd"))
        body = m.group("body")
        pm = re.search(r"CPU Power\s+[0-9.]+\s*W\s+[0-9.]+\s*W\s+([0-9.]+)\s*W", body)
        if not pm or bench not in timing:
            continue
        delta_w = float(pm.group(1))
        mean_j = delta_w * timing[bench].mean_s
        results[bench] = EnergyStats(
            bench=bench,
            mean_j=mean_j,
            sd_j=None,
            n=None,
            source=source,
            note="Point estimate from delta CPU power × mean runtime; CI unavailable from summary file.",
        )
    return results


def welch_test(a: TimingStats, b: TimingStats) -> Tuple[Optional[float], Optional[float]]:
    if stats is None:
        return None, None
    res = stats.ttest_ind_from_stats(
        mean1=a.mean_s, std1=a.sd_s, nobs1=a.n,
        mean2=b.mean_s, std2=b.sd_s, nobs2=b.n,
        equal_var=False,
    )
    # Welch-Satterthwaite df
    s1 = (a.sd_s ** 2) / a.n
    s2 = (b.sd_s ** 2) / b.n
    df = (s1 + s2) ** 2 / ((s1 ** 2) / (a.n - 1) + (s2 ** 2) / (b.n - 1))
    return float(res.pvalue), float(df)


def fmt_s(x: float) -> str:
    if x < 1:
        return f"{x*1000:.3f} ms"
    return f"{x:.6f} s"


def fmt_ci(ci: Tuple[float, float]) -> str:
    return f"[{fmt_s(ci[0])}, {fmt_s(ci[1])}]"


def fmt_j(x: float) -> str:
    return f"{x:.4f} J" if x < 1 else f"{x:.3f} J"


def report_timing(label: str, timing: Dict[str, TimingStats]) -> str:
    lines = [f"\n{label} timing summary"]
    for bench in sorted(timing):
        t = timing[bench]
        lines.append(
            f"- {bench}: mean={fmt_s(t.mean_s)}, sd={fmt_s(t.sd_s)}, "
            f"95% CI={fmt_ci(t.ci95)}, min={fmt_s(t.min_s)}, max={fmt_s(t.max_s)}, n={t.n}"
        )
    return "\n".join(lines)


def report_energy(label: str, energy: Dict[str, EnergyStats]) -> str:
    lines = [f"\n{label} energy summary"]
    for bench in sorted(energy):
        e = energy[bench]
        if e.ci95 is None:
            lines.append(f"- {bench}: mean={fmt_j(e.mean_j)} ({e.note})")
        else:
            ci = e.ci95
            lines.append(f"- {bench}: mean={fmt_j(e.mean_j)}, 95% CI=[{fmt_j(ci[0])}, {fmt_j(ci[1])}], n={e.n}")
    return "\n".join(lines)


def compare_platforms(mac_timing: Dict[str, TimingStats], linux_timing: Dict[str, TimingStats], mac_energy: Dict[str, EnergyStats], linux_energy: Dict[str, EnergyStats]) -> str:
    lines = ["\nCross-platform timing comparison"]
    common = sorted(set(mac_timing) & set(linux_timing))
    for bench in common:
        a = mac_timing[bench]
        b = linux_timing[bench]
        pvalue, df = welch_test(a, b)
        ratio = b.mean_s / a.mean_s
        overlap = not (a.ci95[1] < b.ci95[0] or b.ci95[1] < a.ci95[0])
        lines.append(
            f"- {bench}: Mac mean={fmt_s(a.mean_s)}, Linux mean={fmt_s(b.mean_s)}, "
            f"Linux/Mac ratio={ratio:.3f}, CI overlap={'yes' if overlap else 'no'}"
        )
        if pvalue is not None:
            lines.append(f"  Welch t-test from summary stats: p={pvalue:.3e}, df≈{df:.1f}")
    common_e = sorted(set(mac_energy) & set(linux_energy))
    lines.append("\nCross-platform energy comparison")
    for bench in common_e:
        me = mac_energy[bench]
        le = linux_energy[bench]
        ratio = le.mean_j / me.mean_j
        lines.append(f"- {bench}: Mac={fmt_j(me.mean_j)}, Linux={fmt_j(le.mean_j)}, Linux/Mac energy ratio={ratio:.3f}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Compute 95% confidence intervals and cross-platform comparisons from the uploaded benchmark summary files.")
    parser.add_argument("mac_results", help="Path to the macOS results summary file")
    parser.add_argument("linux_results", help="Path to the Linux results summary file")
    args = parser.parse_args()

    mac_text = Path(args.mac_results).read_text(encoding="utf-8", errors="replace")
    linux_text = Path(args.linux_results).read_text(encoding="utf-8", errors="replace")

    mac_timing = parse_hyperfine(mac_text, "mac")
    linux_timing = parse_hyperfine(linux_text, "linux")
    linux_energy = parse_linux_perf(linux_text, "linux")
    mac_energy = parse_mac_power(mac_text, mac_timing, "mac")

    print(report_timing("macOS", mac_timing))
    print(report_energy("macOS", mac_energy))
    print(report_timing("Linux", linux_timing))
    print(report_energy("Linux", linux_energy))
    print(compare_platforms(mac_timing, linux_timing, mac_energy, linux_energy))


if __name__ == "__main__":
    main()
