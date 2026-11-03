#!/usr/bin/env python3
"""Input-count distribution of FCMP++ txs in the A/B window (3,105,401..3,105,440), read-only RPC to .22.
One FCMP++ proof covers all inputs of a tx, so per-proof verifier memory scales with the input count."""
import json, sys, urllib.request, collections
RPC = "http://192.168.1.22:28081"
def post(path, payload):
    req = urllib.request.Request(RPC + path, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=120))
lo, hi = int(sys.argv[1]), int(sys.argv[2])
hist = collections.Counter(); per_block = []
for h in range(lo, hi):
    b = post("/json_rpc", {"jsonrpc": "2.0", "id": 0, "method": "get_block", "params": {"height": h}})["result"]
    hashes = b.get("tx_hashes", []) or []
    ins = []
    for i in range(0, len(hashes), 100):
        r = post("/get_transactions", {"txs_hashes": hashes[i:i + 100], "decode_as_json": True})
        for t in r.get("txs", []):
            j = json.loads(t["as_json"])
            ins.append(len(j.get("vin", [])))
    hist.update(ins)
    per_block.append((h, len(hashes), sum(ins), max(ins) if ins else 0))
print("height,txs,inputs,max_inputs")
for row in per_block:
    print(",".join(map(str, row)))
print("histogram inputs:count", dict(sorted(hist.items())))
tot = sum(hist.values()); ti = sum(k * v for k, v in hist.items())
print(f"txs={tot} inputs={ti} mean_inputs={ti / max(tot, 1):.2f}")
