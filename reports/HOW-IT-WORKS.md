# How the memory reduction works (technical)

Companion to reports/SUMMARY.md. Plain-language version: reports/HOW-IT-WORKS-plain.md. Evidence for every number is under `experiments/` and `evidence/`.

## 1. Where the memory went

### 1.1 The workload
In FCMP++ every transaction carries **one** membership proof covering all of its inputs. monerod verifies the proofs of a block in `rct::batchVerifyFcmpPpProofs` (`src/ringct/rctSigs.cpp`): it sorts the proofs by input count, bin-packs them into one batch per thread-pool thread (24 on a 12-core/24-thread machine), and each thread calls the Rust crate `fcmps` (monero-oxide) to batch-verify its proofs. Stressnet blocks are full of 128-input transactions, the maximum, so 24 threads each verify 128-input proofs at the same time.

### 1.2 What a verification holds in memory
An FCMP++ proof is a **Generalized Bulletproof**: an arithmetic-circuit proof over two curves (the Selene and Helios circuits, called c1 and c2). To verify it, the verifier has to know the circuit:
- `n` multiplication gates with wires `aL`, `aR`, `aO`;
- `m` Pedersen commitments `V` and `c` vector commitments `C_i` (these scale with inputs × tree layers);
- `q` linear constraints. Each is a `LinComb`: sparse weight vectors `WL`, `WR`, `WO` over the gate wires, `WV` over `V`, one `WCG_i` per vector commitment, and a constant.

The circuit is built by running the gadget code (tree-membership, discrete-log and divisor gadgets) with the Fiat-Shamir transcript as the only input. For a 128-input proof that is millions of constraints, roughly two per multiplication gate plus the divisor constraints.

The stock verifier (`ArithmeticCircuitStatement::new` / `verify`, `generalized-bulletproofs/src/arithmetic_circuit_proof.rs`) **stores the whole circuit** as `Vec<LinComb>` before verifying: about 2 MB per input, so **~250 MB for a 128-input proof**. Heaptrack attributed ~87% of the peak to this (E002b). With 24 threads holding one each, that is the ~5.4-5.6 GB peak. The peak scaled almost linearly with thread count (E003: 1 / 4 / 12 / 24 threads → 1.23 / 2.03 / 3.30 / 5.40 GB).

### 1.3 Why it never came back
After each batch the circuits are freed, but RSS stayed at ~4.8 GB on an idle node. glibc malloc keeps freed memory in **per-thread arenas** for reuse: freed chunks go back to the arena's free lists, and only a large free region at the very top of a heap is returned to the kernel automatically. A 250 MB working set made of millions of small `LinComb` allocations fragments the arena, so almost nothing is trimmed. Each of the 24 pool threads therefore keeps its own high-water mark forever (E004c/E004d: capping the number of batches or arenas did not help, because two threads sharing an arena both peak inside it).

### 1.4 Why it was also slow
The stock `verify` folds the constraints into per-wire weights by `z`-powers in several passes, and for the vector commitments it does **one full pass over all `q` constraints per commitment** (`arithmetic_circuit_proof.rs:779-783` in monero-oxide 31c26d9): O(c·q), quadratic in the input count. That pass was ~52% of all sync CPU on this workload (E006).

## 2. The three fixes

### 2.1 Fix 3, the big one: a streaming verifier (E007, ~1,000 lines in monero-oxide)
**Observation.** `verify` never uses the constraints individually. It only uses the **z-weighted sums** of them: for constraint `k`, every weight is multiplied by `z^(k+1)` and added into running vectors (`l`, `r`, `o` of length `n`; `v` of length `m`; one `cg_i` per vector commitment; a scalar for the constants). Those folded vectors are what enter the final multi-scalar multiplication. And the circuit is a **deterministic function of the transcript state before `z`** (plus public parameters and the commitments): building it only ever calls `challenge()`/`challenge_bytes()`, never reads proof bytes, uses no RNG, and its `WCG` maps are ordered (BTreeMap).

So the circuit does not need to exist in memory at the moment `z` is known. It can be rebuilt and folded on the fly.

