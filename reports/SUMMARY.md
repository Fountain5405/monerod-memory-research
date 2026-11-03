# monerod memory research: summary (draft, 2026-11-03)

**Bottom line:** on the FCMP++ stressnet sync workload, three small, separable changes cut monerod's memory needs by about two thirds: -67% peak in a 40-block worst-case window, -73% over an 18,000-block resync. All guardrails held: same chain state as the reference node, invalid proofs still rejected, no cost shifted to disk or swap.

**Speed is mixed.** Sync is about 2x faster on blocks full of max-input txs, but ~15% slower on blocks of small txs. The 18,000-block resync therefore takes 3.6% longer overall. E011 found that most of that cost comes from the two cheap fixes, not from the streaming verifier. On 2-input txs the thread cap costs +7% and the per-block trim +6%, while the streaming verifier costs +3%. E012 made the cap and the trim adaptive to proof size ("adapt"): small-tx blocks are then only +4% vs base, while heavy-window memory and speed stay at the combined build's level. adapt is being validated as the recommended build (E013).

| metric (40-block FCMP++ window, 3 alternating A/B rounds, medians) | baseline v0.19.0.0-beta.3.1 | combined build (E008) | change |
|---|---|---|---|
| peak anonymous memory (RssAnon) | 5,289 MB | 1,751 MB | **-66.9%** |
| peak private dirty memory | 5,289 MB | 1,763 MB | **-66.7%** |
| memory held after sync, idle (RssAnon) | 4,850 MB | 993 MB | **-79.5%** |
| minimum cgroup MemoryMax that still syncs within 1.1x the wall time, swap off (E009) | 5,750 MB | 1,866 MB | **-67.5%** |
| wall time for the window | 220 s | 117 s | **-46.8%** |
| bytes written to disk | 465 MB | 467 MB | unchanged |
| end block hash = reference node (.22) | 3/3 | 3/3 | same |
| tampered FCMP++ proofs rejected (monerod-level negative test) | 24/24 | 24/24 | same |

**Long run (E010: 3,105,401 → 3,123,400, 18,000 blocks, 1 run per arm, both with `--block-sync-size 5`):**

| metric | baseline | combined build | change |
|---|---|---|---|
| peak RssAnon | 5,603 MB | 1,503 MB | **-73.2%** |
| idle after sync (RssAnon) | 4,376 MB | 1,085 MB | **-75.2%** |
| wall, whole resync | 1,365 s | 1,414 s | **+3.6%** |
| wall, 40-block heavy window | 217 s | 108 s | -50% |
| wall, 7,959 dense small-tx blocks | 1,071 s | 1,230 s | **+14.8%** |
| wall, 10,000 near-empty blocks | 73 s | 73 s | 0% |
| bytes written | 9,394 MB | 9,405 MB | unchanged |
| end hash = .22 | yes | yes | same |

Memory does not grow over the run: after the window the combined build stays at 0.8-1.1 GB. The combined build with DEFAULT settings (no `--block-sync-size`; base wedges there, see E001) also synced all 18,000 blocks: peak 1,588 MB, wall +5.9%.

The owner's target was 40%. The minimum-cgroup number is the "real RAM a node needs" metric, because it counts heap, page cache, and everything else charged to the process.

## Setup
- **Machine:** hydrogen, a Ryzen 9 3900X (12 cores / 24 threads) with 16 GB of RAM.
- **Baseline:** seraphis-migration/monero v0.19.0.0-beta.3.1 (d80596ad1). This is the FCMP++ beta that stressnet runs.
- **Workload:** stressnet (testnet nettype), synced from the owner's node at 192.168.1.22. The A/B window is 3,105,401 → 3,105,441: 40 blocks, 1,044 txs, 109,408 inputs. 851 of those txs have 128 inputs.
- **Method:**
  - Each run first rewinds the DB and verifies the starting hash.
  - Runs alternate ABAB/BABA, one change per experiment.
  - Memory is sampled from /proc every 2 s.
  - Guardrails are listed in README.md.
