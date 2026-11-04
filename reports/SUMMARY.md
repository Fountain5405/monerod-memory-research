# monerod memory research: summary (draft, updated 2026-11-04 after E023)

**Bottom line:** on the FCMP++ stressnet sync workload, three separable changes cut the memory monerod needs by about **two thirds to 70%**, and sync is about as fast or faster:
- -68% peak in a 40-block worst-case window (3 A/B rounds);
- -69% over an 18,000-block resync;
- -67.5% in the minimum cgroup memory a sync can run under.

Over the 18,000-block resync the recommended build is 5.4% faster overall: 2x faster on heavy blocks, 4.1% slower on dense small-tx blocks. On a 1,000-block window of small txs it is 6.6% slower, which is above the +6% I expected before E023 (see E023; the last two patches are not the cause). All guardrails held: the same chain state as the reference node, invalid proofs still rejected (24/24 in E023; 236/236 identical decisions to base in the differential test, E015, rerun on this build in E025), and no cost shifted to disk or swap.

**Recommended build ("final", validated in E023; "adapt" in earlier experiments is this build without items 4 and the threshold of 8)** = beta.3.1 plus:
1. The streaming FCMP++ verifier (E007).
2. For FCMP++ batch calls whose largest proof has ≥ 8 inputs (16 in E012, changed by E022): a cap on the batch count at physical cores, and `malloc_trim(0)` afterwards. Otherwise no cap, and a trim at most every 10 s.
3. The E001 sync-size cap.
4. One `malloc_trim(0)` once verification has been idle for 5 s (E021).

### Headline: 40-block heavy window 3,105,401 → 3,105,441, 3 alternating A/B rounds, medians (E023)

| metric | baseline v0.19.0.0-beta.3.1 | final | change |
|---|---|---|---|
| peak anonymous memory (RssAnon) | 5,606 MB (5,405-5,634) | 1,764 MB (1,613-1,797) | **-68.5%** |
| peak private dirty memory | 5,613 MB | 1,786 MB | **-68.2%** |
| memory held after the window, idle (RssAnon) | 4,977 MB | 1,066 MB | **-78.6%** |
| minimum cgroup MemoryMax that still syncs within 1.1x the wall time, swap off (base E009, final E023) | 5,750 MB | 1,866 MB | **-67.5%** |
| wall time | 221 s | 112 s | **-49.3%** |
| CPU time (utime + stime) | 4,229 s | 914 s | -78.4% |
| bytes written to disk | 466 MB | 466 MB | unchanged |
| end block hash = reference node (.22) | 3/3 | 3/3 | same |
| tampered FCMP++ proofs rejected (monerod-level negtest; base from E013) | 24/24 | 24/24 | same |

### Long run: 18,000-block resync 3,105,401 → 3,123,400, 1 run per arm, `--block-sync-size 5` (E023)

| metric | baseline | final | change |
|---|---|---|---|
| peak RssAnon | 5,369 MB | 1,650 MB | **-69.3%** |
| idle after sync (RssAnon) | 4,190 MB | 1,400 MB | **-66.6%** |
| wall, whole resync | 1,360 s | 1,287 s | **-5.4%** |
| wall, 40-block heavy window | 219 s | 106 s | -52% |
| wall, about 7,960 dense small-tx blocks | 1,062 s | 1,106 s | +4.1% |
| wall, about 10,000 near-empty blocks | 76 s | 72 s | -5% |
| bytes written | 9,409 MB | 9,411 MB | unchanged |
| end hash = .22 | yes | yes | same |

These are single runs, and base itself moved between experiments (peak 5,369 here and 5,613 MB in E013; idle 4,190 and 4,642 MB).

