# W002: wallet refresh memory, fresh wallet over the dense FCMP++ stretch (wallet track, step 2)

**Why:** W001's code map said the wallet's FCMP++ tree cache is bounded by the reorg depth and that the likely wallet peak is a refresh-time transient (pulled block batches, `prepare_tree_state_change`'s tree extension and `CacheStateChange`). This measures it. The wallet is unmodified beta.3.1 code (none of the node series touch it), so this is a baseline, not an A/B.

**Setup:** hydrogen, 2026-11-03 23:07-23:09 (attempt 3; attempts 1 and 2 are in the chain logs and in JOURNAL), scripts/run_w002.sh. `monero-wallet-cli` v0.19.0.0-beta.3.1 built in `~/work/monero-fcmp/build/beta31` (sha 7ab1dd30). The adapt node (sha d6f93d06) serves the synced snapshot (`stressnet_synced_h3123270`) `--offline` on 127.0.0.1:28081. Each run creates a brand-new wallet (`--generate-new-wallet`, no owned outputs), sets its refresh height to 3,105,000 (`--command set refresh-from-block-height`; wallet-cli ignores `--restore-height` for new wallets), then re-opens it with `--command refresh` under the sampler (sample.sh, 2 s: RssAnon, VmRSS, VmHWM, Private_Dirty, threads; CPU from /proc/pid/stat). 18,270 blocks: the heavy window 3,105,401-441 (851 of 1,044 txs with 128 inputs), the dense small-tx stretch to ~3,113,400 (~20-30k txs per 1,000 blocks), the near-empty tail. Governor `performance`, no shadow lanes. Default `--max-concurrency` (24 on this box). One heaptrack run after the three sampled runs.

## Results (fresh wallet, 3,105,000 -> 3,123,270, 18,270 blocks)

| run | wall s | peak RssAnon MB (2 s samples) | VmHWM MB (kernel high-water, exact) | CPU s | threads |
|---|---|---|---|---|---|
| r1 | 15 | 1,139 | 1,173 | 171 | 25 |
| r2 | 14 | 1,002 | 1,037 | 180 | 25 |
| r3 | 16 | 1,226 | 1,260 | 178 | 25 |
| heaptrack run | 23 | 1,074 | 1,114 (incl. heaptrack) | 172 | |
| smoke (270 blocks from 3,123,000) | 5 | 37 | 72 | 4 | |

- **Median peak RSS 1,173 MB (1,037-1,260) for a wallet that owns nothing**, in a 15 s refresh. RssFile is ~35 MB, so almost all of it is anonymous memory. The 2 s sampler sees only 7-8 samples per run; VmHWM is the exact figure and is used as the headline.
- Wall 14-16 s for 18,270 blocks with ~175 CPU s: the refresh runs ~12 threads busy on average (pull, parse and tree-extension work on the threadpool). Blocks received 18,270 in every run (evidence/W002/refresh_lines.txt).
- The node serving the wallet stayed at 396-408 MB anon (it is idle apart from `get_blocks.bin`).
- Private_Dirty equals RssAnon throughout: no file-backed or shared memory involved.

## Attribution (heaptrack, evidence/W002 and ~/work/research-artifacts/w002/heaptrack_peaks.txt on hydrogen)

| | |
|---|---|
| peak heap (live malloc'd bytes) | **349 MB** |
| peak RSS of the same run | **1,200 MB** |
| allocation calls | 17.2 M (749k/s) |
| leaked at exit | 21 MB |

Top peak consumers (live at the heap peak):

| MB | calls | where |
|---|---|---|
| 115 | 1,153 | `CurveTrees::outputs_to_leaves` <- `get_tree_extension` <- `TreeCache::prepare_to_grow_cache` <- `tools::prepare_tree_state_change`, on threadpool threads |
| 31 + 20 + 18 | 2.4 M + 0.4 M + 0.5 M | `std::string` construct / assign / mutate (serialized blocks and txs from `get_blocks.bin`, parsed copies) |
| 23 | 21 | `vector::_M_default_append` (one per batch) |
| 22 | 3.7 M | `_Rb_tree::_M_copy` (map copies, the `CacheStateChange` / locked-outputs maps) |
| 16 + 10 | | `vector::reserve` |
| 15 | 249 | `get_tree_extension` itself |
| 13 | 88 k | `vector<UnifiedOutput>` growth |
| 9.6 + 9.6 | | `prepare_to_grow_cache`, `add_to_locked_outputs_cache` |

## Reading
1. **The wallet's live heap peaks at ~350 MB, its RSS at ~1.2 GB: a 3.4x gap.** That is the glibc arena-retention pattern the node showed (F13): 24 threadpool threads each take transient allocations (tree extension, parsed batches, map copies) in their own arena; the frees do not return the pages, and the next batch lands in other arenas. For the node, capping concurrency and trimming cut RSS by 45% with no change to the live heap. The same two levers exist for the wallet, and one of them is a zero-code environment variable (`MALLOC_ARENA_MAX`). W003 (thread sweep) and W004 (`MALLOC_ARENA_MAX` sweep) test them.
2. **The largest live consumer is the tree extension, not the scan.** `outputs_to_leaves` holds 115 MB at the peak: the wallet converts every output in the batch to curve-tree leaves to grow its own copy of the tree, in parallel per batch. This is FCMP++-specific wallet work (the pre-FCMP wallet only scanned outputs); its memory scales with the outputs in the batches in flight, not with what the wallet owns.
3. **The old refresh-time suspects are there but smaller:** the serialized-string copies (~70 MB over three string paths) and the map copies (22 MB).
4. A wallet that owns outputs (the stressnet spam-wallet case the community note in reports/PRIOR-ART.md refers to) adds `m_transfers`, key-image and tree-path state on top of this; not measured (needs a stressnet seed from the owner).

## Guardrails
- Every run received all 18,270 blocks and ended at 3,123,270; exit 0; balance 0 as expected for a fresh wallet.
- The node was `--offline` on the synced snapshot: the chain served is the one every daemon experiment used; no network variance.
- The wallet binary is unpatched beta.3.1 and the node is adapt; the node's verifier does not affect wallet refresh (the wallet only pulls blocks).
- Wallet seeds printed by the create step are throwaway testnet wallets with no funds; the stdout and wallet logs were not copied into the repo (evidence/W002 holds results, samplers, chain logs and a refresh-line excerpt).
