# E022: sweep of adapt's heavy-proof threshold (8 / 16 / 32 inputs)

**Status: done. Threshold 8 passed the replication criterion on both windows in (e) and is adopted as monerod patch 0007 of v1 / 0008 of v2. It is mainly a CPU change: about -30% CPU for +3-4% wall on 8-input blocks. It does not lower the peak of a run that also holds larger proofs.**

**Why:** `HEAVY_PROOF_MIN_INPUTS = 16` (E012) decides which batch-verify calls count as heavy. A heavy call is capped at physical cores and trimmed after every call. A light call uses the whole thread pool and trims at most every 10 s. The value 16 was a judgment call and was never swept, and SUMMARY lists that as a caveat.

## (a) How much of the chain the threshold affects (E022a scan)
scripts/chain_inputs.py over 3,080,000-3,123,269 on our offline node; evidence/E022/chain_inputs.csv.gz.

| largest tx in the block | blocks |
|---|---|
| empty | 34,507 |
| 1-2 inputs | 8,535 |
| 3-7 | 43 |
| **8-15** | **83** |
| **16-31** | **21** |
| 32-63 | 17 |
| 64 or more | 64 |

Of 762,594 txs, 759,840 have 1-2 inputs. Only 104 of 43,270 blocks change behaviour between thresholds of 8, 16 and 32. The heavy and small-tx windows used so far cannot discriminate. Stressnet's mix is synthetic, so this says nothing about how often mid-size proofs would occur on mainnet.

42 of the 104 are contiguous: 3,106,069-3,106,105 have a largest tx of 8 inputs (37 blocks) and 3,106,106-3,106,110 have 16 (5 blocks). That stretch is the window.

## Setup
hydrogen, 2026-11-04 01:20-02:36, scripts/run_e022.sh (evidence/E022/e022.chain). Three binaries from the full series (idle tree, E021 included), differing only in the constant: t8 (sha d779a522), t16 (sha 6e6f14c6, the E021 binary), t32 (sha cad05936). `ab_window.sh`, `--block-sync-size 5`, 5 alternating rounds, snapshot restored and popped to 3,106,060 before every run, single peer 192.168.1.22, governor `performance`, no shadow lanes.

- t8: the 8-input and 16-input blocks are heavy.
- t16: only the 16-input blocks are heavy.
- t32: neither is heavy, so t32 differs from t16 on just 5 blocks and its reading is weak.

**Decision rule, written into the script before the run:** keep 16 unless another threshold is at least 5% better on CPU or wall with peak not worse by more than 5%, or at least 10% better on peak with wall within 3%. Medians of 5; overlapping ranges count as no difference.

## (b) Results, medians of 5 (min-max)
| arm | peak RssAnon MB | peak Private_Dirty MB | CPU s | post-idle RssAnon MB | hashes |
|---|---|---|---|---|---|
| t16 | 506 (500-509) | 527 (512-533) | 199 (198-202) | 414 (407-427) | 5/5 |
| t8 | **471 (456-481)** | 500 (471-531) | **157 (140-158)** | 421 (414-426) | 5/5 |
| t32 | 503 (494-550) | 520 (515-591) | 207 (206-210) | 419 (412-428) | 5/5 |

**The harness's wall and CPU columns do not cover identical work here.** It stops on a 2 s poll, and arms overshot the end height by different amounts: t8 reached 55-70 blocks (4 of 5 runs above 55), t16 55-60, t32 55. The cause of t8's larger overshoot was not investigated. The harness's wall column (t16 24, t8 26, t32 24 s) is therefore not used.

## (c) Wall over identical heights, from the log timestamps
scripts/e022_segments.py, evidence/E022/segments.csv. `Synced N` means blocks up to index N-1 are done, and batches are 5 blocks, so segments are cut on batch boundaries.

