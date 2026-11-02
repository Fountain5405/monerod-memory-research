# DRAFT (not yet shared): sync wedges permanently when a 100-block batch after an empty stretch exceeds the 100 MB levin packet limit

**Status:** draft for the owner's review. Do not post without approval.
**Found:** 2026-11-02, while syncing stressnet with v0.19.0.0-beta.3.1 (seraphis-migration/monero d80596ad1) from a single LAN peer.
**Also present in:** upstream monero master 3fd0f88c2. The same `get_block_sync_size` logic (only difference: an overflow-safe rewrite of one comparison), the same `LEVIN_DEFAULT_MAX_PACKET_SIZE`, and the same count-only cap on the responder.

## Summary
A syncing node chooses how many blocks to request per `NOTIFY_REQUEST_GET_OBJECTS` from the largest block weight among its own **last 100 blocks**. If those 100 blocks are nearly empty, it requests the maximum of 100 blocks. If the next 100 blocks are large, the peer's `NOTIFY_RESPONSE_GET_OBJECTS` exceeds the receiver's 100 MB levin packet limit. The receiver then drops the connection and immediately re-requests the **same** batch, because its chain (and so its estimate) hasn't changed. The node never advances. With default log settings, the only visible symptom is a repeating `monerod is now disconnected from the network` warning.

## Observed
- The node sat at height 3,105,401 (stressnet, testnet nettype) from 18:47 to 19:08 UTC with no progress, against a single peer (`--add-exclusive-node`).
- With `net.p2p:DEBUG` enabled, the same cycle repeated about once a second: handshake OK, `requesting objects`, then

```
ERROR net contrib/epee/include/net/levin_protocol_handler_async.h:619 [192.168.1.22:28080 OUT] Maximum packet size exceed!, m_max_packet_size = 100000000, packet header received 134253303, command 2004, ...
INFO  net.cn  ... [0] state: closed in state synchronizing
```

  Command 2004 is `NOTIFY_RESPONSE_GET_OBJECTS` (`BC_COMMANDS_POOL_BASE + 4`, cryptonote_protocol_defs.h:273).

## Chain data at the wedge point (from the peer's RPC)
| range (block index) | what | value |
|---|---|---|
| 3,105,301 .. 3,105,400 (the node's last 100 blocks) | max block weight | **328 B** (all < 1 kB) |
| 3,105,401 .. 3,105,500 (the 100-block request) | total weight / txs | **162.4 MB** / 1,793 txs; max block 10.03 MB |
| same | cumulative weight passes 100 MB at | index 3,105,434 |
| two sampled FCMP++ blocks (3,105,434 and 3,105,436) | wire bytes / weight | 0.818, 0.838 |
| request window | estimated wire bytes | **133-136 MB**, vs. the observed 134,253,303-byte response |

## Root cause (line numbers are from the beta.3.1 tree)
1. **Requester** (`core::get_block_sync_size`, cryptonote_core.cpp:930) sets `projected = max(max weight of the last BLOCKS_MAX_WINDOW=100 blocks, average block size in the queue)`. If `projected * 100 < batch_max_weight` (10 MB default), it requests `BLOCKS_MAX_WINDOW` = 100 blocks. The estimate looks only backward, so a transition from empty to full blocks is invisible to it.
2. **Responder** (cryptonote_protocol_handler.inl:1177) limits a request only by count (`CURRENCY_PROTOCOL_MAX_OBJECT_REQUEST_COUNT`), not by bytes, so it builds and sends the whole response (~134 MB here).
3. **Transport** (levin_base.h:64, `LEVIN_DEFAULT_MAX_PACKET_SIZE` = 100,000,000; enforced at levin_protocol_handler_async.h:619) rejects the packet from its header and closes the connection.
4. **No backoff:** after the drop, the node reconnects and computes the same estimate from the same chain tip, so it requests the same oversized batch. With a single peer, it is wedged permanently.
5. **Hidden at default log level:** the levin error is in category `net` at ERROR, which the default categories (`net:FATAL`) suppress.

## Why most nodes are unaffected (partly reasoning)
- Nodes online while those blocks were mined received each block individually through relay (each <= 10 MB).
- Only a node doing a batch sync across exactly this pattern is exposed: >=100 tiny blocks, then >100 MB of wire bytes within the next 100.
- With several peers, other spans may land in the queue and raise the queue-average term enough to shrink the retry. This is untested; a LAN node syncing through the point with normal peers is being watched.
- Whether mainnet consensus rules allow this pattern (a full 100-block window >100 MB right after 100 tiny blocks) has not been checked. On stressnet, ~10 MB blocks appear 33 blocks after the empty stretch ends.

## Reproduction
Needs a synced stressnet DB (beta.3.1) and a peer at the tip.
1. Start offline: `monerod --testnet --data-dir <dir> --offline --non-interactive`
2. Pop back to height 3,105,401 (top index 3,105,400): `curl http://127.0.0.1:28081/pop_blocks -d '{"nblocks": <height - 3105401>}'` (we popped in chunks of 1000). Stop the daemon.
3. Start with default sync settings and one peer at the tip, with net errors visible:
   `monerod --testnet --data-dir <dir> --add-exclusive-node <peer>:28080 --non-interactive --log-level 0`, then `set_log *:WARNING,net:ERROR,net.cn:INFO,global:INFO`
4. Expected (bug): height stays at 3,105,401, and `Maximum packet size exceed! ... packet header received ~134 MB, command 2004` repeats about once a second.
5. Control: the same start with `--block-sync-size 5` syncs through.

Reproduction result: **(pending; run scheduled 2026-11-02)**

## Workaround
`--block-sync-size N` with a small N (5 worked here) for a node syncing through such a stretch.

## Possible fixes (for discussion)
1. **Back off on failure:** when a span request fails (connection dropped while waiting for that response, or an oversize packet), halve the block count for the retry, down to 1.
2. **Forward-looking bound:** cap the batch by the consensus **maximum allowed block weight** at the current height: `N <= floor(budget / max_block_weight_limit)`, with the budget well below the packet limit. A tx's byte size does not exceed its weight (weight = size + clawback; FCMP++ weight ~1.2x bytes here). If that holds for every block version, this bounds the response bytes. It costs smaller batches during empty stretches when the limit is high.
3. **Byte cap on the responder:** stop adding blocks once the serialized response would exceed a budget, and send fewer. This only works if the requester accepts partial responses; not checked.
4. **Visibility:** log oversize-packet disconnects at a level that shows with default settings, ideally with the command name.

Related: seraphis-migration#157 (open) hits the same 100 MB limit through the txpool-complement response.

## Side effect on the serving node
While the requester is wedged, the serving peer builds and sends a ~134 MB response about once a second (for ~20 min here), which costs memory and CPU on the serving node.
