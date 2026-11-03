# Sync permanently wedges when a 100-block batch after an empty stretch exceeds the 100 MB levin packet limit

## Summary
A syncing node sizes each `NOTIFY_REQUEST_GET_OBJECTS` from the largest block weight among its **own last 100 blocks**. After a run of near-empty blocks it requests the maximum 100 blocks. If the next 100 blocks are large, the peer's `NOTIFY_RESPONSE_GET_OBJECTS` exceeds the 100 MB levin packet limit, and the receiver closes the connection. The receiver then re-requests the **same** batch, since its chain tip (and so its estimate) hasn't changed, and it never advances. With default log settings the only symptom is a repeating `monerod is now disconnected from the network` warning.

Found on stressnet. The same logic is present in upstream `master`.

## Environment
- monerod `v0.19.0.0-beta.3.1` (seraphis-migration/monero `d80596ad1`), Release build, Ubuntu 24.04, x86_64.
- Network: stressnet (testnet nettype). The syncing node had a single peer at the tip (`--add-exclusive-node`), and that peer ran the same version.
- Upstream `monero-project/monero` master (`3fd0f88c2`) has the same `core::get_block_sync_size` logic (only an overflow-safe rewrite of one comparison), the same `LEVIN_DEFAULT_MAX_PACKET_SIZE`, and the same count-only cap on the responder.

## Steps to reproduce
1. Take a stressnet node synced past height 3,105,500 and start it offline: `monerod --testnet --offline ...`.
2. Rewind it to height **3,105,401** (top block index 3,105,400):
   - `flush_txpool` (JSON-RPC), then
   - `POST /pop_blocks {"nblocks": <height - 3105401>, "keep_txs": false}`. Pass `keep_txs: false`; with the default `true`, popping heavy blocks refills the txpool and slows to a crawl.
   - Check that the top block hash at index 3,105,400 is `b70c9d6f5a4374fedfe7ab6f9e68b73dc6d9f80ab980454bf34339eabcf3b770`.
3. Restart with default sync settings and one peer at the tip: `monerod --testnet --add-exclusive-node <peer>:28080 ...`, then make net errors visible with `set_log *:WARNING,net:ERROR,net.cn:INFO,global:INFO`.
4. Watch for 60 s. Then repeat with `--block-sync-size 5` as a control.

## Expected
The node syncs past 3,105,401.

## Actual
| run | settings | height after 60 s | oversize errors / object requests |
|---|---|---|---|
| bug | defaults | 3,105,401 (no progress) | 59 / 59 |
| control | `--block-sync-size 5` | 3,105,431 | 0 / 7 |

Every failed request gets the same response size:
```
ERROR net contrib/epee/include/net/levin_protocol_handler_async.h:619 [<peer>:28080 OUT] Maximum packet size exceed!, m_max_packet_size = 100000000, packet header received 134253303, command 2004, connection will be closed.
```
Command 2004 is `NOTIFY_RESPONSE_GET_OBJECTS` (`BC_COMMANDS_POOL_BASE + 4`). Our node first hit this during a normal initial sync and sat there for ~20 minutes until restarted with `--block-sync-size`.

## Chain data at the wedge point
| block index range | role | data |
|---|---|---|
| 3,105,301 .. 3,105,400 | the node's last 100 blocks (estimator input) | max weight **328 B**; all < 1 kB |
| 3,105,401 .. 3,105,500 | the 100-block request | total weight **162.4 MB**, 1,793 txs, largest block 10.03 MB; cumulative weight passes 100 MB at 3,105,434 |

Sampled FCMP++ blocks serialize to ~0.82-0.84 bytes per unit of weight (block 3,105,434: 8,205,218 B vs weight 10,030,357). That puts the window at ~133-136 MB on the wire, which matches the observed 134,253,303-byte response.