**Design as built** (`fcmps/src/lib.rs` `Fcmp::verify`, `circuit-abstraction` `Circuit` modes, `generalized-bulletproofs` `ConstraintAccumulator` / `FoldedStatement` / `PendingVerification`):
1. Read the commitments and check the root-blind proof of knowledge as before (the "prelude"). **Clone the transcript** at this point.
2. **Build A, `Discard` mode, on the real transcript.** The gadgets run exactly as before and push every constraint, but the circuit keeps only counters (gates, constraints pushed), not the `LinComb`s. This advances the transcript to the same state the stored verifier would reach.
3. Run the **transcript phase** of both statements (`FoldedStatement::verify_transcript`): read `AI, AO, S`, derive `y, z`, read `T`, derive `x`, read `tau_x, mu, t_caret`, run the inner-product-argument rounds. Every batch-verifier term that does not depend on the constraints is added now. This returns a `PendingVerification` per circuit, and gives `z1` and `z2`.
4. **Build B, `Accumulate` mode, on the clone.** The same gadget code runs again from the same transcript state, so it emits the same constraints in the same order. Each constraint `k` is immediately multiplied by `z^(k+1)` and added into the folded vectors; nothing is kept. The accumulator performs the same per-constraint validity checks that `ArithmeticCircuitStatement::new` performed on the stored circuit (index bounds against `n`, `c`, `m`; "each `V` individually constrained"), and latches the first error.
5. **Replay check** (`check_replay`): build A and build B must agree on the multiplication count and the constraint count of both circuits, and the real and cloned transcripts must produce the same challenge bytes. Then the folded `q` must equal build A's constraint count. Any mismatch is `InconsistentCircuitReplay`, a rejection.
6. **Apply** the folded vectors to the pending verifications (`PendingVerification::apply`), which adds the constraint-dependent terms to the batch verifier. The batch verifier then does its one multiexp over all proofs, as before.

Memory per verification drops from O(total constraint terms) stored as millions of small heap objects to O(`n + m + Σ|cg_i|`) scalars in a handful of vectors. In the crate micro-benchmark peak heap fell ~73%; at the node level E007 alone gave -59% peak (5,582 → 2,291 MB).

**CPU.** The circuit is built twice, which costs about one extra construction pass (construction was ~5% of CPU). The quadratic O(c·q) fold is gone: the accumulator touches each constraint's own `WCG` entries once. On 128-input proofs this nets out to **2x faster**; on 2-input proofs, where the old fold was cheap, it is ~3% slower (E011).

**Fail-closed properties built in:**
- A `Discard` or `Accumulate` circuit cannot produce a statement (`ConstraintsNotStored`), so nothing can verify against an empty constraint set.
- `z` only ever comes from the real transcript; `apply` rejects folded constraints whose `z`, `n`, `c`, `m` or vector lengths do not match the pending verification.
- Dropping a `PendingVerification` without a successful `apply` poisons its batch verifier, so a forgotten apply fails verification instead of passing it.
- Every error path returns `Err`, which the FFI maps to `false`; the proof format is unchanged; the old stored path is kept under `#[cfg(test)]`.

**How we know it checks the same thing.** New crate tests build real FCMP proofs and assert the streaming path and a **verbatim copy of the verifier before the change** (31c26d9, kept under test only) leave the batch verifier in a **field-by-field identical state**, with the same error on every malformed proof, on valid, tampered and randomly mutated proofs, for 8 input/layer shapes (E016; the first tests compared against the refactored stored path, which the crypto review flagged as F1); the accumulator's folded weights equal the stored fold; tampered proof regions are rejected on both paths. At the node level, 236 tampered/swapped/original transactions produced identical accept/reject decisions and flags on the stock and new binaries (E015). This is evidence of equivalence, not a proof; the change has not been audited by cryptographers.

### 2.1b The same fix in a third of the code: pre-fold into one constraint (E017, "v2", ~500 lines, 25 of them in the audited verifier)
The owner asked whether Fix 3 could be smaller. It can, by pushing the observation in 2.1 one step further.

**Observation sharpened.** Look at what the stock `verify` does with the `q` stored constraints: it weights constraint `k` by `z^(k+1)` and sums (`arithmetic_circuit_proof.rs:211-217`, "powers of z starting with z^1"). It derives `z` from the transcript right after reading the commitments `AI, AO, S` (`:679-683`), and it **never hashes the constraints, or `q`, into the transcript**; the statement is bound to the proof by fcmps' own transcript, outside `verify`. So the verifier cannot tell how many constraints it was given, only their weighted sum. If it is handed a **single** constraint

    L = Σ_k z^k · c_k        (k from 0)

