# Review of the ~70% memory-reduction finding (2026-11-03, at the owner's request)

A critical pass over the headline, going back to raw data and source rather than to my own summaries.

## The claim
The recommended build (adapt = E007 streaming verifier + adaptive batch cap/trim + E001 cap) needs about a third of the memory of v0.19.0.0-beta.3.1 on the FCMP++ stressnet workload: -68% peak anon in the heavy window (3 rounds), -70% over 18,000 blocks, -67.5% minimum cgroup limit, with the same chain state and no weakened verification.

## What I re-checked today
1. **Raw sampler data of the E013 headline runs.** Base: 54 samples per run, 18-24 of them within 90% of the peak (a sustained plateau). adapt: 40 samples per run, only **3-5 within 90% of the peak**: its peak is brief, and a 2-second sampler could miss the true maximum. **This is bounded by the cgroup test**, which is independent of sampling: adapt completed the window under MemoryMax = 1,866 MB with swap off (systemd-run, MemorySwapMax=0) and was OOM-killed at 1,765 MB. So adapt's true peak lies in [1,816, 1,866] MB and base's in [5,617, 5,750]. The reduction is therefore between **-66.8% and -68.4%** whichever way it is computed. The sampler number (1,780 median) is within 3-5% of the truth, and the headline stands.
2. **The O(c·q) mechanism behind the 2x speed-up**, which is the part that looks most like skipped work. Confirmed in the unmodified source (monero-oxide 31c26d9, `generalized-bulletproofs/src/arithmetic_circuit_proof.rs:779-783`): `for i in 0..self.C.len()` wraps `for (constraint, z) in self.constraints.iter()...`, one full pass over all constraints per vector commitment. For a 128-input proof that is the quadratic term. Removing a redundant pass is not skipping a check.
3. **Equivalence tests exist and run on real proofs.** `fcmps/src/tests.rs:866 test_streaming_verify_matches_stored` builds real FCMP proofs (`random_proof`, 8 path/layer combinations), runs both verifier paths and asserts the batch-verifier states equal field by field (g, h, g_bold, h_bold, …), then that both batches verify. `:982` checks the accumulated constraint counts match the stored ones. The verify path itself (`fcmps/src/lib.rs:1064-1081, 1189-1193`) refuses to proceed if the two circuit builds differ in mul count, constraint count, or transcript challenge bytes (`InconsistentCircuitReplay`).
4. **Differential black-box test (E015), finished during this review: PASS.** 236 cases (224 single-bit flips, 5 proof swaps, 7 originals) at two heights; base and adapt gave identical (status, flags) on every case; 225 of the 229 rejections were at the FCMP++ check, 4 at parsing (identically in both). Proof swaps, a valid proof on another tx, are rejected by both.
5. **The cap is really active in adapt.** CPU seconds halve vs E007-alone (904 vs 1,759 s) while wall is equal, which is what 12 instead of 24 verifier threads looks like.

## Decomposition: how much is "just fewer threads"?
| configuration | heavy-window peak | vs stock |
|---|---|---|
| stock, 24 threads | 5,300-5,600 MB | |
| stock, `--max-concurrency 12` (E004a, config only) | 3,302 MB | -39.6% |
| stock, 1 thread (E003) | 1,232 MB | -77% (and 4x slower) |
| cap + trim, ~15 lines (E004e) | 2,943 MB | -44.6% |
| streaming verifier alone, no cap, no trim (E007/E012) | 2,291-2,338 MB | -59% |
| adapt (all, 12 heavy verifiers in flight) | 1,640-1,816 MB | -68% |

Roughly 40 of the 68 points can be had by halving concurrency on the stock binary; the verifier change is what makes the rest possible without giving up speed. At *equal* concurrency (12 heavy verifiers) adapt uses 1,780 MB vs stock's 3,302 MB (-46%), while being 2x faster. adapt with 12 verifications in flight uses only 45% more than a stock node doing one at a time.

## Weaknesses that remain (in order of importance)
1. **Unaudited cryptographic code written and tested by the same (AI) author.** The equivalence tests use honest proofs; the differential test covers 229 malformed cases. Neither is a security argument. Review by the FCMP++ authors is required before anyone relies on it.
2. **One machine, one chain.** 12c/24t, stressnet. E014 (running) tests 1/2/4 threads. No second machine, no mainnet-like traffic except the small-tx window (-30% there). **Update 2026-11-03 evening: E014 done (adapt -47.5% / -25.5% / -28.7% peak at 4 / 2 / 1 threads, F29); E019 done on a second machine, box81 (Ryzen 5 5600G 6c/12t, 14 GB, native builds): -61.5% peak, -71% post-idle, -43% wall, 18/18 hashes, no swap (F30). One chain (stressnet) remains the only workload.**
3. **The remaining 1.7 GB is unattributed.** No heaptrack of the new build yet, so I cannot say what it is (likely the per-proof IPA vectors × 12 threads plus ~300 MB baseline) or whether it could go lower.
4. **Sampling resolution** (point 1 above): headline peaks for fast builds should be quoted with the cgroup bound, which the summary now does.
5. **Tuning constants** (16-input threshold, 10 s trim interval) were chosen, not swept. (Later: E022 swept the threshold and moved it to 8; E026 swept the trim interval and kept 10 s.) Post-idle memory varies by a few hundred MB run to run.
6. **Base peak varies 6% across sessions** (5,289-5,617 MB). It does not change any conclusion, but it is why the headline is quoted from one 3-round session, not pooled.

## Verdict
The ~70% is a real, reproducible measurement on this workload and machine, bounded two independent ways, with no sign of weakened verification. It is not yet a safe-to-deploy result: that needs an external review of E007 and a second machine. **Update 2026-11-03: the second machine is done (E019, experiments/E019-box81-reproduction, same picture). The external review remains.**
