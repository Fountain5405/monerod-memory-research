#!/usr/bin/env python3
"""E021: per-run view from the samplers. For each run: anon at the last sample before the end-of-run plateau's trim point and
after. Idle arm: the drop across the logged trim. Adapt arm: anon change over the same span after the last height change."""
import csv, pathlib, re, datetime, calendar
A = pathlib.Path.home() / "work/research-artifacts"
print("window,run,last_height_change,trim_utc,trim_after_last_height_s,anon_before_MB,anon_after_MB,drop_MB,final_MB,peak_MB")
for w in ("heavy", "small"):
    for f in sorted((A / f"e021_{w}").glob("r*_*.mem.csv")):
        run = f.name.replace(".mem.csv", "")
        rows = [r for r in csv.DictReader(open(f)) if (r.get("RssAnon_kB") or "").strip().isdigit() and (r.get("height") or "").strip().isdigit()]
        t = [int(r["ts"]) for r in rows]; h = [int(r["height"]) for r in rows]; a = [int(r["RssAnon_kB"]) / 1024 for r in rows]
        last_chg = max(i for i in range(1, len(h)) if h[i] != h[i - 1])
        log = (A / f"e021_{w}" / f"{run}.log").read_text(errors="replace")
        m = re.search(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+\s.*returned freed verifier memory", log, re.M)
        if m:
            ts = calendar.timegm(datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").timetuple())
            before = max(i for i in range(len(t)) if t[i] <= ts); after = min(i for i in range(len(t)) if t[i] > ts)
            print(f"{w},{run},{t[last_chg]},{m.group(1)[11:]},{ts - t[last_chg]},{a[before]:.0f},{a[after]:.0f},{a[before] - a[after]:.0f},{a[-1]:.0f},{max(a):.0f}")
        else:
            print(f"{w},{run},{t[last_chg]},,,{a[last_chg]:.0f},{a[-1]:.0f},{a[last_chg] - a[-1]:.0f},{a[-1]:.0f},{max(a):.0f}")