- No upward memory trend over the last 13,000 blocks: after the window final stays at 1.3-1.6 GB, rising about 260 MB up to 3,113,400 and then flat or falling, and it never passes its heavy-window peak. One run, so slow growth over a much longer sync is not excluded.
- With DEFAULT sync settings (no `--block-sync-size`), final also synced all 18,000 blocks: peak 1,511 MB, 1,342 s, 5.9% more written. Base wedges there (E001).
- On a 1,000-block window of small txs (E023, 3 rounds), final uses 807 MB vs base's 1,095 MB (-26%), and is 6.6% slower on identical heights (155.0 vs 145.4 s, ranges not overlapping). E012 measured adapt at +4.0% there. A direct comparison (E023b, 5 rounds) shows the last two patches are not responsible (final vs adapt -1.1%, ranges overlapping), so the gap is adapt's own and E012 understated it.

The owner's target was 40%. The minimum-cgroup number is the "real RAM a node needs" metric, because it counts heap, page cache, and everything else charged to the process.

## How real is this?
A critical re-check of the raw data and source is in reports/REVIEW-70pct.md. Short version: the sampled peak is bounded by the independent cgroup test to within 3-5%, the 2x speed-up is confirmed to come from removing an O(c·q) pass in the stock verifier, and ~40 of the 68 points are available by halving concurrency alone; the rest needs the verifier change.

**Solid:**
- It reproduces across sessions and builds:
  - E008: -67%
  - E010: -73%
  - E012/E013: -68% / -70%
- The streaming verifier is equivalent to the verifier it replaced, not just to its own refactoring (E016): verbatim copies of the pre-change `Fcmp::verify` and `ArithmeticCircuitStatement::verify` from 31c26d9, under test only, leave the batch verifier in the same state as the streaming path on 8 honest shapes, every tampered region and 256 random single-byte mutations, with the same error on every malformed proof.
- It reproduces on a second, different machine (E019, box81, Ryzen 5 5600G 6c/12t, 14 GB, binaries built there): -61.5% peak / -71% post-idle / -43% wall on the heavy window, -33% peak on small-tx blocks, 18/18 hashes. The stock peak is smaller there (3.4 GB at 12 threads) so the percentage is smaller; the absolute saving is 2.1 GB vs 3.8 GB.
- Every A/B has tight, disjoint ranges.
- Two independent metrics agree: peak anon memory, and the minimum cgroup limit (which includes page cache, and whose failures are OOM kills, not slowdowns).
- The guardrails held in every run. The mechanisms (below) are understood and confirmed by heaptrack and perf, not just observed.

**Limits:**
- **Worst-case workload.** 82% of the window's txs have 128 inputs. On 2-input blocks the saving is ~30%. The worst case does set what a node must provision, since anyone can fill blocks with max-input txs.
- **One machine with 24 threads.** The stock node's peak scales with thread count (E003: 1.2 GB at 1 thread, 5.4 GB at 24), so part of the win is the 24-thread baseline. **E014 (done, experiments/E014-thread-sweep) measured base vs adapt at 4, 2 and 1 threads: peak -47.5% / -25.5% / -28.7%, post-idle -66% / -49% / -48%, and adapt is 21-28% faster at every thread count with 25-28% less CPU. So on a 4-thread machine the reduction is about half of the peak; on 1-2 threads about a quarter of the peak and half of the idle footprint, plus a speed-up. The 40% target holds from 4 threads up.** **E019 (done, experiments/E019-box81-reproduction) is the review's second machine: on box81 (Ryzen 5 5600G 6c/12t, 14 GB, binaries built there) adapt is -61.5% peak / -71% post-idle / -43% wall / -73% CPU on the heavy window and -33% peak at +5% wall on small-tx blocks, 18/18 hashes, VmSwap 0 in every sample. Same picture as hydrogen with a smaller stock peak (3.4 GB at 12 threads vs 5.4 GB at 24).**
- **About two thirds of the win is cryptographic code not yet reviewed by cryptographers** (E007, ~1,000 lines in monero-oxide). It was reviewed by me and then by an independent Fable-tier agent (reports/E007-crypto-review.md: no soundness bug, no new panic, fail-closed holds; the one medium test gap, F1, closed by E016). That is still not an audit. Without it, the ~15-line cap + trim changes give about -45%, and the zero-code `--max-concurrency 12` gives -40%.
- `malloc_trim` is glibc-only. FCMP++ itself is still a beta (stressnet), not mainnet.

