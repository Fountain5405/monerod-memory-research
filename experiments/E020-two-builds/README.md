# E020: v2 with two circuit builds instead of three (adapt vs e017 vs e020)

**Why:** E018 and E019 showed that v2 (E017, the pre-folded verifier with the audited `verify` untouched) keeps v1's memory but costs +43-57% wall on heavy blocks and +6-11% on small-tx blocks over v1. The attributed cause was the third circuit construction: v2 built the circuits once to advance the transcript, once more to fold c1 with its `z`, and a third time to fold c2 with its `z`, which is only known after the first proof's verification has consumed the transcript. E020 removes the third build. The stock verifier never hashes the constraints, so its transcript operations depend only on the statement's size (`n`, the number of vector commitments `c`); a small additive function `skip_verify_transcript` replays those operations on a clone of the transcript, after which the second proof's `z` can be peeked before either proof is verified. One Fold rebuild then folds c1 and c2 together: two builds, as in v1, with v2's diff. Pre-registered decision rule (HANDOFF/STATE): if e020's heavy-window wall is within ~10% of adapt and its small-tx wall within ~5%, v2+E020 replaces v1 as the recommended series; otherwise v1 stays.

**Change (monero-oxide branch `e020-two-builds`, commit bde81f4 on top of E017's b180679; patches/v2-E017-minimal/monero-oxide/0003):** generalized-bulletproofs +57 lines, all additive (`skip_verify_transcript<C>(transcript, n, c)`: 3 points, y, z, the T points before and after `ni`, x, 3 scalars, the inner-product challenge, log2(n) rounds of L, R and a challenge, a, b; the fuzz test asserts the skipped transcript lands exactly where `verify` lands); fcmps 26/26 lines in `Fcmp::verify` (peek z1; clone the transcript, skip past proof 1, peek z2; one Fold rebuild with both z's; verify proof 1 on the real transcript; check the real transcript's `challenge_bytes()` equals the skipped clone's, else `FcmpError::InconsistentCircuitReplay`; verify proof 2). Crate tests: GBP suite with `--features tests` PASS including the new assertion; fcmps folded-vs-stored equivalence PASS 3/3 (honest and tampered, 8 shapes). The E017 replay checks (same multiplications, constraints and transcript state between the discard build and the rebuild) are unchanged.

