# E031: cgroup minimum and long resync on the second machine

**Status: done. Final's cgroup minimum is 1,359 MB against base's 3,218 MB, -57.8%. Over the long resync, peak anon -64.7%, post-idle -67.3%, wall -2.9%. One expectation missed: base's minimum was below the expected band. This run also showed a flaw in how the report describes the cgroup metric; see "The cgroup metric" below. Report only.**

**Why:** these were the two measurements of the final series not repeated on the second machine. E027 covered the windows and the differential test. Base's minimum had also not been measured alongside final's in one chain.

**Setup:** box81 (hostname moonpie), 2026-11-04 22:48 to 2026-11-05 02:24, `scripts/run_e031.sh`, chain log evidence/E031/e031.chain. Arms: base (sha bac70623), final (sha a9a22c46), compiled on this box from the published patches. Single peer 192.168.1.22, `--block-sync-size 5`, governor pinned and restored, no lanes. Other users' load sampled every 5 min: 0 of 44 samples showed any. **All figures here compare box81 only.**

## Cgroup minimum, heavy window
`scripts/min_mem.sh`: bisect `MemoryMax` with swap off, pass = reaches the window end within 1.10 x the reference wall on .22's hash. Reference walls are E027's medians on this box (final 137 s, base 236 s). Each limit was run once.

| arm | minimum passing | largest failing | cgroup peak at the generous limit | failures |
|---|---|---|---|---|
| final | **1,359 MB** | 1,257 MB | 1,332 MB (limit 4,000) | OOM kills |
| base | **3,218 MB** | 3,046 MB | 3,495 MB (limit 7,000) | OOM kills |

-57.8%. The true minimums lie inside those brackets, so the reduction lies between -55.4% and -60.9%.

## Long resync 3,105,401 -> 3,123,400, 3 alternating rounds, DB restored from the snapshot before each run
Wall from logs. Medians (min-max). 6/6 hashes, no swap in any run.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 1,372 (1,368-1,374) | 9,337 (9,335-9,342) | 3,573 (3,389-3,576) | 3,573 (3,389-3,577) | 7,051 (6,827-7,072) | 2,949 (2,799-2,967) |
| final | 1,332 (1,330-1,337) | 8,154 (8,151-8,158) | 1,263 (1,128-1,274) | 1,383 (1,327-1,426) | 5,228 (5,218-5,245) | 963 (922-993) |
| change | **-2.9%**, separate | -12.7%, separate | **-64.7%**, separate | -61.3%, separate | -25.9%, separate | **-67.3%**, separate |

| segment, from log timestamps | base s | final s | change |
|---|---|---|---|
| heavy, 3,105,406-3,105,441 | 234.5 | 136.3 | -41.9% |
| dense small-tx, to 3,113,401 | 1,068.1 | 1,127.4 | +5.5% |
| near-empty tail, to 3,123,400 | 69.6 | 69.4 | -0.3% |

RssAnon by height, median MB of each run:

| segment | base r1 / r2 / r3 | final r1 / r2 / r3 |
|---|---|---|
| 3,105,401-3,106,000 | 3,039 / 3,084 / 3,252 | 828 / 832 / 847 |
| 3,106,000-3,110,000 | 2,635 / 2,884 / 2,705 | 805 / 805 / 820 |
| 3,110,000-3,114,000 | 2,838 / 3,006 / 2,949 | 1,061 / 1,055 / 1,074 |
| 3,114,000-3,118,000 | 2,799 / 2,992 / 2,949 | 1,025 / 977 / 1,025 |
| 3,118,000-3,123,401 | 2,799 / 2,967 / 2,949 | 1,027 / 973 / 1,023 |

No upward trend after 3,110,000 in either arm, and in final no later segment passes the heavy window's peak.

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| final's minimum at or below 2,000 MB | 1,359 MB | met |
| base's minimum 3,500-5,000 MB | **3,218 MB** | **miss** |
| reduction about -50 to -65% | -57.8% | met |
| long peak anon about -55 to -65% | -64.7% | met, at the far end |
| long post-idle at least -60% | -67.3% | met |
| long wall between -8% and +3% | -2.9% | met |
| no upward memory trend after 3,110,000 | none | met |
| all hashes match | 6/6 long; every minimum trial that passed | met |

The miss was my band: I weighted hydrogen's 5,750 MB, when E027 had already measured base's anon peak on this 12-thread box at about 3,342 MB.

## The cgroup metric: the report overstated it
The report says this metric counts page cache and is independent of peak anon. These runs show that is not what the method measures:

| | cgroup peak at the generous limit | peak anon | peak RSS |
|---|---|---|---|
| box81 final (E031, E027) | 1,332 MB | 1,311 MB | 2,509 MB |
| box81 base (E031, E027) | 3,495 MB | 3,377 MB | 4,769 MB |
| hydrogen final (E023) | 1,647 MB | 1,613-1,797 MB | 2,948-3,023 MB |

The cgroup peak tracks anon, not RSS, so nearly all of the LMDB pages the node has mapped are not being charged to it. The likely cause is that the kernel charges a page-cache page to the cgroup that first touched it, and in `min_mem.sh` the DB was already read outside the scope, by the snapshot `cp` and `pop_to`. That cause is inferred, not tested. So this minimum is close to the anon requirement, on a warm page cache, and is not independent evidence. It does not show the RAM a cold node needs. The figures remain valid as what they are, and all earlier minimums (E009, E013, E018, E023) share this. E034 tests it with the DB evicted from the page cache before each trial.

## Reading
- **The memory result holds on the second machine over a long run**, as it did on the windows in E027, with three rounds instead of E023's one.
- **Wall is a small gain overall**, the mix being what matters: heavy blocks -41.9%, dense small-tx +5.5%, the same +5.5% as E027's small-tx window. Whether a node comes out ahead depends on that mix.

## Limits
Each minimum limit was run once, so the brackets do not include trial-to-trial spread. One chain on one box, on stressnet's mix.

## Guardrails
Both binaries by sha256 in the chain, built on this box. No lanes, no foreign load. Governor restored. The chain's own `e023_wall.py` call failed because I gave it 3,123,396, a height not every run logs. Nothing was affected: the walls above were computed after the run over 3,105,406-3,123,400. Evidence: evidence/E031 (chain, load samples, min_mem csv and summaries, results.csv, summary.txt, per-run mem.csv).
