# E002: attribute the multi-GB heap in the FCMP++ (beta31) daemon

**Observation:** the beta31 node on stressnet holds ~3.9 GB anon when synced (master on stagenet: ~1.85 GB). After a restart at 3,105,401, anon went from 318 MB to 4.6 GB within ~16 s while processing 20 nearly empty blocks (E001 / JOURNAL 2026-11-02 19:10). Run 1 peaked at 5.26 GB near h ≈ 3,103,110, i.e. after HF17 (3,102,800) and before HF18 (3,103,520).

**Hypotheses:**
- H1: something is initialized on startup or first use and retained (FCMP++/curve-tree state, verifier precomputation, RandomX), independent of the sync workload.
- H2: it is sync-specific (tree growth over the HF17/HF18 window, batch state) and only shows when replaying that window.
- H3: it is allocator retention (freed but not returned to the OS); heaptrack's live-heap peak would then be far below RssAnon.

## E002a: restart the synced node under heaptrack
- DB: ~/work/chains/stressnet at height 3,123,270 (synced). A pristine copy is in ~/work/research-artifacts/snapshots/stressnet_synced_h3123270.
- Binary: beta31 (sha256 in run.txt). Same flags as E000 plus `--block-sync-size 5` (the E001 workaround), under heaptrack 1.5.0, for 600 s, then stopped via stop_daemon.
- Command: `scripts/run_heaptrack.sh E002a-restart-synced 600 ~/work/monero-fcmp/build/beta31/bin/monerod ~/work/chains/stressnet --block-sync-size 5`
- Prediction: if anon jumps to multiple GB again → H1, and heaptrack names the allocator. If not → H2, so go to E002b.

## E002b (if needed): replay the HF17/HF18 window under heaptrack
Copy the snapshot, pop back to before 3,102,800, then sync forward under heaptrack.


## Results

### E002a: synced node restarted, 600 s, no tx verification (2026-11-02 19:52)
- heaptrack peak heap **315.89 MB**; sampler peak RssAnon 316 MB (no gap). Top consumer: randomx::AlignedAllocator **281 MB (89%)**.
- Verdict: **H1-as-startup rejected.** A synced, restarted node needs ~0.32 GB. Evidence: evidence/E002a_heaptrack_peaks.txt, evidence/E002a_mem.csv.

### E002b: sync of the 30+ blocks after 3,105,401 under heaptrack, 420 s (2026-11-02 20:28)
- Start state: ~/work/chains/stressnet rewound to 3,105,401 (pop_to.sh v2, hash-checked). `--block-sync-size 5` (E001 workaround). Exclusive peer .22.
- heaptrack: 359,316,557 allocation calls (797k/s), 83.7M temporary; **peak heap 4.99 GB**; peak RSS including heaptrack 6.44 GB. Sampler peak RssAnon **5,594 MB** at height 3,105,436.
- **H3 (allocator retention) is not the main story at the peak:** the live heap (4.99 GB) is ~89% of RssAnon (5.59 GB).
- Peak consumers (heaptrack_print --print-peaks; the top frame is the allocation site):

| peak | allocation site | component |
|---|---|---|
| 3.45 GB | `alloc::raw_vec::RawVecInner::finish_grow` (fcmp_pp_rust), 147.7M calls | Vec growth inside the FCMP++ Rust crate (caller TBD; peak-weighted stacks pending) |
| 377 MB | `BTreeMap<usize, Vec<(usize, FieldElement)>>` VacantEntry::insert_entry | generalized_bulletproofs circuit / linear-combination structures (dalek_ff_group field) |
| 250 MB | `generalized_bulletproofs::lincomb::LinComb<FieldElement>::sub` | building circuit linear combinations |
| 268 MB | `randomx::AlignedAllocator::allocMemory` | RandomX light cache (fixed) |
| 147 MB | `mdb_page_malloc` | LMDB write txn dirty pages |
| 81 MB | `cryptonote::tx_blob_entry` copy | sync pipeline (tx blobs) |
| 63 MB | `LinComb<HelioseleneField>::sub` | circuit lincombs (helioselene layer) |
| 54 MB | `epee::net_utils::buffer::append` | p2p receive buffer |
| 51 MB | `ArithmeticCircuitProof<Selene>::verify` | proof verification |
| 49 MB | `std::string` construct | misc |
| 42 MB | `ArithmeticCircuitProof<Selene>::yz_challenges` | proof verification |
| 26 MB | `ScalarVector<FieldElement>::powers` | proof verification |
| 24 MB | `LinComb::term`, 50.9M calls | circuit lincombs |
| 19 MB | `monero_fcmp_plus_plus::FCMP_PARAMS` | static params (already cached once) |

- Roughly **4.3 GB of the 4.99 GB peak sits in FCMP++ proof verification** (generalized_bulletproofs circuit construction + verify). The pattern (hundreds of millions of small allocations building linear combinations, BTreeMap constraint maps) suggests that each verification rebuilds the full arithmetic-circuit statement on the heap, and that up to N verifier threads do so concurrently.
- Artifacts: ~/work/research-artifacts/E002b-window/ (400 MB trace; peaks.txt, leaks.txt, mem.csv). Evidence copy: evidence/E002b_heaptrack_peaks.txt, evidence/E002b_mem.csv.

### Next (E003)
1. Peak-weighted folded stacks (`heaptrack_print --flamegraph-cost-type peak -F`) to find the callers of the 3.45 GB finish_grow.
2. `--max-concurrency` sweep (1, 4, 12, default 24) over the same window from the wedge snapshot: does the peak scale with concurrent verifications?
3. Candidate fixes, in rough order of expected payoff:
   a. Build the circuit statement (linear combinations / constraint matrices) once per proof shape and share it read-only. Memory O(1) instead of O(concurrent verifications), and it also removes ~10^8 allocations of CPU work.
   b. Bound concurrent FCMP++ verifications (a semaphore) independently of the thread count.
   c. Exact-capacity allocation (`Vec::with_capacity`) in LinComb/ScalarVector, to drop the doubling slack.
