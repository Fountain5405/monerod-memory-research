#!/bin/bash
# Record E005 (negative) result, plan E006/E007. Run on hydrogen.
set -eu
cd ~/work/research
mkdir -p evidence/E005
cp ~/work/research-artifacts/E005/results.csv ~/work/research-artifacts/E005/summary.txt evidence/E005/
python3 -I - <<'PYEOF'
import re
p = "experiments/E005-lincomb-shrink/README.md"; s = open(p).read()
s = s.replace("**Results:** (pending)", """**Results (2026-11-02 21:55-22:10, 3 alternating rounds, default concurrency, every end hash = .22):**

| round | arm | peak RssAnon MB | peak RSS MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,350 | 6,120 | 222 |
| 1 | e005 | 5,235 | 5,948 | 220 |
| 2 | e005 | 5,380 | 6,278 | 221 |
| 2 | base | 5,564 | 6,407 | 220 |
| 3 | base | 5,278 | 6,360 | 219 |
| 3 | e005 | 5,499 | 6,493 | 218 |

Median peak RssAnon: base 5,350 (5,278-5,564) vs e005 5,380 (5,235-5,499). Wall 220 vs 220 s.

**Conclusion: no effect; hypothesis rejected.** The ranges overlap completely. Term-vector growth slack is not a meaningful part of the per-verifier working set.

**Why (follow-up reading of the E002b peak stacks; folded order confirmed root to leaf):** the largest single stack (310 MB) is growth of the `constraints: Vec<LinComb>` itself in `Circuit::mul` (`member_of_list > mul > grow_one`). `mul` pushes two constraints per gate (a - l, b - r), each a ~200-byte LinComb struct with its own small term-vector allocations; the big WCG divisor-evaluation constraints come on top. Next: a second mul/grow_one stack (151 MB), LinComb add growth (6 x 89 MB), term/BTreeMap insert (82 MB). So the memory is in the NUMBER of stored constraints and terms, not in their slack.

**Implication:** the per-verifier working set can only be cut structurally (not storing the circuit: E007 multi-pass streaming) or bounded by concurrency (E004c). E006 (CPU profile) prices the multi-pass design first.""")
open(p, "w").write(s)

p = "FINDINGS.md"; s = open(p).read()
s += "| F9 | E005 (shrink_to_fit of stored LinComb term vectors): **no effect** (median 5,350 vs 5,380 MB, same wall). The working set is the count of constraints/terms (two LinCombs per mul gate, plus the divisor WCG constraints), not slack. | experiments/E005-lincomb-shrink, evidence/E005/ | 0 | rejected |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-02 22:20", s, count=1)
s = re.sub(r"- \*\*Chained\*\* \(scripts/chain_e005\.sh\).*?\n", "- E005 DONE (no effect; rejected).\n", s, count=1)
s = s.replace("1e. (E005 is the first E004b step; RUNNING via chain)", """1g. **E006 CPU profile** (after E004c; quiet box): `perf record` (flat, -F 199) on the baseline node over the window. Classify self time into circuit construction (LinComb ops/term/add/sub/mul, divisor_challenge_eval, BTreeMap, malloc/free/memcpy) vs curve math/multiexp/IPA. This prices E007.
1h. **E007 streaming verifier (design + prototype):** Circuit modes {Store, Discard, Accumulate(z)}. Fcmp::verify keeps a clone T0 of the transcript at the start of the build. Pass 1 discards both circuits on the real transcript. Split ArithmeticCircuitStatement::verify into (a) read AI/AO/S and derive y,z, then (b) verify with pre-accumulated weights (l/r/o/cg/V weights plus the constant). Pass 2 replays the build on a clone of T0, accumulating c1 with z1; pass 3 does the same for c2. Gadget code is unchanged. Expected: per-verifier memory ~200 MB -> a few MB, at +2x the circuit-building CPU share. Needs careful equivalence testing (same accept/reject on valid AND tampered proofs).
1e. (DONE: E005 rejected)""")
open(p, "w").write(s)
PYEOF
cat >> JOURNAL.md <<'EOF'

## 2026-11-02 22:20 E005 rejected; per-verifier working set analysed; next E006/E007
- E005 A/B: median peak 5,350 (base) vs 5,380 MB (e005); wall 220 vs 220 s. No effect.
- Peak-stack reading: the biggest stack is growth of `constraints: Vec<LinComb>` in Circuit::mul (two constraints per gate). The working set is the constraint/term COUNT. Options: bound concurrency (E004c, in progress) or stop storing the circuit (E007, a multi-pass streaming verifier). E006 will first measure the CPU share of circuit building.
- Process slip: another ssh-quoting failure (an apostrophe in a heredoc inside ssh '...'). Nothing executed. Re-done via a script file (scripts/record_e005.sh). Rule reaffirmed: prose goes into files, never into ssh one-liners.
EOF
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E005 rejected (no effect); stack analysis: constraint count in Circuit::mul; plan E006 profile + E007 streaming verifier"
git log --oneline -1
cat ~/work/research-artifacts/E004c.chain
