# The code: patch series

Two versions of the verifier change are kept on purpose (owner, 2026-11-03):
- **`v1-E007-full-streaming/`**: the measured, validated series (E007 streaming verifier, ~1,000 code lines in monero-oxide restructuring `ArithmeticCircuitStatement::verify`, + ~1,200 lines of tests; independent review in reports/E007-crypto-review.md). Largest saving; largest review burden.
- **`v2-E017-minimal/`** (in progress): same idea with the stock `verify` left byte-identical; fcmps pre-folds each circuit into one constraint. Target ~150-200 code lines. See experiments/E017-minimal-streaming.

Both share the same monerod patches 0001-0003 and 0005; only 0004 (the cargo `[patch]` glue) points at a different monero-oxide branch.

## v1: E007 full streaming verifier (the recommended build as measured in E013)

The source trees live on the work box (`~/work/monero-fcmp-adapt`, `~/work/monero-oxide-e007`). This directory is the complete, ordered set of commits as `git format-patch` output, so the build can be reproduced anywhere. Per-experiment diffs under `evidence/` are the same changes as they were measured at each step (E004c, E004e, E007, E012); this is the canonical series.

## monero-oxide (the Rust crates monerod's FCMP++ verifier uses)
Base: `monero-oxide/monero-oxide` at `31c26d96eaadbba910ffe3613ad8b4cf9c598a93` ("Incorporate zkSecurity's audit of `generalized-bulletproofs`"), which is what v0.19.0.0-beta.3.1's `Cargo.lock` pins.

| patch | what | measured as |
|---|---|---|
| `v1-E007-full-streaming/monero-oxide/0001-E007-verify-FCMPs-with-streaming-constraint-accumula.patch` | streaming FCMP++ verifier: `Circuit` Store/Discard/Accumulate modes, `ConstraintAccumulator`, `FoldedStatement::verify_transcript` / `PendingVerification::apply`, two-build `Fcmp::verify` with replay check; +1,182 lines of tests. 7 files, +2,186/-134. | E007 (-59% peak alone), reviewed in reports/E007-crypto-review.md |

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

All five monerod patches together change `src/ringct/rctSigs.cpp`, `src/cryptonote_core/cryptonote_core.cpp` (E001) and the `fcmp_pp_rust` Cargo files. The combined effect of 0001+0002+0005 on `rctSigs.cpp` is ~25 lines.

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
