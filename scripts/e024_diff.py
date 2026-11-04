#!/usr/bin/env python3
"""E024: compare two perf_symbols.txt sets by absolute cycles per demangled symbol. Each run's percentages are multiplied by that run's event count, so the table
shows where the extra cycles go rather than how each profile's shares moved. Symbols under perf's 0.05% limit are not counted.
Usage: e024_diff.py <artifact dir> <arm a> <arm b>   (runs r1_<arm>, r2_<arm>; prints arm b minus arm a)"""
import re, subprocess, sys, pathlib, collections
d, a, b = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
def load(run):
    t = (d/run/"perf_symbols.txt").read_text(errors="replace")
    total = int(re.search(r"Event count \(approx\.\): (\d+)", t).group(1))
    rows = re.findall(r"^\s*([\d.]+)%\s+\[[.k]\]\s+(\S+)", t, re.M)
    names = subprocess.run(["c++filt", "-s", "rust"], input="\n".join(n for _, n in rows), capture_output=True, text=True).stdout.split("\n")
    o = collections.Counter()
    for (p, _), n in zip(rows, names):
        n = re.sub(r"\[[0-9a-f]+\]", "", n)
        n = re.sub(r"\bcrypto_bigint::|\bcore::|\bgeneralized_bulletproofs::|\bgeneralized_bulletproofs_circuit_abstraction::", lambda m: m.group(0), n)
        o[n] += float(p) / 100 * total
    return total, o
A = [load(f"r{i}_{a}") for i in (1, 2)]; B = [load(f"r{i}_{b}") for i in (1, 2)]
mean = lambda X, k: sum(x[1].get(k, 0) for x in X) / 2
Ta, Tb = sum(x[0] for x in A) / 2, sum(x[0] for x in B) / 2
print(f"total cycles: {a} {Ta/1e12:.2f}e12, {b} {Tb/1e12:.2f}e12, difference {(Tb-Ta)/1e12:+.2f}e12 ({100*(Tb/Ta-1):+.1f}%)")
keys = set().union(*[x[1] for x in A + B])
rows = sorted(((mean(B, k) - mean(A, k), mean(A, k), mean(B, k), k) for k in keys), reverse=True)
print(f"delta_e12,share_of_difference_pct,{a}_e12,{b}_e12,symbol")
for dl, x, y, k in rows[:24] + rows[-8:]:
    print(f"{dl/1e12:+.3f},{100*dl/(Tb-Ta):+.1f},{x/1e12:.3f},{y/1e12:.3f},{k[:170]}")
