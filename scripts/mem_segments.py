#!/usr/bin/env python3
"""mem_segments.py: RssAnon per height segment from an ab_window/sample.sh mem.csv (leak/growth check over long runs).
usage: mem_segments.py <boundaries comma-separated> <label=mem.csv> ...
Prints, per segment [b_i, b_{i+1}): max RssAnon MB, median RssAnon MB, and the last sample's RssAnon MB."""
import sys, csv, statistics
bounds = [int(x) for x in sys.argv[1].split(",")]
for arg in sys.argv[2:]:
    lab, path = arg.split("=", 1)
    rows = []
    for r in csv.DictReader(open(path)):
        try:
            rows.append((int(r["height"]), int(r["RssAnon_kB"]) / 1024))
        except (ValueError, KeyError, TypeError):
            pass
    print(f"== {lab} ({len(rows)} samples)")
    print("  segment                    max MB   median MB   last MB")
    lo = bounds[0]
    for hi in bounds[1:]:
        seg = [a for h, a in rows if lo <= h < hi]
        if seg:
            print(f"  {lo}..{hi}".ljust(28) + f"{max(seg):8.0f} {statistics.median(seg):11.0f} {seg[-1]:9.0f}")
        lo = hi
    pk = max(rows, key=lambda x: x[1])
    print(f"  overall peak {pk[1]:.0f} MB at height {pk[0]}")
