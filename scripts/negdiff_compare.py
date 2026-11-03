#!/usr/bin/env python3
"""Compare negtest2.py reports: the first file is the oracle. Every case id must have the same (status, flags) in every
report, and every report must PASS (all tampered/swapped rejected, all originals accepted).
usage: negdiff_compare.py <oracle json> <other json> ..."""
import json, sys
reps = [json.load(open(p)) for p in sys.argv[1:]]
base = {c["id"]: c for c in reps[0]["cases"]}
ok = True
for p, r in zip(sys.argv[2:], reps[1:]):
    other = {c["id"]: c for c in r["cases"]}
    if set(other) != set(base):
        print(f"{p}: case sets differ ({len(base)} vs {len(other)})"); ok = False; continue
    diff = [i for i in base if (base[i]["status"], base[i]["flags"]) != (other[i]["status"], other[i]["flags"])]
    rdiff = [i for i in base if base[i]["reason"] != other[i]["reason"]]
    print(f"{p}: {len(base)} cases, (status, flags) disagreements: {len(diff)}, reason-text differences: {len(rdiff)}")
    for i in diff[:10]: print("  DISAGREE", i, base[i]["status"], base[i]["flags"], "vs", other[i]["status"], other[i]["flags"])
    ok = ok and not diff
for p, r in zip(sys.argv[1:], reps):
    print(f"{p}: PASS={r['PASS']} n={r['n']} inputs={r['inputs_mix']}")
    ok = ok and r["PASS"]
flags = {}
for c in reps[0]["cases"]:
    if c["kind"] != "original": flags[tuple(c["flags"])] = flags.get(tuple(c["flags"]), 0) + 1
print("oracle rejection flag mix:", {",".join(k) or "(none)": v for k, v in flags.items()})
print("DIFF PASS" if ok else "DIFF FAIL")
