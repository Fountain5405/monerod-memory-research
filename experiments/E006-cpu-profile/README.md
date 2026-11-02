# E006: CPU profile of FCMP++ sync verification (prices the E007 streaming design)

**Setup (2026-11-02 22:35):** baseline beta31, `--block-sync-size 5`, window 3,105,401→3,105,441 (221 s), quiet box. `sudo perf record -F 199 -p <monerod>` (all threads, no call graphs); `perf report --no-children --sort symbol`, demangled with rustfilt. Script: scripts/e006_profile.sh. Raw: ~/work/research-artifacts/E006/perf.data. Evidence: evidence/E006/.

**Results (self time):**

| bucket | share |
|---|---|
| `ArithmeticCircuitStatement::verify` (generalized-bulletproofs), with inlined callees: constraint folding by z powers (`accumulate_vector`), weight vectors, IPA scalar math | **~52%** (50.37% + 1.33% for the two curve instances) |
| curve/field arithmetic: SelenePoint add 12.3%, crypto_bigint Montgomery reduction 8.5% and mul_wide 8.1%, field pow 1.2%, curve25519 scalar mul 1.1%, Helios add 1.0%, multiexp prep_bits 1.6% | ~36% |
| circuit construction: LinComb term 0.65%, append 0.3%, memmove 1.8%, memset 0.5%, malloc/free ~1%, tape 0.3% | **~4-6%** |
| everything else | ~1% |

Note: scripts/perf_classify.py first lumped the 50% verify symbol under "circuit building" because the truncated mangled name contains "ArithmeticCircuitStatement" (regex `Circuit`). The table above is the corrected manual classification; the script needs a fix before reuse.

**Conclusion:** building the circuit (the gadget code producing LinCombs) is cheap (~5% of CPU). The expensive work is the folding and verification inside `verify`, which a streaming design would do exactly once (just earlier). **A 3-pass streaming verifier (E007) should cost roughly +10% CPU** (two extra construction passes) while removing the ~200 MB per-verifier stored circuit. Separately, ~52% of all sync CPU sits in one function; that is a CPU optimization target in its own right (out of scope for memory).
