#!/usr/bin/env python3
"""segment_rates.py: per-segment sync time from monerod 'Synced H/T' log lines.
usage: segment_rates.py <boundaries comma-separated> <label=logfile> [<label=logfile> ...]
For each log, finds the first Synced line with height >= each boundary and prints the seconds spent
in each segment [b_i, b_{i+1}) plus blocks/s. Time origin = first Synced line (first batch already applied,
so segment 1 is slightly understated by one batch for every arm alike)."""
import sys, re, datetime
pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s.*Synced (\d+)/(\d+)")
def parse(path):
    pts = []
    for line in open(path, errors="replace"):
        m = pat.match(line)
        if m:
            t = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp()
            pts.append((t, int(m.group(2))))
    return pts
bounds = [int(x) for x in sys.argv[1].split(",")]
arms = [a.split("=", 1) for a in sys.argv[2:]]
res = {}
for lab, path in arms:
    pts = parse(path)
    t0 = pts[0][0]
    cross = []
    for b in bounds:
        c = next(((t, h) for t, h in pts if h >= b), None)
        cross.append(c)
    res[lab] = (t0, cross, pts)
hdr = "segment".ljust(24) + "".join(l.rjust(14) for l, _ in arms)
print(hdr)
prev = {l: (res[l][0], None) for l, _ in arms}
lo = "first"
for i, b in enumerate(bounds):
    row = f"{lo}..{b}".ljust(24)
    for l, _ in arms:
        c = res[l][1][i]
        pt, _ = prev[l]
        if c is None or pt is None:
            row += "n/a".rjust(14); prev[l] = (None, None); continue
        row += f"{c[0]-pt:9.0f} s".rjust(14)
        prev[l] = (c[0], c[1])
    print(row)
    lo = str(b)
row = "total (first..last b)".ljust(24)
for l, _ in arms:
    c = res[l][1][-1]
    row += (f"{c[0]-res[l][0]:9.0f} s" if c else "n/a").rjust(14)
print(row)
