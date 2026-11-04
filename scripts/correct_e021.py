#!/usr/bin/env python3
"""Correct the E021 write-up published at 94f570b. See the JOURNAL entry written below for what was wrong."""
import pathlib, re, datetime, subprocess
R = pathlib.Path.home() / "work/research"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M"); hhmm = now.split()[1]
def edit(path, old, new):
    p = R / path; s = p.read_text(); assert s.count(old) == 1, (path, old[:60], s.count(old)); p.write_text(s.replace(old, new))
def resub(path, pat, new):
    p = R / path; s = p.read_text(); s2, n = re.subn(pat, lambda m: new, s, flags=re.S); assert n == 1, (path, pat[:50], n); p.write_text(s2)
rd = "experiments/E021-idle-trim/README.md"

resub(rd, r"\*\*Change \(42 lines", "**Result: each idle trim releases 231-234 MB on the heavy window (-17 to -18% of that run's anon) and 37-43 MB on the small-tx window (-5 to -6%), while adapt moves 0-4 MB over the same idle period. Peak, wall and CPU do not move measurably. Corrected " + now + " (see end of file).**\n\n**Change (42 lines")
edit(rd, "(40 blocks of 128-input proofs)", "(40 blocks; 851 of 1,044 txs have 128 inputs, E004)")
resub(rd, r"idle vs adapt \(medians\): \*\*post-idle -19\.4%\*\*;[^\n]*\n", "idle vs adapt (medians): post-idle -19.4%, ranges overlap (adapt 1,045-1,360, idle 1,068-1,140); peak anon -5.2%, ranges overlap (adapt's run-to-run peak spread of 1,402-1,840 MB is the usual one); wall +0.9%; CPU -0.1%; I/O identical. The median gap is not the size of the effect, because it includes run-to-run variance: adapt's round 2 sits below every idle run, and its peak was low too (1,402 MB). The per-run table below measures the effect directly.\n")
resub(rd, r"The trim is visible in the sampler\..*?\| \+12 s \.\.\. \+40 s \|[^\n]*\n\nThe adapt arm in the same position sits at 1,382 MB for the whole 45 s\.", """## (c) The direct measure: anon across the trim, per run (scripts/e021_paired.py, 2 s samplers)

For idle arms, "before" and "after" are the samples either side of the logged trim. For adapt arms, which have no trim, they are the sample at the last height change and the final sample, 45 s later.

| window | run | trim, s after last height change | anon before MB | anon after MB | released MB | peak MB |
|---|---|---|---|---|---|---|
| heavy | r1 idle | 3 | 1,318 | 1,087 | **231** | 1,649 |
| heavy | r2 idle | 3 | 1,371 | 1,140 | **231** | 1,713 |
| heavy | r3 idle | 2 | 1,302 | 1,068 | **234** | 1,801 |
| heavy | r1 adapt | none | 1,349 | 1,347 | 2 | 1,841 |
| heavy | r2 adapt | none | 1,046 | 1,044 | 2 | 1,403 |
| heavy | r3 adapt | none | 1,360 | 1,360 | 0 | 1,808 |
| small | r1 idle | 4 | 770 | 733 | **37** | 833 |
| small | r2 idle | 5 | 764 | 721 | **43** | 819 |
| small | r3 idle | 5 | 758 | 717 | **41** | 823 |
| small | r1 adapt | none | 750 | 747 | 4 | 799 |
| small | r2 adapt | none | 755 | 751 | 4 | 818 |
| small | r3 adapt | none | 750 | 750 | 0 | 814 |

Round 1 idle in detail: 1,317 MB at 23:48:18, trim logged 23:48:19.5, 1,086 MB at 23:48:20, flat afterwards.""")
edit(rd, "(1,000 blocks of 1-2-input proofs)", "(1,000 blocks; 28,871 of 28,891 txs have 1-2 inputs, 12 have 16 or more, E011)")
resub(rd, r"Peak anon 798-818 vs 819-833 MB:.*?so it is read as noise, not a cost\. ", "Peak anon 798-818 vs 819-833 MB: the ranges do not overlap and the medians differ by 9 MB on ~800. No mechanism for a real rise was found: every trim fired 2-5 s after the last height change (table (c)), so during the window the patch adds only one atomic store per verification call. E020's adapt runs on this window spread 801-819 MB. Three rounds cannot exclude a cost this small, so it is reported as unexplained and probably noise. ")
resub(rd, r"## Reading\n.*?\n## Decision\n.*?\n## Guardrails", """## Reading
- **The effect is ~230 MB on the heavy window, about -17%, not the -19% of the medians.** The three releases agree within 3 MB, against adapt's 0-2 MB. This matches E012's open gap between adapt and combo (1,333 vs 1,107 MB, 226 MB), though that comparison crosses experiments.
- **What remains at idle is not attributed.** The roughly 1.1 GB left after the heavy window was not broken down here.
- **No measurable speed cost on either sync window.** Wall and CPU stay within run-to-run spread. The trim's own duration was not timed in this experiment.
- **When it fires on a live node, from reading the code (not measured).** The only caller of `batchVerifyFcmpPpProofs` is the block path (`Blockchain::handle_block_to_main_chain` via `batch_ver_fcmp_pp_consensus`). Pool txs verify through a separate single-proof call (tx_verification_utils.cpp:719) that neither records a timestamp nor trims. So a node at the tip trims at most once per block, and memory freed by pool verification is released only by that next trim. A node at the tip was not measured, in this experiment or in any other for this patch.
- **The log line needs demoting before any upstream use.** It is `MGINFO`, kept for this experiment, and would print once per block on a live node.
- **v2 is not measured with this patch.** The patch passes `git apply --check` on the e020 tree, but no v2 build with it exists. It touches no verifier code, so the result should carry over; that is an expectation.
- **Against stock, across experiments:** E013's stock post-idle on this window was 4,993 MB and its adapt -72.6% (1,368 MB). Subtracting ~230 MB gives about 1,140 MB, roughly -77%. There is no direct A/B of this build against stock.

## Decision
Adopted into the recommended series as monerod patch 0006 (0007 in v2), because the release is real, repeatable and cheap on these windows. E013's negative test, cgroup minimum and long resync were run on patches 0001-0005 and were **not** rerun with 0006. The patch changes only when `malloc_trim` is called, so they are expected to carry over, but that is an argument from the code. The 12 window hashes here are the only correctness check on this binary.

## Guardrails""")
with (R / rd).open("a") as f:
    f.write(f"""
## Correction ({now})
The first version of this file (commit 94f570b) had these errors, found by auditing it against the evidence:
- The sampler table was wrong: kB were divided by 1,000 instead of 1,024 (1,349 -> 1,113 MB should read 1,317 -> 1,086), and it said 6 s samples where the sampler runs at 2 s (every third row had been printed).
- It headlined -19% without saying the post-idle ranges overlap. Replaced by the per-run release, table (c).
- It said the ~1.0 GB left at idle was live data (heap, pool, curve-tree state), with no measurement behind it. Removed.
- It said the small-tx peak gap was noise because "the only new code runs after the window ends". One atomic store per call also runs during the window, and three rounds cannot exclude a small cost.
- It described the small-tx window as all 1-2-input proofs and the heavy window as all 128-input proofs. Both are mixes.
- It said the patch "applies equally" to v2 and gave -78% against stock without saying that neither was measured directly.
""")