it computes `z · L = Σ_k z^(k+1) · c_k`, which is exactly the combination it would have computed from the `q` stored constraints. One line of algebra.

**Design as built** (branch `e017-folded-verify`, patches/v2-E017-minimal). The audited `ArithmeticCircuitStatement::new` / `verify` are left **byte-for-byte unchanged**; what changes is only what fcmps feeds them:
1. Clone the transcript at the start of circuit construction.
2. **Build A, `Discard` mode**, on the real transcript (as in v1), to advance it to the state where the c1 proof's `AI, AO, S` are read.
3. **Peek `z1`** on a clone: read `AI, AO, S`, draw `y, z`, throw the clone away (`peek_z`, the only addition to generalized-bulletproofs: `#[derive(Clone)]` on `VerifierTranscript` plus this helper, +25 lines, nothing removed).
4. **Build B, `Fold` mode for c1** (c2 discarded), from the cloned start state: each c1 constraint `k` is multiplied by `z1^k` and added into dense accumulators (`aL`, `aR`, `aO` weights, one vector per vector commitment, a constant), then forgotten. At the end one `LinComb` is assembled through the public `LinComb::term` / `constant` API and passed to the **unchanged** `new` as a one-element constraint list; the unchanged `verify` runs on the real transcript.
5. Peek `z2` the same way, **build C, `Fold` mode for c2**, verify c2 with the unchanged code.
6. Consistency checks: multiplication and constraint counts equal across A, B and C, and the clones' challenge bytes equal the real transcript's; any mismatch is a rejection.

**Why the diff shrinks.** v1 moved the folding *inside* the verifier: it split `verify` into a transcript phase and an apply phase, added `ConstraintAccumulator`, `FoldedStatement`, `PendingVerification` and the Drop-poison, and re-implemented the fold the stored path used to do. That is +1,004/-134 code lines, **+570 of them inside the audited verifier**, plus +1,182 lines of tests. v2 keeps the folding *outside*: the accumulator lives in the circuit-abstraction crate (one ~40-line function that sums weights), fcmps gains the three builds and the checks (much of its diff is a refactor that turns the layout computation and circuit construction into functions, pure motion under `git diff --color-moved`), and the verifier gains a `Clone` derive and a peek. Totals: **+513/-88 code lines** (generalized-bulletproofs +25 additive, circuit-abstraction +171/-6, fcmps +370/-82 of which 92/33 is the refactor), tests +228 plus a benchmark. What a reviewer has to check also shrinks to four items: the one-line identity; that the ~40-line fold accumulator sums weights correctly (testable against the stored constraints directly); that the three builds see the same transcript (determinism, the same argument as v1, plus the equality checks); and that `new`'s structural checks on one folded constraint are as good as on `q` (for FCMP there are no Pedersen commitments, so the "each `V` individually constrained" check is vacuous, and the index bounds come from our own gadget code, not from proof bytes). And the equivalence tests can target the genuine stock verifier, because it is unchanged: `Fcmp::verify` (folded) against `Fcmp::verify_stored` (the stored circuit through the untouched `verify`), field-by-field identical batch-verifier state on 8 shapes, honest and tampered, and a differential negative test identical to base at the node (236 cases, E018).

