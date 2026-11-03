# E015: differential negative test, base as the oracle (safety)

**Why:** the earlier negtest (8 bit flips per proof, 3 txs) showed that tampered proofs are rejected. It did not show that the new verifier accepts and rejects *exactly* what the old one does, and it had few cases. The owner asked for "the next thing that needs doing to show this works and is safe".

**Method** (scripts/negdiff.sh, negtest2.py, negdiff_compare.py):
- Our node offline at height H, DB restored from a snapshot and verified against .22 by pop_to.sh.
- Cases are chosen once from .22 (read-only) and cached, so both binaries get byte-identical cases: up to 4 txs with ≥ 64 inputs, 3 with 3..63, 3 with 1..2, all with reference_block ≤ H−1.
- Per tx: 32 single-bit flips spread evenly over the fcmp_pp proof bytes (bit k mod 8). Then proof swaps: tx A carrying tx B's proof when the lengths match (a valid proof for a different statement). Then the originals.
- Base (2d1e3e9c) is the oracle. adapt (d6f93d06) must return the same (status, flags) for every case; both must reject every tampered and swapped case and accept every original.

**Results (2026-11-03 11:29-11:45): DIFF PASS at both heights.**

| H | txs (inputs) | tampered | swapped | originals | adapt vs base disagreements | reason-text differences |
|---|---|---|---|---|---|---|
| 3,105,401 | 4 × 128 | 128 rejected | 3 rejected | 4 accepted | 0 / 135 | 0 |
| 3,106,400 | 3 × 2 | 96 rejected | 2 rejected | 3 accepted | 0 / 101 | 0 |

- Where the rejections happened: at H = 3,106,400 all 98 rejections carried `invalid_input` and the node logs show 98 × "Failed to verify input FCMP++ signatures" for each binary. At H = 3,105,401, 127 of 131 did (127 log lines each); **4 rejections had no flag and an empty reason**: the flip at offset 51,679 (bit 4) in each of the four 128-input proofs, which all have the same length. That byte presumably breaks parsing, so the tx is refused before verification. Base and adapt behave identically there too. So 225 of 229 tampered/swapped cases exercised the FCMP++ verifier itself.
- The 3 + 2 proof swaps were all rejected at the FCMP++ check (`invalid_input`), which shows the proof is bound to its tx's statement in both builds.
- No scan for mid-size txs (3..63 inputs) found any within 40 blocks of 3,105,401 or 400 blocks of 3,106,400; the quota for that class stayed empty.
- Timing: adapt took 107 s vs base 166 s for the 135 heavy cases; 5 s vs 26 s for the small ones.

**Limits:** this is black-box equivalence on 236 cases at the monerod level, not a proof of equivalence, and single-bit flips plus swaps are a narrow class of malformed proofs. A crate-level differential fuzz (random mutations, both verifiers, compare decisions) would be the next step up. Evidence: evidence/E015/.
