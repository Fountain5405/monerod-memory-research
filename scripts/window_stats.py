#!/usr/bin/env python3
"""Block-weight stats around a sync start height, from the reference peer (read-only RPC).
usage: window_stats.py <chain_height>   (chain height = number of blocks = top index + 1)
Prints the 100-block lookback (indices H-100..H-1) and the 100-block request window (H..H+99)."""
import json
import sys
import urllib.request

BASE = "http://192.168.1.22:28081/json_rpc"


def headers(a, b):
    out = []
    for s in range(a, b + 1, 100):
        e = min(b, s + 99)
        body = {"jsonrpc": "2.0", "id": 0, "method": "get_block_headers_range", "params": {"start_height": s, "end_height": e}}
        r = json.load(urllib.request.urlopen(urllib.request.Request(BASE, data=json.dumps(body).encode()), timeout=60))
        out += r["result"]["headers"]
    return out


H = int(sys.argv[1])
look = headers(H - 100, H - 1)
win = headers(H, H + 99)
lw = [h["block_weight"] for h in look]
ww = [h["block_weight"] for h in win]
print("lookback indices %d..%d: n=%d max weight %d B, all < 1 kB: %s" % (H - 100, H - 1, len(lw), max(lw), all(w < 1000 for w in lw)))
print("request window %d..%d: n=%d sum weight %.1f MB, txs %d, max block %.2f MB" % (H, H + 99, len(ww), sum(ww) / 1e6, sum(h["num_txes"] for h in win), max(ww) / 1e6))
print("estimated wire bytes at 0.818-0.838 bytes/weight: %.0f-%.0f MB (observed response: 134.25 MB)" % (sum(ww) * 0.818 / 1e6, sum(ww) * 0.838 / 1e6))
running = 0
for h in win:
    running += h["block_weight"]
    if running > 100_000_000:
        print("cumulative weight passes 100 MB at index %d" % h["height"])
        break