**What it buys and what it costs (measured, E017/E018/E019).** Memory: per proof -80% heap vs stock in the crate benchmark, about 25% below v1 (the stock verifier processes the folded weights one commitment at a time, v1 keeps all folded vectors live until apply); at the node the heavy-window peak is within 3% of v1 on hydrogen and 7% below it on box81, and the idle footprint is lower on both. CPU: three circuit constructions instead of two. With the quadratic fold gone, construction is the dominant cost of a verification, so the third pass is about +50% over v1 (the crate benchmark shows it: stock 1x, v1 1.5x, v2 2.1x per proof). At the node, heavy blocks verify 43% (hydrogen) / 57% (box81) slower than with v1, still 29% / 10% faster than stock; ordinary small-tx blocks are 12% / 17% slower than stock, against v1's 6% / 5%. So v2 delivers the memory reduction and part of the speed-up, with the audited verifier untouched and about a third of the code; v1 delivers all of the speed-up with the larger, intrusive diff. The report recommends v1 on the measurements and keeps v2 as the alternative when diff size against audited code matters more than speed. A follow-up that removes the third build was then built and measured (E020, patch 0003 of the v2 series, +57 additive lines in generalized-bulletproofs and 26/26 in fcmps): the stock verifier's transcript operations depend only on the statement's size, so a clone of the transcript can be skipped past the first proof and `z2` peeked from it before either proof is verified; one fold rebuild then folds c1 and c2 together, and after the first proof's real verification the real transcript is checked to have arrived where the skip did. At the node this removes about 40% of v2's heavy-block wall gap to v1 (+28% instead of +46% over v1 on hydrogen, still 37% under stock) and most of its small-block cost (+3% over v1, +8% over stock, where e017 was +8% / +13%), at the same memory (heavy peak +1% vs v1, idle lowest of the three). The rest of the gap has not been profiled. v1 remains the recommended build; the v2 alternative is now the three-patch series.

### 2.2 Fix 1: cap concurrent heavy verifications at physical cores (E004c, E012)
Verification is pure field and curve arithmetic. On big proofs the two SMT siblings of a core fight over the same execution units and cache, so 24 concurrent batches were **slower** than 12 (-9% wall with the cap) while doubling peak memory. The cap limits the number of batches to `boost::thread::physical_concurrency()`. On small proofs, though, SMT does help (+7% wall with the cap, E011), so the final build applies the cap only when the largest proof in the call has ≥ 8 inputs (E022 moved this from 16: about -30% CPU and +3-4% wall on 8-input blocks). About 5 lines in `batchVerifyFcmpPpProofs`.

### 2.3 Fix 2: return freed memory to the kernel (E004e, E012)
After a heavy batch-verify call, `malloc_trim(0)` walks every arena and releases whole free pages back to the kernel (`madvise(MADV_DONTNEED)`), which the automatic top-of-heap trimming never does for fragmented arenas. This is what brings idle memory down from ~4.8 GB to ~1 GB, and it also lowers the peak, because memory freed by one block is no longer still resident when the next block's verifications start. A trim costs ~9 ms, so the final build trims after every heavy call and otherwise at most once every 10 s. glibc only (`#if defined(__GLIBC__)`). About 15 lines.

One gap remained: those trims run only inside a verify call, so after the last call of a sync burst whatever the last light calls freed stayed resident (E012 measured adapt 0.2 GB above the per-call combo at idle). E021 closes it with one more trim from the daemon's idle loop: the verify path records its time in an atomic, and `core::on_idle` checks every 2 s whether a verification has happened since the last trim and is at least 5 s old; if so, one `malloc_trim(0)`. Measured: each trim releases 231-234 MB on the heavy window (about -17%) and 37-43 MB on small-tx blocks, with no measurable change in peak or speed; it fired once per run. Only the block path reaches this verifier, so at the chain tip it should fire at most once per block (from the code, not measured). About 40 lines, patch 0006.

## 3. How the pieces add up (heavy window, 24-thread machine)

| build | peak RssAnon | wall | notes |
|---|---|---|---|
| stock | 5.3-5.6 GB | 220 s | 24 stored circuits |
| stock, `--max-concurrency 12` | 3.3 GB | -11% | config only; 12 stored circuits |
| cap + trim | 2.9 GB | -5% | 12 stored circuits, memory returned per block |
| streaming verifier alone | 2.3 GB | -50% | 24 small verifications, no trim |
| **all three (adapt)** | **1.6-1.8 GB** | **-50%** | 12 small verifications, trimmed |
| all three with the v2 verifier (e017) | 1.6 GB | -29% | same monerod changes, pre-folded constraint instead of streaming (2.1b); three builds |
| all three with the v2 verifier, two builds (e020) | 1.6 GB | -37% | e017 plus patch 0003 (E020): the second `z` peeked on a skipped transcript clone, one fold rebuild |

Independent cross-check: the smallest cgroup `MemoryMax` (swap off) under which the window still syncs at full speed is 5,750 MB for stock and 1,866 MB for adapt (-67.5%); below that the kernel OOM-kills the process rather than it slowing down.