- **Notes and evidence:** every experiment (including the failures) has notes under `experiments/`, data under `evidence/`, and an entry in JOURNAL.md.

## What uses the memory, and the three fixes
1. **FCMP++ proof verification is ~87% of the peak** (E002b, heaptrack).
   - Each verification builds the whole arithmetic circuit (millions of `LinComb` constraints) and stores it before folding.
   - One FCMP++ proof covers all inputs of a tx, so a 128-input proof stores ~250 MB.
   - Verification runs on up to 24 threads at once. The peak scales almost linearly with the thread count (E003: 1/4/12/24 threads → 1.23/2.03/3.30/5.40 GB).
2. **Fix 1 (E004c): cap FCMP++ batch verification at the physical core count.** A one-line change in `rct::batchVerifyFcmpPpProofs`.
   - On its own it barely moves RSS (-1.3%), because of item 3 below.
   - It does make sync 9% faster, since SMT siblings competing for the same core did not help this math.
3. **glibc keeps freed memory per thread arena.** Without a trim, RSS grows to (threads that ever verified) × (per-thread high-water mark) and stays there. That is why an idle node still holds ~4.8 GB after sync.
   - Capping the arena count does not help (E004d: -8%), because two threads sharing an arena both peak inside it.
   - **Fix 2 (E004e): `malloc_trim(0)` once per block, after the FCMP++ batch verify** (glibc builds only).
   - E004c + E004e together give -44.6% peak and -88% idle, 5.5% faster.
4. **The circuit does not need to be stored at all.** The verifier only uses the constraints as sums weighted by powers of the challenge z. The circuit is a deterministic function of challenges that come *before* z.
   - **Fix 3 (E007): streaming verifier.**
     - Build the circuit once on the real transcript, discarding the constraints, to reach z.
     - Process both proofs' transcripts.
     - Rebuild the circuit on a transcript clone, folding each constraint into an accumulator as it is produced.
     - Before applying, check that both builds agree (mul and constraint counts, transcript state).
     - The proof format is unchanged, and the old stored path is kept for tests.
   - Change size: about 1,000 lines in monero-oxide (generalized-bulletproofs, circuit-abstraction, fcmps), plus 1,182 lines of new tests, including equivalence with the old verifier (bit-identical batch-verifier state) and tampered-proof rejection per proof region.
   - Result: -59% peak on its own.
   - **It is also 2x faster.** The old verify folds each vector commitment's weights in a separate pass over all constraints. That costs O(commitments × constraints), roughly quadratic in the input count, and was **~52% of all sync CPU** (E006). The combined build's profile no longer contains that function.

**Combined (E008 = Fix 1 + 2 + 3, plus the E001 sync fix below): -67% peak, -80% idle, -67.5% minimum cgroup memory, 47% faster on the heavy window.** Over the 18,000-block resync (E010): -73% peak, -75% idle, but +3.6% wall (small-tx blocks +15%).

## Guardrails: how we know nothing was weakened
- Every run ends on the same block hash as the reference node (E004-E010).
- **Monerod-level negative test (scripts/negtest.sh):**
  - Txs that are not yet in our chain (128-, 8- and 2-input) were submitted to our own offline node.
  - First 8 copies of each with one bit flipped in the FCMP++ proof, then the original.
  - Baseline and combined build both rejected 24/24 tampered copies at "Failed to verify input FCMP++ signatures", and accepted all 3 originals.
- Crate-level tests (E007):
  - All existing monero-oxide tests pass, including byte-malleation.
  - New tests: streaming vs stored verification on valid and tampered proofs, accumulator vs stored fold, a Discard-mode circuit cannot yield a statement, an un-applied verification fails closed.
- Disk writes are unchanged, and swap is off. Under the minimum cgroup limit both builds keep their unconstrained wall time; every failure below the limit was an OOM kill (kernel log), not slow thrashing.

