# E004: cap FCMP++ verification concurrency at the physical core count

**Hypothesis (from E003):** peak memory during sync = ~1 GB base + ~170-270 MB per concurrently verifying FCMP++ batch. FCMP++ verification is compute-bound and gains nothing from SMT siblings. So limiting verification to the physical core count cuts the peak with no throughput loss on SMT machines.

## E004a: config-level A/B (--max-concurrency 12 vs default 24), 2026-11-02 21:10-21:43
- Box: hydrogen, Ryzen 9 3900X 12C/24T, quiet (no selfishmining lanes, no other runs).
- scripts/ab_window.sh: 3 rounds alternating (r1: c24, c12; r2: c12, c24; r3: c24, c12). Each run is rewound to 3,105,401 and syncs from exclusive peer .22 until log height 3,105,441 (40 blocks, including the ~10 MB stress blocks). Baseline beta31 binary, `--block-sync-size 5` in both arms. Sampler at 2 s. The end hash is checked from an idle --offline restart against .22.

| round | arm | peak RssAnon MB | peak Private_Dirty MB | peak RSS MB | wall s | written MB | end hash = .22 |
|---|---|---|---|---|---|---|---|
| 1 | c24 | 5,660 | 5,660 | 6,434 | 221 | 465 | yes |
| 1 | c12 | 3,393 | 3,393 | 4,492 | 207 | 466 | yes |
| 2 | c12 | 3,611 | 3,638 | 4,481 | 197 | 468 | yes |
| 2 | c24 | 5,465 | 5,544 | 6,223 | 221 | 466 | yes |
| 3 | c24 | 5,614 | 5,614 | 6,447 | 220 | 465 | yes |
| 3 | c12 | 3,392 | 3,459 | 4,476 | 197 | 466 | yes |

| metric (median, range) | c24 (default) | c12 | change |
|---|---|---|---|
| peak RssAnon | 5,614 (5,465-5,660) | 3,393 (3,392-3,611) | **-39.6%** |
| peak RSS | 6,434 (6,223-6,447) | 4,481 (4,476-4,492) | -30.4% |
| wall time | 221 s (220-221) | 197 s (197-207) | **-10.9% (faster)** |
| disk written | 465-466 MB | 466-468 MB | no shift to disk |

**Conclusion:** confirmed. All guardrails pass (same end hash, verification unchanged, faster, no extra I/O). As a flag, though, `--max-concurrency` also limits every other threadpool user, so the real change should be targeted (E004c).

## E004c: targeted code change (prepared 21:50; build and A/B chained after E005)
- Tree ~/work/monero-fcmp-e004c, branch e004c-fcmp-verify-physical-cores (commit 2e80c0685, based on beta.3.1). Diff: evidence/E004c.diff.
- `rct::batchVerifyFcmpPpProofs` (rctSigs.cpp) makes `min(pool size, boost::thread::physical_concurrency())` batches; if the core count is unknown it uses the pool size. Nothing else changes: the threadpool keeps its size for other work.
- Expected on hydrogen: the same as E004a c12 for memory (12 batches), and the same or better wall time (other pool users keep 24 threads).
- On machines without SMT: no change. On SMT machines: up to ~50% fewer concurrent verifier working sets.

**Results E004c (2026-11-02 22:10-22:35, 3 alternating rounds, default settings, every end hash = .22):**

| round | arm | peak RssAnon MB | peak RSS MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,640 | 6,685 | 222 |
| 1 | e004c | 5,237 | 6,240 | 201 |
| 2 | e004c | 5,527 | 6,507 | 201 |
| 2 | base | 5,363 | 6,352 | 220 |
| 3 | base | 5,600 | 6,676 | 220 |
| 3 | e004c | 5,630 | 6,504 | 203 |

Median peak RssAnon: base 5,600 vs e004c 5,527 MB (-1.3%, ranges overlap). Wall: 220 vs 201 s (**-9%**, no overlap).

