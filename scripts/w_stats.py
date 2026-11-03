#!/usr/bin/env python3
"""Per-arm medians for the wallet sweeps (W003/W004 results.csv): usage w_stats.py <results.csv> <reference arm>"""
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
ref = sys.argv[2]
cols = [("wall_s", "wall s"), ("vmhwm_MB", "VmHWM MB"), ("peak_anon_MB", "peak anon MB (1 s samples)"), ("peak_privdirty_MB", "peak Private_Dirty MB"), ("cpu_s", "CPU s"), ("threads_max", "threads")]
arms = []
for r in rows:
    if r["arm"] not in arms: arms.append(r["arm"])
def vals(arm, c): return [float(r[c]) for r in rows if r["arm"] == arm and r.get(c, "") not in ("", None)]
med = {a: {c: statistics.median(vals(a, c)) for c, _ in cols if vals(a, c)} for a in arms}
print("| arm | n | " + " | ".join(f"{n} median (min-max)" for _, n in cols) + " | blocks ok | exit 0 |")
print("|---|---|" + "---|" * (len(cols) + 2))
for a in arms:
    n = len([r for r in rows if r["arm"] == a])
    cells = []
    for c, _ in cols:
        v = vals(a, c)
        cells.append(f"{med[a][c]:,.0f} ({min(v):,.0f}-{max(v):,.0f})" if v else "")
    ok = sum(1 for r in rows if r["arm"] == a and r["blocks_received"] == "18270")
    ex = sum(1 for r in rows if r["arm"] == a and r["exit"] == "0")
    print(f"| {a} | {n} | " + " | ".join(cells) + f" | {ok}/{n} | {ex}/{n} |")
print()
for a in arms:
    if a == ref: continue
    parts = []
    for c, n in cols:
        if c in med[a] and c in med[ref] and med[ref][c]:
            parts.append(f"{n} {100 * (med[a][c] / med[ref][c] - 1):+.1f}%")
    print(f"{a} vs {ref} (medians): " + "; ".join(parts))
