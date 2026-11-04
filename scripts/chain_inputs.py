#!/usr/bin/env python3
"""E022a: per-block FCMP++ input-count distribution over a height range, from a local offline node (RPC env, default
127.0.0.1:28081). One proof covers all inputs of a tx, so the adaptive cap/trim threshold (16 inputs, E012) only matters
on blocks whose largest tx has a mid-size input count. Output csv: height,txs,inputs,max_inputs,n_le2,n_3_15,n_16_63,n_ge64
(flushed per block so progress can be watched), then a histogram line. Usage: chain_inputs.py LO HI OUT.csv"""
import json, sys, urllib.request, collections, os
RPC = os.environ.get("RPC", "http://127.0.0.1:28081")
def post(path, payload):
    req = urllib.request.Request(RPC + path, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))
lo, hi, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
hist = collections.Counter()
with open(out, "w") as f:
    f.write("height,txs,inputs,max_inputs,n_le2,n_3_15,n_16_63,n_ge64\n")
    for h in range(lo, hi):
        b = post("/json_rpc", {"jsonrpc": "2.0", "id": 0, "method": "get_block", "params": {"height": h}})["result"]
        hashes = b.get("tx_hashes", []) or []
        ins = []
        for i in range(0, len(hashes), 100):
            r = post("/get_transactions", {"txs_hashes": hashes[i:i + 100], "decode_as_json": True})
            for t in r.get("txs", []):
                ins.append(len(json.loads(t["as_json"]).get("vin", [])))
        hist.update(ins)
        f.write(f"{h},{len(hashes)},{sum(ins)},{max(ins) if ins else 0},{sum(1 for x in ins if x <= 2)},"
                f"{sum(1 for x in ins if 3 <= x <= 15)},{sum(1 for x in ins if 16 <= x <= 63)},{sum(1 for x in ins if x >= 64)}\n")
        f.flush()
    f.write("# histogram inputs:count " + json.dumps(dict(sorted(hist.items()))) + "\n")
    tot = sum(hist.values()); ti = sum(k * v for k, v in hist.items())
    f.write(f"# txs={tot} inputs={ti} mean_inputs={ti / max(tot, 1):.2f}\n")
print("done")