Crate benchmark (hydrogen, counting allocator, 8 layers, single runs, 2026-11-03 20:0x): per proof e020 vs e017 at 2 inputs 938 KB / 15 ms vs 785 KB / 19 ms; at 8 inputs e020 3.63 MB / 55 ms (e017's hydrogen 8-input line was lost to a `head` cut; its box81 figure is 2.99 MB, E017 README). About +20% heap per proof, because both folded accumulators are live at once, and about -20% time.

**Setup:** hydrogen, 2026-11-03 20:24-22:46, scripts/run_e020.sh (chain log evidence/E020/e020.chain). adapt = `monero-fcmp-adapt` 4a51d434d (sha d6f93d06), e017 = `monero-fcmp-e017` 92f7ac279 (sha 119b94b0), e020 = `monero-fcmp-e020` (a copy of the e017 tree with the cargo `[patch]` paths pointed at monero-oxide-e020, built with ARCH=native, sha a4d8448af856960e, `strings` confirms the e020 crate; build marker evidence/E020/e020.build). All runs `--block-sync-size 5`, governor `performance` for (a) and (b), no shadow lanes for the whole chain, swap off. base was not re-run here; the base figures quoted below are E018's, from the same box, snapshots and settings.

## (a) Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds (DB restored from the wedge snapshot each run)

| metric | adapt (v1) | e017 (v2) | e020 (v2, two builds) | e020 vs adapt | e020 vs e017 | e017 vs adapt |
|---|---|---|---|---|---|---|
| peak anon MB | 1,607 (1,456-1,662) | 1,589 (1,550-1,652) | 1,623 (1,597-1,654) | +1.0% | +2.1% | -1.1% |
| peak Private_Dirty MB | 1,607 (1,456-1,663) | 1,614 (1,573-1,672) | 1,642 (1,621-1,676) | +2.2% | +1.7% | +0.4% |
| peak RSS MB | 2,931 (2,857-2,987) | 2,787 (2,782-2,882) | 2,868 (2,821-2,883) | -2.1% | +2.9% | -4.9% |
| post-idle anon MB | 1,352 (1,210-1,436) | 1,050 (915-1,152) | 1,013 (981-1,027) | **-25.1%** | -3.5% | -22.3% |
| wall s | 109 (108-110) | 159 (156-167) | 140 (136-144) | **+28.4%** | **-11.9%** | +45.9% |
| CPU s | 907 (906-910) | 1,404 (1,404-1,431) | 1,226 (1,204-1,233) | +35.2% | -12.7% | +54.8% |
| read / write MB | 9 / 466 | 9 / 466 | 9 / 466 | | | |

9/9 hashes match. Against E018's base (5,410 MB peak, 222 s): e020 peak -70.0%, wall -37% (e017 -28%, adapt -51%). The peak-anon ranges of all three arms overlap; e020's peak is +1% vs adapt and +2% vs e017 (the crate benchmark predicted +20% per proof, which at the node is within the run-to-run spread). e020's idle footprint is the lowest of the three.

## (b) Small-tx window 3,106,400 -> 3,107,400 (1,000 blocks of 1-2 input txs), 3 alternating rounds (DB restored from the 3,106,400 snapshot each run)

| metric | adapt (v1) | e017 (v2) | e020 (v2, two builds) | e020 vs adapt | e020 vs e017 | e017 vs adapt |
|---|---|---|---|---|---|---|
| peak anon MB | 810 (801-819) | 801 (795-810) | 805 (800-812) | -0.6% | +0.5% | -1.1% |
| peak Private_Dirty MB | 968 (960-997) | 945 (943-961) | 989 (965-996) | +2.2% | +4.7% | -2.4% |
| post-idle anon MB | 746 (743-759) | 776 (772-780) | 755 (751-764) | +1.2% | -2.7% | +4.0% |
| wall s | 156 (156-159) | 169 (167-169) | 161 (159-161) | **+3.2%** | **-4.7%** | +8.3% |
| CPU s | 1,432 (1,432-1,440) | 1,609 (1,607-1,610) | 1,487 (1,483-1,496) | +3.8% | -7.6% | +12.4% |
| read / write MB | 52 / 1,117 | 52 / 1,123 | 52 / 1,117 | | | |

9/9 hashes match. Against E018's base (149 s): e020 +8%, e017 +13%, adapt +5%. Some runs stop at 3,107,405 instead of 3,107,400 (the last 5-block batch overshoots: adapt r2, e017 r1 and r3, e020 r2), a 0.5% difference in blocks that is inside the spread. On ordinary blocks the two-build v2 costs 3% over v1, where e017 cost 8%.

## (c) Differential negative test vs base (scripts/negdiff.sh, base as the oracle): DIFF PASS at both heights

| height | txs (inputs) | cases | (status, flags) disagreements | reason-text differences | oracle rejection flags |
|---|---|---|---|---|---|
| 3,105,401 (scan 40) | 4 (128, 128, 128, 128) | 135 (128 tampered, 3 swapped, 4 original) | 0 | 0 | invalid_input 127, none 4 |
| 3,106,400 (scan 400) | 3 (2, 2, 2) | 101 (96 tampered, 2 swapped, 3 original) | 0 | 0 | invalid_input 98 |

Same case sets as E015 (adapt) and E018 (e017): every tampered and swapped proof is rejected by both binaries with the same status and reason text, every original accepted by both. The `InconsistentCircuitReplay` path is not exercised by these cases (a tampered proof fails inside proof 1's or proof 2's `verify`, before or regardless of the transcript check), so that check is covered by the crate tests only. Evidence: evidence/E020/neg/.

## Decision: v1 (adapt) stays recommended; v2 with two builds (e017 + 0003) replaces e017 as the alternative

Against the pre-registered rule:
- heavy wall within ~10% of adapt: **not met** (+28%; e017 was +46%);
- small-tx wall within ~5% of adapt: **met** (+3%; e017 was +8%);
- memory, hashes, negdiff: unchanged from e017 (peak within 2%, idle lowest, 18/18 hashes, 236 cases identical to base).

The second build removes about 40% of e017's wall gap to v1 on heavy blocks and about 60% of its gap on small blocks, at no memory cost visible at the node. What remains (+28% wall, +35% CPU on heavy blocks over v1) is more than the crate benchmark predicted (per proof e020 was about -20% time against e017, whose box81 cost was +40% over v1, so roughly +12%). The remaining gap has since been profiled in E024 (copying is 3.8% of it; field multiplication 56%, callers not attributed). At the time of writing it had not been profiled. Candidates: v2's fold accumulator in circuit-abstraction does its weight sums per constraint on top of the construction, whereas v1 folds inside the verifier as the constraints arrive; and the transcript clone, skip and the Private_Dirty growth (+2% on both windows) hint at extra copying. A perf profile of the e020 build on the heavy window (as in E006) is the next step if the owner wants v2 pushed further; the outcome would be a v2 at v1's speed or a demonstration that the remaining cost is in the fold itself.

What this means for the report: adapt / v1 remains the recommended build (2x faster than stock on heavy blocks, 3% faster than v2+E020 on small ones, long resync faster than stock). The v2 series now consists of patches 0001-0003 and is the alternative when the diff against the audited verifier matters more than speed: same memory, +28% heavy wall over v1 (still 37% under stock), +3% small-tx wall over v1 (+8% over stock), with the audited `verify` still byte-identical and 57 additive lines beside it. The monerod patches 0004 and 0006 stay unsquashed.

## Guardrails
- End hash equal to .22 in all 18 A/B runs; negdiff identical to base (236 cases); no run timed out.
- No shift to disk or swap: identical write bytes per arm within each window; swap off.
- Quiet box: no shadow lanes for the whole chain (watcher in the chain log), governor `performance` for the timing parts, restored after.
- The e020 binary built for this chain (sha a4d8448a) is the one measured in (a)-(c); `sha256sum` of all three binaries is in the chain log.
- One change per experiment: e020 differs from e017 only by monero-oxide commit bde81f4 (patch 0003); the monerod tree and build flags are the same.
