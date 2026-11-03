# E018: node-level measurement of the v2 / E017 folded verifier (base vs adapt vs e017)

**Why:** E017 is the small replacement for E007 (the audited `ArithmeticCircuitStatement::verify` left byte-identical, fcmps pre-folds each circuit into one constraint). Its crate tests pass and its per-proof heap is below E007's, but a node is not a crate: this experiment runs the e017 build through the same chain adapt went through in E013, with base and adapt alongside, and decides whether v2 replaces v1 as the recommended series. The pre-registered acceptance (experiments/E017-minimal-streaming/README.md): heavy-window peak within ~10% of adapt, wall within ~5% of adapt, same hashes, negative test identical to base.

**Setup:** hydrogen, 2026-11-03 15:26-18:37, scripts/run_e018.sh (chain log evidence/E018/e018.chain). base = v0.19.0.0-beta.3.1 d80596ad1, adapt = `monero-fcmp-adapt` 4a51d434d (E012 cap + trim, monero-oxide-e007 v1 verifier), e017 = `monero-fcmp-e017` 92f7ac279 (adapt's monerod changes, monero-oxide-e017 4bf0c13 + b180679; monerod sha 119b94b0). All runs `--block-sync-size 5`, governor `performance`, no shadow lanes, swap off. Default thread count 24.

Caveat on round 1: the 18.9 GB snapshot stream to box81 (for E019) read hydrogen's SSD at about 37 MB/s from 15:26 to 15:35, overlapping r1_base's restore and sync in (a). base's three heavy walls are 222-224 s and its peaks 5,400-5,609 MB, so no effect is visible, but r1 is flagged and medians are used throughout.

## (a) Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds (DB restored from the wedge snapshot each run)

| metric | base | adapt (v1) | e017 (v2) | adapt vs base | e017 vs base | e017 vs adapt |
|---|---|---|---|---|---|---|
| peak anon MB | 5,410 (5,400-5,609) | 1,590 (1,370-1,754) | 1,631 (1,626-1,654) | **-70.6%** | **-69.9%** | +2.6% |
| peak Private_Dirty MB | 5,410 (5,408-5,609) | 1,614 (1,376-1,755) | 1,654 (1,646-1,656) | -70.2% | -69.4% | +2.5% |
| peak RSS MB | 6,682 (6,672-6,910) | 2,712 (2,473-2,892) | 2,859 (2,828-2,888) | -59.4% | -57.2% | +5.4% |
| post-idle anon MB | 4,917 (4,878-4,971) | 1,280 (932-1,345) | 1,071 (1,023-1,127) | -74.0% | **-78.2%** | -16.3% |
| wall s | 222 (222-224) | 110 (108-115) | 157 (157-158) | -50.5% | -29.3% | **+42.7%** |
| CPU s | 4,244 (4,206-4,258) | 903 (901-906) | 1,404 (1,403-1,404) | -78.7% | -66.9% | **+55.5%** |
| read / write MB | 10 / 466 | 9 / 466 | 9 / 466 | | | |

9/9 hashes match. e017's peak is within 3% of adapt's (acceptance met) and its run-to-run spread is 28 MB against adapt's 384 MB. Its wall is 43% above adapt's (acceptance "within ~5%" not met), though still 29% below base.

## (b) Small-tx window 3,106,400 -> 3,107,400 (1,000 blocks of 1-2 input txs), 3 alternating rounds (DB restored from the 3,106,400 snapshot each run)

| metric | base | adapt (v1) | e017 (v2) | adapt vs base | e017 vs base | e017 vs adapt |
|---|---|---|---|---|---|---|
| peak anon MB | 1,201 (1,026-1,234) | 810 (808-821) | 797 (792-798) | **-32.6%** | **-33.6%** | -1.6% |
| peak Private_Dirty MB | 1,340 (1,190-1,443) | 985 (983-995) | 949 (935-968) | -26.5% | -29.2% | -3.7% |
| post-idle anon MB | 1,096 (991-1,234) | 766 (759-767) | 778 (777-786) | -30.1% | -29.0% | +1.6% |
| wall s | 149 (148-150) | 158 (154-159) | 167 (166-168) | +6.0% | **+12.1%** | +5.7% |
| CPU s | 1,321 (1,317-1,329) | 1,438 (1,424-1,438) | 1,598 (1,591-1,607) | +8.9% | +21.0% | +11.1% |
| read / write MB | 54 / 1,117 | 52 / 1,123 | 52 / 1,123 | | | |

9/9 hashes match. On ordinary blocks v2 keeps v1's memory and costs a further 6% wall (12% over base; the combo of E010/E011 was +15%, which was judged too much and led to E012).

## (c) Differential negative test vs base (scripts/negdiff.sh, base as the oracle): DIFF PASS at both heights

| height | txs (inputs) | cases | (status, flags) disagreements | reason-text differences | oracle rejection flags |
|---|---|---|---|---|---|
| 3,105,401 (scan 40) | 4 (128, 128, 128, 128) | 135 (128 tampered, 3 swapped, 4 original) | 0 | 0 | invalid_input 127, none 4 |
| 3,106,400 (scan 400) | 3 (2, 2, 2) | 101 (96 tampered, 2 swapped, 3 original) | 0 | 0 | invalid_input 98 |

Every tampered and swapped proof is rejected by both binaries with the same status and the same reason text; every original is accepted by both. Same case sets as E015 (adapt). Evidence: evidence/E018/neg/.

## (d) Minimum cgroup MemoryMax for e017 (scripts/min_mem.sh; ref wall 157 s, factor 1.10, swap off)

| limit MB | result | wall s | cgroup peak MB | OOM kills |
|---|---|---|---|---|
| 4,000 | PASS | 161 | 1,726 | 0 |
| 750 | FAIL | 8 | 741 | 1 |
| 2,375 | PASS | 161 | 1,681 | 0 |
| 1,562 | FAIL | 73 | 1,499 | 1 |
| 1,968 | PASS | 158 | 1,797 | 0 |
| 1,765 | PASS | 157 | 1,649 | 0 |
| 1,663 | FAIL | 76 | 1,663 | 1 |

**Minimum = 1,765 MB** (adapt in E013: 1,866 MB; base 5,750 MB). Largest fail 1,663 MB. That is -69.3% vs base and one 125 MB grid point below adapt, consistent with v2's lower per-proof heap. Every fail is an OOM kill and the wall at the minimum equals the reference (157 s), so the bound is a memory cliff, not a slowdown. Evidence: evidence/E018/minmem/.

## (e) Long resync 3,105,401 -> 3,123,400, e017_bss5, 1 run (DB restored from the wedge snapshot)

| arm | blocks | wall s | peak RssAnon MB | post-idle MB | write MB | CPU s | hash |
|---|---|---|---|---|---|---|---|
| base_bss5 (E013) | 18,234 | 1,345 | 5,613 | 4,642 | 9,412 | 13,581 | yes |
| adapt_bss5 (E013) | 18,289 | 1,283 (-4.6%) | 1,657 (-70.5%) | 1,379 | 9,419 | 10,931 | yes |
| e017_bss5 | 18,309 | 1,414 (**+5.1%** vs base, +10.2% vs adapt) | 1,553 (**-72.3%**) | 1,218 (-73.8%) | 9,421 | 12,524 | yes |

Per segment (scripts/segment_rates.py): 

| segment | base_bss5 (E013) | adapt_bss5 (E013) | e017_bss5 |
|---|---|---|---|
| heavy window (to 3,105,441) | 219 s | 108 s | 159 s |
| dense small-tx 3,105,441..3,113,400 | 1,051 s | 1,099 s (+4.6%) | 1,177 s (**+12.0%** vs base, +7.1% vs adapt) |
| near-empty tail to 3,123,400 | 73 s | 72 s | 73 s |

The whole regression is on the ~8,000 dense small-tx blocks, where v2's third construction pass is not hidden by anything; the tail is identical. Net against base: -60 s in the window, +126 s on small-tx blocks.

Memory per segment: e017 peaks inside the window (1,554 MB at 3,105,436, the same height as base and adapt), then holds 1.20-1.36 GB over the dense stretch (median 1,241 MB) and 1.28-1.32 GB in the tail, with no upward trend over 18,000 blocks: no leak from the fold accumulator or the trim. That plateau is below adapt's 1.3-1.6 GB (median 1,455) because v2 idles lower; base sits at 4.5-4.7 GB. Evidence: evidence/E018/long/ (mem_segments.txt, segments.txt).

## Decision: v1 (adapt) stays the recommended build; v2 is the small-diff alternative at a CPU cost

Against the pre-registered acceptance:
- heavy peak within ~10% of adapt: **met** (+2.6% here, -7% on box81 in E019);
- hashes: **met** (18/18 here, 18/18 on box81);
- negative test identical to base: **met** (236 cases, 0 disagreements);
- wall within ~5% of adapt: **not met**, on either machine. Heavy window +43% (hydrogen) / +57% (box81) over adapt; small-tx blocks +6% / +11% over adapt, +12% / +17% over base. Long resync: +5.1% vs base where adapt is -4.6%, so v2 turns v1's net gain over 18,000 blocks into a net loss, inside the 10% guardrail.

So v2 delivers v1's memory (and a lower idle footprint) with about a third of the diff and the audited verifier untouched, but gives back roughly half of v1's speed-up on heavy blocks and doubles v1's small-block cost. The reason is in the crate numbers already (E017: per-proof CPU +110% over stock vs v1's +50%): once the O(c x q) fold is gone, circuit construction is the dominant cost of a verification, so v2's third construction pass costs about +50% over v1, on heavy and small proofs alike. The E017 prediction that the extra pass would be "~5%" was made against base's CPU budget, which no longer applies after the fold is removed.

