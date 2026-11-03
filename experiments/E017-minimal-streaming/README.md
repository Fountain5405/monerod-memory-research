# E017: a much smaller streaming verifier ("pre-fold to one constraint"), to replace E007

**Why:** the owner's concern (2026-11-03): E007's monero-oxide patch is 1,004 non-test lines (plus 1,182 of tests), and 570 of them restructure `ArithmeticCircuitStatement::verify` in generalized-bulletproofs, the crate under external audit. Human reviewers must not have to re-audit the verifier for a memory optimization. Question: can the same memory reduction be had with far fewer, and less sensitive, changes?

**E007's size, by file (non-test lines added):**

| file | lines | why |
|---|---|---|
| generalized-bulletproofs/src/arithmetic_circuit_proof.rs | 570 | `verify` split into `verify_transcript` / `PendingVerification::apply`, `ConstraintAccumulator`, `FoldedStatement`, Drop-poison |
| fcmps/src/lib.rs | 311 | two-build `Fcmp::verify`, replay checks, `verify_stored` |
| fcmps/circuit-abstraction/src/lib.rs | 98 | Store / Discard / Accumulate modes |
| fcmps/src/circuit.rs | 21 | plumbing |
| generalized-bulletproofs/src/transcript.rs | 4 | `VerifierTranscript: Clone` |

## The idea
The stock verifier folds the q constraints with weights z^1, z^2, …, z^q (constraint k gets z^(k+1); `arithmetic_circuit_proof.rs:211-217`, "powers of z starting with z^1"). It derives z from the transcript right after reading AI, AO, S (`:679-683`), and it **never hashes the constraints or q into the transcript**; the statement is bound externally, by fcmps' own transcript. So:

> If the verifier is handed a **single** constraint L = Σ_k z^k · c_k (k from 0), it computes z · L = Σ_k z^(k+1) · c_k, which is exactly the combination the stock verifier computes from the q stored constraints. One line of algebra.

The stock `verify` can therefore stay **byte-for-byte unchanged**. What changes is only *what fcmps feeds it*: one pre-folded constraint instead of millions. To pre-fold, fcmps needs z before the circuit exists, which it gets the same way E007 does: build the circuit once discarding constraints to advance the transcript, then peek z from a clone.

## Design (three circuit builds, no change to `verify`)
In `Fcmp::verify` (base `fcmps/src/lib.rs:938-985` builds c1 and c2 in one gadget pass, then calls `c1_statement.verify` and `c2_statement.verify`):
1. Clone the transcript at the start of circuit construction (T_start).
2. **Build A, Discard mode**, on the real transcript, as E007 does. The transcript reaches S0.
3. **Peek z1**: on a clone of S0, read AI, AO, S of the c1 proof and draw y, z (a 10-line helper in generalized-bulletproofs, or inline in fcmps; `read_point` and `challenge` are already public).
4. **Build B, Fold mode for c1** (c2 discarded), from a clone of T_start: each c1 constraint k is multiplied by z1^k and added into dense accumulators (aL, aR, aO weights grown on demand; one vector per vector commitment; a constant). At the end, `folded_statement()` builds one `LinComb` from those via the public `LinComb::term` / `constant` API and calls the **unchanged** `ArithmeticCircuitStatement::new` with `vec![L1]`.
5. `c1_statement.verify(...)` on the real transcript, unchanged code. The transcript reaches S1.
6. Peek z2 from a clone of S1; **build C, Fold mode for c2**, from a clone of T_start; `c2_statement.verify(...)`.
7. Cheap consistency checks (muls and constraint counts equal across A/B/C; the clones' transcript challenge bytes equal the real one's at S0), returning an error on mismatch.

Builds B and C each still run the whole gadget pass (c1 and c2 are interleaved in the transcript), so this is **three constructions instead of E007's two**. Construction was ~5% of baseline CPU per pass (E006), so the extra pass should cost ~5% more than E007 on small transactions (E011: E007 +2.7% there), and nothing visible on heavy ones, where the O(c·q) fold that disappears dominated. With q = 1, the stock verifier's per-commitment fold loop is O(c), so the 2x speed-up is kept.

**Estimated size:** generalized-bulletproofs ~15 lines (`VerifierTranscript: Clone`, the peek helper), circuit-abstraction ~100 (Discard and Fold modes, `folded_statement`, `statement()` refusing non-Store modes), fcmps ~60 (the three builds and checks). **~150-200 non-test lines, with the audited `verify` untouched.** Tests: the equivalence target is the genuine stock verifier, because it is unchanged: "stock verify on the stored circuit" vs "stock verify on the pre-folded constraint", same proof, same RNG, assert identical batch-verifier state; the 8 shapes, honest and tampered; plus the differential fuzz from reports/E007-crypto-review.md section 5.