# ---- FINDINGS, SUMMARY, HOW-IT-WORKS, patches README
resub("FINDINGS.md", r"\| F37 \| .*?\| done, adopted \|", "| F37 | **Idle trim (E021): one `malloc_trim(0)` from `core::on_idle` once no FCMP++ batch verification has run for 5 s releases 231-234 MB on the heavy window (-17 to -18% of that run's anon) and 37-43 MB on small-tx (-5 to -6%); adapt moves 0-4 MB over the same idle period. Peak, wall and CPU show no measurable change (small-tx wall +1.3%; small-tx peak +9 MB with non-overlapping ranges, unexplained and probably noise).** 42 lines, glibc-guarded, one trim per run 2-5 s after the last height change (6/6), 12/12 hashes. Median post-idle 1,349 -> 1,087 MB overstates it; those ranges overlap. Adopted as monerod patch 0006 of v1 (0007 of v2, not built or measured). E013's negtest, min_mem and long resync were not rerun with it; a node at the tip was not measured. | experiments/E021-idle-trim, evidence/E021 | idle ~-17% vs adapt | done, adopted |")
edit("reports/SUMMARY.md", "at idle this gap is closed by E021's single idle trim (post-idle 1,349 -> 1,087 MB on the heavy window, F37), now patch 0006 of the series.", "at idle E021's single idle trim releases ~230 MB of it on the heavy window (about -17%, F37), now patch 0006 of the series. E013's validation was not rerun with that patch, and it is unmeasured at the chain tip.")
edit("reports/SUMMARY.md", "one `malloc_trim(0)` 5 s after the last verification; glibc-guarded; -19% idle on top of E012, no speed cost |", "one `malloc_trim(0)` 5 s after the last verification; glibc-guarded; about -17% idle on top of E012 on the heavy window, no measurable speed cost on sync windows; demote its log line first |")
resub("reports/SUMMARY.md", r"- E021 \(hydrogen\): done [^\n]*\n", "- E021 (hydrogen): done (experiments/E021-idle-trim, F37). One `malloc_trim(0)` from `core::on_idle` once FCMP++ verification has been idle for 5 s releases 231-234 MB on the heavy window (about -17%) and 37-43 MB on small-tx (about -5%), with no measurable change in peak, wall or CPU; 12/12 hashes, one trim per run. Adopted as monerod patch 0006 (v1) / 0007 (v2, not built). Against stock on the heavy window, across experiments, idle is about -77%. Not rerun with it: negative test, cgroup minimum, long resync. Not measured: a node at the chain tip.\n")
edit("reports/HOW-IT-WORKS.md", "Measured: post-idle 1,349 -> 1,087 MB on the heavy window (-19%), nothing else moves; the trim fires exactly once per burst. About 40 lines, patch 0006.", "Measured: each trim releases 231-234 MB on the heavy window (about -17%) and 37-43 MB on small-tx blocks, with no measurable change in peak or speed; it fired once per run. Only the block path reaches this verifier, so at the chain tip it should fire at most once per block (from the code, not measured). About 40 lines, patch 0006.")
edit("patches/README.md", "E021 (post-idle -19% on top of E012, no speed cost; E013's validation was run without it)", "E021 (releases ~230 MB at idle on the heavy window, about -17% on top of E012, no measurable speed cost on sync windows; E013's validation was run without it; not built on v2)")

