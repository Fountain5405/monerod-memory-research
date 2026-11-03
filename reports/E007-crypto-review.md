# E007 streaming verifier: independent security review (Fable-tier agent, 2026-11-03)

**Provenance:** at the owner's request, a separate Fable 5.1 agent (frugal:sage) with no prior involvement in E007 reviewed the change statically: the unmodified crates (monero-oxide 31c26d9), the modified crates (c215a80), the full diff, and monerod's FFI glue (`panic = "abort"`). It did not build or run tests (the control box must not build). The brief asked for soundness equivalence check by check, transcript discipline, fail-closed paths, the new panic/DoS surface, the memory claim, and test gaps. The author's notes were given last, as claims to verify. The report below is the agent's, unedited apart from this header. My follow-ups are listed at the end.

---

# E007 streaming FCMP++ verifier: independent security review

Paths below are relative to `e007/crypto/` unless prefixed `base/`. `acp.rs` = `generalized-bulletproofs/src/arithmetic_circuit_proof.rs`, `fcmps.rs` = `fcmps/src/lib.rs`, `ca.rs` = `fcmps/circuit-abstraction/src/lib.rs`. Static review only: no build, no test run (control box must not build).

## 1. Verdict

As written, the streaming path checks the same relation as the base verifier for every proof, honest or malformed: every weight the base folds (WL, WR, WO, each WCG_i, WV, c) is folded with the same z^(k+1) weight, every structural check in base `ArithmeticCircuitStatement::new` is reproduced in `ConstraintAccumulator::push`/`finish` in the same order and with the same error precedence, and the final MSM terms are identical up to the order of `verifier.additional` (irrelevant to the multiexp). I found no soundness bug, no path that returns Ok without a fully applied accumulator, and no new attacker-reachable panic. The build-twice design is sound because circuit construction is a pure function of (params, layers, inputs, commitments, transcript digest state) and I found no RNG, HashMap, interior-mutability or mode-dependent branch in the gadget/tape/param code. Deployable to an experimental node now; before upstream use, address the medium test gap (the FCMP-level "stored" comparator is no longer the base verifier) and consider the hardening in F3.

## 2. Findings (severity order)

**F1 (medium, test gap). The FCMP-level equivalence test does not compare against the base verifier.** `acp.rs:993-1007`: `ArithmeticCircuitStatement::verify` is now a wrapper `verify_transcript` + `fold_stored_constraints` + `apply`. `fcmps.rs:1208-1250` `verify_stored` calls that wrapper. So `tests.rs:866` and `:886` compare streaming vs the *refactored* path, not vs base. The only test against the genuine base code is `acp/tests.rs:277` using the verbatim copy `legacy_verify` (`:491-654`, confirmed identical to `base/acp.rs:657-820`) on random Ristretto instances (N=16, c<16, m<4, q<12). Fix: add a verbatim copy of base `Fcmp::verify` + base `ArithmeticCircuitStatement::verify` under `#[cfg(test)]` and run the 8 shapes + tampering against it, comparing `additional` as a multiset.

**F2 (low, robustness). `check_replay` proves count and challenge equality, not constraint equality.** `fcmps.rs:1064-1083`. Correct today because construction is deterministic (`fcmps.rs:997-1058` takes only `&FcmpParams`, `&[Input]`, `&Commitments`, a `Transcript` trait object exposing only `challenge`/`challenge_bytes` (`ca.rs:30-44`), and fresh circuits whose only gadget-visible state is `muls`). A future gadget that branches on circuit mode or stored constraints would not be caught if coefficients differed but counts did not. Hardening option: keep a running Blake2b of each pushed `LinComb` in both Discard and Accumulate modes and compare digests in `check_replay` (cost: one hash pass over constraint terms; could be `cfg(debug_assertions)`-only).

**F3 (low, API hazard). Public constructors allow folding the wrong constraints.** `ConstraintAccumulator::new` (`acp.rs:370`) and `FoldedStatement` (`:489`) are public; `apply` (`:1223-1238`) binds the fold to the proof only through `z`, `n`, `c`, `m`. Inside `Fcmp::verify` usage is correct (`fcmps.rs:1169-1197`). Suggest `#[doc(hidden)]`/`pub(crate)` for `ConstraintAccumulator::new` so the only production entry is `PendingVerification::accumulator`.

**F4 (note). Fail-closed poison is deterministic.** `acp.rs:1039-1046` adds `g += 1` on drop-without-apply. Sound (adversary cannot predict batch weights) and every such drop also returns `Err` (`fcmps.rs:1157-1197`, all `?`). A `corrupted: bool` on `BatchVerifier` would be clearer, but not required.

**F5 (note). Residual memory is O(c_full * n) folded CG weights, not O(q).** `acp.rs:359,387,436` grow each `cg_weights[i]` to highest index+1. Base computed one CG vector at a time (`base/acp.rs:779-797`) but held all q constraints. For 128 inputs the full-length "word" commitments dominate (~30 x n x 32 B per circuit); consistent with the notes' 65 MB figure. Discard mode (`ca.rs:246`) allocates nothing per constraint beyond the transient `LinComb` the gadget builds.

