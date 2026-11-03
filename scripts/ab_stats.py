#!/usr/bin/env python3
"""Summarize an ab_window.sh results.csv: per-arm median/min/max of peak anon, privdirty, RSS, wall, post-idle anon;
deltas of each arm vs the first arm (base). Usage: ab_stats.py <results.csv> [base_label]"""
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
base = sys.argv[2] if len(sys.argv) > 2 else rows[0]["arm"]
arms = {}
for r in rows:
    arms.setdefault(r["arm"], []).append(r)
cols = [("peak_anon_MB", "peak RssAnon MB"), ("peak_privdirty_MB", "peak Private_Dirty MB"), ("peak_rss_MB", "peak RSS MB"),
        ("wall_s", "wall s"), ("post_idle_anon_MB", "post-idle RssAnon MB"), ("read_MB", "read MB"), ("write_MB", "write MB")]
med = {}
print("| arm | n | " + " | ".join(c[1] + " median (min-max)" for c in cols) + " | hashes match |")
print("|---|---|" + "---|" * len(cols) + "---|")
for a, rs in arms.items():
    cells = []
    for k, _ in cols:
        v = [float(r[k]) for r in rs if r.get(k) not in (None, "")]
        if not v:
            cells.append("n/a"); continue
        m = statistics.median(v); med[(a, k)] = m
        cells.append(f"{m:,.0f} ({min(v):,.0f}-{max(v):,.0f})")
    hm = all(r["hash_match"] == "yes" for r in rs)
    print(f"| {a} | {len(rs)} | " + " | ".join(cells) + f" | {'all yes' if hm else 'NO'} |")
print()
for a in arms:
    if a == base:
        continue
    parts = []
    for k, lbl in cols:
        if (a, k) in med and (base, k) in med and med[(base, k)]:
            parts.append(f"{lbl} {100 * (med[(a, k)] / med[(base, k)] - 1):+.1f}%")
    print(f"{a} vs {base} (medians): " + "; ".join(parts))
    # overlap check on peak anon
    bv = [float(r["peak_anon_MB"]) for r in arms[base]]; av = [float(r["peak_anon_MB"]) for r in arms[a]]
    print(f"  peak anon ranges overlap: {'yes' if max(av) >= min(bv) and max(bv) >= min(av) else 'no'} (base {min(bv):,.0f}-{max(bv):,.0f}, {a} {min(av):,.0f}-{max(av):,.0f})")
