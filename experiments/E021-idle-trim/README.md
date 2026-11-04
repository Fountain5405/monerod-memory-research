# E021: one trim when FCMP++ verification goes idle (refinement of adapt)

**Why:** adapt (E012, the recommended build) trims after every heavy batch-verify call and at most once every 10 s on light calls, but only *inside* a verify call. After the last call of a sync burst nothing trims, so whatever the last light calls freed stays resident in the glibc arenas until the next verification. E012 measured it: post-idle 1,333 MB for adapt against 1,107 MB for the non-adaptive combo, and E012's README listed "one trim when sync goes idle, or a timer" as the refinement. This is that refinement, kept as small as possible: no new thread, no timer object, a check from the daemon's existing idle loop.

**Change (42 lines, 4 files, `scripts/e021_patch_idle_trim.py`; patch `patches/v1-E007-full-streaming/monerod/0006-E021-*.patch`):**
- `rctSigs.cpp`: two atomics record when the last FCMP++ batch verification ran and when the last trim ran (steady clock, ms). The E012 trim block now stores the verification time first, then does its own trim as before, so a trim done inside the verify path counts as "after the last verification". New `rct::idleTrimFcmpPp(idle_ms)`: if a verification has happened since the last trim and it was at least `idle_ms` ago, `malloc_trim(0)` once and log it at INFO. glibc only (`#if defined(__GLIBC__)`), otherwise a no-op returning false.
- `cryptonote_core.cpp/.h`: `core::on_idle` calls `rct::idleTrimFcmpPp(5000)` through a 2 s `once_a_time_seconds`, next to the existing periodic tasks. Cost when nothing happened: two relaxed atomic loads every 2 s.

So the trim fires exactly once per sync burst, 5-7 s after the last verification, and never repeats a trim the verify path already did.

**Setup:** hydrogen, 2026-11-03 23:33 to 2026-11-04 00:58, `scripts/run_e021.sh` (chain log evidence/E021/e021.chain). Tree `~/work/monero-fcmp-idle` = adapt 4a51d434d + the patch, built with the adapt recipe (Release, ARCH=native, ninja -j10, build log evidence/E021/e021.build.log). Arms: **adapt** (sha d6f93d06, the E013 binary) vs **idle** (sha 6e6f14c6). Same harness as E012/E013/E020: `ab_window.sh`, `--block-sync-size 5`, 3 alternating rounds, DB restored from the snapshot before every run, the single exclusive peer 192.168.1.22, governor `performance`, no shadow lanes. Post-idle anon is sampled 45 s after the peer is banned at the end of the window, so the 5 s idle trim has had time to fire.

## (a) Heavy window 3,105,401 -> 3,105,441 (40 blocks of 128-input proofs), medians of 3 (min-max)

| arm | n | peak RssAnon MB | peak Private_Dirty MB | peak RSS MB | wall s | **post-idle RssAnon MB** | read MB | write MB | CPU s | hashes |
|---|---|---|---|---|---|---|---|---|---|---|
| adapt | 3 | 1,807 (1,402-1,840) | 1,830 (1,400-1,861) | 3,034 (2,737-3,067) | 110 (110-112) | 1,349 (1,045-1,360) | 9 (9-32) | 466 | 911 (910-916) | 3/3 |
| idle | 3 | 1,713 (1,649-1,800) | 1,713 (1,649-1,800) | 3,026 (2,985-3,056) | 111 (108-112) | **1,087 (1,068-1,140)** | 9 (9-27) | 466 | 910 (906-910) | 3/3 |