## Things that did not work (kept for the record)
| attempt | result | why |
|---|---|---|
| E005: `shrink_to_fit` on stored constraint vectors | no effect (5,350 vs 5,380 MB) | the working set is the number of constraints, not Vec slack |
| E004c alone (batch cap) | RSS -1.3% (wall -9%) | arena retention: freed working sets stay in every thread's arena |
| E004d: cap glibc arenas at physical cores | -8% | two concurrently verifying threads can share an arena, and both peak in it |

## Zero-code option available today
`--max-concurrency <physical cores>` (E004a) gives **-39.6% peak and 11% faster sync** on SMT machines with the stock binary. It also shrinks the other thread pools.

## Side findings
- **E001: sync wedge (bug, with a tested fix).**
  - After ≥100 empty blocks, the adaptive `get_block_sync_size` asks for 100 blocks. On stressnet those serialize to ~134 MB, over the 100 MB levin packet limit, and the node retries forever.
  - Repro: a pop + resync.
  - Fix: cap the batch by `0.9 × levin limit / block weight limit`, which is 4 blocks on stressnet.
  - Write-up: reports/E001-sync-wedge-ISSUE.md, ready for the owner to file upstream.
- **O(c·q) verify fold:** ~52% of sync CPU on large-input proofs. It is fixable on its own, without the memory change, e.g. by bucketing constraints by commitment.
- **`pop_blocks` defaults to keep_txs = true.** Popping heavy blocks then re-pools every tx (85k), and the pool prune is super-linear, so the pop stalls for a long time.
- The RPC server stops responding while 24 threads verify heavily.
- The stressnet window is a worst case: max-input txs. With mainnet-like 1-2-input txs the per-proof circuit is a few MB, so the absolute savings are smaller. The worst case still sets the RAM a node must have, since anyone can fill blocks with max-input txs.

## Caveats
- One machine (12c/24t). The headline is one 40-block window with 3 A/B rounds. The 18,000-block resync (E010, 1 run per arm) confirms the memory result over a long, mixed workload.
- `malloc_trim` is glibc-only. musl, macOS and Windows allocators are untested.
- E007 is security-critical cryptographic code. It was reviewed by me and heavily tested, but **not audited**. Upstream use needs review by the FCMP++ authors.
- **Small-tx slowdown (measured in E010):** the combined build is ~15% slower on blocks of small txs (1,071 → 1,230 s over 7,959 dense blocks). Suspects: E007's double circuit build (the old fold is not quadratic at low input counts), E004c's thread cap, or E004e's per-block trim. E011 (one change per arm, 1,000 blocks of 2-input txs, 3 rounds) attributes it: the cap +7.3% (SMT siblings help small proofs), the trim +6.0% (~9 ms per block), the streaming verifier +2.7%. E012 (running) applies the cap and the trim only after heavy calls.
- Post-sync idle memory of the combined build varies run to run (673-1,181 MB), because a trim cannot release fragmented arenas completely.

## Upstreamability (if the owner wants it)
| change | size | notes |
|---|---|---|
| E001 sync-size cap | ~10 lines | ready (reports/E001-sync-wedge-ISSUE.md) |
| E004c batch cap at physical cores | ~5 lines | simple; 9% faster on its own |
| E004e `malloc_trim` after FCMP++ batch verify | ~5 lines | glibc-guarded |
| E007 streaming verifier | ~1,000 lines + tests (monero-oxide) | biggest win; needs crypto review; alternatively, propose only the O(c·q) fold fix for CPU |

## Results still pending
- E010 long resync: DONE (above).
- E011 small-tx attribution: DONE (cap +7%, trim +6%, streaming verifier +3%).
- E012 adaptive cap + trim: DONE (small-tx +4.0% vs base instead of +15%; heavy window = combo).
- E013 validation of adapt (A/B vs base, negtest, min_mem, long resync): running.
- Wallet: W001 code map done (the tree cache is bounded by reorg depth); W002 measurement next.