**F6 (note). CPU regression for small proofs.** Two circuit builds; notes' micro-benchmark shows +40-50% for 1-8 inputs. Not a security issue; mainnet-like txs pay it.

### Considered and found correct (Q1-Q3)
- Clone point: `fcmps.rs:1139` after prelude (commitments read, PoK challenge sampled), exactly where base built its circuits (`base/fcmps.rs:938`). `VerifierTranscript` clone copies digest + slice ref; building never reads bytes.
- z used for folding is `pending.z()` from the real transcript (`acp.rs:1088,1183,1216`); `apply` rejects a fold with a different z (`:1235`).
- z-power indexing: accumulator starts `next_weight = z` and multiplies after each push (`acp.rs:379,427,445`) = base `z^(k+1)` (`base/acp.rs:212-217,701`). Verified by `naive_fold` test (`acp/tests.rs:238-274,366-389`).
- RNG draws: unchanged order (PoK weight; per statement t-weight then steps-3/5 weight; IPA draws none).
- `x_ni` captured before scaling (`acp.rs:1113`), `weighted_x` after (`:1135,1187`); matches base `:729-735` vs `:757-802`.
- Error precedence in accumulator (`acp.rs:409-421`) matches base `new` (`base/acp.rs:143-158`); tested `acp/tests.rs:394-482`.
- Discard/Accumulate circuits cannot yield a statement (`ca.rs:284-288`); `Fcmp::verify` never calls `statement()`.
- Stored path reachability in production: `Circuit::verify` and `verify_stored` are `cfg(test)` (`fcmps/src/circuit.rs:61`, `fcmps.rs:1206`); FFI calls only `Fcmp::verify` (`ffi/src/lib.rs:1136`). The pub `ArithmeticCircuitStatement::verify` is itself the new path, so there is one verifier implementation.
- Prover untouched: GBP `prove`, `Fcmp::prove`, `Fcmp::input` byte-identical to base (diffed). No `unsafe` in the three crates. No timing change on secret data.

## 3. Check-by-check equivalence (base -> e007)
| Base check / term | Base loc | e007 loc | Same? |
|---|---|---|---|
| highest_a_index < n | acp:144 | acp:409 (push) | yes, same error |
| highest_c_index < c | acp:147 | acp:411 | yes |
| highest_v_index < m | acp:150 | acp:413 | yes |
| V individually constrained | acp:153-158 | acp:422-424, 455-457 (finish) | yes |
| C.len() < usize::MAX>>4 | acp:164 | acp:372 (acc) and 506 (FoldedStatement::new) | yes |
| g_bold/h_bold/h_sum resize | acp:663-667 | acp:1068-1072 | yes |
| read AI,AO,S; y,z | acp:679-683 | acp:1084-1088 | yes |
| y_inv powers | acp:205-206 | acp:1091-1092 | yes |
| z powers | acp:211-217 | acc next_weight | yes |
| T reads, x powers | acp:688-696 | acp:1095-1104 | yes |
| WL/WR/WO fold | acp:701-705 | acp:428-430 | yes |
| r_weights*y_inv, delta | acp:706-708 | acp:1259-1261 | yes |
| tau_x, mu, t_caret | acp:710-712 | acp:1106-1108 | yes |
| weight1: g+=t_caret, h+=tau_x | acp:719-720 | acp:1117-1118 | yes |
| g -= w*x[ni]*(delta - <z,c>) | acp:728-730 | acp:1271 (c_sum acp:442) | yes |
| WV fold * x[ni], push V | acp:731-743 | acp:441, 1272-1280 | yes (order differs, m=0 for FCMP) |
| T pushes | acp:744-749 | acp:1122-1127 | yes |
| weight2, x*=w | acp:754-757 | acp:1132-1135 | yes |
| AI/AO/S pushes, h_sum | acp:761-769 | acp:1139-1147 | yes |
| h_bold_scalars l*x[ilr], g_bold += r*x[ilr], + o*x[jo] | acp:773-777 | acp:1289-1293 | yes |
| per-C: WCG fold, push (x[j],C), += WCG*x[i] | acp:779-797 | acp:431-440, 1154-1159, 1296-1302 | yes (CG truncated; elided entries zero) |
| *y_inv, h_bold += | acp:800-803 | acp:1305-1308 | yes |
| h -= w*mu | acp:806 | acp:1162 | yes |
| ip_x, g += w*ip_x*t_caret, IPA | acp:811-819 | acp:1167-1175 | yes |
| (new) dims/z consistency | - | acp:1228-1238 | extra |
| (new) replay counts + transcript | - | fcmps:1064-1083, 1189-1193 | extra |

