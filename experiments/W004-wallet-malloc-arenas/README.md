# W004: wallet refresh memory vs `MALLOC_ARENA_MAX` (wallet track, step 4, zero code)

**Why:** W003 showed the wallet's refresh peak scales with the worker-thread count (357 MB at 1 thread, 1,100 MB at 24) while its live heap peaks at ~350 MB regardless (W002 heaptrack). The node's E004d/E004e work pinned the equivalent gap on glibc per-thread arenas keeping freed pages. glibc exposes the arena count as an environment variable, `MALLOC_ARENA_MAX`, so the hypothesis can be tested with no code and no loss of threads: if the gap is arena retention, capping the arenas should bring a 24-thread refresh down to the live-heap figure.

**Setup:** hydrogen, 2026-11-03 23:21-23:28, scripts/run_w004.sh (chain log evidence/W004/w004.chain). Same as W002/W003: unmodified `monero-wallet-cli` v0.19.0.0-beta.3.1 (sha 7ab1dd30), adapt node serving the synced snapshot `--offline`, a brand-new wallet per run refreshing 3,105,000 -> 3,123,270 (18,270 blocks), governor `performance`, no shadow lanes, sampler at 1 s, VmHWM exact. Four arms alternated within each of 3 rounds; the arms differ only in the environment of the wallet process (`env MALLOC_ARENA_MAX=N`) and, for the last arm, `--max-concurrency 12`.

## Results (fresh wallet, 18,270 blocks, medians of 3, min-max)

| arm | wall s | VmHWM MB (exact peak RSS) | peak anon MB (1 s samples) | CPU s | threads | vs default: peak / wall |
|---|---|---|---|---|---|---|
| default (glibc arenas = 8 x cores, 24 threads) | 15 (15-16) | 1,132 (1,053-1,239) | 1,097 (1,008-1,205) | 184 (180-184) | 25 | |
| `MALLOC_ARENA_MAX=1` | 17 (17-19) | 352 (352-353) | 300 (294-325) | 216 (212-217) | 25 | **-69%** / +13% |
| `MALLOC_ARENA_MAX=2` | 16 (16-16) | 370 (364-433) | 335 (329-398) | 191 (187-192) | 25 | **-67%** / +7% |
| `MALLOC_ARENA_MAX=1` + `--max-concurrency 12` | 24 (24-26) | 352 (352-353) | 291 (290-294) | 129 (127-130) | 13 | -69% / +60% |

12/12 runs received all 18,270 blocks and exited 0 (evidence/W004/refresh_lines.txt). The node serving the wallet stayed at ~260-400 MB anon.

## Reading
- **Confirmed: the ~750 MB above the live heap is glibc arena retention, not per-thread live data.** With the arenas capped the 24-thread refresh peaks at 352-370 MB, the live-heap figure heaptrack measured (349 MB), and the run-to-run spread collapses from ~190 MB to 1 MB at `MALLOC_ARENA_MAX=1`. All 24 workers are still used (threads 25, CPU 184-216 s).
- **`MALLOC_ARENA_MAX=2` is the practical setting: -67% peak RSS for +7% wall (1 s on a 15 s refresh) and +4% CPU.** `=1` saves a further 18 MB but serializes every allocation on one arena lock: +13% wall, +17% CPU. Capping threads as well (last arm) buys nothing in memory once the arenas are capped, and costs 60% wall; it is the wrong lever for the wallet (contrast W003, where threads were the only lever available without the environment variable).
- **This is a zero-code, user-side fix available today** for any glibc build of the wallet: `MALLOC_ARENA_MAX=2 monero-wallet-cli ...` (or the same variable in the environment of monero-wallet-rpc or a GUI that launches it). It meets the owner's 40% target on the wallet with no change to the wallet. The code-side equivalent is a `mallopt(M_ARENA_MAX, 2)` at wallet start-up, or the node's E004e recipe (`malloc_trim(0)` after each processed batch), either a few lines in wallet2; not built here, since the environment variable already demonstrates the effect and the choice between them is a design decision for the wallet maintainers (the arena cap trades some allocator parallelism; the trim keeps the arenas and pays a syscall per batch).
- **Contrast with the node:** for monerod, capping arenas alone gave only -8% (E004d), because the node's live working sets (the stored verifier circuits, ~250 MB each) were real and large; it needed the streaming verifier (E007) plus the cap and trim. The wallet's live heap is already small; its whole excess was retention, so the cheapest lever is enough.
- The remaining 350 MB is live data at the peak: the tree extension (`outputs_to_leaves`, 115 MB), serialized block/tx strings (~70 MB), map copies (22 MB), per W002's heaptrack. Reducing it would need wallet code changes (smaller pull batches, or building the tree extension per sub-batch); the node side (the 400 MB adapt node serving the wallet) is already measured separately.

## Guardrails
- Every run: 18,270 blocks received, end height 3,123,270, exit 0, balance 0 (fresh wallet).
- One variable per arm (environment only; the last arm adds the one flag), same binary, same node, same snapshot, arms alternated per round.
- `MALLOC_ARENA_MAX` only affects glibc malloc; a wallet linked against another allocator (jemalloc builds, musl static builds) would not see this effect and would need measuring on its own.
- Wallet stdout and logs (which print the throwaway seed) are not in the repo; evidence/W004 holds results.csv, the samplers, the chain log, stats.txt and a refresh-line excerpt.
