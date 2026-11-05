# E033: the monerod patches alone, no verifier change

Five patches against v0.19.0.0-beta.3.1 (`d80596ad1`), +71/-1 lines in `src/ringct/rctSigs.cpp`, `rctSigs.h`, `src/cryptonote_core/cryptonote_core.cpp` and `.h`. They are v1's monerod 0001, 0002, 0005, 0006 and 0007. Left out: 0003 (the E001 sync cap, not a memory change) and 0004 (the cargo glue that points at a patched verifier).

One difference from the published 0006: its context held an include that 0003 adds, so that context line is removed here. What 0006 adds is the same.

Applied with `git am`, the tree hash is `e8d76fb5404d57ff7c09dce8acf7c5ec0adbb827`. It compiled on box81 (2026-11-05). Measurements: `experiments/E033-*/`, when done.
