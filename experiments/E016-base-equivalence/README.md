# E016: base-equivalence test for the v1 streaming verifier (closes the crypto review's F1)

**Why:** reports/E007-crypto-review.md, finding F1 (medium, test gap): the E007 equivalence tests compare the streaming path with `Fcmp::verify_stored`, which runs through the *refactored* `ArithmeticCircuitStatement::verify` (a wrapper over `verify_transcript` + `fold_stored_constraints` + `apply`), not through the verifier as it was before the change. So a mistake shared by both paths would pass. The review asked for a verbatim copy of the base verifiers under test and a comparison against them, plus a differential fuzz with random byte mutations. E018 decided that v1 stays the recommended series, so this became necessary (v2/E017 has it by construction, since its `verify` is the unchanged stock one).

**What was built** (hydrogen, 2026-11-03 18:50-19:1x, branch `e016-base-equivalence` on `~/work/monero-oxide-e007`, one commit on top of c215a80; patch in patches/v1-E007-full-streaming/monero-oxide/0002-E016-test-the-streaming-verifier-against-verbatim-co.patch):
- `ArithmeticCircuitStatement::verify_base` in generalized-bulletproofs: the 164-line body of `verify` at monero-oxide 31c26d9 (the commit the E007 branch is based on, "Incorporate zkSecurity's audit"), copied verbatim from `git show 31c26d9:...` by script, renamed, behind the crate's existing `tests` feature (which fcmps already enables for its dev-dependency). It compiled unchanged against the E007 tree: every helper it uses (`yz_challenges`, `accumulate_vector`, `IpStatement`, the struct fields) is still there with the same meaning.
- `Fcmp::verify_base` in fcmps: the 227-line body of `Fcmp::verify` at 31c26d9, copied verbatim the same way, renamed, under `#[cfg(test)]`, with its two `c?_statement.verify(` calls redirected to `verify_base`. Also compiled unchanged: the tape, branch and gadget calls of the base verifier are the same code E007 uses.
- Tests (crypto/fcmps/src/tests.rs, +285/-54 of which 54 are the move of the tampering-region computation into a shared `tampering_regions` helper, so the existing test and the new one use the same offsets):
  - `test_streaming_verify_matches_base`: 8 (inputs, layers) shapes (1,1) (1,2) (1,3) (1,5) (2,1) (2,4) (3,2) (3,3), honest proofs, the same deterministic RNG fed to both verifiers: both accept, the two batch verifiers are equal field by field (`g`, `h`, `g_bold`, `h_bold`, `h_sum` exactly; `additional` as a multiset of (scalar, point) so the order terms were pushed in does not matter), and both batches verify.
  - `test_streaming_verify_matches_base_on_tampered_proofs`: shapes (2,3) and (1,2); for every region of the serialized proof (vector commitments, AI, AO, S, first and last T, tau_x, mu, t_caret, first L and last R, a, b, for both circuits, and the root-blind PoK) two tamperings: replace the element with another valid one, and flip one bit. Both verifiers must return the same `Ok`/`Err`, **the same error (Debug representation compared)**, equal verifier states when `Ok`, and the batch must not verify.
  - `test_streaming_verify_matches_base_under_random_mutation`: shapes (2,3) and (1,2), 128 random single-byte XOR mutations each at a uniformly random offset anywhere in the proof; the same four assertions.

## Result: all PASS (release build, 148 s for the three)

| test | cases | outcome |
|---|---|---|
| matches_base | 8 shapes, honest | identical verifier states, all verify |
| matches_base_on_tampered_proofs | 2 shapes x 23-27 regions x 2 tamperings | identical Ok/Err and error, identical states, none verify |
| matches_base_under_random_mutation | 256 mutations (68 + 62 still well-formed, the rest rejected at parse) | identical Ok/Err and error, identical states, none verify |

The full fcmps suite and the generalized-bulletproofs suite (with the `tests` feature) pass with the change: fcmps 14/14 (release, 2,625 s including the benchmarks), generalized-bulletproofs 9/9 with the tests feature, clippy clean except one warning that predates E016 (InconsistentWitness never constructed).

## What it says
1. **The streaming verifier is equivalent to the verifier that shipped at 31c26d9, not just to its own refactoring.** On every honest and tampered proof tried, the base verifier and the streaming verifier leave the batch verifier in the same state, so the final multiexp checks the same equation. This is the test the review asked for.
2. **Error behaviour is identical too**, which the review did not ask for: on the ~640 malformed proofs, both return the same error variant. The streaming path's extra error (`InconsistentCircuitReplay`) never fired, as expected: it guards against the two builds disagreeing, which byte tampering cannot cause.
3. **The copies are verbatim by construction.** They were extracted by line range from `git show 31c26d9:<file>` and only the function names (and the two inner `verify` calls) were changed; a reviewer can re-derive them with `diff <(git show 31c26d9:crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs | sed -n 657,820p) <(...)`. The patch keeps them test-only (`#[cfg(test)]` / feature `tests`), so nothing reaches a release binary.
4. **Limits.** Shapes are at most 3 inputs and 5 layers (the test helper's `random_paths` limit), so 128-input proofs are covered only by the node-level differential test (E015/E018 negdiff, 236 cases, base binary as the oracle). Equivalence is shown by testing, not proved; the review's other items (external cryptographic review) are untouched by this.

## Guardrails
- One change per experiment: tests only; no verifier code changed (`git diff --stat` on the patch: lib.rs and arithmetic_circuit_proof.rs gain test-only functions, tests.rs gains tests and one helper move).
- Both crates' full suites pass; clippy clean on the test build.
