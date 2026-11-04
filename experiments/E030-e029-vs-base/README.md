# E030: e029 against base, small-tx window

**Status: done. All expectations met. On small-tx blocks e029 is not separable from base on wall (+1.1%, ranges overlap) or CPU (-0.7%, overlap), and its peak anon is -23.5% (separate). This is a report on the E029 option. Final stays the recommended build (owner's decision, 2026-11-04).**

**Why:** E029 compared e029 only with final. Its comparison with base was across two chains, and it is the option's main claim.

**Setup:** hydrogen, 2026-11-04 20:20-21:32, `scripts/run_e030.sh`, chain log evidence/E030/e030.chain. Arms: base (sha 2d1e3e9c), e029 (sha d93a9703). Small-tx window 3,106,400 -> 3,107,400, `ab_window.sh`, `--block-sync-size 5`, 5 alternating rounds, DB restored from the snapshot before each run, single peer 192.168.1.22, governor pinned, no shadow lanes. 10/10 hashes.

## Result, medians of 5 (min-max)
| arm | wall s, logs, 3,106,405-3,107,400 | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 145.5 (143.9-147.6) | 1,336 (1,324-1,340) | 1,137 (950-1,295) | 1,297 (1,142-1,434) | 4,155 (4,116-4,313) | 977 (950-1,137) |
| e029 | 147.1 (144.8-148.4) | 1,327 (1,321-1,331) | 870 (854-891) | 1,060 (1,032-1,098) | 4,074 (4,050-4,108) | 729 (713-743) |
| change | +1.1%, overlap | -0.7%, overlap | **-23.5%, separate** | -18.3%, separate | -1.9%, overlap | **-25.4%, separate** |

Peak anon recomputed from the samplers up to the window end gives 1,134 vs 867 MB, also -23.5%. e029 was slower in 3 of 5 rounds by log wall. A small real cost cannot be ruled out in 5 rounds, and the median says +1.1% (+1.6 s).

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| wall within 1.5% of base | +1.1%, overlap | met |
| CPU within 2% of base | -0.7%, overlap | met |
| peak anon below base, separate, about -15 to -25% | -23.5%, separate | met |
| post-idle anon about -25 to -30% | -25.4% | met, at the near end |
| all hashes match | 10/10 | met |

## Reading
- **The option removes the recommended build's main cost on these blocks.** Final is +5.5% against base here (E028, 5 rounds), and e029 is +1.1% with overlapping ranges. It keeps most of final's small-tx memory saving: -23.5% against E028's -23.8% for final, each against its own run's base, with base's peak soft (950-1,295 MB here, 1,028-1,262 MB in E028). Those two percentages should not be read as equal: E029 measured e029 at +7.0% against final directly.
- **The across-chain reading in E029 holds.** It gave 146.2 vs 146.4 s; the direct run gives 147.1 vs 145.5 s, with overlapping ranges in both.
- **Nothing changes in the recommendation.** The goal is memory, and final has the lower peak. E029's limits still apply, above all that proofs of 3-7 inputs are not measured.

## Limits
One window, one box. Heavy window not rerun here: e029 vs final there is in E029, and base vs final in E023. Base's peak is soft, so the percentage against it carries that.

## Guardrails
One arm pair, sha256 of each in the chain. 10/10 hashes. No lanes at the start. Governor restored. box81 idle at the 20:47 check, with nothing of ours queued there. Evidence: evidence/E030 (chain, results.csv, summary.txt, per-run mem.csv).
