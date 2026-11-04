# The code: patch series

Two versions of the verifier change are kept on purpose (owner, 2026-11-03):
- **`v1-E007-full-streaming/`**: the measured, validated series (E007 streaming verifier, ~1,000 code lines in monero-oxide restructuring `ArithmeticCircuitStatement::verify`, + ~1,200 lines of tests; independent review in reports/E007-crypto-review.md). Largest saving; largest review burden.
- **`v2-E017-minimal/`** (measured at the node in E018/E019/E020: same memory as v1, negdiff identical to base, but slower than v1: with all three patches, heavy blocks +28% wall over v1 (37% under stock) and small-tx blocks +3% over v1 (+8% over stock), and E025 found the same gap with E021 + E022 on both series (+27.5%, +2.7%); with 0001-0002 alone +43-57% and +12-17%; the alternative series, not the recommended one): same idea with the stock `verify` left byte-identical; fcmps pre-folds each circuit into one constraint. Target ~150-200 code lines. See experiments/E017-minimal-streaming.

Both share the same monerod patches 0001-0003, 0005, the E021 idle trim (0006 in v1, 0007 in v2) and the E022 threshold (0007 in v1, 0008 in v2); only 0004 (the cargo `[patch]` glue) points at a different monero-oxide branch (v2 adds 0006 to repoint it).

## v1: E007 full streaming verifier (the recommended build as measured in E013)

The source trees live on the work box (`~/work/monero-fcmp-adapt`, `~/work/monero-oxide-e007`). This directory is the complete, ordered set of commits as `git format-patch` output, so the build can be reproduced anywhere. Per-experiment diffs under `evidence/` are the same changes as they were measured at each step (E004c, E004e, E007, E012); this is the canonical series.

## monero-oxide (the Rust crates monerod's FCMP++ verifier uses)
Base: `monero-oxide/monero-oxide` at `31c26d96eaadbba910ffe3613ad8b4cf9c598a93` ("Incorporate zkSecurity's audit of `generalized-bulletproofs`"), which is what v0.19.0.0-beta.3.1's `Cargo.lock` pins.

