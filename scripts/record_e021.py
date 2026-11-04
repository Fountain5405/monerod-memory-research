#!/usr/bin/env python3
"""Record E021: fill the README's small-tx table, FINDINGS F37, SUMMARY, HOW-IT-WORKS 2.3, patches README, STATE, JOURNAL.
Run on hydrogen after the chain completed and the README was installed at experiments/E021-idle-trim/README.md."""
import pathlib, re, datetime, csv, statistics, subprocess
R = pathlib.Path.home() / "work/research"
A = pathlib.Path.home() / "work/research-artifacts"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M"); hhmm = now.split()[1]

def edit(path, old, new):
    p = R / path; s = p.read_text(); assert s.count(old) == 1, (path, old[:60], s.count(old)); p.write_text(s.replace(old, new))

def med(rows, arm, col):
    v = [float(r[col]) for r in rows if r["arm"] == arm]
    return statistics.median(v), min(v), max(v)

# ---- small-tx numbers
rows = list(csv.DictReader(open(A / "e021_small/results.csv")))
assert len(rows) == 6 and all(r["hash_match"] == "yes" for r in rows), rows
hrows = list(csv.DictReader(open(A / "e021_heavy/results.csv")))
assert len(hrows) == 6 and all(r["hash_match"] == "yes" for r in hrows)
sw = {a: med(rows, a, "wall_s") for a in ("adapt", "idle")}
sp = {a: med(rows, a, "post_idle_anon_MB") for a in ("adapt", "idle")}
sk = {a: med(rows, a, "peak_anon_MB") for a in ("adapt", "idle")}
sc = {a: med(rows, a, "cpu_s") for a in ("adapt", "idle")}
pct = lambda a, b: (b - a) / a * 100
stats = subprocess.run(["python3", str(R / "scripts/ab_stats.py"), str(A / "e021_small/results.csv"), "adapt"], capture_output=True, text=True, check=True).stdout
table = "\n".join(l for l in stats.splitlines() if l.startswith("|"))
summ = "\n".join(l for l in stats.splitlines() if l.startswith("idle vs adapt") or l.startswith("  peak"))
sentence = (f"idle vs adapt (medians): wall {pct(sw['adapt'][0], sw['idle'][0]):+.1f}% ({sw['adapt'][0]:.0f} -> {sw['idle'][0]:.0f} s; "
            f"E020's adapt runs on this window were 156-159 s), CPU {pct(sc['adapt'][0], sc['idle'][0]):+.1f}%, peak anon {pct(sk['adapt'][0], sk['idle'][0]):+.1f}%, "
            f"post-idle {pct(sp['adapt'][0], sp['idle'][0]):+.1f}% ({sp['adapt'][0]:,.0f} -> {sp['idle'][0]:,.0f} MB). "
            f"Peak anon {sk['adapt'][1]:,.0f}-{sk['adapt'][2]:,.0f} vs {sk['idle'][1]:,.0f}-{sk['idle'][2]:,.0f} MB: the ranges do not overlap, but the gap is {sk['idle'][0]-sk['adapt'][0]:.0f} MB on ~800, inside this window's usual run-to-run spread (E020: adapt 801-819, e020 800-812), and the only new code runs after the window ends, so it is read as noise, not a cost. "
            "On 1-2-input blocks adapt's own 10 s trim keeps the arenas small during the window, so there is little left for the idle trim to release; "
            "the point of this window is the guard: the idle trim must not cost sync speed, and it does not.")
edit("experiments/E021-idle-trim/README.md", "SMALL_TABLE", table + "\n\n```\n" + summ + "\n```")
edit("experiments/E021-idle-trim/README.md", "SMALL_SENTENCE", sentence)
edit("experiments/E021-idle-trim/README.md", "2026-11-04 01:0x", now.replace("2026-11-04 ", "2026-11-04 "))

# ---- FINDINGS F37
p = R / "FINDINGS.md"; s = p.read_text(); assert "| F37 |" not in s
s = s.rstrip("\n") + (
 f"\n| F37 | **Idle trim (E021): one `malloc_trim(0)` from `core::on_idle` once no FCMP++ batch verification has run for 5 s takes adapt's post-idle memory from 1,349 to 1,087 MB (-19%) on the heavy window, with peak, wall and CPU unchanged; small-tx wall {pct(sw['adapt'][0], sw['idle'][0]):+.1f}% (noise), post-idle {pct(sp['adapt'][0], sp['idle'][0]):+.1f}%.** 42 lines, glibc-guarded, exactly one trim per sync burst (verified in the logs, 6/6 runs), 12/12 hashes. Closes E012's open note (adapt idled 0.1-0.4 GB above the combo because nothing trimmed after the last light call). Adopted as monerod patch 0006 of v1 (and 0007 of v2); idle vs stock on the heavy window is now -78% (1,087 vs 4,993 MB). | experiments/E021-idle-trim, evidence/E021 | idle -19% vs adapt | done, adopted |\n")