## The code
`patches/`: the full ordered patch series (monero-oxide + monerod) with build instructions. Source trees on the work box: `~/work/monero-oxide-e007` (c215a80) and `~/work/monero-fcmp-adapt` (4a51d434d).

## How it works
Two explanations of the mechanism, written at the owner's request: reports/HOW-IT-WORKS.md (technical: where the memory went, the streaming verifier's design and fail-closed properties, the cap and the trim, where to look in the code) and reports/HOW-IT-WORKS-plain.md (plain language).

## Prior art
reports/PRIOR-ART.md: what upstream already did about FCMP++ verification memory (Oct-Dec 2025: per-proof footprint 1.2 GB -> 250 MB inside monero-oxide, one batch per thread, glibc arena cap; the '250 MB x threads, not returned to the OS' shape was stated and accepted in seraphis-migration/monero#224). A cap on heavy verifications and a 16-input size split were suggested in #202 but shipped differently; not storing the circuit, the trim, and the O(c x q) fold removal were not found proposed anywhere.

## Setup
- **Machines:** hydrogen, a Ryzen 9 3900X (12 cores / 24 threads) with 16 GB of RAM, for every experiment unless stated. box81, a Ryzen 5 5600G (6 cores / 12 threads) with 14 GB of RAM, for the independent reproduction (E019: base vs adapt vs e017 on the heavy and small-tx windows) and the E017 crate work. Each box builds its own binaries (ARCH=native); timings are never compared across boxes, only percentages.
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
   - Result (as measured in E012/E013; later E023 measured +4.1% on the long resync's dense stretch and +6.6% on the short small-tx window): small-tx blocks are +4% instead of +15%, the heavy window is unchanged, and the long resync is 4.6% faster than base.

### Build history
| build | what | heavy-window peak | heavy wall | small-tx wall | status |
|---|---|---|---|---|---|
| base | v0.19.0.0-beta.3.1 | 5.3-5.6 GB | 220 s | 150 s | reference |
| E004e | cap + trim | 2.9 GB (-45%) | -5% | +13% | superseded |
| E007 | streaming verifier | 2.3 GB (-59%) | -50% | +3% | component |
| E008 combo | E004c + E004e + E007 + E001 | 1.75-1.86 GB (-67%) | -47% | +15% | superseded |
| **E012 adapt** | combo with an adaptive cap and trim | **1.64-1.78 GB (-68%)** | **-50%** | **+4%** | **recommended** |
| E017 e017 (v2) | adapt's monerod changes + the pre-folded verifier (stock `verify` untouched, ~1/3 of the diff) | 1.63 GB (-70%) | -29% | +12% | superseded by e020 |
| E020 e020 (v2, two builds) | e017 + patch 0003: the second proof's `z` peeked on a skipped transcript clone, one fold rebuild for both circuits | 1.62 GB (-70%) | -37% | +8% | alternative (E020) |

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
  - E025 reran the same case files on the final v1 and v2 builds: 0 disagreements for either. The cases use 128- and 2-input txs only.
- Crate-level tests (E007):
  - All existing monero-oxide tests pass, including byte-malleation.
  - New tests: streaming vs stored verification on valid and tampered proofs; accumulator vs stored fold (bit-identical batch-verifier state); a Discard-mode circuit cannot yield a statement; an un-applied verification fails closed.
- **Independent static review (reports/E007-crypto-review.md):** a separate Fable-tier agent walked the base verifier check by check against the streaming path: every structural check and every multiexp term is reproduced, the transcript is cloned at the right point and never sees proof bytes, every error path rejects, and no new panic is reachable from proof bytes (the FFI aborts on panic). The one finding, that the crate's equivalence test compared against the refactored stored path rather than the base verifier, is closed by E016 (verbatim base verifiers under test; identical states and errors on honest, tampered and randomly mutated proofs).
- Disk writes are unchanged, and swap is off. Under the minimum cgroup limit the builds keep their unconstrained wall time; every failure below it was an OOM kill (kernel log), not slow thrashing.

## Things that did not work (kept for the record)
| attempt | result | why |
|---|---|---|
| E005: `shrink_to_fit` on stored constraint vectors | no effect (5,350 vs 5,380 MB) | the working set is the number of constraints, not Vec slack |
| E004c alone (batch cap) | RSS -1.3% (wall -9%) | arena retention: freed working sets stay in every thread's arena |
| E004d: cap glibc arenas at physical cores | -8% | two concurrently verifying threads can share an arena, and both peak in it |
| E008 combo as the final build | +15% on small-tx blocks | non-adaptive cap and per-block trim (E011); fixed by adapt |

## Zero-code option available today
- **Wallet:** `MALLOC_ARENA_MAX=2 monero-wallet-cli ...` (or in the environment of monero-wallet-rpc / a GUI that launches it): refresh peak -67% (1,132 -> 370 MB on 18,270 stressnet blocks), wall +7%, CPU +4%, all threads kept (W004, F36). glibc builds only.
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
- The headline numbers are from hydrogen (12c/24t). E019 reproduced the A/B on a second machine, box81 (6c/12t, 14 GB): -61.5% peak, -71% post-idle, -43% wall on the heavy window, -33% peak on small-tx blocks, 18/18 hashes, no swap. The headline is one 40-block window with 3 A/B rounds; the 18,000-block resyncs (E010, E013, E018) are 1 run per arm, on hydrogen only.
- adapt's threshold is now 8 inputs: E022 swept 8 / 16 / 32 and replicated 8 against 16 on two stretches (about -30% CPU, +3-4% wall on 8-input blocks; no lower peak once larger proofs are in the run; 83 of 43,270 blocks affected on this synthetic chain; below 8 untested; F38). The figures in this report for adapt were measured with 16 unless they cite E022 or later. E026 swept the 10 s trim interval on small-tx blocks: 60 s saves 0.8% wall (ranges overlap) and costs +4.4% peak, no light-call trim saves 1.4% and costs +4.6%, so 10 s stays and light-call trims are not what the small-tx wall gap is made of (F42). adapt holds ~0.1-0.4 GB more than the non-adaptive combo during light-block sync, because it trims less often; at idle E021's single idle trim releases ~230 MB of it on the heavy window (about -17%, F37), but only 70-79 MB after a long resync (F39), so that gain is specific to a burst ending on heavy blocks. E023 reran the validation with both patches; the E015 differential test was not rerun. The idle trim is unmeasured at the chain tip.
- Post-sync idle memory varies run to run by a few hundred MB: a trim cannot release fragmented arenas completely.
- E007 is security-critical cryptographic code and **not audited**. Upstream use needs review by the FCMP++ authors.

## Upstreamability (if the owner wants it)
| change | size | notes |
|---|---|---|
| E001 sync-size cap | ~10 lines | stressnet-tested. For post-FCMP++ mainnet use the owner's window-aware cap (simulated, not built) |
| adaptive batch cap + `malloc_trim` (E012) | ~25 lines in rctSigs.cpp | glibc-guarded trim; independent of E007 |
| idle trim (E021) | ~40 lines (rctSigs.cpp + a 2 s check in `core::on_idle`) | one `malloc_trim(0)` 5 s after the last verification; glibc-guarded; about -17% idle on top of E012 on the heavy window, no measurable speed cost on sync windows; demote its log line first |
| E007 streaming verifier | ~1,000 lines + tests (monero-oxide) | biggest win; independent static review found no defect (reports/E007-crypto-review.md); base-equivalence test added (E016, F1 closed); apply the two low hardening items first; still needs review by the FCMP++ authors; alternatively, propose only the O(c·q) fold fix for CPU |

## Still running / next
- E014 thread-count sweep: done (above).
- E018 (hydrogen): done (experiments/E018-node-level-v2, F31). v2 keeps v1's memory (heavy peak +2.6%, idle -16%, cgroup minimum 1,765 vs 1,866 MB, long-resync peak -72%) and its correctness (negdiff identical to base, 236 cases; all hashes), but fails the pre-registered speed criterion: heavy window +43% wall over v1, small-tx +12% over base, long resync +5.1% over base where v1 is -4.6%. **v1 / adapt stays the recommended build; v2 is the small-diff alternative (reports/HOW-IT-WORKS.md 2.1b).**
- E019 (box81): done (above).
- E016 (done, experiments/E016-base-equivalence): the streaming verifier is now tested against verbatim copies of the 31c26d9 verifiers (8 honest shapes, ~100 region tamperings, 256 random byte mutations): identical verifier states and identical errors. Closes the crypto review's F1.
- E020 (hydrogen): done (experiments/E020-two-builds, F33). v2 with two circuit builds instead of three (the second proof's `z` is peeked on a transcript clone skipped past the first proof; one fold rebuild for both circuits; +57 additive lines in generalized-bulletproofs, 26/26 in fcmps). Same memory as v1 and e017 (heavy peak +1%, idle -25% vs adapt), negdiff identical to base, all hashes; heavy wall +28% over v1 (e017 was +46%), small-tx +3% over v1 (e017 +8%). The pre-registered rule (heavy within 10% of v1) is not met, so **v1 / adapt stays recommended; the v2 alternative is now patches 0001-0003 (e020)**. The remaining gap to v1 is unprofiled; a perf profile of e020 on the heavy window is the next step if v2 is to be pushed further.
- E021 (hydrogen): done (experiments/E021-idle-trim, F37). One `malloc_trim(0)` from `core::on_idle` once FCMP++ verification has been idle for 5 s releases 231-234 MB on the heavy window (about -17%) and 37-43 MB on small-tx (about -5%), with no measurable change in peak, wall or CPU; 12/12 hashes, one trim per run. Adopted as monerod patch 0006 (v1) / 0007 (v2, built and measured in E025). Against stock on the heavy window, across experiments, idle is about -77%. Not rerun with it: negative test, cgroup minimum, long resync. Not measured: a node at the chain tip.
- E023 (hydrogen): done (experiments/E023-final-validation, F39); headline tables above carry it. E023b: the small-tx miss is adapt's own cost.
- E024 (hydrogen): done (experiments/E024-e020-profile, F40). e020's extra cycles are mostly field multiplication and the fold and verify loops; copying is 3.8% of them. No call graphs, so the callers are inferred.
- E025 (hydrogen): done (experiments/E025-v2final-and-difftest, F41). Final and v2final both match base on all 236 differential cases. v2 with its last two patches builds and runs: against final, heavy wall +27.5%, small-tx wall +2.7% (ranges overlap), post-idle after heavy blocks 795 vs 1,129 MB, 12/12 hashes. v1 stays recommended.
- E026 (hydrogen): done (experiments/E026-trim-interval, F42). 10 s stays, under a rule fixed before the run.
- E027 (box81): running. The final series on the second machine: part a met its expectations (the published patches reproduce the final source tree exactly; differential test at the heavy height, 135 cases, 0 disagreements); the base vs final A/B is under way.
- Wallet: W001 code map done (the tree cache is bounded by reorg depth). W002 done (experiments/W002-wallet-refresh, F34): a fresh, empty wallet peaks at 1.17 GB RSS refreshing 18,270 stressnet blocks in 15 s on 24 threads, against a 349 MB live heap: the same glibc arena-retention gap the node had (F13). The largest live consumer is the FCMP++ tree extension (`outputs_to_leaves`, 115 MB). W003 (`--max-concurrency` 24/12/4/1: peak 1,100 / 909 / 510 / 357 MB, wall 16 / 23 / 55 / 105 s; F35) shows the peak is ~325 MB + ~32 MB per worker thread. **W004: `MALLOC_ARENA_MAX=2` in the wallet's environment cuts the peak 67% (1,132 -> 370 MB) at +7% wall with all threads kept (F36)**; the excess was glibc arena retention entirely, the live heap is ~350 MB. Zero code, available today. Not yet measured: a wallet that owns many outputs (needs a stressnet seed).
