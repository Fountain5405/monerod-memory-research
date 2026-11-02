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

## Possible fixes (for discussion)
1. **Back off on failure:** if a span request fails (the connection is dropped while waiting on it, or the packet is oversize), halve the block count for that retry, down to 1.
2. **Forward-looking bound:** also cap the count by the consensus maximum allowed block weight at that height, `N <= floor(budget / max_block_weight_limit)`, with the budget below the packet limit. This bounds the response size as long as a block's serialized size never exceeds its weight. It costs smaller batches during empty stretches when the limit is high.
3. **Byte cap on the responder:** stop adding blocks once the response would exceed a budget, and send fewer. This requires the requester to accept partial responses (not checked).
4. **Visibility:** log oversize-packet disconnects at a level that is visible by default, ideally with the command name.

## Side effect on the serving peer
While a requester is wedged, the serving peer rebuilds and sends a ~134 MB response about once per second.

## Related
- seraphis-migration/monero#157: the same 100 MB levin limit hit by the txpool-complement response.
