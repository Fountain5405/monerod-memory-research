# E021: one trim when FCMP++ verification goes idle (refinement of adapt)

**Why:** adapt (E012, the recommended build) trims after every heavy batch-verify call and at most once every 10 s on light calls, but only *inside* a verify call. After the last call of a sync burst nothing trims, so whatever the last light calls freed stays resident in the glibc arenas until the next verification. E012 measured it: post-idle 1,333 MB for adapt against 1,107 MB for the non-adaptive combo, and E012's README listed "one trim when sync goes idle, or a timer" as the refinement. This is that refinement, kept as small as possible: no new thread, no timer object, a check from the daemon's existing idle loop.

**Result: each idle trim releases 231-234 MB on the heavy window (-17 to -18% of that run's anon) and 37-43 MB on the small-tx window (-5 to -6%), while adapt moves 0-4 MB over the same idle period. Peak, wall and CPU do not move measurably. Corrected 2026-11-04 01:04 (see end of file).**

**Change (42 lines, 4 files, `scripts/e021_patch_idle_trim.py`; patch `patches/v1-E007-full-streaming/monerod/0006-E021-*.patch`):**
- `rctSigs.cpp`: two atomics record when the last FCMP++ batch verification ran and when the last trim ran (steady clock, ms). The E012 trim block now stores the verification time first, then does its own trim as before, so a trim done inside the verify path counts as "after the last verification". New `rct::idleTrimFcmpPp(idle_ms)`: if a verification has happened since the last trim and it was at least `idle_ms` ago, `malloc_trim(0)` once and log it at INFO. glibc only (`#if defined(__GLIBC__)`), otherwise a no-op returning false.
- `cryptonote_core.cpp/.h`: `core::on_idle` calls `rct::idleTrimFcmpPp(5000)` through a 2 s `once_a_time_seconds`, next to the existing periodic tasks. Cost when nothing happened: two relaxed atomic loads every 2 s.

So the trim fires exactly once per sync burst, 5-7 s after the last verification, and never repeats a trim the verify path already did.

**Setup:** hydrogen, 2026-11-03 23:33 to 2026-11-04 00:58, `scripts/run_e021.sh` (chain log evidence/E021/e021.chain). Tree `~/work/monero-fcmp-idle` = adapt 4a51d434d + the patch, built with the adapt recipe (Release, ARCH=native, ninja -j10, build log evidence/E021/e021.build.log). Arms: **adapt** (sha d6f93d06, the E013 binary) vs **idle** (sha 6e6f14c6). Same harness as E012/E013/E020: `ab_window.sh`, `--block-sync-size 5`, 3 alternating rounds, DB restored from the snapshot before every run, the single exclusive peer 192.168.1.22, governor `performance`, no shadow lanes. Post-idle anon is sampled 45 s after the peer is banned at the end of the window, so the 5 s idle trim has had time to fire.

## (a) Heavy window 3,105,401 -> 3,105,441 (40 blocks; 851 of 1,044 txs have 128 inputs, E004), medians of 3 (min-max)

| arm | n | peak RssAnon MB | peak Private_Dirty MB | peak RSS MB | wall s | **post-idle RssAnon MB** | read MB | write MB | CPU s | hashes |
|---|---|---|---|---|---|---|---|---|---|---|
| adapt | 3 | 1,807 (1,402-1,840) | 1,830 (1,400-1,861) | 3,034 (2,737-3,067) | 110 (110-112) | 1,349 (1,045-1,360) | 9 (9-32) | 466 | 911 (910-916) | 3/3 |
| idle | 3 | 1,713 (1,649-1,800) | 1,713 (1,649-1,800) | 3,026 (2,985-3,056) | 111 (108-112) | **1,087 (1,068-1,140)** | 9 (9-27) | 466 | 910 (906-910) | 3/3 |

idle vs adapt (medians): post-idle -19.4%, ranges overlap (adapt 1,045-1,360, idle 1,068-1,140); peak anon -5.2%, ranges overlap (adapt's run-to-run peak spread of 1,402-1,840 MB is the usual one); wall +0.9%; CPU -0.1%; I/O identical. The median gap is not the size of the effect, because it includes run-to-run variance: adapt's round 2 sits below every idle run, and its peak was low too (1,402 MB). The per-run table below measures the effect directly.

## (c) The direct measure: anon across the trim, per run (scripts/e021_paired.py, 2 s samplers)

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

Round 1 idle in detail: 1,317 MB at 23:48:18, trim logged 23:48:19.5, 1,086 MB at 23:48:20, flat afterwards. Exactly one "returned freed verifier memory" line per idle run (3/3 heavy, 3/3 small-tx; evidence/E021/trim_lines.txt).

## (b) Small-tx window 3,106,400 -> 3,107,400 (1,000 blocks; 28,871 of 28,891 txs have 1-2 inputs, 12 have 16 or more, E011), medians of 3 (min-max)

| arm | n | peak RssAnon MB median (min-max) | peak Private_Dirty MB median (min-max) | peak RSS MB median (min-max) | wall s median (min-max) | post-idle RssAnon MB median (min-max) | read MB median (min-max) | write MB median (min-max) | CPU s median (min-max) | hashes match |
|---|---|---|---|---|---|---|---|---|---|---|
| adapt | 3 | 813 (798-818) | 996 (973-1,017) | 3,924 (3,914-3,938) | 155 (154-159) | 750 (749-755) | 52 (51-52) | 1,117 (1,117-1,117) | 1,435 (1,433-1,436) | all yes |
| idle | 3 | 822 (819-833) | 1,017 (1,006-1,030) | 3,942 (3,934-3,961) | 157 (156-157) | 721 (717-733) | 51 (51-52) | 1,117 (1,117-1,123) | 1,434 (1,433-1,443) | all yes |

```
idle vs adapt (medians): peak RssAnon MB +1.1%; peak Private_Dirty MB +2.1%; peak RSS MB +0.5%; wall s +1.3%; post-idle RssAnon MB -3.9%; read MB -1.9%; write MB +0.0%; CPU s -0.1%
  peak anon ranges overlap: no (base 798-818, idle 819-833)
```

idle vs adapt (medians): wall +1.3% (155 -> 157 s; E020's adapt runs on this window were 156-159 s), CPU -0.1%, peak anon +1.1%, post-idle -3.9% (750 -> 721 MB). Peak anon 798-818 vs 819-833 MB: the ranges do not overlap and the medians differ by 9 MB on ~800. No mechanism for a real rise was found: every trim fired 2-5 s after the last height change (table (c)), so during the window the patch adds only one atomic store per verification call. E020's adapt runs on this window spread 801-819 MB. Three rounds cannot exclude a cost this small, so it is reported as unexplained and probably noise. On 1-2-input blocks adapt's own 10 s trim keeps the arenas small during the window, so there is little left for the idle trim to release; the point of this window is the guard: the idle trim must not cost sync speed, and it does not.

## Reading
- **The effect is ~230 MB on the heavy window, about -17%, not the -19% of the medians.** The three releases agree within 3 MB, against adapt's 0-2 MB. This matches E012's open gap between adapt and combo (1,333 vs 1,107 MB, 226 MB), though that comparison crosses experiments.
- **What remains at idle is not attributed.** The roughly 1.1 GB left after the heavy window was not broken down here.
- **No measurable speed cost on either sync window.** Wall and CPU stay within run-to-run spread. The trim's own duration was not timed in this experiment.
- **When it fires on a live node, from reading the code (not measured).** The only caller of `batchVerifyFcmpPpProofs` is the block path (`Blockchain::handle_block_to_main_chain` via `batch_ver_fcmp_pp_consensus`). Pool txs verify through a separate single-proof call (tx_verification_utils.cpp:719) that neither records a timestamp nor trims. So a node at the tip trims at most once per block, and memory freed by pool verification is released only by that next trim. A node at the tip was not measured, in this experiment or in any other for this patch.
- **The log line needs demoting before any upstream use.** It is `MGINFO`, kept for this experiment, and would print once per block on a live node.
- **v2 is not measured with this patch.** The patch passes `git apply --check` on the e020 tree, but no v2 build with it exists. It touches no verifier code, so the result should carry over; that is an expectation.
- **Against stock, across experiments:** E013's stock post-idle on this window was 4,993 MB and its adapt -72.6% (1,368 MB). Subtracting ~230 MB gives about 1,140 MB, roughly -77%. There is no direct A/B of this build against stock.

## Decision
Adopted into the recommended series as monerod patch 0006 (0007 in v2), because the release is real, repeatable and cheap on these windows. E013's negative test, cgroup minimum and long resync were run on patches 0001-0005 and were **not** rerun with 0006. The patch changes only when `malloc_trim` is called, so they are expected to carry over, but that is an argument from the code. The 12 window hashes here are the only correctness check on this binary.

## Guardrails
- One change per experiment: the idle tree differs from adapt by the 42-line patch only; sha256 of both binaries in the chain log.
- 12/12 runs reached the window end with matching tip hashes; both arms same snapshot, same peer, alternated per round; governor pinned and restored; no shadow lanes (checked at start).
- Evidence: evidence/E021/ (chain and build logs, heavy/ and small/ results.csv, summary.txt, check.log, per-run mem.csv samplers, trim_lines.txt).

## Correction (2026-11-04 01:04)
The first version of this file (commit 94f570b) had these errors, found by auditing it against the evidence:
- The sampler table was wrong: kB were divided by 1,000 instead of 1,024 (1,349 -> 1,113 MB should read 1,317 -> 1,086), and it said 6 s samples where the sampler runs at 2 s (every third row had been printed).
- It headlined -19% without saying the post-idle ranges overlap. Replaced by the per-run release, table (c).
- It said the ~1.0 GB left at idle was live data (heap, pool, curve-tree state), with no measurement behind it. Removed.
- It said the small-tx peak gap was noise because "the only new code runs after the window ends". One atomic store per call also runs during the window, and three rounds cannot exclude a small cost.
- It described the small-tx window as all 1-2-input proofs and the heavy window as all 128-input proofs. Both are mixes.
- It said the patch "applies equally" to v2 and gave -78% against stock without saying that neither was measured directly.
