# E009: minimum cgroup memory (the "real RAM needed" metric), base vs E008 combo

**Question:** what is the smallest memory budget in which each build still syncs the FCMP++ window? The budget is a cgroup v2 MemoryMax that covers heap, page cache, LMDB dirty pages and everything else charged to the process, with swap disabled. A build passes if it syncs 3,105,401 → 3,105,441 within 1.1x its own unconstrained wall time and ends on .22's block hash. This rules out "saving" memory by trading it for disk thrash or swap.

**Method:** scripts/min_mem.sh (binary search; `systemd-run --scope -p MemoryMax=… -p MemorySwapMax=0`) driven by scripts/run_minmem.sh, 2026-11-03 02:54-03:23.
- Governor pinned to performance; quiet box (no shadow lanes).
- Reference walls are the E008 A/B medians: base 220 s, combo 117 s.
- Bounds: combo lo 750 / hi 4000 / tol 125 MB; base lo 2000 / hi 8000 / tol 250 MB.
- Before each trial the DB is rewound to 3,105,401, outside the cgroup.

**Results:**

| build | limit MB | result | wall s | end h | cgroup peak MB |
|---|---|---|---|---|---|
| combo | 4000 | PASS | 106 | 3,105,441 | 1,853 |
| combo | 750 | FAIL (OOM) | 8 | 3,105,421 | 742 |
| combo | 2375 | PASS | 108 | 3,105,441 | 1,895 |
| combo | 1562 | FAIL (OOM) | 46 | 3,105,426 | 1,536 |
| combo | 1968 | PASS | 108 | 3,105,441 | 1,813 |
| combo | 1765 | FAIL (OOM) | 48 | 3,105,431 | 1,759 |
| combo | **1866** | **PASS** | 106 | 3,105,441 | 1,701 |
| base | 8000 | PASS | 219 | 3,105,441 | 5,447 |
| base | 2000 | FAIL (OOM) | 8 | 3,105,421 | 1,824 |
| base | 5000 | FAIL (OOM) | 91 | 3,105,431 | 5,000 |
| base | 6500 | PASS | 220 | 3,105,441 | 5,068 |
| base | **5750** | **PASS** | 219 | 3,105,441 | 5,631 |
| base | 5375 | FAIL (OOM) | 162 | 3,105,436 | 5,356 |
| base | 5562 | FAIL (OOM) | 164 | 3,105,436 | 5,537 |

- **Minimum passing MemoryMax: base 5,750 MB (largest fail 5,562), combo 1,866 MB (largest fail 1,765).**
- **Reduction: -67.5%.** Taking the bracket ends against us, -66.5% (1,866 vs 5,562); with them in our favor, -69.3% (1,765 vs 5,750).
- All passing trials ended on .22's hash. Wall times at the minimum were 219 s (base) and 106 s (combo), no slower than unconstrained, so no hidden cost was shifted to disk.
- **Every FAIL is a memcg OOM kill.** The kernel log (`journalctl -k`) shows `Memory cgroup out of memory: Killed process … (monerod)` for all 7 failing trials, with anon-rss at about the limit (combo-1765: anon 1,786 MB; base-5562: anon 5,666 MB). The failure mode is the heap peak, not page-cache thrash. Base at 5,375/5,562 MB first slowed down (blocks 3,105,426 → 3,105,431 took 70 s), as page cache was squeezed out by anon growth, and was then killed.
- Interpretation: the RAM a node needs for this sync is about its peak anon memory plus ~100-200 MB. The ~1 GB of LMDB/file pages seen in unconstrained RSS can be evicted without a wall-time cost. So the anon/private-dirty peak (A/B metric) and the cgroup minimum (this metric) agree: **-67% on both.**

**Harness bug found (F19):** `oom_kills` reads 0 in the CSV even for OOM-killed trials. min_mem.sh read `memory.events` after the monerod process had died, and systemd garbage-collects an empty scope immediately, so the file no longer existed. The kernel log is authoritative here. Fixed in min_mem.sh v2: `memory.events` is now polled inside the trial loop, together with `memory.peak`.

**Verdict: CONFIRMED.** The combined build needs about 1.9 GB instead of 5.75 GB to sync the FCMP++ worst-case window on this box. This is the owner's "real" metric, and it is well past the 40% target.

Evidence: evidence/E009/ (CSVs, summaries, chain log, kernel OOM lines).
