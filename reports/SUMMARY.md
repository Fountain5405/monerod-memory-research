# monerod memory research: summary (draft, updated 2026-11-03 after E013)

**Bottom line:** on the FCMP++ stressnet sync workload, three separable changes cut the memory monerod needs by about **two thirds to 70%**, and sync is about as fast or faster:
- -68% peak in a 40-block worst-case window (3 A/B rounds);
- -70% over an 18,000-block resync;
- -67.5% in the minimum cgroup memory a sync can run under.

Over the 18,000-block resync the recommended build is 4.6% faster overall: 2x faster on heavy blocks, 4.6% slower on small-tx blocks. All guardrails held: the same chain state as the reference node, invalid proofs still rejected (24/24 in E013; 236/236 identical decisions to base in the differential test E015), and no cost shifted to disk or swap.

**Recommended build ("adapt", E012/E013)** = beta.3.1 plus:
1. The streaming FCMP++ verifier (E007).
2. For FCMP++ batch calls whose largest proof has ≥ 16 inputs: a cap on the batch count at physical cores, and `malloc_trim(0)` afterwards. Otherwise no cap, and a trim at most every 10 s.
3. The E001 sync-size cap.

### Headline: 40-block heavy window 3,105,401 → 3,105,441, 3 alternating A/B rounds, medians (E013)

| metric | baseline v0.19.0.0-beta.3.1 | adapt | change |
|---|---|---|---|
| peak anonymous memory (RssAnon) | 5,600 MB (5,403-5,617) | 1,780 MB (1,762-1,816) | **-68.2%** |
| peak private dirty memory | 5,601 MB | 1,804 MB | **-67.8%** |
| memory held after the window, idle (RssAnon) | 4,993 MB | 1,368 MB | **-72.6%** |
| minimum cgroup MemoryMax that still syncs within 1.1x the wall time, swap off (E009, E013) | 5,750 MB | 1,866 MB | **-67.5%** |
| wall time | 222 s | 111 s | **-50.0%** |
| CPU time (utime + stime) | 4,258 s | 904 s | -78.8% |
| bytes written to disk | 466 MB | 466 MB | unchanged |
| end block hash = reference node (.22) | 3/3 | 3/3 | same |
| tampered FCMP++ proofs rejected (monerod-level negtest) | 24/24 | 24/24 | same |

### Long run: 18,000-block resync 3,105,401 → 3,123,400, 1 run per arm, `--block-sync-size 5` (E013)

| metric | baseline | adapt | change |
|---|---|---|---|
| peak RssAnon | 5,613 MB | 1,657 MB | **-70.5%** |
| idle after sync (RssAnon) | 4,642 MB | 1,379 MB | **-70.3%** |
| wall, whole resync | 1,345 s | 1,283 s | **-4.6%** |
| wall, 40-block heavy window | 219 s | 108 s | -51% |
| wall, 7,959 dense small-tx blocks | 1,051 s | 1,099 s | +4.6% |
| wall, 10,000 near-empty blocks | 73 s | 72 s | 0% |
| bytes written | 9,412 MB | 9,419 MB | unchanged |
| end hash = .22 | yes | yes | same |

- Memory does not grow over the run: after the window adapt stays at 1.3-1.6 GB.
- With DEFAULT sync settings (no `--block-sync-size`), adapt also synced all 18,000 blocks: peak 1,663 MB, 1,305 s. Base wedges there (E001).
- On a window of 2-input txs only (E012, 3 rounds), adapt uses 822 MB vs base's 1,167 MB (-30%), and is 4.0% slower (157 vs 151 s).

The owner's target was 40%. The minimum-cgroup number is the "real RAM a node needs" metric, because it counts heap, page cache, and everything else charged to the process.

## How real is this?
A critical re-check of the raw data and source is in reports/REVIEW-70pct.md. Short version: the sampled peak is bounded by the independent cgroup test to within 3-5%, the 2x speed-up is confirmed to come from removing an O(c·q) pass in the stock verifier, and ~40 of the 68 points are available by halving concurrency alone; the rest needs the verifier change.

**Solid:**
- It reproduces across sessions and builds:
  - E008: -67%
  - E010: -73%
  - E012/E013: -68% / -70%
- Every A/B has tight, disjoint ranges.
- Two independent metrics agree: peak anon memory, and the minimum cgroup limit (which includes page cache, and whose failures are OOM kills, not slowdowns).
- The guardrails held in every run. The mechanisms (below) are understood and confirmed by heaptrack and perf, not just observed.

**Limits:**
- **Worst-case workload.** 82% of the window's txs have 128 inputs. On 2-input blocks the saving is ~30%. The worst case does set what a node must provision, since anyone can fill blocks with max-input txs.
- **One machine with 24 threads.** The stock node's peak scales with thread count (E003: 1.2 GB at 1 thread, 5.4 GB at 24), so part of the win is the 24-thread baseline. **E014 (running) measures base vs adapt at 4, 2 and 1 threads.**
- **About two thirds of the win is unaudited cryptographic code** (E007, ~1,000 lines in monero-oxide). It was reviewed and tested by me, not by cryptographers. Without it, the ~15-line cap + trim changes give about -45%, and the zero-code `--max-concurrency 12` gives -40%.
- `malloc_trim` is glibc-only. FCMP++ itself is still a beta (stressnet), not mainnet.

