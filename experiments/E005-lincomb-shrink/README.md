# E005: shrink stored FCMP++ circuit constraints to fit (Rust, no transcript change)

**Background:** E002b/E003 show ~170-270 MB of transient working set per concurrent FCMP++ verifier thread. Code reading (2026-11-02 21:30):
- `fcmp_pp_verify` (fcmp_pp_rust/src/lib.rs:1166) creates one ed25519 BatchVerifier and two generalized-bulletproofs batch verifiers per batch, then for each proof calls `FcmpPlusPlus::verify`. That calls `Fcmp::verify` (crypto/fcmps/src/lib.rs:762), which builds fresh `Circuit::<C1>::verify()` and `Circuit::<C2>::verify()` (lib.rs:938) per proof.
- `Circuit` stores every constraint as a `LinComb` (circuit-abstraction/src/lib.rs:81, `constraints: Vec<LinComb<F>>`; `constrain_equal_to_zero` just pushes it). A `LinComb` holds sparse `WL`, `WR`, `WO`, `WV: Vec<(usize, F)>` (40 B per term), plus `WCG: BTreeMap<usize, Vec<(usize, F)>>`.
- `ArithmeticCircuitStatement::verify` (generalized-bulletproofs/src/arithmetic_circuit_proof.rs:657) reads AI/AO/S, derives y and z, then only *folds* the constraints into dense weight vectors (`l_weights += z_q * WL_q`, etc.). So the circuit is materialized only to be folded into vectors of length n.
- Streaming accumulation (no stored constraints) would need y and z before circuit construction. But circuit construction itself interleaves with the transcript (per-input gadgets take `&mut transcript` and derive the dlog challenges lazily), and c2's y and z come after c1's full verification. So streaming needs a two-pass or reordered design (extra CPU, touches the proof transcript). Deferred (E007).
- 3.45 GB of the 4.99 GB peak was attributed to `RawVecInner::finish_grow` (Vec growth) in fcmp_pp_rust, which suggests a sizable share is Vec capacity slack from repeated `push` (doubling).
- Also noted: `ArithmeticCircuitStatement` zeroizes its constraints on drop (public verifier data). That is CPU only, not memory.

**Hypothesis:** shrinking each `LinComb`'s term vectors to their length when the constraint is stored removes the doubling slack. That should cut the per-thread working set (and the 24-thread peak) by roughly 15-35%, with no change to verification results or the transcript, at a small CPU cost (one realloc and copy per stored constraint).

**Change (one change only):**
- monero-oxide copy ~/work/monero-oxide-e005 (git, branch e005-lincomb-shrink, based on 31c26d96): `LinComb::shrink_to_fit()` (shrinks WL/WR/WO/WV and every WCG vector), called in `Circuit::constrain_equal_to_zero` before the push. Diff: evidence/E005_monero-oxide.diff.
- monero tree ~/work/monero-fcmp-e005 (branch e005-lincomb-shrink, based on beta.3.1 d80596ad1): `[patch."https://github.com/monero-oxide/monero-oxide"]` points generalized-bulletproofs and generalized-bulletproofs-circuit-abstraction at the local copy. Cargo.lock: only those two entries lose their git source (plus the lockfile format v3→v4 rewrite).
- The E001 fix is NOT included, so it stays a single-variable change vs beta31. Runs use `--block-sync-size 5` like the baseline arm.

**Measurement plan:** scripts/ab_window.sh, arms `base` (beta31) vs `e005`, default concurrency (24), window 3,105,401→3,105,441, 3 alternating rounds. Metrics: peak RssAnon, Private_Dirty, wall time, io, end hash vs .22.
**Prediction:** peak 5.4 GB → ~4.0-4.6 GB; wall time within ±5%.

**Results:** (pending)