idle vs adapt (medians): **post-idle -19.4%**; peak anon -5.2% (ranges overlap, adapt's run-to-run peak spread of 1,402-1,840 MB is the usual one); wall +0.9%; CPU -0.1%; I/O identical.

The trim is visible in the sampler. Round 1, idle arm (evidence/E021/heavy/r1_idle.mem.csv), 6 s samples after the window:

| sample | height | RssAnon MB |
|---|---|---|
| last block applied | 3,105,446 | 1,349 |
| +6 s (trim logged 23:48:19, "idle for 5 s") | 3,105,446 | 1,113 |
| +12 s ... +40 s | 3,105,446 | 1,113 |

The adapt arm in the same position sits at 1,382 MB for the whole 45 s. Exactly one "returned freed verifier memory" line per idle run (3/3 heavy, 3/3 small-tx; evidence/E021/trim_lines.txt).

## (b) Small-tx window 3,106,400 -> 3,107,400 (1,000 blocks of 1-2-input proofs), medians of 3 (min-max)

| arm | n | peak RssAnon MB median (min-max) | peak Private_Dirty MB median (min-max) | peak RSS MB median (min-max) | wall s median (min-max) | post-idle RssAnon MB median (min-max) | read MB median (min-max) | write MB median (min-max) | CPU s median (min-max) | hashes match |
|---|---|---|---|---|---|---|---|---|---|---|
| adapt | 3 | 813 (798-818) | 996 (973-1,017) | 3,924 (3,914-3,938) | 155 (154-159) | 750 (749-755) | 52 (51-52) | 1,117 (1,117-1,117) | 1,435 (1,433-1,436) | all yes |
| idle | 3 | 822 (819-833) | 1,017 (1,006-1,030) | 3,942 (3,934-3,961) | 157 (156-157) | 721 (717-733) | 51 (51-52) | 1,117 (1,117-1,123) | 1,434 (1,433-1,443) | all yes |

```
idle vs adapt (medians): peak RssAnon MB +1.1%; peak Private_Dirty MB +2.1%; peak RSS MB +0.5%; wall s +1.3%; post-idle RssAnon MB -3.9%; read MB -1.9%; write MB +0.0%; CPU s -0.1%
  peak anon ranges overlap: no (base 798-818, idle 819-833)
```

idle vs adapt (medians): wall +1.3% (155 -> 157 s; E020's adapt runs on this window were 156-159 s), CPU -0.1%, peak anon +1.1%, post-idle -3.9% (750 -> 721 MB). Peak anon 798-818 vs 819-833 MB: the ranges do not overlap, but the gap is 9 MB on ~800, inside this window's usual run-to-run spread (E020: adapt 801-819, e020 800-812), and the only new code runs after the window ends, so it is read as noise, not a cost. On 1-2-input blocks adapt's own 10 s trim keeps the arenas small during the window, so there is little left for the idle trim to release; the point of this window is the guard: the idle trim must not cost sync speed, and it does not.

## Reading
- **It does what E012 predicted: adapt's idle figure drops to the combo's.** 1,087 MB post-idle vs combo's 1,107 MB in E012 (same window, same harness), with adapt's peak and speed untouched. The remaining ~1.0 GB at idle is the node's live data (LMDB-adjacent heap, the tx pool and curve-tree state) plus fragmented arena pages that `malloc_trim` cannot release; E013's long resync idled at 1,379 MB for the same reason.
- **No speed cost, by construction and by measurement.** The trim runs only after 5 s without verification, so it cannot sit in the sync path; wall and CPU on both windows are within the run-to-run spread (E020's adapt small-tx walls were 156-159 s).
- **It is independent of the verifier change.** Like 0001/0002/0005 it is glibc-guarded, lives in rctSigs.cpp plus a two-line hook in core::on_idle, and applies equally to the v1 and v2 series (the patch is included in both monerod directories).
- Against stock: stock idles at 4.6-5.0 GB after the same windows (E008/E013), so idle memory with the full v1 series is now -78% on the heavy window (1,087 vs 4,993 MB) instead of -73%.

## Decision
Adopted into the recommended build as monerod patch 0006 (E021). The E013 validation (negative test, cgroup minimum, long resync) was run on patches 0001-0005; 0006 does not touch verification or the DB, only when `malloc_trim` is called, and its A/B here matched all 12 window hashes. SUMMARY and HOW-IT-WORKS 2.3 record the new idle number.

## Guardrails
- One change per experiment: the idle tree differs from adapt by the 42-line patch only; sha256 of both binaries in the chain log.
- 12/12 runs reached the window end with matching tip hashes; both arms same snapshot, same peer, alternated per round; governor pinned and restored; no shadow lanes (checked at start).
- Evidence: evidence/E021/ (chain and build logs, heavy/ and small/ results.csv, summary.txt, check.log, per-run mem.csv samplers, trim_lines.txt).