## Setup
- **Machine:** hydrogen, a Ryzen 9 3900X (12 cores / 24 threads) with 16 GB of RAM.
- **Baseline:** seraphis-migration/monero v0.19.0.0-beta.3.1 (d80596ad1). This is the FCMP++ beta that stressnet runs.
- **Workload:** stressnet (testnet nettype), synced from the owner's node at 192.168.1.22.
  - Heavy A/B window: 3,105,401 → 3,105,441, 40 blocks, 1,044 txs, 109,408 inputs (851 txs have 128 inputs).
  - Small-tx window: 3,106,400 → 3,107,400, 28,891 txs, mean 2.01 inputs.
- **Method:**
  - Each run restores or rewinds the DB and verifies the starting hash.
  - Runs alternate ABAB/BABA. Governor pinned to performance. Memory is sampled from /proc every 2 s.
  - Guardrails are listed in README.md.
- **Notes and evidence:** every experiment (including the failures) has notes under `experiments/`, data under `evidence/`, and an entry in JOURNAL.md.

## What uses the memory, and the three fixes
1. **FCMP++ proof verification is ~87% of the peak** (E002b, heaptrack).
   - Each verification builds the whole arithmetic circuit (millions of `LinComb` constraints) and stores it before folding.
   - One FCMP++ proof covers all inputs of a tx, so a 128-input proof stores ~250 MB.
   - Verification runs on up to 24 threads at once, and the peak scales almost linearly with the thread count (E003).
2. **glibc keeps freed memory per thread arena.** Without a trim, RSS grows to (threads that ever verified) × (per-thread high-water mark) and stays there. That is why an idle stock node holds ~4.8 GB after sync.
   - Capping the arena count does not help (E004d: -8%), because two threads sharing an arena both peak inside it.
   - **Fix 1 + 2 (E004c + E004e):** cap FCMP++ batches at physical cores, and `malloc_trim(0)` after each batch verify. Together: -44.6% peak, -88% idle (~15 lines in `rct::batchVerifyFcmpPpProofs`).
3. **The circuit does not need to be stored at all.** The verifier only uses the constraints as sums weighted by powers of the challenge z, and the circuit is a deterministic function of challenges that come *before* z.
   - **Fix 3 (E007): streaming verifier.**
     - Build the circuit once on the real transcript, discarding the constraints, to reach z.
     - Process both proofs' transcripts.
     - Rebuild the circuit on a transcript clone, folding each constraint into an accumulator as it is produced.
     - Before applying, check that both builds agree (mul and constraint counts, transcript state).
     - The proof format is unchanged; the old stored path is kept for tests.
   - About 1,000 lines in monero-oxide (generalized-bulletproofs, circuit-abstraction, fcmps), plus 1,182 lines of new tests.
   - Result: -59% peak on its own.
   - **It is also 2x faster on heavy blocks.** The old verify folds each vector commitment's weights in a separate pass over all constraints. That is O(commitments × constraints), roughly quadratic in the input count, and was **~52% of all sync CPU** (E006). It is gone from the new build's profile.
4. **Fixes 1 and 2 had to become adaptive (E010 → E011 → E012).**
   - The first combined build (E008) was 2x faster on heavy blocks, but 15% slower on small-tx blocks, which made the 18,000-block resync 3.6% slower.
   - E011 attributed that cost, one change per arm, on 2-input txs:
     - cap +7.3% (SMT siblings do help small proofs);
     - per-block trim +6.0% (~9 ms per block);
     - streaming verifier +2.7%.
   - adapt (E012) applies the cap and the per-call trim only when the largest proof has ≥ 16 inputs, and otherwise trims at most every 10 s.
   - Result: small-tx blocks are +4% instead of +15%, the heavy window is unchanged, and the long resync is 4.6% faster than base.

### Build history
| build | what | heavy-window peak | heavy wall | small-tx wall | status |
|---|---|---|---|---|---|
| base | v0.19.0.0-beta.3.1 | 5.3-5.6 GB | 220 s | 150 s | reference |
| E004e | cap + trim | 2.9 GB (-45%) | -5% | +13% | superseded |
| E007 | streaming verifier | 2.3 GB (-59%) | -50% | +3% | component |
| E008 combo | E004c + E004e + E007 + E001 | 1.75-1.86 GB (-67%) | -47% | +15% | superseded |
| **E012 adapt** | combo with an adaptive cap and trim | **1.64-1.78 GB (-68%)** | **-50%** | **+4%** | **recommended** |

