#!/usr/bin/env python3
"""Gate for E013: adapt must keep the combo's heavy-window peak (median <= 1.10 x combo) and recover the small-tx
wall (median <= 1.08 x base). Prints the numbers and GATE PASS / GATE FAIL. usage: gate_e012.py <e012_small csv> <e012_heavy csv>"""
import csv, statistics, sys
def med(path, arm, col):
    v = [float(r[col]) for r in csv.DictReader(open(path)) if r["arm"] == arm and r.get(col)]
    return statistics.median(v), len(v)
small, heavy = sys.argv[1], sys.argv[2]
ap, n1 = med(heavy, "adapt", "peak_anon_MB"); cp, n2 = med(heavy, "combo", "peak_anon_MB")
aw, n3 = med(small, "adapt", "wall_s"); bw, n4 = med(small, "base", "wall_s")
ok = ap <= 1.10 * cp and aw <= 1.08 * bw and min(n1, n2, n3, n4) >= 3
print(f"heavy peak adapt {ap:.0f} vs combo {cp:.0f} MB ({ap / cp - 1:+.1%}); small wall adapt {aw:.0f} vs base {bw:.0f} s ({aw / bw - 1:+.1%}); n={min(n1, n2, n3, n4)}")
print("GATE PASS" if ok else "GATE FAIL")