## Root cause (line numbers from the beta.3.1 tree)
1. **Requester:** `core::get_block_sync_size` (`src/cryptonote_core/cryptonote_core.cpp:930`) projects from `max(max weight of last BLOCKS_MAX_WINDOW=100 blocks, average block size in the queue)`. When `projected * 100 < batch_max_weight` (10 MB default), it requests 100 blocks. It only looks backward, so an empty-to-full transition is invisible to it.
2. **Responder:** `handle_request_get_objects` limits requests only by count (`CURRENCY_PROTOCOL_MAX_OBJECT_REQUEST_COUNT`, `cryptonote_protocol_handler.inl:1177`), not by bytes, so it builds and sends the whole ~134 MB response.
3. **Transport:** `LEVIN_DEFAULT_MAX_PACKET_SIZE` = 100,000,000 (`contrib/epee/include/net/levin_base.h:64`) is enforced from the packet header (`levin_protocol_handler_async.h:619`), and the connection is closed.
4. **No backoff:** after the drop, the node reconnects, computes the same estimate from the same tip, and sends the same request. With one peer it is wedged indefinitely. (With several peers, other spans may land and raise the queue-average term; I have not tested this.)
5. **Hidden by default:** the error is logged in category `net` at ERROR, which the default log categories (`net:FATAL`) suppress.

## Who is affected
Nodes that were online while these blocks were mined received them one at a time via relay (the largest was 10.03 MB) and are unaffected. The exposure is any node **batch-syncing across a point where ≥100 near-empty blocks are followed by >100 MB of serialized blocks within the next 100**. On stressnet that point is 3,105,401. Mainnet's current block-weight rules do not permit this pattern at the default `--batch-max-weight`, but they do at larger values, and the post-FCMP++ rules the research lab has agreed would permit it at the default (see next section).

