#!/usr/bin/env python3
import pathlib, re, datetime, shutil
R = pathlib.Path.home() / "work/research"; A = pathlib.Path.home() / "work/research-artifacts"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M"); hhmm = now.split()[1]
e = R / "evidence/E022/guard_small"; e.mkdir(parents=True, exist_ok=True)
shutil.copy(A / "e022b.chain", e); shutil.copy(A / "e022_small/results.csv", e); shutil.copy(A / "e022_small/summary.txt", e)
for f in (A / "e022_small").glob("*.mem.csv"): shutil.copy(f, e)
rd = R / "experiments/E022-threshold-sweep/README.md"; s = rd.read_text()
old = "adoption depends on the guard in (d), which is running."
assert s.count(old) == 1
s = s.replace(old, "the small-tx guard in (d) turned out to be an A/A, so adoption depends on the replication in (e), which is running.")
s, n = re.subn(r"## \(d\) Guard\n.*?\n\n## Guardrails", lambda m: f"""## (d) Small-tx guard: it passed, but it has no power
t8 vs t16 on the standard small-tx window, 3 rounds, {hhmm[:0]}2026-11-04 02:40-03:24, scripts/run_e022b.sh, evidence/E022/guard_small. Medians (min-max):

| arm | wall from logs, blocks 3,106,405-3,107,399, s | CPU s | peak RssAnon MB | hashes |
|---|---|---|---|---|
| t16 | 152.8 (152.4-153.6) | 1,440 (1,433-1,441) | 803 (802-817) | 3/3 |
| t8 | 152.5 (152.3-152.9) | 1,448 (1,443-1,449) | 811 (805-838) | 3/3 |

The pre-set criterion is met literally, but **this window contains no block with a largest tx of 8-15 inputs (E022a scan: 0 of 1,000), so the two builds behave identically on it.** I chose the window without checking that. It is an A/A run and says nothing about the cost of threshold 8, so it is not counted as support.

It does measure the noise floor between two builds that behave the same: peak anon +1.0% (8 MB) and CPU +0.6%, with CPU ranges that do not overlap (t8 also ran 5 blocks further in 2 of 3 runs). Non-overlapping ranges over 3 rounds are therefore weak evidence at this scale. That supports E021's reading of its 9 MB small-tx peak gap as probably noise.

## (e) Replication
t8 vs t16 on two independent stretches where the arms really differ, 5 rounds each, scripts/run_e022c.sh. Running.
- Window A: 3,105,080 -> 3,105,106. Largest tx 8 inputs on 3,105,089-3,105,101, those txs nearly all 8-input.
- Window B: 3,106,260 -> 3,106,286. Largest tx 8 inputs on 3,106,268-3,106,280, about a third of the txs 8-input.

Wall from log timestamps and CPU from scripts/cpu_watch.sh, both over identical heights. **Criterion, fixed before the run. On both windows: t8's CPU at least 5% lower with non-overlapping ranges, wall no more than +5%, peak anon not worse by more than 5%, all hashes match. Then threshold 8 becomes a one-line patch. Otherwise 16 stays.**

## Guardrails""", s, flags=re.S)
assert n == 1
rd.write_text(s)
er = R / "experiments/E021-idle-trim/README.md"; t = er.read_text()
old = "Three rounds cannot exclude a cost this small, so it is reported as unexplained and probably noise. "
assert t.count(old) == 1
er.write_text(t.replace(old, old + "E022's A/A run on this same window later showed an 8 MB gap between two builds that behave identically. "))
p = R / "STATE.md"; t = p.read_text()
t = t.replace(re.search(r"Last updated: .*", t).group(0), f"Last updated: {now}", 1)
old = "E022 GUARD RUNNING (scripts/run_e022b.sh, marker e022b.chain ends CHAIN_E022B_COMPLETE, ETA ~03:25): t8 vs t16 on the small-tx window x3. Pass (all hashes; wall, CPU, peak each within 3% or better) -> one-line monerod patch, F38, SUMMARY caveat. Fail -> 16 stays."
assert t.count(old) == 1
t = t.replace(old, f"Small-tx guard done {hhmm}: passed literally, but that window has 0 blocks with a largest tx of 8-15 inputs, so it was an A/A with no power; not counted as support. E022 REPLICATION RUNNING (scripts/run_e022c.sh, started {hhmm}, marker e022c.chain ends CHAIN_E022C_COMPLETE, ETA ~05:30): t8 vs t16 on windows 3,105,080-3,105,106 and 3,106,260-3,106,286, 5 rounds each, cpu_watch.sh gives CPU over identical heights. Analyse with scripts/e022c_segments.py <dir> <from> <to> (A: 3105085 3105105, B: 3106265 3106285). Criterion in the script: must replicate on BOTH windows or 16 stays. Pass -> one-line monerod patch, F38, SUMMARY caveat.", 1)
p.write_text(t)
with (R / "JOURNAL.md").open("a") as f:
    f.write(f"""
## 2026-11-04 {hhmm} E022 guard was an A/A; replication launched on real 8-input stretches
- Guard passed its criterion (wall -0.2% from logs, CPU +0.6%, peak +1.0%, 6/6 hashes), but the window has no block with a largest tx of 8-15 inputs, so the arms behave identically. My mistake: I picked the window as the standard guard without checking it against the scan. Not counted as support for threshold 8; useful only as a noise floor.
- Replication launched: 13 sensitive blocks on each of two independent stretches, 5 rounds each. New scripts/cpu_watch.sh closes the CPU overshoot gap. Criterion fixed in run_e022c.sh: both windows or 16 stays.
""")
print("ok", now)
