# E025: build v2 with its last two patches, and rerun the differential test on both final series

**Status: done. Both series give base's decision on all 236 differential cases. v2 now builds and runs with E021 and E022. v1 stays recommended: v2's peak is no better on the evidence and heavy wall stays +27.5%.**

**Why:** E023 left two gaps open and said so. The differential test E015 predates E021 and E022, and v2's patches 0007 + 0008 had only passed an apply check. Neither patch touches verification, so the argument that E015 carried over came from reading the code.

**Setup:** hydrogen, 2026-11-04 09:44-11:29, `scripts/run_e025.sh`, chain log evidence/E025/e025.chain. Tree `~/work/monero-fcmp-v2final` = the e020 tree (including its local Cargo.toml repoint) + `git am` of v2's 0007 and 0008, build dir `build/beta31-v2final`. Arms by sha256: base 2d1e3e9c, final d779a522, v2final a9969e61. A/B: `ab_window.sh`, `--block-sync-size 5`, 3 alternating rounds, DB restored from the snapshot before each run, single peer 192.168.1.22, governor pinned, no shadow lanes.

## Expectations, fixed in the script before the run
| expectation | result | |
|---|---|---|
| DIFF PASS at both heights | PASS at both | met |
| all hashes match | 12/12 | met |
| v2final peak anon within 5% of final, small-tx | +0.2%, ranges overlap | met |
| v2final peak anon within 5% of final, heavy | **-7.1%**, ranges overlap | outside the band, on the favourable side |
| heavy wall about +28% | +27.5% from logs, ranges separate | met |
| small-tx wall about +3% | +2.7% from logs, ranges overlap | met, but not separable from final in 3 rounds |

The heavy peak is a literal miss and I do not read it as a v2 win: final's range (1,658-1,841 MB) overlaps v2final's (1,640-1,677 MB). v2final's peak varied less in these 3 rounds, which is all this can show.

## (a) Differential test
`scripts/negdiff.sh`, base as the oracle, final and v2final compared against it. evidence/E025/neg.

| height | txs (inputs) | cases | tampered / swapped / original | (status, flags) disagreements, final / v2final | reason-text differences |
|---|---|---|---|---|---|
| 3,105,401 | 4 (128 each) | 135 | 128 / 3 / 4 | 0 / 0 | 0 / 0 |
| 3,106,400 | 3 (2 each) | 101 | 96 / 2 / 3 | 0 / 0 | 0 / 0 |

**236 cases, 0 disagreements for either build.** The input case files have the same sha256 as E015's (a650d846... and b4cf579f...), so this is the same test on the later builds, not a new sample. In all three builds the log shows 127 + 98 = 225 rejections at the FCMP++ check, and the oracle's flag mix gives 225 `invalid_input` plus 4 with no flag, as in E015. These 236 cases use 128- and 2-input txs only: rejection on the 8-input path that E022 moved into the heavy branch is covered by E023's negative test, not by this table.

## (b) Heavy window 3,105,401 -> 3,105,441, medians of 3 (min-max)
| arm | peak anon MB | peak RSS MB | wall s, logs, 3,105,406-3,105,441 | CPU s | post-idle anon MB | hashes |
|---|---|---|---|---|---|---|
| final | 1,803 (1,658-1,841) | 3,031 (2,997-3,072) | 107.2 (106.0-108.9) | 911 (904-916) | 1,129 (1,082-1,152) | 3/3 |
| v2final | 1,675 (1,640-1,677) | 2,871 (2,847-2,881) | 136.7 (134.6-141.2) | 1,222 (1,220-1,230) | 795 (771-802) | 3/3 |

v2final vs final: peak anon -7.1% (overlap), wall **+27.5%** (harness figure +26.1%), CPU +34.1%, post-idle **-29.6%** (ranges separate).

## (c) Small-tx window 3,106,400 -> 3,107,400, medians of 3 (min-max)
| arm | peak anon MB | peak RSS MB | wall s, logs, 3,106,405-3,107,400 | CPU s | post-idle anon MB | hashes |
|---|---|---|---|---|---|---|
| final | 803 (802-813) | 3,953 (3,952-3,955) | 155.1 (154.9-162.6) | 1,440 (1,437-1,442) | 712 (707-712) | 3/3 |
| v2final | 805 (793-808) | 3,946 (3,943-3,949) | 159.3 (156.6-159.5) | 1,492 (1,484-1,503) | 711 (709-714) | 3/3 |

v2final vs final: peak +0.2%, wall +2.7% (harness +2.5%, ranges overlap, one final run at 162.6 s is what makes them overlap), CPU +3.6%, post-idle -0.1%.

## Reading
- **The carry-over argument now has a measurement behind it.** Final decides all 236 cases as base does. E023's report of "run on the build before E021 and E022" can go.
- **E021 and E022 change v2 as expected.** Its gap to v1 is what E020 measured before them (+28% and +3%).
- **v2's one memory gain is post-idle after heavy blocks,** 795 vs 1,129 MB. It is gone after small-tx blocks (711 vs 712 MB). Why it holds less after heavy blocks is not investigated. E020 saw the same direction (-25% vs adapt).
- **Decision: no change.** v1 stays recommended and v2 stays the alternative. Choosing between them is still the owner's call.

## Not measured on v2final
Cgroup minimum, long resync, negative test `negtest.sh`, second machine. Those figures for v2 are from E018/E019/E020, before E021 and E022. Timings in the negdiff logs are single runs on a different workload and are not read.

## Guardrails
One change per arm by sha256 in the chain. 12/12 hashes. No shadow lanes at the start of each A/B. Governor restored. Evidence: evidence/E025 (chain, per-window results.csv, summary.txt, mem.csv; negdiff summaries and verdict JSON, without the raw logs or the 2 MB case files).
