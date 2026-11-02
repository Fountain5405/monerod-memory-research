# Findings (living summary)

Status: FIRST CONFIRMED WIN (E004a): -39.6% peak anon memory during FCMP++ sync, 11% faster. Targeted code version (E004c) and a constraint-storage change (E005) are being A/B tested.

| # | Finding / candidate | Evidence | Est. saving | Status |
|---|---|---|---|---|
| F1 | The FCMP++ branch already caps glibc arenas (`rct::limitMaxMemArenas()`, called from cryptonote_core.cpp:444; M_ARENA_MAX = max(2, nthreads)). Upstream master does not. | code read, JOURNAL 2026-11-02 | already in the primary baseline | noted |
| F2 | Stagenet (master build): transient heap spike 217 MB @105k -> ~1.45 GB peak @139-146k -> 994 MB @183k; sync slowed ~10x in that stretch | E000 trace | TBD (peak is the target) | to attribute (heaptrack) |
| F3 | RandomX keeps 2 light-mode caches (main + secondary seed), 256 MB each | rx-slow-hash.c:258-275, 430, 508, 535 | up to 256 MB if the second is avoidable | to measure |
| F4 | **FCMP++ proof verification holds ~4.3 GB of the 4.99 GB live peak** during sync (generalized_bulletproofs circuit construction: Vec growth 3.45 GB, BTreeMap constraint maps 377 MB, LinComb ops ~310 MB, verify ~120 MB). A synced restart with no tx verification needs 0.32 GB. | E002b heaptrack (evidence/E002b_heaptrack_peaks.txt) | up to ~4 GB (~80% of peak) if the circuit is shared or concurrency bounded | caller attribution + concurrency sweep (E003) |
| F5 | Sync wedge: a 100-block batch after an empty stretch exceeds the 100 MB levin limit; deterministic repro; fix prototyped (cap by block weight limit) | E001, reports/ | n/a (bug) | fix under test |
| F6 | pop_blocks keep_txs=true default + tx_memory_pool::prune is super-linear on heavy blocks (85,841 txs re-pooled) | JOURNAL 20:20 | n/a | noted |
| F7 | **Peak scales with concurrent FCMP++ verifier threads:** 1/4/12/24 threads give 1.23/2.03/3.30/5.40 GB peak over the same 40-block window. ~1.0 GB base + ~170-270 MB per verifier thread. 12 threads were faster than 24 (199 vs 220 s). | E003 | -39% peak on this box by using physical cores only (to be A/B-confirmed in E004a); more if the per-thread working set shrinks (E004b) | A/B running |
| F8 | **CONFIRMED (E004a, 3 alternating rounds):** limiting verification to physical cores (12 vs 24 on a 3900X) gives median peak RssAnon 5,614 → 3,393 MB (**-39.6%**), RSS -30.4%, wall time 221 → 197 s (**-10.9%**), same end hash, same disk writes | experiments/E004-verify-concurrency, evidence/E004a/ | -39.6% peak on SMT machines | targeted code change E004c queued |
| F9 | E005 (shrink_to_fit of stored LinComb term vectors): **no effect** (median 5,350 vs 5,380 MB, same wall). The working set is the count of constraints/terms (two LinCombs per mul gate, plus the divisor WCG constraints), not slack. | experiments/E005-lincomb-shrink, evidence/E005/ | 0 | rejected |
