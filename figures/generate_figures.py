#!/usr/bin/env python3
"""Generate manuscript figures without third-party plotting dependencies."""

from __future__ import annotations

import math
from pathlib import Path


OUT_DIR = Path(__file__).resolve().parent

APPLE = "#00796B"
RYZEN = "#D55E00"
TEXT = "#202020"
GRID = "#D8D8D8"
AXIS = "#404040"


def esc(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def svg_doc(width: int, height: int, body: str) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="white"/>
  <style>
    text {{ font-family: Arial, Helvetica, sans-serif; fill: {TEXT}; }}
    .title {{ font-size: 18px; font-weight: 700; }}
    .axis {{ font-size: 13px; }}
    .tick {{ font-size: 12px; fill: #444; }}
    .label {{ font-size: 12px; }}
    .legend {{ font-size: 13px; }}
    .note {{ font-size: 11px; fill: #555; }}
  </style>
{body}
</svg>
"""


def line(x1, y1, x2, y2, stroke=AXIS, width=1):
    return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{width}"/>'


def rect(x, y, w, h, fill, stroke="none"):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}" stroke="{stroke}"/>'


def text(x, y, value, size_class="axis", anchor="middle", weight=None, rotate=None):
    attrs = [f'x="{x:.1f}"', f'y="{y:.1f}"', f'class="{size_class}"', f'text-anchor="{anchor}"']
    if weight:
        attrs.append(f'font-weight="{weight}"')
    if rotate:
        attrs.append(f'transform="rotate({rotate} {x:.1f} {y:.1f})"')
    return f"<text {' '.join(attrs)}>{esc(value)}</text>"


def legend(x, y):
    return "\n".join(
        [
            rect(x, y - 10, 14, 14, APPLE),
            text(x + 20, y + 2, "Apple M3", "legend", "start"),
            rect(x + 110, y - 10, 14, 14, RYZEN),
            text(x + 130, y + 2, "Ryzen 7 3750H", "legend", "start"),
        ]
    )


def panel_bars(x, y, w, h, title, ylabel, apple, ryzen, ymax, ticks, apple_err=None, ryzen_err=None, value_fmt="{:.1f}"):
    left = x + 55
    right = x + w - 20
    top = y + 42
    bottom = y + h - 58
    plot_w = right - left
    plot_h = bottom - top
    bar_w = 52
    gap = 22
    cx = left + plot_w / 2
    apple_x = cx - bar_w - gap / 2
    ryzen_x = cx + gap / 2

    def yy(v):
        return bottom - (v / ymax) * plot_h

    parts = [
        text(x + w / 2, y + 22, title, "axis", "middle", "700"),
        line(left, top, left, bottom),
        line(left, bottom, right, bottom),
    ]
    for t in ticks:
        ty = yy(t)
        parts.append(line(left, ty, right, ty, GRID))
        parts.append(text(left - 8, ty + 4, f"{t:g}", "tick", "end"))
    parts.append(text(left - 42, top + plot_h / 2, ylabel, "axis", "middle", rotate=-90))

    for bx, val, err, color, label in [
        (apple_x, apple, apple_err, APPLE, "Apple"),
        (ryzen_x, ryzen, ryzen_err, RYZEN, "Ryzen"),
    ]:
        by = yy(val)
        parts.append(rect(bx, by, bar_w, bottom - by, color))
        if err:
            low, high = err
            ey_low = yy(low)
            ey_high = yy(high)
            ex = bx + bar_w / 2
            parts.append(line(ex, ey_high, ex, ey_low, "#111", 1.3))
            parts.append(line(ex - 8, ey_high, ex + 8, ey_high, "#111", 1.3))
            parts.append(line(ex - 8, ey_low, ex + 8, ey_low, "#111", 1.3))
        parts.append(text(bx + bar_w / 2, by - 8, value_fmt.format(val), "label"))
        parts.append(text(bx + bar_w / 2, bottom + 18, label, "tick"))
    return "\n".join(parts)


def make_runtime():
    width, height = 980, 480
    body = "\n".join(
        [
            text(width / 2, 32, "Execution Time by Benchmark", "title"),
            legend(365, 62),
            panel_bars(
                35,
                85,
                445,
                345,
                "fib(40)",
                "Time (ms)",
                583.6,
                474.8,
                650,
                [0, 150, 300, 450, 600],
                apple_err=(578.445, 588.755),
                ryzen_err=(473.957, 475.643),
                value_fmt="{:.1f}",
            ),
            panel_bars(
                500,
                85,
                445,
                345,
                "matmul 256x256",
                "Time (ms)",
                26.0,
                26.4,
                32,
                [0, 8, 16, 24, 32],
                apple_err=(25.941, 26.059),
                ryzen_err=(25.538, 27.262),
                value_fmt="{:.1f}",
            ),
            text(width / 2, 455, "Error bars show 95% confidence intervals over 100 measured runs.", "note"),
        ]
    )
    (OUT_DIR / "runtime_comparison.svg").write_text(svg_doc(width, height, body), encoding="utf-8")


def make_energy():
    width, height = 980, 480
    body = "\n".join(
        [
            text(width / 2, 32, "Package Energy per Completed Run", "title"),
            legend(365, 62),
            panel_bars(
                35,
                85,
                445,
                345,
                "fib(40)",
                "Energy (J)",
                0.5241,
                3.05,
                3.5,
                [0, 1, 2, 3],
                value_fmt="{:.3g}",
            ),
            panel_bars(
                500,
                85,
                445,
                345,
                "matmul 256x256",
                "Energy (J)",
                0.0282,
                0.18,
                0.21,
                [0, 0.05, 0.10, 0.15, 0.20],
                value_fmt="{:.3g}",
            ),
            text(width / 2, 455, "Apple values are point estimates from delta CPU power x mean runtime; Ryzen values are package-energy counter readings.", "note"),
        ]
    )
    (OUT_DIR / "energy_per_run.svg").write_text(svg_doc(width, height, body), encoding="utf-8")


def make_tradeoff():
    width, height = 780, 520
    left, right, top, bottom = 85, 735, 70, 455
    plot_w, plot_h = right - left, bottom - top
    x_min, x_max = 15, 650
    y_min, y_max = 0, 3.35

    def xx(v):
        return left + ((v - x_min) / (x_max - x_min)) * plot_w

    def yy(v):
        return bottom - ((v - y_min) / (y_max - y_min)) * plot_h

    points = [
        ("fib Apple", 583.6, 0.5241, APPLE, -62, -14),
        ("fib Ryzen", 474.8, 3.05, RYZEN, -70, -14),
        ("matmul Apple", 26.0, 0.0282, APPLE, 18, -2),
        ("matmul Ryzen", 26.4, 0.18, RYZEN, 18, -14),
    ]
    parts = [
        text(width / 2, 32, "Runtime-Energy Tradeoff", "title"),
        line(left, top, left, bottom),
        line(left, bottom, right, bottom),
    ]
    for t in [0, 100, 200, 300, 400, 500, 600]:
        tx = xx(t)
        parts.append(line(tx, top, tx, bottom, GRID))
        parts.append(text(tx, bottom + 20, f"{t:g}", "tick"))
    for t in [0, 0.5, 1, 1.5, 2, 2.5, 3]:
        ty = yy(t)
        parts.append(line(left, ty, right, ty, GRID))
        parts.append(text(left - 8, ty + 4, f"{t:g}", "tick", "end"))
    parts.append(text(width / 2, 495, "Execution time (ms)", "axis"))
    parts.append(text(24, top + plot_h / 2, "Energy per run (J)", "axis", rotate=-90))
    parts.append(text(right - 6, top + 15, "Lower-left is better", "note", "end"))

    for label, xval, yval, color, dx, dy in points:
        px, py = xx(xval), yy(yval)
        parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="7" fill="{color}" stroke="#111" stroke-width="1"/>')
        parts.append(text(px + dx, py + dy, label, "label", "start" if dx > 0 else "end"))
    (OUT_DIR / "runtime_energy_tradeoff.svg").write_text(svg_doc(width, height, "\n".join(parts)), encoding="utf-8")


def main():
    make_runtime()
    make_energy()
    make_tradeoff()


if __name__ == "__main__":
    main()
