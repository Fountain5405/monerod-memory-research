# W001: wallet FCMP++ tree cache, code map and memory hypotheses (wallet track, step 1)

**Source:** a read-only code map of ~/work/monero-fcmp (beta31) by a scout agent, 2026-11-03 ~03:45. I checked it for plausibility. The line numbers come from the scout's grep/sed reads.

## TreeCache (src/fcmp_pp/tree_cache.h, namespace fcmp_pp::curve_trees)
| member | type | one entry = | pruned? |
|---|---|---|---|
| `m_locked_outputs` (h:256) | unordered_map<LastLockedBlockIdx, vector<UnifiedOutput>> | outputs that unlock at a block | yes: erased when the block leaves the reorg window (`shrink_to_reorg_depth`, cpp:1051), or on pop |
| `m_locked_output_ref_hashes` (h:257) | unordered_map<CreatedBlockIdx, unordered_map<LastLockedBlockIdx, NumOutputs>> | per created block | yes (cpp:1056) |
| `m_registered_outputs` (h:263) | unordered_map<OutputRefHash, AssignedLeafIdx> | one wallet-owned output | **no** (insert at cpp:746 from wallet2.cpp:2642; only `clear`) |
| `m_leaf_cache` (h:266) | unordered_map<ChildChunkIdx, CachedLeafChunk{vector<OutputPair>, ref_count}> | one leaf chunk | refcount-driven, within the reorg window |
| `m_tree_elem_cache` (h:267) | unordered_map<LayerIdx, unordered_map<ChildChunkIdx, CachedTreeElemChunk{vector<ec_point>, ref_count}>> | one path chunk per layer | refcount-driven, within the reorg window |
| `m_cached_blocks` (h:274) | deque<BlockMeta{idx, hash, n_leaf_tuples}> | one block | bounded: `size() > m_max_reorg_depth` (cpp:1044), default ORPHANED_BLOCKS_MAX_COUNT = 100 |

- All 7 members are serialized into the wallet cache file (tree_cache.h:282-291; wallet2.h:966-968, version >= 3).
- wallet2 owns `TreeCacheV1 m_tree_cache` (wallet2.h:1710), with max_reorg_depth 100 (settable).

## Assessment
- The tree cache is **bounded by design** apart from `m_registered_outputs`. That one grows by roughly 50-80 B per owned output: 32 B key + 16 B value + hash-node overhead. A 100k-output wallet would hold ~5-8 MB. **This is not a meaningful RAM target.**
- The bounded parts scale with the leaves and path chunks touched in the last 100 blocks, so heavy chains (stressnet) cost more. Each leaf is an OutputPair of ~64 B. Stressnet's dense stretch has ~20-30k txs per 1,000 blocks, so ~100 blocks hold a few thousand to tens of thousands of leaves: about a few MB.
- **Likely real peak candidates (refresh-time transients, not the cache):**
  - `pull_and_parse_next_blocks` (wallet2.cpp:3853) holds the whole pulled `parsed_blocks` batch (blocks + txs + parsed outputs).
  - `prepare_tree_state_change` (wallet2.cpp:3182-3240) builds `outs_by_last_locked_blocks` for the whole batch, plus a full `CacheStateChange` (tree extension + locked-outputs copy, tree_cache.cpp:823-824), at once.
  - These overlap in a refresh pipeline (pull of the next batch ∥ processing of the current one).
  - Then classic wallet2 state: m_transfers, m_blockchain hashes, tx history.

## Next (W002, after the daemon E010 run frees the box)
Measure instead of guessing:
- Restore a fresh random wallet (no owned outputs) at height ~3,105,000.
- Refresh with monero-wallet-cli/rpc against OUR local node (not .22), across the dense FCMP++ stretch.
- Sample RssAnon/peak, plus heaptrack for attribution.
- Then a wallet that owns outputs, if a stressnet wallet with funds can be obtained (needs owner).
