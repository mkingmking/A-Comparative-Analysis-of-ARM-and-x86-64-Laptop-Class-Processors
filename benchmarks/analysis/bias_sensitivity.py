#!/usr/bin/env python3
"""Break-even bias-sensitivity analysis for a two-platform energy ratio.

Given observed energies E_A (Apple), E_R (Ryzen), model a systematic
correction as E_true = E_observed * (1 + delta): delta > 0 means the
observed value underestimated the true energy, delta < 0 means it
overestimated it.

R_observed = E_R / E_A  (Ryzen/Apple ratio, matches Table tab:energy)
R_corrected = R_observed * (1 + delta_R) / (1 + delta_A)

Three break-even cases, each solving R_corrected = 1 (the point at which
the claimed energy advantage disappears):

  1. Only Apple underestimated (delta_R = 0):  delta_A = R_observed - 1
  2. Only Ryzen overestimated  (delta_A = 0):  delta_R = 1/R_observed - 1
  3. Opposite, equal-magnitude bias (delta_A = +b, delta_R = -b):
         b = (R_observed - 1) / (R_observed + 1)

Usage:
    python3 bias_sensitivity.py <benchmark_label> <E_apple_J> <E_ryzen_J>
"""
import sys


def analyze(label, e_apple, e_ryzen):
    r = e_ryzen / e_apple
    delta_a_only = r - 1
    delta_r_only = 1 / r - 1
    b_opposite = (r - 1) / (r + 1)

    print(f"=== {label}: E_Apple={e_apple:.4f} J, E_Ryzen={e_ryzen:.4f} J ===")
    print(f"  R (Ryzen/Apple)                         = {r:.4f}")
    print(f"  Break-even if only Apple underestimated  : delta_A = +{delta_a_only*100:.1f}%")
    print(f"  Break-even if only Ryzen overestimated   : delta_R = {delta_r_only*100:.1f}%")
    print(f"  Break-even if opposite, equal bias b      : b = {b_opposite*100:.1f}%")
    print()
    return r, delta_a_only, delta_r_only, b_opposite


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <benchmark_label> <E_apple_J> <E_ryzen_J>")
        sys.exit(1)
    label, e_apple, e_ryzen = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    analyze(label, e_apple, e_ryzen)


if __name__ == "__main__":
    main()
