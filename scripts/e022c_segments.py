#!/usr/bin/env python3
"""E022 replication: wall (log timestamps) and CPU (cpu_watch.sh) over identical heights. Usage: e022c_segments.py <dir> <from Synced h> <to Synced h>"""
import re, sys, pathlib, datetime, statistics as st, csv
d, a, b = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Synced (\d+)/(\d+)", re.M)
o = {}
print("run,wall_s,cpu_s")
for f in sorted(d.glob("r*_t*.log")):
    if "rewind" in f.name: continue
    ev = {}
    for t, h, _ in pat.findall(f.read_text(errors="replace")):
        ev.setdefault(int(h), datetime.datetime.strptime(t, "%Y-%m-%d %H:%M:%S.%f"))
    w = (ev[b] - ev[a]).total_seconds()
    rows = [(int(r[1]), int(r[2])) for r in csv.reader(open(f.with_suffix(".cpu.csv"))) if len(r) == 3 and r[1].isdigit()]
    c = (next(x for h, x in rows if h >= b) - next(x for h, x in rows if h >= a)) / 100
    print(f"{f.stem},{w:.2f},{c:.1f}")
    o.setdefault(f.stem.split("_")[1], []).append((w, c))
for i, n in ((0, "wall_s"), (1, "cpu_s")):
    m = {k: st.median(r[i] for r in v) for k, v in o.items()}
    for k, v in sorted(o.items()):
        x = [r[i] for r in v]
        print(f"# {k} {n}: median {m[k]:.2f} min {min(x):.2f} max {max(x):.2f}")
    print(f"# t8 vs t16 {n}: {(m['t8'] / m['t16'] - 1) * 100:+.1f}%")
