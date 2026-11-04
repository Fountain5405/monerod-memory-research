#!/usr/bin/env python3
import pathlib, re, datetime, shutil, subprocess
R = pathlib.Path.home() / "work/research"; A = pathlib.Path.home() / "work/research-artifacts"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M"); hhmm = now.split()[1]
e = R / "evidence/E022"; (e / "window").mkdir(parents=True, exist_ok=True)
shutil.copy(A / "e022.chain", e); shutil.copy(A / "e022/results.csv", e / "window"); shutil.copy(A / "e022/summary.txt", e / "window")
for f in (A / "e022").glob("*.mem.csv"): shutil.copy(f, e / "window")
(e / "segments.csv").write_text(subprocess.run(["python3", str(R / "scripts/e022_segments.py")], capture_output=True, text=True, check=True).stdout)
d = R / "experiments/E022-threshold-sweep"; d.mkdir(exist_ok=True)
s = pathlib.Path("/tmp/E022-README.md").read_text()
s = s.replace("GUARD_STATUS", "running").replace("GUARD_SECTION", "## (d) Guard\nt8 vs t16 on the standard small-tx window, 3 rounds, scripts/run_e022b.sh. Running. Pass, fixed before the run: all hashes match, and t8's median wall, CPU and peak anon are each within 3% of t16's or better.")
(d / "README.md").write_text(s)
p = R / "STATE.md"; t = p.read_text()
t = t.replace(re.search(r"Last updated: .*", t).group(0), f"Last updated: {now}", 1)
old = "**E022 RUNNING (hydrogen, started 01:20,"
assert t.count(old) == 1
t = t.replace(old, f"**E022 window measured {hhmm} (experiments/E022-threshold-sweep, evidence/E022): t8 vs t16 wall +2.8% on identical heights, CPU -21%, peak anon -7%; t32 no benefit; the pre-set rule selects 8. E022 GUARD RUNNING (scripts/run_e022b.sh, marker e022b.chain ends CHAIN_E022B_COMPLETE, ETA ~03:25): t8 vs t16 on the small-tx window x3. Pass (all hashes; wall, CPU, peak each within 3% or better) -> one-line monerod patch, F38, SUMMARY caveat. Fail -> 16 stays. Short-window lesson: results.csv wall and CPU stop on a 2 s poll with differing overshoot, use scripts/e022_segments.py style log timing.** Was: E022 RUNNING (hydrogen, started 01:20,", 1)
p.write_text(t)
with (R / "JOURNAL.md").open("a") as f:
    f.write(f"""
## 2026-11-04 {hhmm} E022 window done: the pre-set rule selects threshold 8; guard running
- 15/15 hashes. t8 vs t16: peak anon 471 vs 506 MB, CPU 157 vs 199 s, both with non-overlapping ranges. t32: no benefit, on just 5 differing blocks.
- Caught before write-up: the harness wall and CPU columns are not like for like here, because arms overshot the end by 0-15 blocks (t8 most). Harness wall read +8.3%; on identical heights from log timestamps it is +2.8% (whole window) and +4.0% (8-input blocks). My first segment script also mislabelled a 2-input batch as the 16-input one (Synced N means up to index N-1); fixed before anything was recorded.
- Cap and trim are switched together by heavy_call, so which gives the CPU saving is not separated. Below 8 is untestable on this chain. Guard launched: small-tx window x3, criterion in run_e022b.sh.
""")
print("ok", now)
