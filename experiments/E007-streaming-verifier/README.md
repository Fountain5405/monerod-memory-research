# E007: streaming FCMP++ verifier (fold constraints as they are built; don't store the circuit)

**Motivation:** E002b/E003/E005 show the per-verifier working set (~200 MB) is the stored circuit (`Vec<LinComb>`, two constraints per mul gate, plus the divisor WCG constraints). `ArithmeticCircuitStatement::verify` only uses those constraints as z-power-weighted sums. E006: circuit construction costs only ~5% of CPU; folding and verification ~52%.

## Feasibility review (Plan agent, 2026-11-02 23:00; line numbers from monero-oxide @ 31c26d96)
Verdict: **FEASIBLE WITH CHANGES.**
- `VerifierTranscript` = { Blake2b512 digest, `&[u8]` cursor } (generalized-bulletproofs/src/transcript.rs:134-137). Not `Clone` today, but trivially cloneable. `challenge()` finalizes a clone of the digest, so challenges depend only on the hash state.
- Circuit building only calls `challenge`/`challenge_bytes` (circuit-abstraction `Transcript` trait, L30-43). It never reads proof bytes, so a replay on a clone reproduces identical challenges. Lazy dlog challenges are locals, recomputed at the same point on replay (input 0).
- Transcript order in `Fcmp::verify`: new(L884) → read C1/C2 commitments (L888-889) → root-blind PoK challenge (L911/924) → per input: discrete_log challenges (challenge_bytes + sqrt-retry loops), 6 challenges per tuple_member_of_list, lazy additional-layer challenges → c1 statement verify (AI, AO, S → y, z → T → x → tau_x, mu, t_caret → ip_x → IPA rounds) → c2 statement verify.
- Constraint contents are deterministic (challenges, public inputs, params, commitments; no RNG; WCG is a BTreeMap). Building never reads stored constraints (`eval` is prover-only; `muls` is a counter).
- `ArithmeticCircuitStatement::new` validation (index bounds vs n/c/m, V "individually constrained", the C.len bound) can be done per constraint. It is **mandatory**: `accumulate_vector` indexes without bounds checks.
- In `verify`, all uses of constraints (l/r/o weights, the `<z,c>` sum, V weights, per-commitment CG weights: c+3 full passes today) are z-weighted sums in push order. **No transcript op after (y, z) depends on the folded weights, and every BatchVerifier update is additive.** So each statement's verify splits into a transcript phase and an apply phase.
- That gives a **2-build plan** (better than the 3-pass sketch): build A (Discard) on the real transcript → c1 and c2 transcript phases (z1, z2) → build B on a clone, folding c1 with z1 and c2 with z2 together → apply. Extra cost: one construction pass (~+5% CPU). The folding itself may get cheaper (one cache-hot pass instead of c+3 passes over ~200 MB).
- Risks and guards: a Discard/Accumulate circuit must never yield a statement (it would verify vacuously); z must come from the real transcript; determinism guards (mul/constraint counts equal between builds; replay transcript state equals real state); bounds checks returning errors, not panics; the prover path and existing tests must keep using stored mode. Proof format unchanged.
- Size: ~300-400 lines in 5 files / 3 crates (transcript.rs, arithmetic_circuit_proof.rs, circuit-abstraction lib.rs, fcmps lib.rs and circuit.rs). Fallback if this proves too risky: a compact arena of `(u32, F)` terms plus canonicalized LinCombs (constant-factor saving only).

## Implementation (delegated to an agent, started 23:05)
Spec: ~/work/monero-oxide-e007 (branch e007-streaming-verify) + ~/work/monero-fcmp-e007 (cargo [patch]). Required tests: existing crate tests (incl. byte malleation), streaming-vs-stored equivalence on valid proofs, rejection of tampered proofs (commitments, AI/AO/S, T, IPA) on both paths, accumulator-vs-stored folded-weights equality, and the Discard-cannot-make-statement guard.

**Then:** my own review of the diff → build monerod → window A/B vs base (3 rounds; peak RSS, wall, end hash) → min_mem test.

**Results:** (pending)