## Guardrails: how we know nothing was weakened
- Every run ends on the same block hash as the reference node (E004-E013).
- **Monerod-level negative test (scripts/negtest.sh)**, run on base, combo and adapt:
  - Txs that are not yet in our chain (128-, 8- and 2-input) were submitted to our own offline node.
  - First came 8 copies of each with one bit flipped in the FCMP++ proof, then the original.
  - Every build rejected 24/24 tampered copies at "Failed to verify input FCMP++ signatures" and accepted all 3 originals.
- **Differential negative test (E015): PASS.**
  - Up to 10 real txs per height, at two heights, with mixed input counts.
  - 32 bit flips spread over each proof, plus proof swaps between txs (a valid proof for another statement), then the originals.
  - The base binary is the oracle; adapt gave the identical (status, flags) on all 236 cases (224 flips, 5 swaps, 7 originals). 225 of the 229 rejections were at the FCMP++ check, 4 at parsing, identically in both builds.
- Crate-level tests (E007):
  - All existing monero-oxide tests pass, including byte-malleation.
  - New tests: streaming vs stored verification on valid and tampered proofs; accumulator vs stored fold (bit-identical batch-verifier state); a Discard-mode circuit cannot yield a statement; an un-applied verification fails closed.
- Disk writes are unchanged, and swap is off. Under the minimum cgroup limit the builds keep their unconstrained wall time; every failure below it was an OOM kill (kernel log), not slow thrashing.

## Things that did not work (kept for the record)
| attempt | result | why |
|---|---|---|
| E005: `shrink_to_fit` on stored constraint vectors | no effect (5,350 vs 5,380 MB) | the working set is the number of constraints, not Vec slack |
| E004c alone (batch cap) | RSS -1.3% (wall -9%) | arena retention: freed working sets stay in every thread's arena |
| E004d: cap glibc arenas at physical cores | -8% | two concurrently verifying threads can share an arena, and both peak in it |
| E008 combo as the final build | +15% on small-tx blocks | non-adaptive cap and per-block trim (E011); fixed by adapt |

## Zero-code option available today
`--max-concurrency <physical cores>` (E004a) gives **-39.6% peak and 11% faster sync** on SMT machines with the stock binary. It also shrinks the other thread pools.

## Side findings
- **E001: sync wedge (bug, with a tested fix for stressnet).**
  - After ≥ 100 empty blocks, the adaptive `get_block_sync_size` asks for 100 blocks. On stressnet those serialize to ~134 MB, over the 100 MB levin packet limit, and the node retries forever.
  - Write-up: reports/E001-sync-wedge-ISSUE.md.
  - The owner's analysis (72a62f5) shows:
    - Today's mainnet rules permit the wedge only at `--batch-max-weight` above ~33.
    - The agreed post-FCMP++ rules would permit it at the default.
    - The proposed cap is too loose there, because the limit can double after 51 blocks. A window-aware cap is simulated in that write-up.
    - On stressnet both caps give 4 blocks.
- **O(c·q) verify fold:** ~52% of sync CPU on large-input proofs. It is fixable on its own, without the memory change, e.g. by bucketing constraints by commitment.
- **SMT and proof size:** SMT siblings slow 128-input proof verification (the cap is 9% faster, E004c) but speed up 2-input proofs (the cap is 7% slower, E011). A size-aware thread policy is the right default.
- **`pop_blocks` defaults to keep_txs = true.** Popping heavy blocks then re-pools every tx (85k), and the pool prune is super-linear, so the pop stalls for a long time.
- The RPC server stops responding while 24 threads verify heavily.

## Caveats
- One machine (12c/24t). The headline is one 40-block window with 3 A/B rounds; the 18,000-block resyncs (E010, E013) are 1 run per arm.
- adapt's threshold of 16 inputs and its trim interval of 10 s are judgment calls; neither was swept. adapt holds ~0.1-0.4 GB more than the non-adaptive combo during light-block sync and at idle, because it trims less often.
- Post-sync idle memory varies run to run by a few hundred MB: a trim cannot release fragmented arenas completely.
- E007 is security-critical cryptographic code and **not audited**. Upstream use needs review by the FCMP++ authors.

## Upstreamability (if the owner wants it)
| change | size | notes |
|---|---|---|
| E001 sync-size cap | ~10 lines | stressnet-tested. For post-FCMP++ mainnet use the owner's window-aware cap (simulated, not built) |
| adaptive batch cap + `malloc_trim` (E012) | ~25 lines in rctSigs.cpp | glibc-guarded trim; independent of E007 |
| E007 streaming verifier | ~1,000 lines + tests (monero-oxide) | biggest win; needs crypto review; alternatively, propose only the O(c·q) fold fix for CPU |

## Still running / next
- Fable-tier code review of the E007 monero-oxide change (in flight).
- E014 thread-count sweep (how the win scales on 1-4 thread machines).
- Wallet: W001 code map done (the tree cache is bounded by reorg depth); W002 measurement next.
