# E035: the window-aware E001 sync cap, built and tested

**Status: done. Part b: on the real chain the cap passes the wedge and behaves as the current cap does, 4 blocks at every decision, no cost in wall, CPU or memory, 11/11 hashes; two expectations missed, one narrowly and one because I wrote it wrongly. Part a: against Blockchain's real weight-limit code, the window-aware cap keeps every batch at or under 90.0 MB of weight at HF 16, at v17 with F 625 kB and at stressnet's F 10 MB. The current cap reaches 116-129 MB at v17, and 148 MB at HF 16 with `--batch-max-weight 50`. The real code reproduces the owner's simulation to within 0.1 MB in all 24 cells. Report only.**

**Why:** the owner's analysis (72a62f5, `reports/E001-sync-wedge-ISSUE.md`) found patch 0003's cap too loose for post-FCMP++ mainnet rules and proposed this one, simulated but not built. Owner approved building and testing it on 2026-11-05.

**The change:** `patches/options/E035-window-cap/`, on top of `final`. +17/-4 in `cryptonote_core.cpp`, +11 in `cryptonote_core.h`, the owner's formula in a function `get_block_sync_size_cap`, so it can be tested. Plus `tests/unit_tests/block_sync_size_cap.cpp` (+217) and one line of CMake.

**Why two parts:** on stressnet the limit is 20 MB, so this cap gives 4 blocks, the same as the current one, unless the largest recent block reaches 11.25 MB. The step above 50 blocks needs a limit under 1.8 MB and never applies there. A passing live sync says nothing about the new logic.

## Part a: the real limit code (box81, 2026-11-05 11:26 to 11:37, `scripts/run_e035a.sh`, no timing, no .22)
The test instantiates `Blockchain` on an in-memory test DB and calls the real `update_next_cumulative_weight_limit` and `get_next_long_term_block_weight`. It builds each window shape from `scripts/e001_batch_weight_sim.py` (k small blocks then 100-k of weight A, and the reverse, keeping only windows where every block fit under the limit in force), then fills 100 more blocks to the limit the code computes. Full grid: 72,922 windows per rule set. HF 17 with F 625 kB comes from a second tree with that one constant changed, test-only and never run on a network. Three tests passed in each tree, on the coarse grid and the full one.

Worst batch, MB of weight. Each cell is real code, with the simulation's figure in brackets where it had one:

| rules | `--batch-max-weight` | no cap | current cap (0003) | window-aware cap | blocks |
|---|---|---|---|---|---|
| HF 16, F 300 kB | 10 (default) | 89.5 (89.5) | 89.5 (89.5) | **89.5** (89.5) | 100 |
| | 30 | 89.7 (89.7) | 89.7 (89.7) | **89.7** (89.7) | 100 |
| | 40 | 119.3 (119.3) | 119.3 (119.3) | **89.7** (89.7) | 100 |
| | 50 | 149.4 (149.4) | 148.2 (148.2) | **89.7** (89.7) | 100 |
| v17, F 625 kB | 10 (default) | 186.3 (186.3) | 116.4 (116.4) | **88.9** (88.9) | 61 |
| | 30 | 186.5 (186.6) | 116.7 (116.7) | **89.2** (89.2) | 61 |
| | 40 | 186.7 (186.7) | 116.8 (116.8) | **89.4** (89.4) | 61 |
| | 50 | 186.8 (186.8) | 129.3 (129.3) | **90.0** (90.0) | 50 |
| v17, F 10 MB, stressnet | 10 (default), 30, 40 | 2,980 | 80.0 | **80.0** | 4 |
| | 50 | 2,980 | 95.0 | **90.0** | 4 |

The model and the real code differ by at most 0.1 MB, in one cell. Worst-case block counts also agree: 72 and 61 and 50 at v17.

**One case the simulation did not include:** at stressnet's F 10 MB with `--batch-max-weight 50`, the current cap reaches 95.0 MB and the window-aware cap 90.0 MB. So the new cap's window term matters on stressnet too, but only with that flag and a window whose blocks reach 11.25 MB or more.

**Random windows, an addition not fixed in advance (`scripts/e035_random_windows.py`, evidence/E035/e035_random.txt):** the grid only has two-weight shapes. 20,000 random windows per rule set, in bursts of small, random and full blocks, through the simulation's model. Window-aware cap's worst: 89.7 MB at today's rules and 89.4 MB at v17. Random windows rarely hold a very small W, so they reach much lower totals at the default batch size (about 20 MB), and they test mixed shapes only.

### Expectations for part a, fixed before the run
| expectation | result | |
|---|---|---|
| `values` test passes | passed in both trees | met |
| real code within 0.5 MB of the simulation (none, patch, window; HF 16 and v17 F 625 kB) | at most 0.1 MB, 24 cells | met |
| window-aware worst at or under 90.5 MB in every cell, including F 10 MB | at most 90.0 MB | met |

