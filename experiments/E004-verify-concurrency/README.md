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

**Results E004c:** (pending)