What this means for the report:
- **adapt / v1 remains the recommended build** on the measurements: same memory, 2x faster on heavy blocks, +6% on small blocks, long resync faster than base (E013).
- **v2 is the recommended build for a reviewer who values the diff size and the untouched verifier over speed**: it is the only series whose equivalence to the stock verifier is checked against the stock verifier itself (E017 tests), so the crypto review's F1 (base-equivalence test for v1, E016) applies to v1 only.
- **A v2 without the third pass is the obvious next experiment** (E020 candidate): the stock verifier never hashes the constraints, so z1 and z2 both depend only on proof bytes and could both be peeked from the first (discard) build; one Fold pass could then fold c1 and c2 together, giving v1's two builds with v2's diff. To be verified against the transcript order before it is tried.
- Since v1 stays recommended, E016 (base-equivalence test for E007) is back on the queue.

## Guardrails
- End hash equal to .22 in all 18 A/B runs and the long resync; negdiff identical to base (236 cases); no run timed out.
- No shift to disk or swap: identical write bytes per arm; swap off.
- Quiet box: no shadow lanes for the whole chain, governor `performance` for the timing parts; the round-1 overlap with the box81 snapshot stream is recorded above.
- The e017 binary built in this chain (sha 119b94b0) is the one measured in (a)-(e) and in the negdiff.