## 4. New panic surface (added by diff, proof-reachable)
| Site | Trigger by attacker? | Why |
|---|---|---|
| acp:1091 `y.invert().expect` | no | same as base 205; challenge asserts nonzero |
| acp:1113,1123,1126,1158 `x[..]` | no | indices < t_poly_len, as base |
| acp:1143 `while (1<<log2_n)!=n` | no | n from ipa_rows pow2, as base |
| acp:1146 `h_sum[log2_n]`, 1155 `C.0[i]` | no | resized / i<c |
| acp:423 `individually_constrained[..]` | no | guarded by 413 |
| acp:432 `cg_weights[*i]` | no | guarded by 411 |
| acp:428-441 `accumulate_vector` indexing | no | guarded by 409/413 (highest_a_index covers WCG j) |
| acp:436 `hi+1` | no | hi<n |
| acp:1291,1307 `g_bold[i]`,`h_bold[i]` | no | verifier held by &mut, resized at 1068; lengths checked 1228-1234 |
| acp:1259,1293 ScalarVector debug_asserts | no | lengths checked at 1228-1234 |
| fcmps:881 `c1_branches.len()-inputs` (now run twice) | no | same as base 866 |
| ca:243 counter | no | - |
Base-inherited panics (`input()` unwraps at fcmps:408/481/508, `root[0]` match at 947-957, `ipa_rows` overflow) are unchanged and not attacker-reachable via proof bytes.

## 5. Test gaps and proposed tests
1. (F1) `test_streaming_matches_BASE`: verbatim base `Fcmp::verify` + base AC verify under cfg(test); 8 shapes; honest + tampered; multiset compare of `additional`.
2. FCMP differential fuzz: for each shape, 32 random single-byte mutations anywhere in the proof (current test only hits chosen regions: first/last T, first L/last R), plus: swap two inputs, mutate one `Input` coordinate, pass `layers+-1`, pass the other curve's root. Assert `verify` and `verify_stored` agree on Ok/Err and verifier state, and that batch verify fails.
3. Replay-divergence injection: `#[cfg(test)]` hook in `build_verifier_circuits` (e.g. `static TEST_EXTRA_CHALLENGE: AtomicBool`) applied only on the second build; assert `Fcmp::verify` returns `InconsistentCircuitReplay` and both verifiers fail `verify()`. Same for an injected out-of-range constraint -> `AcStatementError` and poisoned verifier.
4. `apply` with wrong `m` (current `test_pending_verification_fails_closed` covers n, c, z only).
5. GBP: run the folded path (`verify_transcript` + accumulator + `apply`) on the 8 malleated proofs too (`acp/tests.rs:309-330` runs only legacy vs wrapper).
6. Property: accumulator with duplicate `(j,w)` entries for one commitment in one constraint (from `LinComb + LinComb`) equals naive fold.

## 6. Claims in E007-notes.md
- "streaming vs stored: bit-identical BatchVerifier states" (L37): true, but "stored" is the refactored path, not base (F1).
- "The old flow is kept as verify_stored" (L30) / "old stored path kept for tests": only the FCMP-level driver is kept; the base AC verifier survives only as `legacy_verify` in GBP tests.
- "2x faster ... O(c*q) fold removed" (L100): mechanism is real (`base/acp.rs:779-785` c passes over q constraints with a BTreeMap lookup each); timings not verifiable here.
- "-73% peak heap", negtest 24/24, A/B numbers: not verifiable from the bundle.
- "accumulate_vector indexes without bounds checks" (L11): it is bounds-checked (Vec index panic), so the per-constraint checks prevent a panic, not UB. Conclusion unchanged.
- "Every error path either returns Err or poisons" (L63): both, in all paths traced.
- All other mechanical claims (clone point, RNG order, x_ni capture, CG truncation safety) confirmed.

---

## Follow-ups (optimizer, 2026-11-03)
- **F1 (medium, test gap): CLOSED by E016 (2026-11-03 19:38, experiments/E016-base-equivalence, patch 0002 of the v1 series): verbatim copies of the 31c26d9 `Fcmp::verify` and `ArithmeticCircuitStatement::verify` under test, compared with the streaming path on the 8 shapes (honest), all tampering regions and 256 random single-byte mutations; identical verifier states (`additional` as a multiset) and identical errors.** The plan was: A verbatim copy of the base `Fcmp::verify` and base `ArithmeticCircuitStatement::verify` under `#[cfg(test)]`, run against the streaming path on the 8 shapes with honest and tampered proofs, comparing the batch-verifier state (with `additional` as a multiset). Plus the proposed FCMP-level differential fuzz (random single-byte mutations anywhere in the proof, input swaps, wrong layer count, wrong root). Queued behind E014, since compiling on hydrogen would disturb its timing runs.
- **F2, F3 (low):** recorded as upstream recommendations (constraint digest in `check_replay`; `pub(crate)` for `ConstraintAccumulator::new`). Not applied to the research build, to avoid re-validating a behaviour-neutral change.
- The notes' claim "stored path kept for tests" is corrected in E007's README: only the FCMP-level driver was kept; the base AC verifier survives as `legacy_verify` in the GBP tests.
