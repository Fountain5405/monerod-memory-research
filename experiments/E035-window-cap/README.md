# E035: the window-aware E001 sync cap, built and tested

**Status: part a done, part b waiting for E033. Against Blockchain's real weight-limit code, the window-aware cap keeps every batch at or under 90.0 MB of weight at HF 16, at v17 with F 625 kB and at stressnet's F 10 MB. The current cap reaches 116-129 MB at v17, and 148 MB at HF 16 with `--batch-max-weight 50`. The real code reproduces the owner's simulation to within 0.1 MB in all 24 cells. Report only.**

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

## Part b: the real chain (hydrogen, `scripts/run_e035b.sh`, chained behind E033)
Wedge control at default settings, long resync against `final` x3, logged runs for cap decisions and oversize errors. Expectations are in the script's header. Not yet run.

## Evidence
evidence/E035/parta (chain, test output for both trees and both grids, random windows).
