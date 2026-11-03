#!/usr/bin/env python3
"""Monerod-level FCMP++ negative test (guardrail: no verification weakened).
Our node (offline, local RPC) is at height N (blocks 0..N-1). Take txs from block N on .22 (read-only RPC):
one max-input tx and the smallest-input tx. For each: submit K tampered copies (one bit flipped inside the
fcmp_pp proof at spread offsets) -> every one must be rejected; then submit the original -> must be accepted.
Usage: negtest.py <local rpc port> <out json>"""
import json, sys, urllib.request
PORT = int(sys.argv[1]); OUT = sys.argv[2]
def post(base, p, d, to=300):
    r = urllib.request.Request(base + p, data=json.dumps(d).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=to))
LOCAL = f"http://127.0.0.1:{PORT}"; PEER = "http://192.168.1.22:28081"
N = post(LOCAL, "/get_height", {})["height"]
blk = post(PEER, "/json_rpc", {"jsonrpc": "2.0", "id": 0, "method": "get_block", "params": {"height": N}})["result"]
txs = post(PEER, "/get_transactions", {"txs_hashes": blk["tx_hashes"], "decode_as_json": True})["txs"]
info = []
for t in txs:
    j = json.loads(t["as_json"]); pr = j.get("rctsig_prunable", {})
    info.append({"hash": t["tx_hash"], "hex": t["as_hex"], "inputs": len(j["vin"]), "fcmp": pr.get("fcmp_pp", ""), "ref": pr.get("reference_block")})
info.sort(key=lambda x: x["inputs"])
picks = [info[-1]] + ([info[0]] if info[0]["inputs"] != info[-1]["inputs"] else [])
report = {"local_height": N, "block_txs": len(info), "cases": []}
for tx in picks:
    h = tx["hex"]; f = tx["fcmp"]; pos = h.find(f)
    assert f and pos > 0 and h.count(f) == 1, "fcmp_pp hex not found uniquely in blob"
    nbytes = len(f) // 2
    offsets = [8, 40, 100, nbytes // 4, nbytes // 2, (3 * nbytes) // 4, nbytes - 40, nbytes - 8]
    case = {"tx": tx["hash"], "inputs": tx["inputs"], "reference_block": tx["ref"], "fcmp_bytes": nbytes, "tampered": []}
    for off in offsets:
        i = pos + 2 * off
        b = int(h[i:i + 2], 16) ^ 0x01
        th = h[:i] + f"{b:02x}" + h[i + 2:]
        r = post(LOCAL, "/send_raw_transaction", {"tx_as_hex": th, "do_not_relay": True})
        case["tampered"].append({"offset": off, "status": r.get("status"), "reason": r.get("reason", ""),
                                 "flags": {k: v for k, v in r.items() if isinstance(v, bool) and v}})
    r = post(LOCAL, "/send_raw_transaction", {"tx_as_hex": h, "do_not_relay": True})
    case["original"] = {"status": r.get("status"), "reason": r.get("reason", ""), "flags": {k: v for k, v in r.items() if isinstance(v, bool) and v}}
    case["all_tampered_rejected"] = all(x["status"] != "OK" for x in case["tampered"])
    case["original_accepted"] = case["original"]["status"] == "OK"
    report["cases"].append(case)
report["PASS"] = all(c["all_tampered_rejected"] and c["original_accepted"] for c in report["cases"])
json.dump(report, open(OUT, "w"), indent=1)
for c in report["cases"]:
    print(f"tx {c['tx'][:16]} inputs={c['inputs']} ref={c['reference_block']} fcmp_bytes={c['fcmp_bytes']}: "
          f"tampered rejected {sum(x['status'] != 'OK' for x in c['tampered'])}/{len(c['tampered'])}, original {c['original']['status']} {c['original']['reason']}")
print("PASS" if report["PASS"] else "FAIL")