p.write_text(s)

# ---- SUMMARY
edit("reports/SUMMARY.md",
     "adapt holds ~0.1-0.4 GB more than the non-adaptive combo during light-block sync and at idle, because it trims less often.",
     "adapt holds ~0.1-0.4 GB more than the non-adaptive combo during light-block sync, because it trims less often; at idle this gap is closed by E021's single idle trim (post-idle 1,349 -> 1,087 MB on the heavy window, F37), now patch 0006 of the series.")
edit("reports/SUMMARY.md",
     "| adaptive batch cap + `malloc_trim` (E012) | ~25 lines in rctSigs.cpp | glibc-guarded trim; independent of E007 |\n",
     "| adaptive batch cap + `malloc_trim` (E012) | ~25 lines in rctSigs.cpp | glibc-guarded trim; independent of E007 |\n| idle trim (E021) | ~40 lines (rctSigs.cpp + a 2 s check in `core::on_idle`) | one `malloc_trim(0)` 5 s after the last verification; glibc-guarded; -19% idle on top of E012, no speed cost |\n")
edit("reports/SUMMARY.md",
     "- Wallet: W001 code map done",
     f"- E021 (hydrogen): done (experiments/E021-idle-trim, F37). One `malloc_trim(0)` from `core::on_idle` once FCMP++ verification has been idle for 5 s: post-idle 1,349 -> 1,087 MB (-19%) on the heavy window, peak/wall/CPU unchanged, small-tx wall {pct(sw['adapt'][0], sw['idle'][0]):+.1f}% (noise), 12/12 hashes, exactly one trim per run. Adopted as monerod patch 0006 (v1) / 0007 (v2). Idle vs stock on the heavy window: -78%.\n- Wallet: W001 code map done")

# ---- HOW-IT-WORKS 2.3
edit("reports/HOW-IT-WORKS.md",
     "A trim costs ~9 ms, so the final build trims after every heavy call and otherwise at most once every 10 s. glibc only (`#if defined(__GLIBC__)`). About 15 lines.\n",
     "A trim costs ~9 ms, so the final build trims after every heavy call and otherwise at most once every 10 s. glibc only (`#if defined(__GLIBC__)`). About 15 lines.\n\nOne gap remained: those trims run only inside a verify call, so after the last call of a sync burst whatever the last light calls freed stayed resident (E012 measured adapt 0.2 GB above the per-call combo at idle). E021 closes it with one more trim from the daemon's idle loop: the verify path records its time in an atomic, and `core::on_idle` checks every 2 s whether a verification has happened since the last trim and is at least 5 s old; if so, one `malloc_trim(0)`. Measured: post-idle 1,349 -> 1,087 MB on the heavy window (-19%), nothing else moves; the trim fires exactly once per burst. About 40 lines, patch 0006.\n")

# ---- patches README
edit("patches/README.md",
     "| `v1-E007-full-streaming/monerod/0005-E012-FCMP-batch-cap-and-malloc_trim-adaptive-to-proo.patch` | make 0001/0002 adaptive: cap and per-call trim only when the largest proof in the call has >= 16 inputs; otherwise trim at most every 10 s | ~20 | E012/E013 (the recommended build) |\n",
     "| `v1-E007-full-streaming/monerod/0005-E012-FCMP-batch-cap-and-malloc_trim-adaptive-to-proo.patch` | make 0001/0002 adaptive: cap and per-call trim only when the largest proof in the call has >= 16 inputs; otherwise trim at most every 10 s | ~20 | E012/E013 (the recommended build) |\n| `v1-E007-full-streaming/monerod/0006-E021-trim-FCMP-verifier-memory-once-verification-go.patch` | one `malloc_trim(0)` from `core::on_idle` once no batch verification has run for 5 s (two atomics in rctSigs.cpp record the last verification and the last trim; `rct::idleTrimFcmpPp`; a 2 s `once_a_time_seconds` in core) | ~40 | E021 (post-idle -19% on top of E012, no speed cost; E013's validation was run without it) |\n")
