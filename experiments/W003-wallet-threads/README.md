# W003: wallet refresh memory vs `--max-concurrency` (wallet track, step 3)

**Why:** W002 found a fresh wallet's refresh peaks at ~1.17 GB RSS against a 349 MB live heap, with ~25 threads busy. If the gap is per-thread transients plus glibc arena retention, as it was for the node (F13), the thread count is the first lever, and it is a stock flag: `--max-concurrency` (wallet_args.cpp:110, "Max number of threads to use for a parallel job", default = hardware threads). This sweeps it. Zero code.

**Setup:** hydrogen, 2026-11-03 23:10-23:21, scripts/run_w003.sh (chain log evidence/W003/w003.chain). Same as W002: unmodified `monero-wallet-cli` v0.19.0.0-beta.3.1 (sha 7ab1dd30), adapt node serving the synced snapshot `--offline`, a brand-new wallet per run refreshing 3,105,000 -> 3,123,270 (18,270 blocks, `set refresh-from-block-height` then `--command refresh`), governor `performance`, no shadow lanes. Four arms alternated within each of 3 rounds; sampler at 1 s; VmHWM (kernel high-water mark of RSS) is the exact peak. The wallet-cli arguments differ only by `--max-concurrency N`.

## Results (fresh wallet, 18,270 blocks, medians of 3, min-max)

| arm | wall s | VmHWM MB (exact peak RSS) | peak anon MB (1 s samples) | CPU s | threads | vs default: peak / wall |
|---|---|---|---|---|---|---|
| c24 (default on this box) | 16 (15-16) | 1,100 (1,033-1,120) | 1,057 (999-1,085) | 184 (180-185) | 25 | |
| c12 | 23 (22-23) | 909 (869-920) | 875 (834-886) | 109 (109-111) | 13 | **-17%** / +44% |
| c4 | 55 (55-56) | 510 (474-515) | 475 (439-481) | 107 (107-107) | 5 | **-54%** / +244% |
| c1 | 105 (104-106) | 357 (356-357) | 294 (294-325) | 104 (103-105) | 2 | **-68%** / +556% |

12/12 runs received all 18,270 blocks and exited 0 (evidence/W003/refresh_lines.txt). The node serving the wallet stayed at 259-404 MB anon throughout.

## Reading
- **Peak RSS is almost linear in the thread count:** about 325 MB fixed plus ~32 MB per worker thread (1 -> 357, 4 -> 510, 12 -> 909, 24 -> 1,100). The single-thread peak, 357 MB, equals the live-heap peak heaptrack measured in W002 (349 MB): with one worker there is nothing to retain across arenas, so RSS is the live heap. Everything above it at higher thread counts is per-thread transient working sets (each worker holds a batch's parsed blocks and its tree-extension leaves) plus glibc keeping those pages in per-thread arenas after they are freed.
- **CPU: 24 threads burn 184 CPU s for a 16 s refresh; 12 or fewer burn ~105 s.** The extra 75% CPU at 24 is SMT contention on the same 12 physical cores (the node showed the same in E003/E011); it buys 1.4x wall over 12 threads at +190 MB.
- **Trade-off table for a user today:** `--max-concurrency 12` costs 7 s on an 18k-block refresh for -17% peak; `4` costs 40 s for -54%; `1` costs 90 s for -68% (357 MB). On a 24-thread box the default is the worst memory point by a wide margin; on small boxes (4-8 threads) the default already sits near the 500 MB mark.
- Whether the retained part can be released without giving up threads is W004's question (`MALLOC_ARENA_MAX`, also zero-code), and after that a wallet-side `malloc_trim` after each batch, the node's E004e recipe.

## Guardrails
- Every run: 18,270 blocks received, end height 3,123,270, exit 0, balance 0 (fresh wallet).
- One variable per arm (`--max-concurrency`); same binary, same node, same snapshot, arms alternated per round.
- Wallet stdout and logs (which print the throwaway seed) are not in the repo; evidence/W003 holds results.csv, the samplers, the chain log, stats.txt and a refresh-line excerpt.