**Interpretation:** the cap took effect (the wall time matches E004a's c12), but RSS did not drop. Most likely cause: **glibc arena retention.** The pool still has 24 threads and over time all of them run FCMP++ batch tasks. `limitMaxMemArenas()` sets M_ARENA_MAX = pool size = 24, and freed memory stays inside each thread's arena. So RSS ≈ 24 × the per-thread high-water mark even though only 12 batches are live at once. In E004a, `--max-concurrency 12` lowered both the pool and M_ARENA_MAX, which is why it showed the full -39.6%. This is exactly where live heap and RSS diverge; RSS is the metric we use.

## E004d: E004c + arenas capped at physical cores (prepared 22:38; build + A/B chained after E006)
- Tree ~/work/monero-fcmp-e004d, branch e004d-arenas-physical-cores (19e2a7db8 on top of 2e80c0685). `limitMaxMemArenas()` uses min(pool size, physical cores). Diff vs beta31: evidence/E004d.diff.
- Prediction: peak RssAnon ≈ E004a c12 (~3.4 GB), wall ≈ 200 s.

**Results E004d (2026-11-02 22:45-23:05, 3 alternating rounds, default settings, every end hash = .22):**

| round | arm | peak RssAnon MB | peak RSS MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,108 | 6,021 | 222 |
| 1 | e004d | 5,146 | 6,085 | 197 |
| 2 | e004d | 4,991 | 5,831 | 197 |
| 2 | base | 5,601 | 6,634 | 220 |
| 3 | base | 5,622 | 6,611 | 220 |
| 3 | e004d | 5,360 | 6,311 | 199 |

Median peak RssAnon: base 5,601 vs e004d 5,146 MB (-8%; ranges partly overlap: base min 5,108 < e004d max 5,360). Wall 220 → 197 s (-10%).

**Prediction failed.** Capping the arena count does not stop retention. With 24 pool threads sharing 12 arenas, two concurrently verifying threads can land in the same arena, whose high-water mark then becomes two working sets; total retention stays near 24 working sets. The variable that matters is how many distinct threads ever run FCMP++ work (E004a's --max-concurrency 12 made that 12), not the arena count. Evidence for retention as the mechanism: E000's idle node held 3.9 GB anon after sync, and a restart (E002a) brought it to 0.32 GB.

## E004e: E004c + malloc_trim(0) after each FCMP++ batch verification (prepared 23:15)
- Tree ~/work/monero-fcmp-e004e, branch e004e-malloc-trim (3ffb58c77 on top of 2e80c0685). `malloc_trim(0)` (glibc only) right after all batches of a batchVerifyFcmpPpProofs call finish (once per block). Diff vs beta31: evidence/E004e.diff.
- Harness v2 (scripts/ab_window.sh) adds post_idle_anon_MB: at END the peer is temporarily banned on OUR node (local RPC; the ban is lifted before stopping), and RssAnon is sampled after 45 s idle.
- Predictions: (1) peak ≈ 12 concurrent working sets + base ≈ 3.4-3.8 GB; (2) post-idle anon ≈ restart level (~0.3-0.6 GB) instead of multi-GB; (3) wall time within a few % of e004c (the trim costs madvise + re-faulting).
- The A/B runs once the box is quiet (after the E007 agent's cargo builds/tests).

**Results E004e (2026-11-03 00:25-00:53, 3 alternating rounds, governor pinned to performance, every end hash = .22):**

| round | arm | peak RssAnon MB | post-idle RssAnon MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,154 | 4,794 | 219 |
| 1 | e004e | 2,941 | 574 | 207 |
| 2 | e004e | 2,943 | 539 | 207 |
| 2 | base | 5,309 | 4,441 | 218 |
| 3 | base | 5,347 | 5,201 | 222 |
| 3 | e004e | 2,965 | 630 | 205 |

Medians and ranges (scripts/ab_stats.py, evidence/E004e/stats.md):
- **peak RssAnon 5,309 → 2,943 MB (-44.6%)**. The ranges don't overlap: base 5,154-5,347, e004e 2,941-2,965.
- **peak Private_Dirty 5,321 → 2,944 MB (-44.7%)**
- peak RSS 6,209 → 3,858 MB (-37.9%; RSS includes mmap'd LMDB pages, which don't count)
- **post-idle RssAnon 4,794 → 574 MB (-88.0%)**
- wall 219 → 207 s (-5.5%)
- bytes written to disk unchanged at 466 MB, and bytes read 0 for both arms, since the DB was in page cache. No cost was shifted to disk or swap; swap is off on the box.

**All 3 predictions held:**
- (1) Peak lands at about 12 concurrent working sets plus base. It came in 2.94 GB, even below E004a's 3.39 GB, because E004a still retained memory.
- (2) Post-idle memory drops to near the level after a restart: 0.57 GB vs 0.32 GB after a restart (E002a).
- (3) Wall time is within a few percent of E004c. The trim costs about 4 points of E004c's 9% speedup. Net, it is still 5.5% faster than base.

**Interpretation:** most of the baseline's peak "memory" on this workload is freed heap that glibc never returned to the OS. With 24 verifier threads, each thread's arena keeps its high-water mark of a ~200 MB transient FCMP++ working set. E004d showed that capping the arena count doesn't help. Trimming once per block after the batch verify does. The batch cap (E004c) bounds how many working sets are live at once; the trim stops freed ones from accumulating.

**Caveats:**
- glibc-specific: `malloc_trim` is guarded by `__GLIBC__`. musl and macOS/Windows allocators behave differently and are untested.
- The window is a worst case: 851 of 1,044 txs have 128 inputs (evidence/window_inputs_3105401-3105440.txt).
- One 40-block window. Still to come: min cgroup memory (min_mem.sh), the combined build, and a longer resync.

Verdict: **CONFIRMED.** This is the first single build to pass the owner's 40% target on peak anon/private-dirty, with all guardrails held (hash, wall time, disk). Superseded only if E007 or the combined build does better.

