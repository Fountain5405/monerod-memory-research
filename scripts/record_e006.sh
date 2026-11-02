#!/bin/bash
# Record E004c (surprise) + E006 (profile) results. Run on hydrogen.
set -eu
cd ~/work/research
mkdir -p evidence/E004c evidence/E006 experiments/E006-cpu-profile
cp ~/work/research-artifacts/E004c/results.csv ~/work/research-artifacts/E004c/summary.txt evidence/E004c/
cp ~/work/research-artifacts/E006/summary.txt evidence/E006/summary.txt
cp ~/work/research-artifacts/E006/perf_symbols.txt evidence/E006/perf_symbols.txt
python3 -I - <<'PYEOF'
import re
p = "experiments/E004-verify-concurrency/README.md"; s = open(p).read()
s = s.replace("**Results E004c:** (pending)", """**Results E004c (2026-11-02 22:10-22:35, 3 alternating rounds, default settings, every end hash = .22):**

| round | arm | peak RssAnon MB | peak RSS MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,640 | 6,685 | 222 |
| 1 | e004c | 5,237 | 6,240 | 201 |
| 2 | e004c | 5,527 | 6,507 | 201 |
| 2 | base | 5,363 | 6,352 | 220 |
| 3 | base | 5,600 | 6,676 | 220 |
| 3 | e004c | 5,630 | 6,504 | 203 |

Median peak RssAnon: base 5,600 vs e004c 5,527 MB (-1.3%, ranges overlap). Wall: 220 vs 201 s (**-9%**, no overlap).

**Interpretation:** the cap took effect (the wall time matches E004a's c12), but RSS did not drop. Most likely cause: **glibc arena retention.** The pool still has 24 threads and over time all of them run FCMP++ batch tasks. `limitMaxMemArenas()` sets M_ARENA_MAX = pool size = 24, and freed memory stays inside each thread's arena. So RSS ≈ 24 × the per-thread high-water mark even though only 12 batches are live at once. In E004a, `--max-concurrency 12` lowered both the pool and M_ARENA_MAX, which is why it showed the full -39.6%. This is exactly where live heap and RSS diverge; RSS is the metric we use.

## E004d: E004c + arenas capped at physical cores (prepared 22:38; build + A/B chained after E006)
- Tree ~/work/monero-fcmp-e004d, branch e004d-arenas-physical-cores (19e2a7db8 on top of 2e80c0685). `limitMaxMemArenas()` uses min(pool size, physical cores). Diff vs beta31: evidence/E004d.diff.
- Prediction: peak RssAnon ≈ E004a c12 (~3.4 GB), wall ≈ 200 s.""")
open(p, "w").write(s)

open("experiments/E006-cpu-profile/README.md", "w").write("""# E006: CPU profile of FCMP++ sync verification (prices the E007 streaming design)

**Setup (2026-11-02 22:35):** baseline beta31, `--block-sync-size 5`, window 3,105,401→3,105,441 (221 s), quiet box. `sudo perf record -F 199 -p <monerod>` (all threads, no call graphs); `perf report --no-children --sort symbol`, demangled with rustfilt. Script: scripts/e006_profile.sh. Raw: ~/work/research-artifacts/E006/perf.data. Evidence: evidence/E006/.

**Results (self time):**

| bucket | share |
|---|---|
| `ArithmeticCircuitStatement::verify` (generalized-bulletproofs), with inlined callees: constraint folding by z powers (`accumulate_vector`), weight vectors, IPA scalar math | **~52%** (50.37% + 1.33% for the two curve instances) |
| curve/field arithmetic: SelenePoint add 12.3%, crypto_bigint Montgomery reduction 8.5% and mul_wide 8.1%, field pow 1.2%, curve25519 scalar mul 1.1%, Helios add 1.0%, multiexp prep_bits 1.6% | ~36% |
| circuit construction: LinComb term 0.65%, append 0.3%, memmove 1.8%, memset 0.5%, malloc/free ~1%, tape 0.3% | **~4-6%** |
| everything else | ~1% |

Note: scripts/perf_classify.py first lumped the 50% verify symbol under "circuit building" because the truncated mangled name contains "ArithmeticCircuitStatement" (regex `Circuit`). The table above is the corrected manual classification; the script needs a fix before reuse.

**Conclusion:** building the circuit (the gadget code producing LinCombs) is cheap (~5% of CPU). The expensive work is the folding and verification inside `verify`, which a streaming design would do exactly once (just earlier). **A 3-pass streaming verifier (E007) should cost roughly +10% CPU** (two extra construction passes) while removing the ~200 MB per-verifier stored circuit. Separately, ~52% of all sync CPU sits in one function; that is a CPU optimization target in its own right (out of scope for memory).
""")

p = "FINDINGS.md"; s = open(p).read()
s += "| F10 | E004c (FCMP++ batch count capped at physical cores, pool still 24): wall -9% but RSS only -1.3%. Cause: glibc arena retention across all 24 pool threads (M_ARENA_MAX = pool size). Live concurrency ≠ RSS. | experiments/E004-verify-concurrency, evidence/E004c/ | 0 alone | E004d (also cap arenas) queued |\n"
s += "| F11 | E006 CPU profile: ~52% of sync CPU in ArithmeticCircuitStatement::verify (folding + IPA), ~36% curve math, only ~5% circuit construction. A streaming verifier costs ~+10% CPU. | experiments/E006-cpu-profile | enables E007 | done |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-02 22:50", s, count=1)
s = re.sub(r"- \*\*E004c A/B RUNNING\*\*.*?\n- \*\*E006 queued\*\*.*?\n", "- E004c DONE (wall -9%, RSS -1.3%: arena retention). E006 DONE (construction ~5% of CPU).\n- **E004d chain RUNNING** (scripts/chain_build_ab.sh e004d ...): build, then A/B base vs e004d, 3 rounds. Marker: CHAIN_E004D_COMPLETE at the end of ~/work/research-artifacts/e004d.chain; data in ~/work/research-artifacts/e004d/results.csv.\n", s, count=1, flags=re.S)
s = s.replace("1g. **E006 CPU profile**", "1g. (DONE 22:45) **E006 CPU profile**")
open(p, "w").write(s)
PYEOF
cat >> JOURNAL.md <<'EOF'

## 2026-11-02 22:35-22:50 E004c surprise; E006 profile; E004d chained
- E004c A/B: wall 220 → 201 s (-9%), but peak RssAnon 5,600 → 5,527 MB (-1.3%). Explanation: glibc arena retention; M_ARENA_MAX = pool size (24), and all 24 pool threads run FCMP++ batches over time, so each arena keeps its high-water working set. E004d = E004c + arenas capped at physical cores; built and A/B'd via the new generic scripts/chain_build_ab.sh.
- E006 perf profile: ~52% of CPU in ArithmeticCircuitStatement::verify (folding + IPA), ~36% curve math, ~5% circuit construction. So E007 (streaming, 3-pass) costs ~+10% CPU. perf_classify.py misattributed the 50% symbol (regex 'Circuit' matched ArithmeticCircuitStatement); corrected manually. Fix the script before reuse.
- Harness note: an ssh launching a nohup'd chain did not return (stdin probably not redirected); TaskStop'd the local ssh and the remote chain survived. Use `< /dev/null` for remote nohup launches.
EOF
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E004c: faster but RSS unchanged (arena retention); E006: construction ~5% CPU; E004d chained"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
tail -3 ~/work/research-artifacts/e004d.chain