| patch | what | measured as |
|---|---|---|
| `v1-E007-full-streaming/monero-oxide/0001-E007-verify-FCMPs-with-streaming-constraint-accumula.patch` | streaming FCMP++ verifier: `Circuit` Store/Discard/Accumulate modes, `ConstraintAccumulator`, `FoldedStatement::verify_transcript` / `PendingVerification::apply`, two-build `Fcmp::verify` with replay check; +1,182 lines of tests. 7 files, +2,186/-134. | E007 (-59% peak alone), reviewed in reports/E007-crypto-review.md |
| `v1-E007-full-streaming/monero-oxide/0002-E016-test-the-streaming-verifier-against-verbatim-co.patch` | tests only: verbatim copies of the 31c26d9 `Fcmp::verify` and `ArithmeticCircuitStatement::verify` (`#[cfg(test)]` / feature `tests`) and three tests comparing the streaming verifier against them on honest, tampered and randomly mutated proofs. 3 files, +641/-54 (54 = moving the tampering-region computation into a helper). | E016 (closes the review's F1) |

Touches `crypto/generalized-bulletproofs/`, `crypto/fcmps/`, `crypto/fcmps/circuit-abstraction/`.

## monerod (seraphis-migration/monero)
Base: v0.19.0.0-beta.3.1 = `d80596ad1`.

| patch | what | lines | measured as |
|---|---|---|---|
| `v1-E007-full-streaming/monerod/0001-rctSigs-cap-FCMP-batch-verification-at-physical-core.patch` | cap concurrent FCMP++ batches at physical cores (`rct::batchVerifyFcmpPpProofs`) | ~8 | E004c |
| `v1-E007-full-streaming/monerod/0002-rctSigs-malloc_trim-after-FCMP-batch-verification-on.patch` | `malloc_trim(0)` after each batch verify (glibc only) | ~8 | E004e (with 0001: -44.6% peak, -88% idle) |
| `v1-E007-full-streaming/monerod/0003-cryptonote_core-cap-adaptive-block-sync-size-by-the-.patch` | E001 sync-wedge fix: cap the adaptive block-sync batch by the levin limit / block weight limit | ~10 | E001 (not a memory change; see reports/E001-sync-wedge-ISSUE.md, and the owner's note that a window-aware cap is needed for post-fork mainnet) |
| `v1-E007-full-streaming/monerod/0004-E007-build-fcmp_pp_rust-against-local-monero-oxide-e.patch` | `src/fcmp_pp/fcmp_pp_rust/Cargo.toml`: a `[patch]` section pointing the five monero-oxide crates at the patched tree, plus the `Cargo.lock` change | build glue | E007/E008 |
| `v1-E007-full-streaming/monerod/0005-E012-FCMP-batch-cap-and-malloc_trim-adaptive-to-proo.patch` | make 0001/0002 adaptive: cap and per-call trim only when the largest proof in the call has >= 16 inputs; otherwise trim at most every 10 s | ~20 | E012/E013 (the recommended build) |
| `v1-E007-full-streaming/monerod/0006-E021-trim-FCMP-verifier-memory-once-verification-goe.patch` | one `malloc_trim(0)` from `core::on_idle` once no batch verification has run for 5 s (two atomics in rctSigs.cpp record the last verification and the last trim; `rct::idleTrimFcmpPp`; a 2 s `once_a_time_seconds` in core) | ~40 | E021 (releases ~230 MB at idle on the heavy window, about -17% on top of E012, no measurable speed cost on sync windows; E013's validation was run without it, E023's with it; not built on v2) |
| `v1-E007-full-streaming/monerod/0007-E022-count-FCMP-batch-calls-as-heavy-from-8-inputs-n.patch` | `HEAVY_PROOF_MIN_INPUTS` 16 -> 8 in rctSigs.cpp | 1 | E022 (about -30% CPU, +3-4% wall on 8-input blocks, on two stretches; no lower peak once larger proofs are in the run; negative test, min_mem and long resync rerun with it in E023) |

All seven monerod patches together change `src/ringct/rctSigs.cpp` and `.h`, `src/cryptonote_core/cryptonote_core.cpp` and `.h` (E001, E021) and the `fcmp_pp_rust` Cargo files. The combined effect of 0001+0002+0005 on `rctSigs.cpp` is ~25 lines; 0006 adds ~35 more plus a two-line hook in core. The E013-measured binary (sha256 `d6f93d06...`) is 0001-0005; with 0006 the build is the E021 idle binary (sha256 `6e6f14c6acdc4b5b...`).

## Reproducing the build
```sh
# 1. the Rust crates
git clone https://github.com/monero-oxide/monero-oxide && cd monero-oxide
git checkout 31c26d96eaadbba910ffe3613ad8b4cf9c598a93
git am ../patches/v1-E007-full-streaming/monero-oxide/*.patch
cd ..
# 2. monerod
git clone --recursive https://github.com/seraphis-migration/monero monero-adapt && cd monero-adapt
git checkout d80596ad1
git am ../patches/v1-E007-full-streaming/monerod/*.patch
# 0004 hard-codes `path = "/home/optimizer/work/monero-oxide-e007/..."` in src/fcmp_pp/fcmp_pp_rust/Cargo.toml;
# point those five paths at your monero-oxide checkout from step 1.
sed -i 's#/home/optimizer/work/monero-oxide-e007#'"$PWD"'/../monero-oxide#' src/fcmp_pp/fcmp_pp_rust/Cargo.toml
mkdir -p build/adapt && cd build/adapt
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF ../.. && ninja daemon
```
The measured binary was built this way with ccache and `-j10` (sha256 `d6f93d0664604726eaefbaf99982f181adc5bb8f31480f4902660bb686fa3ae8`).

To build the intermediate configurations instead: 0001 only = E004c; 0001+0002 = E004e; monero-oxide patch + 0004 only = E007; 0001-0004 = the E008 "combo".

## Crate tests
In the patched monero-oxide: `cargo test -p full-chain-membership-proofs --release -- --skip prove_benchmark` and `cargo test -p generalized-bulletproofs --release`. The full fcmps suite including `test_malleated_proofs` takes ~45 min on a 3900X.

## v2: E017 minimal streaming verifier (measured in E018/E019/E020; alternative to v1, which stays recommended on speed)
Same monerod changes as v1. In monero-oxide the audited `ArithmeticCircuitStatement::verify` is left byte-identical; instead fcmps hands it ONE pre-folded constraint `sum(z^k c_k)`, which `verify` weights by `z`, giving the same `sum(z^(k+1) c_k)` it computed from the stored constraints. Design and results: experiments/E017-minimal-streaming/README.md.

| patch | what | measured as |
|---|---|---|
| `v2-E017-minimal/monero-oxide/0001-fcmps-extract-verifier_layout-and-build_verifier_cir.patch` | refactor only, no behaviour change: the verifier's layout computation and circuit construction become functions so the circuits can be built more than once (review with `git diff --color-moved`) | |
| `v2-E017-minimal/monero-oxide/0002-E017-verify-FCMPs-with-the-constraints-folded-into-o.patch` | generalized-bulletproofs: `#[derive(Clone)]` on `VerifierTranscript` and the additive `peek_z` (+25 lines, nothing removed); circuit-abstraction: Discarded/Folded constraint modes, the folding accumulator, `CircuitStatementError`; fcmps: three builds (discard; fold c1 with its peeked z; fold c2), replay checks, `#[cfg(test)] verify_stored`; tests | crate: equivalence with the unchanged stock verifier PASS, tampered PASS, peak heap -80% per verify at 1-16 inputs |
| `v2-E017-minimal/monero-oxide/0003-E020-fold-both-circuits-in-one-rebuild-peeking-the-s.patch` | generalized-bulletproofs: the additive `skip_verify_transcript` (+57 lines: replays the stock `verify`'s transcript reads and challenges for a statement of `n` generators and `c` vector commitments) plus an assertion in the fuzz test that it lands where `verify` lands; fcmps (26/26 lines in `Fcmp::verify`): the second proof's `z` is peeked on a transcript clone skipped past the first proof, c1 and c2 are folded in ONE rebuild (two builds instead of three), and after the first proof's real verification the real transcript must equal the skipped clone (`InconsistentCircuitReplay`) | crate: same tests PASS; node (E020): heavy wall -12% vs 0001-0002 (+28% vs v1), small-tx -5% (+3% vs v1), memory unchanged, negdiff identical to base |

Sizes vs 31c26d9: code +513 / -88 (refactor commit 92/33 of it is motion), tests +228 plus a benchmark; patch 0003 adds +83 / -26 (57 additive lines beside the audited verifier, none inside it). v1 for comparison: code +1,004 / -134, with +570 inside the audited verifier.

monerod for v2: `v2-E017-minimal/monerod/0001-0005` are v1's patches unchanged, plus `0006` which repoints the cargo `[patch]` paths from the E007 tree to the E017 tree (0004 + 0006 together are the build glue; they will be squashed if v2 becomes the recommended series), plus `0008` = v1's 0007 (E022 threshold), plus `0007` = v1's 0006 (E021 idle trim) renumbered; both built and measured in E025, on top of the e020 build. Build as for v1, with `monero-oxide-e017` in the `sed`. Apply 0001-0003 for the measured e020 build (0001-0002 alone is the slower e017 build of E018/E019).