**Memory:** the folded `LinComb` is dense, ~3n + Σ|cg_i| terms of (usize, scalar) = 40 B each, plus the stock verifier's own l/r/o weight vectors; roughly O(n) like E007's folded vectors, perhaps 1.5x E007's per-proof heap, still far below the ~250 MB stored circuit. The prediction to test: **window peak within ~10% of E007/adapt (≤ 2.0 GB vs base 5.6 GB)**, wall within ~5% of adapt, same hashes, negtest identical to base.

**What reviewers would have to check:** (a) one algebraic identity; (b) that the Fold accumulator sums weights correctly (a ~40-line function, testable against the stored constraints directly); (c) that the three builds see the same transcript (determinism, same argument as E007, plus the equality checks); (d) that `new`'s structural checks on the single folded constraint are as good as on the q constraints: for FCMP m = 0 so "V individually constrained" is vacuous, and the index bounds are set by our own gadget code, not by proof bytes, so the check on the folded constraint is a defence-in-depth check, not a soundness one.

## Alternatives considered
- **No crypto change at all:** patches 0001+0002+0005 (adaptive cap + trim, ~25 lines in rctSigs.cpp): -45% peak, -88% idle, no monero-oxide change. Available today if the audit timeline makes any verifier change unwelcome.
- **Trim E007 in place** (drop `PendingVerification`'s Drop-poison, the `verify_stored` driver and the wrapper): perhaps -25%, but `verify` stays restructured. Not worth it next to E017.
- **Compact constraint storage** (E005's direction, a (u32, scalar) arena): constant-factor only, keeps the O(c·q) fold. Rejected.

## Plan
Needs cargo on hydrogen, so it runs after E014's timing runs (~14:20): implement on a new branch of ~/work/monero-oxide-e007 from 31c26d9 (not on top of E007), crate tests, then a monerod build (`adapt` with the E007 cargo patch pointed at the new branch) and the standard validation: heavy-window A/B vs adapt and base, small-tx window, negdiff vs base, min_mem, long resync. If it holds, E017 replaces E007 in `patches/` and in the recommended build, and E016's base-equivalence test is written against it instead.

## Implementation (2026-11-03 12:10-12:45)
Branch `e017-folded-verify` on upstream monero-oxide 31c26d9 (built and tested on box81; also as a worktree on hydrogen). Two commits: (1) refactor only, `verifier_layout` + `build_verifier_circuits` extracted so the circuits can be built more than once; (2) the fold. Sizes vs 31c26d9: generalized-bulletproofs **+25 lines, additive** (`#[derive(Clone)]` on `VerifierTranscript`, `peek_z`); circuit-abstraction +171/-6 (Discarded/Folded modes, the `FoldedConstraints` accumulator, `CircuitStatementError`); fcmps +370/-82 (of which the refactor commit is pure motion); tests +228 plus a benchmark. The audited `ArithmeticCircuitStatement::verify` is byte-identical.

Compile history: round 1 failed (cloning `PointWithDlog` / `TranscriptedInput` for the rebuilds needs `Clone` bounds the parameter types lack); fixed by recomputing the layout per build. Round 2 clean.

## Crate-level results (box81, 2026-11-03)
- **`test_folded_verify_matches_stored` PASS:** on 8 (inputs, layers) shapes, `Fcmp::verify` (folded) and `Fcmp::verify_stored` (the stored circuit through the UNCHANGED stock `verify`) leave the batch verifiers field-by-field identical, and both batches verify.
- **`test_folded_verify_matches_stored_on_tampered_proofs` PASS:** 64 random single-bit flips per shape (4 shapes) plus the genuine proof with two inputs swapped: identical Ok/Err decisions, identical verifier state where Ok, and the batch never verifies.
- `test_discarded_and_folded_circuit_statements` PASS: a discarded circuit cannot yield a statement; a folded circuit refuses Pedersen commitments.
- **Peak heap of one verification** (counting global allocator, `verify_memory_benchmark`, 8 layers; `random_paths` allows at most 18 paths, so 128-input proofs are measured at the node level in E018):

| inputs | stored (stock) | folded (E017) | change | stored ms | folded ms |
|---|---|---|---|---|---|
| 1 | 1.97 MB | 0.41 MB | -79% | 5 | 10 |
| 2 | 3.93 MB | 0.78 MB | -80% | 9 | 18 |
| 8 | 15.5 MB | 3.0 MB | -81% | 32 | 66 |
| 16 | 31.1 MB | 6.1 MB | -81% | 69 | 133 |

The memory saving per proof is larger than the E007 micro-benchmark showed (0.53 / 1.05 / 4.1 MB for 1 / 2 / 8 inputs). The CPU cost at these sizes is about 2x per verification (three circuit builds instead of one, and no quadratic fold to remove at small input counts); E007 measured +40-50%. What this means for node wall time on small-tx blocks is measured in E018 (the E007 crate-level +40-50% became +2.7% at the node).

**Status:** crate tests passing on box81 12:45; GBP / circuit-abstraction suites and the existing fcmps suite running; node-level measurement E018 armed on hydrogen.
