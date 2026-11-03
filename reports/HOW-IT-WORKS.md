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

**How we know it checks the same thing.** New crate tests build real FCMP proofs and assert the streaming and stored paths leave the batch verifier in a **field-by-field identical state**, on valid and tampered proofs, for 8 input/layer shapes; the accumulator's folded weights equal the stored fold; tampered proof regions are rejected on both paths. At the node level, 236 tampered/swapped/original transactions produced identical accept/reject decisions and flags on the stock and new binaries (E015). This is evidence of equivalence, not a proof; the change has not been audited by cryptographers.

### 2.2 Fix 1: cap concurrent heavy verifications at physical cores (E004c, E012)
Verification is pure field and curve arithmetic. On big proofs the two SMT siblings of a core fight over the same execution units and cache, so 24 concurrent batches were **slower** than 12 (-9% wall with the cap) while doubling peak memory. The cap limits the number of batches to `boost::thread::physical_concurrency()`. On small proofs, though, SMT does help (+7% wall with the cap, E011), so the final build applies the cap only when the largest proof in the call has ≥ 16 inputs. About 5 lines in `batchVerifyFcmpPpProofs`.

### 2.3 Fix 2: return freed memory to the kernel (E004e, E012)
After a heavy batch-verify call, `malloc_trim(0)` walks every arena and releases whole free pages back to the kernel (`madvise(MADV_DONTNEED)`), which the automatic top-of-heap trimming never does for fragmented arenas. This is what brings idle memory down from ~4.8 GB to ~1 GB, and it also lowers the peak, because memory freed by one block is no longer still resident when the next block's verifications start. A trim costs ~9 ms, so the final build trims after every heavy call and otherwise at most once every 10 s. glibc only (`#if defined(__GLIBC__)`). About 15 lines.

## 3. How the pieces add up (heavy window, 24-thread machine)

| build | peak RssAnon | wall | notes |
|---|---|---|---|
| stock | 5.3-5.6 GB | 220 s | 24 stored circuits |
| stock, `--max-concurrency 12` | 3.3 GB | -11% | config only; 12 stored circuits |
| cap + trim | 2.9 GB | -5% | 12 stored circuits, memory returned per block |
| streaming verifier alone | 2.3 GB | -50% | 24 small verifications, no trim |
| **all three (adapt)** | **1.6-1.8 GB** | **-50%** | 12 small verifications, trimmed |

Independent cross-check: the smallest cgroup `MemoryMax` (swap off) under which the window still syncs at full speed is 5,750 MB for stock and 1,866 MB for adapt (-67.5%); below that the kernel OOM-kills the process rather than it slowing down.

What remains in adapt's ~1.7 GB has not been attributed yet (no heaptrack of the new build). The likely composition is the folded weight vectors, proof data and IPA generators of 12 concurrent verifications on top of a ~300 MB baseline (DB, pools, networking).

## 4. Where to look in the code
- monero-oxide, branch `e007-streaming-verify` (c215a80 on 31c26d9), diff in `evidence/E007_monero-oxide.diff`:
  - `crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs`: `ConstraintAccumulator`, `FoldedStatement::verify_transcript`, `PendingVerification::apply`; the old `verify` is now a wrapper over the stored fold.
  - `crypto/fcmps/circuit-abstraction/src/lib.rs`: `Circuit` modes Store / Discard / Accumulate.
  - `crypto/fcmps/src/lib.rs`: `Fcmp::verify` (two builds, replay check, apply), `InconsistentCircuitReplay`.
  - `crypto/fcmps/src/tests.rs`, `crypto/generalized-bulletproofs/src/arithmetic_circuit_proof/tests.rs`: the equivalence and fail-closed tests.
- monerod (`evidence/E004c.diff`, `evidence/E004e.diff`, `evidence/E012/e012.diff`): `src/ringct/rctSigs.cpp`, `batchVerifyFcmpPpProofs`.
