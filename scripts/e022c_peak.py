#!/usr/bin/env python3
"""E022 replication: peak RssAnon from the 2 s sampler, restricted to rows whose height is inside the window, so runs that overshot the
window end by different amounts compare on the same blocks. The sampler's height comes from RPC and can lag the node by one poll.
Usage: e022c_peak.py <dir> <start_h> <end_h>"""
import csv, sys, pathlib, statistics as st
d, lo, hi = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
by = {}
print("run,samples_in_window,last_height_in_window,peak_anon_MB_in_window,peak_anon_MB_whole_run,last_height_whole_run")
for f in sorted(d.glob("r*_t*.mem.csv")):
    rows = list(csv.DictReader(f.open()))
    good = [r for r in rows if (r.get("RssAnon_kB") or "").isdigit() and (r.get("height") or "").isdigit()]
    win = [r for r in good if lo <= int(r["height"]) <= hi]
    run = f.name.split(".")[0]
    peak = max(int(r["RssAnon_kB"]) for r in win) / 1024 if win else float("nan")
    whole = max(int(r["RssAnon_kB"]) for r in good) / 1024
    print(f'{run},{len(win)},{max(int(r["height"]) for r in win) if win else ""},{peak:.0f},{whole:.0f},{max(int(r["height"]) for r in good)}')
    by.setdefault(run.split("_")[1], []).append(peak)
for arm, v in sorted(by.items()):
    print(f"# {arm}: median {st.median(v):.0f} min {min(v):.0f} max {max(v):.0f}")
if "t8" in by and "t16" in by:
    print(f'# t8 vs t16: {100*(st.median(by["t8"])/st.median(by["t16"])-1):+.1f}%')