| segment | t16 s | t8 s | t32 s |
|---|---|---|---|
| whole window, blocks 3,106,065-3,106,114 | 18.65 (18.58-18.77) | 19.16 (19.11-19.50), **+2.8%** | 18.77 (18.66-18.95), +0.6% |
| blocks 3,106,070-3,106,104, all at 8 inputs | 13.66 (13.63-13.74) | 14.21 (13.98-14.41), **+4.0%** | 13.70 (13.62-13.82), +0.3% |
| blocks 3,106,105-3,106,109, four at 16 inputs | 2.56 (2.52-2.69) | 2.63 (2.53-2.70), +2.9% | 2.61 (2.57-2.66), +2.0% |

t8's whole-window and 8-input ranges do not overlap t16's. The last row's ranges all overlap, and t8 and t16 treat those 16-input blocks the same way, so about 3% is within noise on a segment that short.

## Reading
- **t8 trades a small wall cost for less CPU and a lower peak on 8-input blocks.** Whole-window wall +2.8%, CPU -21%, peak anon -7% (35 MB). t8's CPU figure covers at least as many blocks as t16's, so -21% is if anything understated. The one like-for-like run, round 3, had 55 blocks in both arms and shows 140 vs 199 s.
- **Under the rule t8 is selected:** CPU is more than 5% better with non-overlapping ranges, and peak is not worse. The rule did not state a limit on wall when CPU improves, so the +2.8% is reported rather than decided by it.
- **t32 gives nothing:** wall and peak ranges overlap t16's, and CPU is +4%, under the 5% line and in the wrong direction. Its test covers only 5 blocks.
- **Cap and trim are not separated.** `heavy_call` switches both, so this does not say which one produces the CPU saving. The pattern of less CPU and slightly more wall resembles SMT contention seen in E004c and E011, but that is an inference.
- **Absolute stakes are small on this chain:** 83 of 43,270 blocks fall between 8 and 15 inputs, and the memory saving is 35 MB on a ~500 MB peak.
- **Below 8 is untested.** Blocks with a largest tx of 3-7 inputs number 43 and do not form a usable window. E011 showed the cap costing +7.3% wall at 2 inputs, so the crossover in wall lies somewhere below 8 inputs but is not located.

## (d) Small-tx guard: it passed, but it has no power
t8 vs t16 on the standard small-tx window, 3 rounds, 2026-11-04 02:40-03:24, scripts/run_e022b.sh, evidence/E022/guard_small. Medians (min-max):

| arm | wall from logs, blocks 3,106,405-3,107,399, s | CPU s | peak RssAnon MB | hashes |
|---|---|---|---|---|
| t16 | 152.8 (152.4-153.6) | 1,440 (1,433-1,441) | 803 (802-817) | 3/3 |
| t8 | 152.5 (152.3-152.9) | 1,448 (1,443-1,449) | 811 (805-838) | 3/3 |

The pre-set criterion is met literally, but **this window contains no block with a largest tx of 8-15 inputs (E022a scan: 0 of 1,000), so the two builds behave identically on it.** I chose the window without checking that. It is an A/A run and says nothing about the cost of threshold 8, so it is not counted as support.

It does measure the noise floor between two builds that behave the same: peak anon +1.0% (8 MB) and CPU +0.6%, with CPU ranges that do not overlap (t8 also ran 5 blocks further in 2 of 3 runs). Non-overlapping ranges over 3 rounds are therefore weak evidence at this scale. That supports E021's reading of its 9 MB small-tx peak gap as probably noise.

## (e) Replication
t8 vs t16 on two independent stretches where the arms really differ, 5 rounds each, scripts/run_e022c.sh, 03:26-05:04.
- Window A: 3,105,080 -> 3,105,106. Largest tx 8 inputs on 3,105,089-3,105,101, those txs nearly all 8-input.
- Window B: 3,106,260 -> 3,106,286. Largest tx 8 inputs on 3,106,268-3,106,280, about a third of the txs 8-input.

Wall from log timestamps and CPU from scripts/cpu_watch.sh, both over identical heights. **Criterion, fixed before the run. On both windows: t8's CPU at least 5% lower with non-overlapping ranges, wall no more than +5%, peak anon not worse by more than 5%, all hashes match. Then threshold 8 becomes a one-line patch. Otherwise 16 stays.**

Medians of 5 (min-max), wall and CPU over identical heights (evidence/E022/repl_a, repl_b):

