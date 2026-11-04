# E026: sweep the light-call trim interval

**Status: done. 10 s stays. Trimming less often does not meet the rule: 60 s saves 0.8% wall with overlapping ranges and raises the peak by 4.4%. Removing light-call trims altogether saves 1.4% at most, so they do not explain the small-tx wall gap.**

**Why:** the 10 s interval was the last tuning constant never swept, and SUMMARY listed it as a judgment call. Small-tx wall (+6.6% vs base in E023) is the build's main cost, so a longer interval was the obvious thing to try.

**Setup:** hydrogen, 2026-11-04 11:29-13:22, `scripts/run_e026.sh`, chain log evidence/E026/e026.chain. Three binaries from the final tree, differing only in the constant in `now_ms - s_fcmp_last_trim_ms ... >= 10000` in rctSigs.cpp: i10 (sha d779a522, the final binary), i60 (266f354b), inever (3a858c3b, about 30 years, so no light-call trim). Heavy calls and the idle trim are unchanged. Small-tx window 3,106,400 -> 3,107,400, `ab_window.sh`, `--block-sync-size 5`, 5 alternating rounds, DB restored from the snapshot before each run, single peer 192.168.1.22, governor pinned, no shadow lanes. The tree was restored afterwards: clean, binary back at d779a522.

**Rule, fixed in the script before the run:** adopt i60 only if its wall is at least 2% below i10 with non-overlapping ranges, peak anon not worse by more than 5%, and all hashes match. Otherwise 10 s stays. inever is a bound, never a candidate.

## Result, medians of 5 (min-max)
| arm | wall s, logs, 3,106,405-3,107,400 | peak anon MB | peak Private_Dirty MB | CPU s | post-idle anon MB | hashes |
|---|---|---|---|---|---|---|
| i10 | 156.1 (154.7-157.1) | 810 (793-821) | 978 (958-1,006) | 1,440 (1,433-1,441) | 708 (701-727) | 5/5 |
| i60 | 154.8 (153.4-155.7) | 846 (840-854) | 1,026 (1,014-1,056) | 1,436 (1,431-1,450) | 715 (709-723) | 5/5 |
| inever | 154.0 (152.2-155.1) | 847 (827-853) | 1,019 (1,008-1,027) | 1,442 (1,437-1,448) | 717 (708-723) | 5/5 |

| vs i10 | wall, logs | wall ranges | peak anon | peak ranges | CPU |
|---|---|---|---|---|---|
| i60 | -0.8% | overlap | +4.4% | separate | -0.3% |
| inever | -1.4% | overlap | +4.6% | separate | +0.1% |

In each of the 5 rounds both were faster than i10 from the logs, i60 by 1.0-2.2 s and inever by 1.6-3.2 s, so the direction looks real even though the ranges overlap. It is just small.

## Against the rule
| condition | result | |
|---|---|---|
| wall at least 2% below i10 | -0.8% | **not met** |
| non-overlapping wall ranges | overlap | **not met** |
| peak anon not worse by more than 5% | +4.4% | met |
| all hashes match | 15/15 | met |

**Decision: 10 s stays.** No patch.

## Reading
- **The interval trades a little memory against a little wall, and 10 s is a defensible point.** Going from 10 s to 60 s gives up nearly all the peak benefit of light-call trims (+4.4%, against +4.6% with none) for a wall saving of 0.8%. About 36 MB for about 1.3 s on this window.
- **Light-call trims are not the small-tx cost.** With none at all, wall drops by 1.4%. E023's gap against base on this window is +6.6%, so most of it lies elsewhere in adapt. This compares across experiments, on the same window and box. Which part of adapt carries it is not measured here; E011's +2.7% for E007 alone and +7.3% for the cap alone predate the adaptive cap and do not settle it. (E028 later measured it: streaming verifier +3.8%, the rest +0.8% each.)
- **No effect on CPU or post-idle anon that the spread can show.** CPU medians are within 0.3%, and post-idle ranges overlap, as expected: the idle trim is unchanged.

## Limits
Only 10 s, 60 s and no trim were tried, on hydrogen, on one window. Shorter intervals were not tried, and neither was a long sync at the tip. The peak here is about 810-850 MB of a small-tx window; heavy blocks trim on every call and are unaffected.

## Guardrails
One constant changed per arm, sha256 of each binary in the chain. 15/15 hashes. No shadow lanes at the start. Governor restored. Box81 was not syncing from .22 during this run: E027's A/B was held until the marker appeared. Evidence: evidence/E026 (chain, results.csv, summary.txt, per-run mem.csv).
