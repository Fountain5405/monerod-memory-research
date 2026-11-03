#!/usr/bin/env python3
"""E015 differential FCMP++ negative test (guardrail: no verification weakened; the base binary is the oracle).
Our node (offline, local RPC) is at height H (blocks 0..H-1).
Case selection (once, cached in <cases json> so every binary gets identical cases): scan blocks H..H+SCAN-1 on .22
(read-only RPC) for txs whose reference_block <= H-1 (valid against our chain). Pick, in chain order, up to QBIG
txs with >= 64 inputs, QMID with 3..63 and QSMALL with 1..2 inputs.
Per run, in this order (rejected txs never enter the pool, so the order of the rejected cases does not matter):
  1. tampered: for each tx, M single-bit flips spread evenly over the fcmp_pp proof (bit index k % 8) -> must reject;
  2. swapped: for consecutive pairs of picked txs whose proofs have equal length, tx A with B's proof (a valid
     proof for a different statement) -> must reject;
  3. originals -> must be accepted.
Usage: negtest2.py <local rpc port> <cases json> <out json> [scan blocks=40]"""
import json, os, sys, urllib.request
PORT = int(sys.argv[1]); CASES = sys.argv[2]; OUT = sys.argv[3]; SCAN = int(sys.argv[4]) if len(sys.argv) > 4 else 40
QBIG, QMID, QSMALL, M = 4, 3, 3, 32
LOCAL = f"http://127.0.0.1:{PORT}"; PEER = "http://192.168.1.22:28081"
def post(base, p, d, to=600):
    r = urllib.request.Request(base + p, data=json.dumps(d).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=to))
H = post(LOCAL, "/get_height", {})["height"]
if os.path.exists(CASES):
    sel = json.load(open(CASES)); assert sel["H"] == H, f"cases are for H={sel['H']}, node is at {H}"
else:
    picks = {"big": [], "mid": [], "small": []}; quota = {"big": QBIG, "mid": QMID, "small": QSMALL}
    for bh in range(H, H + SCAN):
        if all(len(picks[k]) >= quota[k] for k in picks): break
        blk = post(PEER, "/json_rpc", {"jsonrpc": "2.0", "id": 0, "method": "get_block", "params": {"height": bh}})["result"]
        hs = blk.get("tx_hashes", []) or []
        for i in range(0, len(hs), 50):
            for t in post(PEER, "/get_transactions", {"txs_hashes": hs[i:i + 50], "decode_as_json": True})["txs"]:
                j = json.loads(t["as_json"]); pr = j.get("rctsig_prunable", {})
                f = pr.get("fcmp_pp", ""); ref = pr.get("reference_block"); n = len(j.get("vin", []))
                if not f or ref is None or ref > H - 1 or t["as_hex"].count(f) != 1: continue
                k = "big" if n >= 64 else ("mid" if n >= 3 else "small")
                if len(picks[k]) < quota[k]:
                    picks[k].append({"hash": t["tx_hash"], "block": bh, "inputs": n, "ref": ref, "hex": t["as_hex"], "fcmp": f})
    sel = {"H": H, "scan": SCAN, "txs": picks["big"] + picks["mid"] + picks["small"]}
    json.dump(sel, open(CASES, "w"))
def submit(hexblob):
    r = post(LOCAL, "/send_raw_transaction", {"tx_as_hex": hexblob, "do_not_relay": True})
    return {"status": r.get("status"), "reason": r.get("reason", ""), "flags": sorted(k for k, v in r.items() if isinstance(v, bool) and v)}
rep = {"H": H, "cases": []}
txs = sel["txs"]
for tx in txs:  # 1. tampered
    h, f = tx["hex"], tx["fcmp"]; pos = h.find(f); nb = len(f) // 2
    for k in range(M):
        off = 1 + round(k * (nb - 2) / (M - 1)); bit = k % 8; i = pos + 2 * off
        th = h[:i] + f"{int(h[i:i + 2], 16) ^ (1 << bit):02x}" + h[i + 2:]
        rep["cases"].append({"id": f"{tx['hash'][:16]}/flip@{off}.{bit}", "kind": "tampered", "inputs": tx["inputs"], **submit(th)})
for a, b in zip(txs, txs[1:]):  # 2. swapped proofs
    if len(a["fcmp"]) == len(b["fcmp"]) and a["fcmp"] != b["fcmp"]:
        sh = a["hex"].replace(a["fcmp"], b["fcmp"], 1)
        rep["cases"].append({"id": f"{a['hash'][:16]}/proof-of-{b['hash'][:16]}", "kind": "swapped", "inputs": a["inputs"], **submit(sh)})
for tx in txs:  # 3. originals
    rep["cases"].append({"id": f"{tx['hash'][:16]}/original", "kind": "original", "inputs": tx["inputs"], **submit(tx["hex"])})
bad = [c for c in rep["cases"] if (c["kind"] == "original") != (c["status"] == "OK")]
rep["n"] = {k: sum(c["kind"] == k for c in rep["cases"]) for k in ("tampered", "swapped", "original")}
rep["inputs_mix"] = [t["inputs"] for t in txs]
rep["PASS"] = not bad
json.dump(rep, open(OUT, "w"), indent=1)
print(f"H={H} txs={len(txs)} inputs={rep['inputs_mix']} cases={rep['n']} wrong={len(bad)}")
for c in bad[:10]: print("  WRONG:", c["id"], c["kind"], c["status"], c["reason"], c["flags"])
print("PASS" if rep["PASS"] else "FAIL")
