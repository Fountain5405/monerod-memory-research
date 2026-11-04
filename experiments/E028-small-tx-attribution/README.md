# E028: where the small-tx wall cost lies

**Status: done. Most of it is the streaming verifier: +3.8% of the +5.5% total, the only step with separate ranges. The rest of adapt and the light-call trims add about +0.8% each, too small to separate in 5 rounds. The whole gap is +5.5% here, not E023's +6.6%: one expectation missed.**

**Why:** small-tx wall is the recommended build's main cost. E023b showed the last two patches do not cause it, and E026 showed light-call trims are at most about 1.4% of it.

**Setup:** hydrogen, 2026-11-04 14:50-17:18, `scripts/run_e028.sh`, chain log evidence/E028/e028.chain. Four arms, each one step from the last: base (sha 2d1e3e9c), e007 (base + streaming verifier, the E011 binary, ab3038be), inever (final with no light-call trim, the E026 binary, 3a858c3b), final (d779a522). Small-tx window 3,106,400 -> 3,107,400, `ab_window.sh`, `--block-sync-size 5`, 5 alternating rounds, DB restored from the snapshot before each run, single peer 192.168.1.22, governor pinned, no shadow lanes. 20/20 hashes.

**Reading, fixed in the script before the run:** a step counts as a contribution only if the two arms' ranges do not overlap. Report only, no change to the recommended build.

## Result, medians of 5 (min-max)
| arm | wall s, logs, 3,106,405-3,107,400 | CPU s | peak anon MB | post-idle anon MB | peak RSS MB |
|---|---|---|---|---|---|
| base | 146.4 (144.6-147.5) | 1,337 (1,333-1,343) | 1,073 (1,028-1,262) | 1,016 (956-1,211) | 4,114 (4,056-4,475) |
| e007 | 151.9 (151.3-152.9) | 1,444 (1,437-1,455) | 906 (895-938) | 905 (895-938) | 4,057 (4,038-4,080) |
| inever | 153.1 (152.5-154.4) | 1,442 (1,439-1,448) | 847 (841-857) | 713 (710-728) | 4,004 (3,996-4,009) |
| final | 154.4 (152.3-154.7) | 1,443 (1,440-1,448) | 818 (807-821) | 717 (700-725) | 3,945 (3,933-3,949) |

## The steps
| step | what it adds | wall | wall ranges | CPU | peak anon | peak ranges |
|---|---|---|---|---|---|---|
| base -> e007 | the streaming verifier | **+3.8%** (+5.5 s) | separate | +8.0% | -15.6% | separate |
| e007 -> inever | the rest of adapt, E021, E022, no light-call trim | +0.8% (+1.2 s) | overlap | -0.1% | -6.5% | separate |
| inever -> final | light-call trims every 10 s | +0.8% (+1.3 s) | overlap | +0.1% | -3.4% | separate |
| base -> final | all of it | **+5.5%** (+8.0 s) | separate | +7.9% | -23.8% | separate |

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| e007 about +3% over base (E011 +2.7%) | +3.8% | met, on the high side |
| inever within 1% of e007, from reading the code | +0.8%, overlap | met |
| final about +1.4% over inever (E026) | +0.8%, overlap | below it; E026's ranges overlapped too |
| final about +6.6% over base (E023) | **+5.5%** | **miss** |

The script said these could not all hold, since +2.7% and +1.4% do not add up to +6.6%. The one that gave way is the total. With 5 rounds in one chain, I put more weight on +5.5% than on E023's +6.6% from 3 rounds, but E023's stands as measured. Box81 also measured +5.5% (E027).

## Reading
- **About two-thirds of the cost is the verifier** (5.5 of 8.0 s), the only separate step, and the only one that costs CPU: +8.0%, against 0.1% or less for the others. E011 traced this to building every circuit twice.
- **The two smaller steps cost wall and no CPU that shows.** Taken together, final vs e007 is +1.6%: slower in all 5 rounds, by 0.2-3.4 s, though the ranges overlap. Their source is not measured here. On the fixed reading neither step counts alone.
- **There is no tuning left to recover this.** The constants are swept (E022, E026). What is left is the double build, and v2 does not remove it: v2final is another +2.7% (E025). Any further gain needs a change to the verifier.
- **Every step lowers memory.** Peak goes 1,073 -> 906 -> 847 -> 818 MB, all with separate ranges. Post-idle falls most at e007 -> inever (905 -> 713 MB). That step bundles the heavy-call trims and E021, and this run does not separate them.
- **The wall steps pay for memory.** The verifier's +3.8% comes with -15.6% peak here, and with far more on heavy blocks, where it is 2x faster.

## Limits
One window, one box. The e007 binary is from E011, built on the same base. Base's peak is the soft figure it always is (1,028-1,262 MB here), so the percentages against it carry that.

## Guardrails
One step per arm, sha256 of each in the chain. 20/20 hashes. No lanes at the start. Governor restored. box81 was idle, so only this box was syncing from .22 of the two. Evidence: evidence/E028 (chain, results.csv, summary.txt, per-run mem.csv).
