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

**Implementation result (agent finished 2026-11-03 ~00:20):**
- monero-oxide-e007 branch `e007-streaming-verify` at c215a805a (on 31c26d96): 7 files, +2186/-134, of which 1,182 lines are tests. monero-fcmp-e007 branch `e007-streaming-verify` at bfd179a6a: a cargo `[patch]` pointing generalized-bulletproofs, circuit-abstraction, fcmps, ec-gadgets and ec-divisors at the local tree; the Cargo.lock change is only the format bump and the dropped git `source` lines. Diff: evidence/E007_monero-oxide.diff.
- Design as built:
  - `VerifierTranscript: Clone`.
  - GBP gets `ConstraintAccumulator`, which folds each constraint with z^(k+1) as it arrives and runs the same per-constraint checks as `ArithmeticCircuitStatement::new` (bounds, then "individually constrained"). It latches the first error.
  - `verify` is split into `FoldedStatement::verify_transcript` (all transcript reads, including the IPA, plus every constraint-independent BatchVerifier term), which returns a `PendingVerification`, and `PendingVerification::apply(FoldedConstraints)`. The old `verify` is now a wrapper that folds the stored constraints.
  - `Circuit` gets Store/Discard/Accumulate modes; `statement()` on a non-Store circuit returns `ConstraintsNotStored`.
  - `Fcmp::verify` clones the transcript after the prelude (commitments read, root-blind PoK checked), then runs build A (Discard) on the real transcript, snapshots it, runs the c1 and c2 transcript phases, and runs build B (Accumulate, z from the real transcript) on the clone. It then checks mul/constraint counts and transcript state are equal, and that the folded q equals build A's constraint count, before both applies.
  - The old flow is kept as `#[cfg(test)] verify_stored`.
- Extra safety the agent added: dropping a `PendingVerification` without a successful `apply` poisons its BatchVerifier (`g += 1`). A forgotten `apply` would otherwise check the proof against an empty, trivially satisfiable constraint set.
- CG weights are truncated to the highest referenced index + 1, as `prove` already did; old `verify` kept them dense at n. l/r/o stay at length n.
- Tests (logs in ~/work/e007-logs/; spot-checked by me):
  - Full run: fcmps 11/11 including `test_malleated_proofs` (2,673 s), GBP 6/6, GBP integration 3/3.
  - Final re-run after a cfg-only change, `--skip prove_benchmark`: fcmps 10/10, GBP 6/6, integration 3/3.
  - New tests:
    - streaming vs stored: bit-identical BatchVerifier states, with the same RNG, over 8 input/layer shapes, on valid and tampered proofs.
    - tampered regions rejected: commitments, AI/AO/S, first/last T, tau_x/mu/t_caret, first L/last R, a/b, root-blind PoK. Each is tested with a valid replacement element and with a bit flip.
    - accumulator equals stored folding, on GBP and on real FCMP circuits.
    - Discard/Accumulate circuits cannot produce statements.
    - the replay check detects divergence.
    - an un-applied PendingVerification fails closed.
- Agent micro-measurement: counting allocator, verify call only, 15 interleaved runs, governor not pinned.

| inputs, layers | streaming time | stored time | streaming peak heap | stored peak heap |
|---|---|---|---|---|
| 1, 8 | 8.0 ms | 5.7 ms | 0.53 MB | 1.97 MB |
| 2, 8 | 13.6 ms | 9.3 ms | 1.05 MB | 3.93 MB |
| 8, 8 | 47.4 ms | 31.8 ms | 4.1 MB | 15.7 MB |

  Peak heap is about -73%. The verify call costs +40-50% CPU, because both builds are paid for. Note: the 52% hotspot in E006 is the folding, and folding is not duplicated, so the extra cost should be closer to "one more circuit build". The macro A/B decides the wall-time question.

**My review (2026-11-03 00:25, diff read in full apart from the tests):**
- Transcript and RNG order are unchanged:
  - prelude → build A (real transcript) → c1 AI/AO/S, y, z, T, x, tau_x/mu/t_caret, ip_x, IPA → the same for c2.
  - RNG draws are two per statement, at the same points: the t-check weight, then the steps-3/5 weight that scales x.
  - `x_ni` is captured before x is scaled; `weighted_x` after, matching the old code's use of unscaled x[ni] in step 4 and scaled x elsewhere.
- Soundness:
  - z comes only from the real transcript; `apply` rejects folded constraints whose z, n, c, m, or vector lengths don't match.
  - Build B starts from a clone taken at exactly the point where build A starts.
  - Building never reads proof bytes, since `Self::input` only gets the `Transcript` trait. So both builds see the same challenges, and determinism is checked anyway (counts plus transcript state).
  - A Discard/Accumulate circuit cannot yield a statement.
  - Every error path either returns Err (and the FFI maps Err to false) or poisons the verifier.
  - The BatchVerifier updates moved into `apply` are all additive. Their order inside `additional` does not matter for the multiexp, and the tests show bit-identical states.
- CG truncation is safe: the elided entries are exactly zero, and `apply` zips the shorter vector into the length-n h_bold scalars and rejects any cg longer than n.
- Non-issues noted:
  - The specific error kind for invalid proofs can differ. It is still a rejection.
  - `statement()` has a new error type. Nothing in the workspace or the FFI matches on it.
  - The `FoldedStatement` API could be misused by a future caller that folds the wrong constraints; the doc comment says so. Inside `Fcmp::verify` it is used correctly.
- Verdict: **OK for an experimental monerod build.** This is not an audit. Upstream use would need independent cryptographic review.

**Why E007 should matter on this workload (2026-11-03 00:27, scripts/window_inputs.py, read-only RPC to .22):**
- The A/B window 3,105,401..3,105,440 has 1,044 txs with 109,408 inputs: 851 txs with 128 inputs, 15 with 8, 2 with 4, and 176 with 2. Mean 104.8 inputs per tx.
- One FCMP++ proof covers all of a tx's inputs. At about 2 MB of stored constraints per input (agent measurement), a 128-input proof stores roughly 250 MB, which matches the ~150-200 MB per verifier thread seen in E002b/E003/E004a. Streaming would bring that to about 65 MB.
- Caveat for the report: stressnet's window is dominated by 128-input (max-size) txs. Mainnet-like 1-2-input txs keep only a few MB per thread. The peak here is therefore a worst-case / adversarial-block measurement, which is still the number that sets the RAM a node must have.

**Results (monerod window A/B):** queued as chain e007 (scripts/chain_build_ab.sh v2, waits for CHAIN_E004E_COMPLETE).
