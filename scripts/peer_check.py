#!/usr/bin/env python3
"""Read-only checks against the reference peer .22 (unrestricted RPC on 28081).
1) heights of .22's current peers (is anyone wedged at 3,105,401?)
2) the real serialized bytes of a big block vs its reported weight
"""
import json
import sys
import urllib.request

BASE = "http://192.168.1.22:28081"


def rpc(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data)
    return json.load(urllib.request.urlopen(req, timeout=30))


def jrpc(method, params=None):
    body = {"jsonrpc": "2.0", "id": 0, "method": method}
    if params is not None:
        body["params"] = params
    return rpc("/json_rpc", body)["result"]


conns = jrpc("get_connections").get("connections", [])
print("connections:", len(conns))
for c in sorted(conns, key=lambda c: c.get("height", 0)):
    direction = "IN " if c.get("incoming") else "OUT"
    print("%-24s %s h=%s state=%s live=%ss" % (c.get("address", ""), direction, c.get("height"), c.get("state"), c.get("live_time")))

heights = [int(h) for h in sys.argv[1:]] or [3105434]
for h in heights:
    b = jrpc("get_block", {"height": h})
    hdr = b["block_header"]
    blk = len(b["blob"]) // 2
    txh = b.get("tx_hashes", [])
    tx_bytes = 0
    for i in range(0, len(txh), 50):
        r = rpc("/get_transactions", {"txs_hashes": txh[i:i + 50], "decode_as_json": False})
        tx_bytes += sum(len(t["as_hex"]) // 2 for t in r.get("txs", []))
    print("block %d: weight %d, block blob %d B, %d txs, tx bytes %d, total bytes %d (bytes/weight %.3f)"
          % (h, hdr["block_weight"], blk, len(txh), tx_bytes, blk + tx_bytes, (blk + tx_bytes) / max(1, hdr["block_weight"])))