### What part a does not show
- **It is a search, not a proof.** It covers the shapes above and the random windows. The issue's derivation gives the general bound; I re-derived it by hand and agree with it, which is not a machine check.
- **Weight, not bytes.** The levin limit is in bytes. The 10% margin relies on bytes per unit of weight staying under about 1.1. The issue measured 0.82-0.84 on stressnet FCMP++ blocks and estimated about 1.02 for small pre-FCMP++ txs; this test adds nothing to that.
- **F is held constant.** The long-term median sits at the floor because 1,200 small blocks are prefilled with a 1,000-block window (mainnet's is 100,000). So F rising inside a batch is not tested.
- **No real blocks or sockets.** No batch over the network at v17's sizes. That would need a purpose-built chain with full 1.25 MB blocks.
- **Queued spans:** W does not include queued blocks, so this case stays partly covered, as the issue says.
- **The v17 constants are from the issue** (`fcmp++-stage` f25388d, 625 kB). I did not recheck them against that branch today.
- Only this test's filter was run, not the whole unit test suite.

## Part b: the real chain (hydrogen, 2026-11-05 13:44 to 17:40, `scripts/run_e035b.sh`, chain log evidence/E035/partb/e035b.chain)
Tree `~/work/monero-fcmp-e035` = final + this patch, tree hash ced7116c as expected. Arms: base (sha 2d1e3e9c), final (sha d779a522), window (sha 91ca4cfa). Default sync settings, no `--block-sync-size`. Single peer 192.168.1.22, DB restored before each run, governor pinned and restored, no lanes. W006 was mining on box81 and .22 relayed its blocks throughout; E033 found no visible effect from that.

**This is a regression test.** On stressnet the limit is 20 MB, and the largest block in the whole range is 10,030,448 bytes, under the 11.25 MB that would move this cap off 4 blocks. So both caps should decide the same thing every time, and they did.

### Wedge control from 3,105,401, 120 s, default settings
| arm | height after 120 s | oversize errors | requests | hash |
|---|---|---|---|---|
| base | 3,105,401, no progress | 120 | 120 | yes |
| final | 3,105,450 | 0 | 29 | yes |
| window | 3,105,448 | 0 | 27 | yes |

### Long resync 3,105,401 -> 3,123,400, 3 alternating rounds
Medians (min-max). 6/6 hashes, no swap. Walls from log timestamps, from the first height all runs logged, 3,105,409, since at default settings 3,105,406 is not logged.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| final | 1,330.1 (1,327.9-1,332.3) | 10,977 (10,970-10,984) | 1,634 (1,603-1,639) | 1,690 (1,612-1,700) | 5,524 (5,496-5,560) | 1,142 (1,114-1,179) |
| window | 1,324.7 (1,320.0-1,325.6) | 10,967 (10,961-10,976) | 1,589 (1,587-1,608) | 1,683 (1,645-1,697) | 5,574 (5,517-5,586) | 1,194 (1,142-1,210) |
| change | -0.4%, **separate by 2.3 s** | -0.1%, overlap | -2.8%, overlap | -0.4%, overlap | +0.9%, overlap | +4.6%, overlap |

| segment | final s | window s | change |
|---|---|---|---|
| heavy, 3,105,409-3,105,441 | 113.7 | 111.8 | -1.6%, overlap |
| dense small-tx, to 3,113,403 | 1,134.5 | 1,126.3 | -0.7%, overlap |
| near-empty tail, to 3,123,400 | 82.3 | 82.5 | +0.2%, overlap |

### Logged runs, once per arm, untimed, cn at INFO
| arm | seconds | tip | hash | oversize errors | requests | cap lines | cap lines not saying 4 blocks |
|---|---|---|---|---|---|---|---|
| final | 1,287 | 3,123,552 | yes | 0 | 4,648 | 4,420 | 0 |
| window | 1,291 | 3,123,578 | yes | 0 | 4,654 | 4,426 | 0 |

The largest W in any window cap line is 1,873,395 bytes.

### Expectations for part b, fixed before the run
| expectation | result | |
|---|---|---|
| base no progress, oversize errors | 3,105,401, 120 errors | met |
| final and window progress, 0 oversize errors, matching hash | yes | met |
| long 6/6 hashes | 6/6 | met |
| window vs final wall within 2% | -0.4% | met |
| ...with overlapping ranges | **separate by 2.3 s** | **narrow miss** |
| peak anon ranges overlap | yes | met |
| logged: 0 oversize errors | 0, 0 | met |
| every cap line says 4 blocks unless W is at or above 11.25 MB | all 4 blocks, W never that high | met |
| at least one cap line with W above 10 MB | **largest 1.87 MB** | **miss, my expectation was wrong** |

**The wall miss.** Every whole-run window figure sits 2 to 12 s under every final one, while all three segments overlap. The two binaries made the same cap decision in every cap line of the logged runs, and differ by 6 requests in about 4,650, so I have no mechanism for the patch making sync faster. It is 0.4%, three rounds, in the arm's favour. I would call it no cost and not claim a gain.

**The W miss.** Cap lines are written only when the estimate exceeds the cap, and the estimate is `batch_max_weight / W`, 10 MB over W by default. So once W passes 2.5 MB the estimate is at most 4, nothing is capped and no line is written. The line I asked for cannot exist at default settings. It was a bad expectation, not a fault in the cap: real weights show the chain does carry two blocks over 10 MB (10,030,448 and 10,030,357, at 3,105,437 and 3,105,434). This does leave one thing unobserved in logs: the cap being computed with W that large. Part a's unit test exercises it directly.

### What part b shows
- The window-aware cap passes the wedge and behaves as the current cap does on the one real chain we have. No cost in wall, CPU or memory.
- On this chain it cannot show its reason for existing. That evidence is part a, with its limits above.

I also found while reading these logs that the heavy part of the window is single-block sync at default settings regardless of either cap: from 3,105,429 on, W is over 5 MB, so the estimate is 1 block. The cap's work here is entirely in the first requests into the window, where W is still small.

`scripts/e023_wall.py` stopped with `KeyError: 3105406` at the end of the chain for the logging reason above, after everything else had finished. The segment table is from the scratchpad script that picks the nearest common height.

## Evidence
evidence/E035/parta (chain, test output for both trees and both grids, random windows). evidence/E035/partb (chain, long results.csv, summary.txt, per-run mem.csv, cap line counts and largest block weights; no raw logs).
