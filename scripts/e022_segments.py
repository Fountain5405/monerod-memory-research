#!/usr/bin/env python3
"""E022: wall over identical heights from the 'Synced N/M' log lines. results.csv stops at a 2 s poll and arms overshoot the end
height by different amounts, so its wall and CPU columns do not cover identical work. 'Synced N' means blocks up to index N-1 are
done and batches are 5 blocks, so segments are cut on batch boundaries:
  whole : Synced 3106065 -> 3106115, blocks 3106065-3106114, all sensitive blocks included
  seg8  : Synced 3106070 -> 3106105, blocks 3106070-3106104, 35 blocks whose largest tx has 8 inputs
  seg16 : Synced 3106105 -> 3106110, blocks 3106105-3106109, 1 block at 8 inputs and 4 at 16
Output csv per run, then medians per arm."""
import re, pathlib, datetime, statistics as st
A = pathlib.Path.home() / "work/research-artifacts/e022"
pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Synced (\d+)/(\d+)", re.M)
segs = {"whole": (3106065, 3106115), "seg8": (3106070, 3106105), "seg16": (3106105, 3106110)}
out = {}
print("run,blocks_logged_to," + ",".join(segs))
for f in sorted(A.glob("r*_t*.log")):
    if "rewind" in f.name: continue
    ev = {}
    for a, h, _ in pat.findall(f.read_text(errors="replace")):
        ev.setdefault(int(h), datetime.datetime.strptime(a, "%Y-%m-%d %H:%M:%S.%f"))
    row = {k: (ev[b] - ev[a]).total_seconds() for k, (a, b) in segs.items()}
    print(f"{f.stem},{max(ev)}," + ",".join(f"{row[k]:.2f}" for k in segs))
    out.setdefault(f.stem.split("_")[1], []).append(row)
base = {k: st.median(r[k] for r in out["t16"]) for k in segs}
for a in ("t16", "t8", "t32"):
    for k in segs:
        c = [r[k] for r in out[a]]
        print(f"# {a} {k}: median {st.median(c):.2f} min {min(c):.2f} max {max(c):.2f} vs t16 {(st.median(c) / base[k] - 1) * 100:+.1f}%")
