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
Nodes that were online while these blocks were mined received them one at a time via relay (each ≤ 10 MB) and are unaffected. The exposure is any node **batch-syncing across a point where ≥100 near-empty blocks are followed by >100 MB of serialized blocks within the next 100**. On stressnet that point is 3,105,401. I have not checked whether mainnet's block-weight rules permit this pattern.

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
- On mainnet, with a block weight limit around 600 kB, the cap works out to ~150 blocks, above `BLOCKS_MAX_WINDOW` (100), so behavior is unchanged.
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