So the ~70% is the three changes together, not the verifier alone. Each piece on its own: the streaming verifier -59% (2.3 GB), the cap plus trim -45% (2.9 GB), and even the stock binary with `--max-concurrency 12` -40% (3.3 GB). They overlap, because each attacks the same product, number of concurrent verifications x memory per verification: the cap halves the first factor, the verifier shrinks the second by ~50x, and the trim stops the per-thread high-water marks from accumulating. That is why the three add up to -68% rather than the sum of their separate percentages. The idle-node figure (-74 to -88%) comes almost entirely from the trim. SUMMARY.md's "Build history" table gives the same progression with the small-tx wall per build.

### 3.1 Does the saving cost speed?
For the recommended build, no. The streaming verifier removes the stored circuit and, as a side effect, the quadratic O(c·q) fold that was half of all sync CPU, so adapt is both smaller and faster where it matters: 2x faster on heavy blocks, 43-50% less wall over the heavy window (E013, E018, E019), and 4.6% faster over an 18,000-block resync (E013). The one cost is on ordinary small-transaction blocks, where adapt is 5-6% slower than stock (E011/E012: the periodic trim and the second circuit build; the cap, which costs 7% there, is switched off for small proofs). That is real but small, and the net over a full resync is still positive.

v2 (2.1b) does trade speed, but for review burden, not for memory. It keeps all of the memory saving (peak within 3% of v1 on hydrogen, 7% below on box81; idle lower; cgroup minimum 1,765 MB vs v1's 1,866 and stock's 5,750) and gives back part of the speed-up: heavy blocks still 29% / 10% faster than stock but 43% / 57% slower than v1, and ordinary blocks 12% / 17% slower than stock. What it buys is a third of the code and an untouched audited verifier. With the third build removed (E020, patch 0003) the v2 cost shrinks to +28% over v1 on heavy blocks (37% under stock) and +3% over v1 on ordinary blocks (+8% over stock), at the same memory. The choice is v1's speed against v2's smaller diff; memory is the same either way.

What remains in adapt's ~1.7 GB has not been attributed yet (no heaptrack of the new build). The likely composition is the folded weight vectors, proof data and IPA generators of 12 concurrent verifications on top of a ~300 MB baseline (DB, pools, networking).

## 4. Where to look in the code
- monero-oxide, branch `e007-streaming-verify` (c215a80 on 31c26d9), diff in `evidence/E007_monero-oxide.diff`:
  - `crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs`: `ConstraintAccumulator`, `FoldedStatement::verify_transcript`, `PendingVerification::apply`; the old `verify` is now a wrapper over the stored fold.
  - `crypto/fcmps/circuit-abstraction/src/lib.rs`: `Circuit` modes Store / Discard / Accumulate.
  - `crypto/fcmps/src/lib.rs`: `Fcmp::verify` (two builds, replay check, apply), `InconsistentCircuitReplay`.
  - `crypto/fcmps/src/tests.rs`, `crypto/generalized-bulletproofs/src/arithmetic_circuit_proof/tests.rs`: the equivalence and fail-closed tests.
- monero-oxide, branch `e017-folded-verify` (4bf0c13 + b180679 on 31c26d9), patches in `patches/v2-E017-minimal/monero-oxide/` (0001 refactor only, 0002 the fold):
  - `crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs`: `#[derive(Clone)]` on `VerifierTranscript` and `peek_z`; `new` / `verify` untouched.
  - `crypto/fcmps/circuit-abstraction/src/lib.rs`: constraint modes Stored / Discarded / Folded, the `FoldedConstraints` accumulator, `folded_statement()`, `CircuitStatementError`.
  - `crypto/fcmps/src/lib.rs`: `verifier_layout`, `build_verifier_circuits`, `Fcmp::verify` (discard build, peek, two fold builds, checks), `verify_stored` under `#[cfg(test)]`.
  - `crypto/fcmps/src/tests.rs`: `test_folded_verify_matches_stored`, `test_folded_verify_matches_stored_on_tampered_proofs`, `test_discarded_and_folded_circuit_statements`, `verify_memory_benchmark`.
- monerod (`evidence/E004c.diff`, `evidence/E004e.diff`, `evidence/E012/e012.diff`): `src/ringct/rctSigs.cpp`, `batchVerifyFcmpPpProofs`. The same monerod patches serve v1 and v2 (`patches/README.md`); only the cargo `[patch]` glue points at a different monero-oxide tree.