| window | segment (Synced) | arm | wall s | CPU s | peak anon MB, whole run | peak anon MB, samples inside the window | hashes |
|---|---|---|---|---|---|---|---|
| A | 3,105,085-3,105,105 | t16 | 8.20 (8.14-8.28) | 67.9 (66.7-68.2) | 478 (475-483) | 478 (470-484) | 5/5 |
| A | | t8 | 8.45 (8.32-8.59) | 47.1 (46.8-48.1) | 470 (428-484) | 425 (422-427) | 5/5 |
| B | 3,106,265-3,106,285 | t16 | 6.62 (6.58-6.64) | 53.6 (50.6-54.5) | 437 (432-443) | 423 (423-424) | 5/5 |
| B | | t8 | 6.86 (6.79-6.97) | 37.6 (36.1-37.9) | 431 (415-444) | 400 (394-420) | 5/5 |

| criterion | A | B |
|---|---|---|
| CPU at least 5% lower, ranges not overlapping | -30.5%, no overlap: pass | -29.9%, no overlap: pass |
| wall no more than +5% | +3.0%: pass | +3.7%: pass |
| peak anon not worse by more than 5% | -1.7% whole run, -11.2% inside the window: pass | -1.4% whole run, -5.6% inside the window: pass |
| all hashes match | 10/10: pass | 10/10: pass |

**Passes on both windows, so threshold 8 is adopted.**

### Reading the replication
- **The whole-run peak and the in-window peak say different things, and both are reported.** The whole-run column comes from ab_stats and includes each arm's overshoot past the window end (80-90 blocks recorded on A, 30-35 on B), and its ranges overlap. The in-window column (scripts/e022c_peak.py) keeps only sampler rows whose height is inside the window. Those ranges do not overlap, but each run has only 5 samples at 2 s spacing, and a sampled height from RPC can lag. On A the last in-window sample is at height 3,105,100, so that column does not reach A's blocks of 16-32 inputs.
- **So t8 lowers memory only while 8-15 input blocks are being verified.** Once a run includes larger proofs, which are heavy in both arms, the peak moves by less than the run-to-run spread. The -7% on the first window in (b) does not carry over as a general peak reduction. This does not touch the headline heavy-window peak, which larger proofs set.
- **The measured segments are not purely 8-input blocks.** A's segment holds 3,105,102-3,105,104 at 16-32 inputs. B's holds 3,106,281 at 16 inputs and 3,106,284 at 64. Both arms treat those the same, so they dilute the differences rather than inflate them. An earlier note assumed A had no such blocks; the scan shows it does.
- **CPU resolution:** cpu_watch.sh samples every 0.5 s, and the height it reads changes only at batch boundaries. The spread across runs is under 4 s against a gap of 16-21 s, so the sampling does not decide the result.
- **Stakes stay small on this chain:** 83 of 43,270 blocks have a largest tx of 8-15 inputs. Cap and trim are still switched together, so which one gives the CPU saving is not separated. Thresholds below 8 remain untested.

### Adoption
One-line commit adbe70cf8 in `~/work/monero-fcmp-idle`. Rebuilding from that commit gives sha256 d779a522, byte-identical to the t8 binary measured here. Patches: `patches/v1-E007-full-streaming/monerod/0007-E022-*.patch` and `patches/v2-E017-minimal/monerod/0008-E022-*.patch`. On v2, 0007 + 0008 pass `git apply --check` on the e020 tree; that combination has not been built or measured.

`--version` on these binaries still prints 4a51d434d, because the version string is fixed when CMake configures. Identify them by sha256.

**Not rerun at adoption:** the headline windows, the negative test, min_mem and the long resync. The small-tx window has no 8-15 input blocks (d), but the heavy window 3,105,401-3,105,445 has 2 of its 24 non-empty blocks in that range, so the behaviour there changes slightly. E023 (experiments/E023-final-validation) validated the final series afterwards.

## Guardrails
- One change per arm: the constant only; three distinct sha256 in the chain log; tree restored and clean afterwards.
- 15/15 runs matched .22's hash at their tip on the first window, 6/6 on the guard, 20/20 on the replication. No shadow lanes during the chains. Governor restored.