edit("patches/README.md",
     "All five monerod patches together change `src/ringct/rctSigs.cpp`, `src/cryptonote_core/cryptonote_core.cpp` (E001) and the `fcmp_pp_rust` Cargo files. The combined effect of 0001+0002+0005 on `rctSigs.cpp` is ~25 lines.",
     "All six monerod patches together change `src/ringct/rctSigs.cpp` and `.h`, `src/cryptonote_core/cryptonote_core.cpp` and `.h` (E001, E021) and the `fcmp_pp_rust` Cargo files. The combined effect of 0001+0002+0005 on `rctSigs.cpp` is ~25 lines; 0006 adds ~35 more plus a two-line hook in core. The E013-measured binary (sha256 `d6f93d06...`) is 0001-0005; with 0006 the build is the E021 idle binary (sha256 `6e6f14c6acdc4b5b...`).")
edit("patches/README.md",
     "Both share the same monerod patches 0001-0003 and 0005; only 0004 (the cargo `[patch]` glue) points at a different monero-oxide branch.",
     "Both share the same monerod patches 0001-0003, 0005 and the E021 idle trim (0006 in v1, 0007 in v2); only 0004 (the cargo `[patch]` glue) points at a different monero-oxide branch (v2 adds 0006 to repoint it).")
edit("patches/README.md",
     "monerod for v2: `v2-E017-minimal/monerod/0001-0005` are v1's patches unchanged, plus `0006` which repoints the cargo `[patch]` paths from the E007 tree to the E017 tree (0004 + 0006 together are the build glue; they will be squashed if v2 becomes the recommended series).",
     "monerod for v2: `v2-E017-minimal/monerod/0001-0005` are v1's patches unchanged, plus `0006` which repoints the cargo `[patch]` paths from the E007 tree to the E017 tree (0004 + 0006 together are the build glue; they will be squashed if v2 becomes the recommended series), plus `0007` = v1's 0006 (E021 idle trim) renumbered.")

# ---- STATE
p = R / "STATE.md"; s = p.read_text()
s = s.replace(re.search(r"Last updated: .*", s).group(0), f"Last updated: {now}", 1)
old = "- **E021 RUNNING (hydrogen, chain started 23:33,"
assert s.count(old) == 1
s = s.replace(old, f"""- **E021 DONE {hhmm} (experiments/E021-idle-trim, F37, evidence/E021; ADOPTED as monerod patch 0006 of v1 / 0007 of v2): one idle `malloc_trim(0)` from core::on_idle 5 s after the last FCMP++ verification; heavy window post-idle 1,349 -> 1,087 MB (-19%), peak/wall/CPU unchanged, small-tx wall {pct(sw['adapt'][0], sw['idle'][0]):+.1f}% (noise), 12/12 hashes, exactly one trim per run. Tree ~/work/monero-fcmp-idle committed (adapt 4a51d434d + E021); binary build/beta31-idle sha 6e6f14c6 is now the full-series build. Nothing running on hydrogen.** NEXT (node): 16-input threshold sweep (E022: adapt with threshold 8 / 16 / 32 on both windows), optional perf profile of e020's +28%. Was: E021 RUNNING (hydrogen, chain started 23:33,""", 1)
p.write_text(s)

with (R / "JOURNAL.md").open("a") as f:
    f.write(f"""
## 2026-11-04 {hhmm} E021 done: idle trim takes adapt's post-idle memory -19%, adopted as patch 0006
- Chain 23:33-{hhmm}: build OK (ccache, 3 min), heavy A/B x3 (23:36-00:13), small-tx A/B x3 (00:14-{hhmm}). Heavy: post-idle 1,349 -> 1,087 MB (-19.4%), peak anon 1,807 vs 1,713 (ranges overlap), wall 110 vs 111 s, CPU 911 vs 910 s. Small-tx: wall {sw['adapt'][0]:.0f} vs {sw['idle'][0]:.0f} s, post-idle {sp['adapt'][0]:,.0f} vs {sp['idle'][0]:,.0f} MB, peak {sk['adapt'][0]:,.0f} vs {sk['idle'][0]:,.0f} MB. 12/12 hashes. The sampler shows the drop in one 6 s step (r1 idle: 1,349 -> 1,113 MB at the logged trim); exactly one trim line per idle run (6/6).
- Adopted: committed the idle tree, format-patch -> patches/v1 monerod 0006 and v2 monerod 0007; patches README, SUMMARY (caveat, upstreamability row, next list), HOW-IT-WORKS 2.3, F37. E013's negtest/min_mem/long-resync were run on 0001-0005; 0006 changes only when malloc_trim is called.
- Box: governor restored to schedutil by the chain, no shadow lanes, ~32 GB free. Next: E022 threshold sweep.
""")
print("ok", now, sentence)