# ---- STATE, JOURNAL
p = R / "STATE.md"; s = p.read_text()
s = s.replace(re.search(r"Last updated: .*", s).group(0), f"Last updated: {now}", 1)
old = "heavy window post-idle 1,349 -> 1,087 MB (-19%), peak/wall/CPU unchanged,"
assert s.count(old) == 1
s = s.replace(old, f"each trim releases 231-234 MB on the heavy window (about -17%; the median 1,349 -> 1,087 overstates it, ranges overlap; corrected {hhmm}) and 37-43 MB on small-tx, peak/wall/CPU show no measurable change,", 1)
old = "NEXT (node): 16-input threshold sweep (E022: adapt with threshold 8 / 16 / 32 on both windows), optional perf profile of e020's +28%."
assert s.count(old) == 1
s = s.replace(old, "Not rerun with 0006: negtest, min_mem, long resync; not measured at the tip. NEXT (node): E022 16-input threshold sweep. The two existing windows cannot discriminate (128-input and 1-2-input txs trip every threshold or none), so E022a scans the input-count distribution first (scripts/run_e022scan.sh, RUNNING since 00:59, offline node on the synced snapshot, marker e022scan.chain ends E022SCAN_COMPLETE, output e022scan/chain_inputs.csv). If no mid-size stretch exists, the sweep is not worth running on this chain: record that and move on. Then: optional perf profile of e020's +28%.", 1)
p.write_text(s)
with (R / "JOURNAL.md").open("a") as f:
    f.write(f"""
## 2026-11-04 {hhmm} E021 write-up corrected after an audit against the evidence
- Commit 94f570b was published with errors, all mine: kB/1000 in the sampler table (1,349 -> 1,113 should be 1,317 -> 1,086) plus a wrong sample interval; -19% headlined without the overlap of the post-idle ranges; an unmeasured attribution of the remaining idle memory; "no new code during the window"; v2 and stock comparisons not labelled as unmeasured or cross-experiment. The 00:58 entry above carries the wrong table figure.
- New: scripts/e021_paired.py measures the release across each trim. Heavy 231 / 231 / 234 MB, small 37 / 43 / 41 MB, adapt 0-4 MB. Replaces -19% with about -17% everywhere. Decision unchanged (adopted), with the validation gap stated.
- Code read: only the block path reaches batchVerifyFcmpPpProofs; pool txs use the single-proof call at tx_verification_utils.cpp:719. So at the tip the trim fires at most once per block, and its MGINFO line needs demoting before upstream use. Not measured.
""")
print("ok", now)
