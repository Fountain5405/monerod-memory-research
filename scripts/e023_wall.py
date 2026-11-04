#!/usr/bin/env python3
"""Wall over identical heights from log timestamps, for any two-arm ab_window directory. Runs overshoot a window end by differing amounts and
results.csv wall stops on a 2 s poll, so this is the like-for-like figure. Synced N means blocks up to index N-1 are done.
Usage: e023_wall.py <dir> <from Synced h> <to Synced h> <reference arm> <other arm>"""
import re, sys, pathlib, datetime, statistics as st
d, a, b, ref, oth = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Synced (\d+)/(\d+)", re.M)
o = {}
print("run,wall_s")
for f in sorted(d.glob("r*_*.log")):
    if "rewind" in f.name: continue
    ev = {}
    for t, h, _ in pat.findall(f.read_text(errors="replace")):
        ev.setdefault(int(h), datetime.datetime.strptime(t, "%Y-%m-%d %H:%M:%S.%f"))
    w = (ev[b] - ev[a]).total_seconds()
    print(f"{f.stem},{w:.1f}")
    o.setdefault(f.stem.split("_", 1)[1], []).append(w)
for k, v in sorted(o.items()):
    print(f"# {k}: median {st.median(v):.1f} min {min(v):.1f} max {max(v):.1f}")
print(f"# {oth} vs {ref}: {100 * (st.median(o[oth]) / st.median(o[ref]) - 1):+.1f}%")
print(f"# ranges overlap: {'yes' if min(o[oth]) <= max(o[ref]) and min(o[ref]) <= max(o[oth]) else 'no'}")