## Does mainnet permit this pattern?
**Today's rules don't permit the wedge at the default `--batch-max-weight`. They do permit it at `--batch-max-weight` above about 33 (see "Larger `--batch-max-weight`"), and at the default they allow a one-off oversize response when spans are queued ahead of the tip (see "Queued spans"). After the FCMP++ hard fork they would permit the wedge at the default.** The research lab agreed the post-fork rules at its 17 December 2025 meeting ([ArticMine, `MoneroScaling2026-02.pdf`](https://github.com/ArticMine/Monero-Documents/blob/master/MoneroScaling2026-02.pdf)): a full reward zone of 625,000 bytes, a surge factor of 8, and each block's long-term weight clamped to within 1.2× of the long-term median (was 1.7×). `fcmp++-stage` (`f25388d`) implements the same values. They haven't been released yet, and the fork height isn't set (that branch's mainnet v17/v18 heights are still mock values).

**The rule.** Since HF v15 (2021 scaling, active on mainnet), `Blockchain::update_next_cumulative_weight_limit` sets the block weight limit to `2 × min(max(F, short-term median), surge × F)`. Here F is the long-term effective median, `max(full reward zone, long-term median)`. Empty blocks lower the short-term median but never take the limit below 2F. The short-term median (`epee::misc_utils::median` of the last 100 block weights, which averages the two middle values) only rises above F once 51 of those 100 blocks are above F. So after a quiet stretch, blocks 1-51 are capped at about 2F and blocks 52-100 at 4F, and a 100-block batch can weigh at most **298 × F**. Filling every block to its limit is the worst case, because each limit only grows with the weights before it. The surge cap (50 × F today, 8 × F from v17) never binds within 100 blocks of a quiet tip.

| | F | limit after a quiet stretch | max weight of the next 100 blocks |
|---|---|---|---|
| mainnet today (v16) | 300 kB. `get_info` at height 3,797,876 (2026-11-02) reports `block_weight_limit` 600,000 and `block_weight_median` 300,000 | 600 kB | 89.4 MB: under the 100 MB levin limit |
| mainnet v17 per `fcmp++-stage` `f25388d` | 625 kB (`CRYPTONOTE_BLOCK_GRANTED_FULL_REWARD_ZONE_V17`) | 1.25 MB | 186 MB: over |
| stressnet v17 (`d80596ad1`) | 10 MB (same constant, marked "STRESSNET SPECIFIC") | 20 MB | 2.98 GB: over |

**Bytes per unit of weight** (this answers "please confirm" under "Trade-offs and assumptions"):
- Pre-FCMP++ txs: `get_transaction_weight` returns the blob size, plus the BP+ clawback above 2 outputs, so weight is never below size. A response adds a little that weight doesn't count, about 34 bytes per tx (its hash in the block blob plus a length prefix), which is about 2% for the smallest txs. That puts mainnet's 89.4 MB at about 92 MB on the wire. This overhead is estimated from the format, not measured, and the margin to 100 MB is only about 8%.
- FCMP++ txs: `get_fcmp_pp_transaction_weight_v1` computes weight from the input count, output count and extra length, assuming 7 tree layers (`fake_n_tree_layers`) and maximum-length varints. A real tx is no larger than its weight while the tree has at most 7 layers, and is smaller when it has fewer. The 0.82-0.84 measured on stressnet depends on stressnet's tree depth, so the figures below use 1.0 as well as 0.83.

**What a post-fork mainnet wedge needs** (F = 625 kB). The estimator requests `min(100, batch_max_weight / W)` blocks, where W is the largest of the node's last 100 blocks. A wedge needs:
- every one of those 100 blocks to be at most 151 kB at 1.0 bytes per weight (135 kB at 0.83), with the default `--batch-max-weight` of 10 MB;
- then a surge that fills the next ~66-100 blocks close to the limit.

**Larger `--batch-max-weight`.** The 298 × F bound needs every block in the window to be at most F, so that the limit sits at the 2F floor for 51 more blocks. The estimator only guarantees that at the default batch size. With a larger batch the window can hold blocks above F, and then the short-term median catches up after the first new block, not the 51st. Example under today's rules: 100 blocks at 500 kB, which is legal (under the 600 kB floor limit) and penalty-free once the median has caught up. Then W = 500 kB and the limit is 1 MB. A node with `--batch-max-weight 50` (the allowed maximum) requests 100 blocks (500 kB × 100 < 50 MB), and the next 100 can weigh 51 × 1 MB + 49 × 2 MB = 149 MB. So `--batch-max-weight` above about 33 is exposed under today's rules, and the post-fork rules are exposed at the default. The worst cases below come from [`scripts/e001_batch_weight_sim.py`](../scripts/e001_batch_weight_sim.py), which searches windows of k small blocks followed by 100 − k blocks of one weight, and the reverse, keeping only windows the rules can produce (a search over those shapes, not a proof). The three caps are defined under "Effect on the proposed fix".

| rules | `--batch-max-weight` | unpatched | patch as proposed | step-51 cap | window-aware cap |
|---|---|---|---|---|---|
| today | 10 (default) | 89.5 MB | 89.5 | 89.5 | 89.5 |
| today | 30 | 89.7 | 89.7 | 89.7 | 89.7 |
| today | 40 | 119.3 | 119.3 | 118.7 | 89.7 |
| today | 50 | 149.4 | 148.2 | 148.2 | 89.7 |
| v17 | 10 (default) | 186.3 | 116.4 | 88.9 | 88.9 |
| v17 | 30 | 186.6 | 116.7 | 89.2 | 89.2 |
| v17 | 40 | 186.7 | 116.8 | 93.2 | 89.4 |
| v17 | 50 | 186.8 | 129.3 | 115.9 | 90.0 |

**Stressnet.** The trigger is the stressnet-specific 10 MB zone. At the wedge point the patched binary logged a limit of exactly 20,000,000 (2 × the zone), so the long-term median was at or below the zone and the shortened 10,080-block long-term window played no part.

**Queued spans.** The bound above assumes the request starts at the chain tip, which is the wedge's steady state. When downloaded spans are queued ahead of the tip, the estimator uses `max_average_of_blocksize_in_queue()` (the largest per-span average), and the request starts after the queue. Then even today's rules allow a one-off oversize response. Example: a queued 100-block span averaging 96 kB, with 16 blocks of 600 kB at its end, followed by a 100-block request that can reach 116 MB of weight. From reading the code (not tested), this should not wedge. `on_connection_close` calls `flush_spans(id, false)`, which only drops spans that have no blocks yet, so the queued span is kept and added, and the next estimate sees the 600 kB blocks. The oversize close takes that path: the check at `levin_protocol_handler_async.h:619` returns false from `handle_recv`, the connection is torn down, the levin handler's destructor calls `del_connection`, which calls `on_connection_close` (`levin_protocol_handler_async.h:709`), and `net_node.inl:2841` forwards it to the protocol handler's `on_connection_close`. `drop_connection_with_score`, whose flush-all flag is set at runtime, is not on that path. Traced by reading, not tested.

**Effect on the proposed fix.** From a quiet tip, the limit L = 2F holds for 51 blocks and can then double. So it can't rise within a 4-block batch in the wedge state. The step that matters comes after block 51: a batch of N > 51 blocks from a quiet tip can weigh up to about (2N − 51) × L. The patch caps N at 0.9 × 100 MB / L, which only accounts for L:

| F | patch cap | max batch weight | corrected cap | max batch weight |
|---|---|---|---|---|
| 300 kB (mainnet today) | 100 | 89.4 MB | 100 | 89.4 MB |
| 500 kB | 90 | 129.0 MB | 70 | 89.0 MB |
| 625 kB (`fcmp++-stage` v17) | 72 | 116.3 MB | 61 | 88.8 MB |
| 10 MB (stressnet) | 4 | 80.0 MB | 4 | 80.0 MB |

The corrected cap counts the step: `cap = (cap + 51) / 2` when `cap > 51`. That fixes the quiet-tip case (the "step-51 cap" column in the table under "Larger `--batch-max-weight`") but still fails when the window already holds blocks above F, because then the median catches up after one block. The limit to budget for is the one the chain will have once the median reaches W, the largest block in the window, and that is at most L_W = max(L, 2W). From any window, blocks 1-50 are at most L_W (with fewer than 50 new blocks, both middle values of the median are old blocks, so at most W), block 51 at most 1.5 L_W, block 52 at most 2.5 L_W, and blocks 53-100 at most 2 L_W (the next doubling needs 51 blocks above L_W). So N blocks weigh at most (2N − 50) × L_W. The estimator already has W as `max_weight`. This is the "window-aware cap" column; it has been simulated, not built or tested:

```cpp
// The limit can only rise once the short-term median does, and until 50 more blocks have
// arrived the median is at most W, the largest block in the window. So budget for
// L = max(current limit, 2 * W) for the next 50 blocks and 2 * L after that.
const uint64_t budget_limit = std::max<uint64_t>(weight_limit, 2 * max_weight);
size_t cap = std::max<uint64_t>(1, budget / budget_limit);
const size_t step = CRYPTONOTE_REWARD_BLOCKS_WINDOW / 2;
if (cap > step)
  cap = (cap + step) / 2;
```

In the simulation this keeps every batch at or under 90.0 MB of weight under both rule sets for every `--batch-max-weight` up to 50, keeps 100-block batches on today's quiet mainnet, and gives 61 blocks on a quiet post-fork tip. It only partly covers the queued-span case, since W doesn't include queued blocks; backoff on failure would.

## Workaround
Run with `--block-sync-size N` using a small N (5 worked) while syncing through such a stretch.

## Proposed fix (prototype, tested)
Bound the adaptive batch by the consensus block weight limit, so that `N × block_weight_limit` stays within 90% of the levin packet limit. It is forward-looking (independent of the blocks we already have) and deterministic (it does not depend on why a connection dropped). An explicit `--block-sync-size` is left as is.

```diff
--- a/src/cryptonote_core/cryptonote_core.cpp
+++ b/src/cryptonote_core/cryptonote_core.cpp
@@ -39,6 +39,7 @@ using namespace epee;
 #include <unordered_set>
 #include <thread>
 #include "cryptonote_core.h"
+#include "net/levin_base.h"
 #include "common/util.h"
 #include "common/updates.h"
 #include "common/download.h"
@@ -958,6 +959,25 @@ namespace cryptonote
         res = batch_max_weight / projected_blocksize;
         MINFO("projected blocksize is " << projected_blocksize << " bytes, sync " << res << " blocks in next batch");
       }
+
+      // The estimate above only looks backward, at blocks we already have. After a run of
+      // near-empty blocks it asks for BLOCKS_MAX_WINDOW blocks even if the next blocks are
+      // large, and the peer's NOTIFY_RESPONSE_GET_OBJECTS can then exceed the levin packet
+      // limit: the connection is dropped and the same request is retried forever.
+      // Bound the request by the consensus block weight limit instead: a block's serialized
+      // size does not exceed its weight, so N blocks at the limit fit in N * limit bytes
+      // (plus small per-block/per-tx overhead, covered by the 10% margin).
+      const uint64_t weight_limit = m_blockchain_storage.get_current_cumulative_block_weight_limit();
+      if (weight_limit > 0)
+      {
+        const uint64_t budget = LEVIN_DEFAULT_MAX_PACKET_SIZE / 10 * 9;
+        const size_t cap = std::max<uint64_t>(1, budget / weight_limit);
+        if (res > cap)
+        {
+          MINFO("capping block sync size from " << res << " to " << cap << " blocks (block weight limit " << weight_limit << " bytes)");
+          res = cap;
+        }
+      }
     }
 
     static size_t max_block_size = 0;
```

**Test** (same wedge state at 3,105,401, single peer at the tip, 90 s per run, both runs with the patched binary):

| run | settings | height after 90 s | oversize errors | cap applied | end block hash matches peer |
|---|---|---|---|---|---|
| bug | defaults | 3,105,431 (+30) | 0 | `capping block sync size from 100 to 4 blocks (block weight limit 20000000 bytes)` (7x) | yes |
| control | `--block-sync-size 5` | 3,105,431 (+30) | 0 | no (explicit size) | yes |

With the unpatched binary the default-settings run stays at 3,105,401 indefinitely (table above). A longer default-settings run of the patched binary went from 3,105,401 to 3,106,475 (+1,074 blocks) in ~7 min with 0 oversize errors.

**Trade-offs and assumptions:**
- The cap applies only while the block weight limit is large. On stressnet (limit 20 MB) it allows 4 blocks per request. Through this heavy window throughput was unchanged (verification-bound: 30 blocks / 90 s in both runs). During long empty stretches it means more round trips per block than the 100-block batches; requests to several peers still run in parallel.
- On mainnet, with a block weight limit around 600 kB, the cap works out to ~150 blocks, above `BLOCKS_MAX_WINDOW` (100), so behavior is unchanged. That holds for today's rules. At the v17 zone in `fcmp++-stage` (limit 1.25 MB) the cap is 72 blocks, which is not enough, and under today's rules it doesn't protect nodes run with `--batch-max-weight` 40 or above; see "Does mainnet permit this pattern?" for both and for the window-aware cap that does.
- The cap relies on a block's serialized size (block blob + tx blobs + small framing) not exceeding its weight by more than the 10% margin. Measured on FCMP++ blocks: 0.82-0.84 bytes per unit of weight. For other tx versions I believe weight ≥ size by construction (clawback); please confirm.
- The limit is read at the current tip; it could rise within a 4-block batch. The 10% margin absorbs a small rise, and the backoff below would make this airtight.

## Other possible fixes (complementary)
1. **Back off on failure:** if a span request fails (the connection is dropped while waiting on it, or the packet is oversize), halve the block count for that retry, down to 1.
2. **Forward-looking bound:** this is the proposed fix above.
3. **Byte cap on the responder:** stop adding blocks once the response would exceed a budget, and send fewer. This requires the requester to accept partial responses (not checked).
4. **Visibility:** log oversize-packet disconnects at a level that is visible by default, ideally with the command name.

## Side effect on the serving peer
While a requester is wedged, the serving peer rebuilds and sends a ~134 MB response about once per second.

## Related
- seraphis-migration/monero#157: the same 100 MB levin limit hit by the txpool-complement response.
- monero-project/research-lab#154 ("Limit blocks to 32 MB", open): treats the 100 MB levin limit as a problem only for a single block over 100 MB. It settled on no hard cap and slower scaling, which "means we have years warning to fix how blocks are sent around the network" (Boog900, 2026-01-23). This issue hits the limit with a batch of blocks that are each at most 2.5 MB under the agreed post-fork rules, reachable as soon as the fork activates. So that timeline doesn't cover batched sync, and a per-block cap wouldn't prevent it.
