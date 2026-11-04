# E027: the final v1 series on the second machine (box81, hostname moonpie)

**Status: done. Eight of nine expectations met. The miss is small-tx peak: -18.8% against about -33%. Final's own figure did not move; base's did, and I do not know why. Everything here compares base and final on this box, never with hydrogen.**

**Why:** E019 reproduced adapt on box81, but E021 and E022 came later, so every final-series figure was from hydrogen alone. I had listed this as not planned. The owner asked whether anything useful could run on moonpie, and this was the answer.

**Setup:** box81 (Ryzen 5 5600G, 6c/12t, 14 GB, 12 verifier threads by default), 2026-11-04 11:56-14:48, `scripts/run_e027a.sh` and `run_e027b.sh`, chain logs evidence/E027/e027a.chain and e027b.chain. Arms by sha256: base bac70623 (the E019 binary), final a9a22c46, built here natively with `nice -n 10`, `-j6`, Release, ARCH=native. `ab_window.sh` has not changed since before E019. `--block-sync-size 5`, 3 alternating rounds, single peer 192.168.1.22. Heavy runs restore the DB from the snapshot; small-tx runs rewind in place with `pop_to.sh`, as in E019. Governor pinned, then restored. The A/B waited for E026 to finish, so the two boxes did not share .22 during E026's timing.

## Expectations, fixed in the script headers before the run
| expectation | result | |
|---|---|---|
| final's source tree matches hydrogen's | same tree hash, fcbc96d34eee, from `git am` of the published patches 0006 and 0007 on adapt | met |
| differential test PASS, heavy height, 135 cases | 0 disagreements | met |
| differential test PASS, 3,106,400, 101 cases | 0 disagreements | met |
| heavy peak anon about -60% | **-61.0%** | met |
| heavy post-idle at least -71% | **-76.3%** | met |
| heavy wall about -43% | **-42.3%** from logs | met |
| small-tx peak anon about -33% | **-18.8%** | **MISS** |
| small-tx post-idle at least -18.5% | **-27.9%** | met |
| small-tx wall +5% to +7% | **+5.5%** from logs (+6.0% harness) | met |

Also: 13/13 window hashes matched .22 (12 A/B runs and the prep sync), and VmSwap was 0 in every A/B sample.

## Heavy window 3,105,401 -> 3,105,441, medians of 3 (min-max)
| arm | peak anon MB | peak RSS MB | wall s, logs, 3,105,406-3,105,441 | CPU s | post-idle anon MB | hashes |
|---|---|---|---|---|---|---|
| base | 3,342 (3,230-3,377) | 4,647 (4,530-4,769) | 232.8 (232.1-235.2) | 2,387 (2,373-2,417) | 2,903 (2,854-3,003) | 3/3 |
| final | 1,303 (1,302-1,311) | 2,510 (2,509-2,527) | 134.3 (134.2-135.5) | 658 (656-671) | 687 (647-739) | 3/3 |

final vs base: peak anon -61.0%, peak RSS -46.0%, wall -42.3%, CPU -72.4%, post-idle -76.3%. All ranges separate.

## Small-tx window 3,106,400 -> 3,107,400, medians of 3 (min-max)
| arm | peak anon MB | peak RSS MB | wall s, logs, 3,106,405-3,107,400 | CPU s | post-idle anon MB | hashes |
|---|---|---|---|---|---|---|
| base | 904 (834-913) | 3,949 (3,833-4,105) | 146.4 (145.0-147.8) | 979 (976-981) | 904 (814-913) | 3/3 |
| final | 734 (734-738) | 3,759 (3,458-3,814) | 154.4 (154.1-154.5) | 1,071 (1,060-1,071) | 652 (647-661) | 3/3 |

final vs base: peak anon -18.8%, wall +5.5%, CPU +9.4%, post-idle -27.9%. Peak anon, wall and CPU ranges separate.

## The miss
| | E019 (2026-11-03) | E027 |
|---|---|---|
| base small-tx peak anon | 1,091 (964-1,252) | 904 (834-913) |
| adapt / final small-tx peak anon | 729 (727-738) | 734 (734-738) |

**Final's figure is where adapt's was. The percentage moved because base's did**, with separate ranges, on the same binary (sha bac70623), harness and window. I set -33% from one 3-run median of a figure that varies this much, and that was the error in the expectation. E014's check-in already noted base's peak varying run to run while adapt's stays tight. Why base came in lower this time is not investigated: the runs differ in time and in arm count, three arms in E019 and two here. The honest range for small-tx peak on this box is -19% to -33%, and on hydrogen E023 measured -26.3%.

## Differential test
Same case files as E015 and E025 by sha256, base as the oracle: 236 cases, 0 disagreements in (status, flags) or reason text, with 225 rejections at the FCMP++ check, the same as on hydrogen. The base binary and the final binary here were compiled with ARCH=native for Zen3, so this exercises different machine code from hydrogen's. evidence/E027/neg.

## Reading
- **The final series reproduces on a second machine.** The heavy-window gains hold on a CPU with half the cores, and the wall gain and the peak gain are in line with E019.
- **The idle trim shows here too.** Same box, across experiments: heavy post-idle 902 MB for adapt in E019, 687 MB for final here. Small-tx 695 MB against 652 MB. These cross a day, so they are indicative.
- **The small-tx wall cost is real and not specific to hydrogen:** +5.5% here, +6.6% in E023.
- **Peak figures for base on small-tx blocks are soft on both machines.** Any percentage against them carries that.

## Limits
No cgroup minimum and no long resync on this box. No thread sweep on the final series. 3 rounds per window. The in-place rewind for small-tx can leave LMDB's file laid out differently from a restored copy, for both arms alike; this is E019's protocol, kept for comparability.

## Guardrails
Idle check at the start: load 0.00, 4 `user` sessions with nothing running. `selfishmining` and `blocksize` had no processes when part a started. Nothing outside /home/optimizer touched except the governor, restored to powersave. 43 GB free at the end. Negdiff at 3,106,400 ran with the working DB as its snapshot, so its `cp` failed on purpose ("are the same file") and `pop_to.sh` did the rewind; RESULT OK. Evidence: evidence/E027 (chains, results.csv, summary.txt, per-run mem.csv, negdiff summaries and verdict JSON; no raw logs).
