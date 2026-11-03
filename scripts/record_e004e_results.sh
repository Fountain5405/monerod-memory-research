#!/bin/bash
# Record E004e results; rewrite STATE.md running/queue/in-flight sections. Run on hydrogen.
set -eu
cd ~/work/research
mkdir -p evidence/E004e
cp ~/work/research-artifacts/e004e/results.csv ~/work/research-artifacts/e004e/summary.txt evidence/E004e/
cp ~/work/research-artifacts/e004e.chain evidence/E004e/chain.txt
python3 -I scripts/ab_stats.py ~/work/research-artifacts/e004e/results.csv base > evidence/E004e/stats.md
python3 -I - <<'PYEOF'
import re
p = "experiments/E004-verify-concurrency/README.md"; s = open(p).read()
res = open("/home/optimizer/work/research/.e004e_results.md").read()
anchor = "- The A/B runs once the box is quiet (after the E007 agent's cargo builds/tests)."
assert anchor in s
s = s.replace(anchor, anchor + "\n" + res, 1)
open(p, "w").write(s)

p = "FINDINGS.md"; s = open(p).read()
s += "| F13 | **E004e (FCMP++ batch cap at physical cores + malloc_trim(0) once per block after batch verify): peak RssAnon -44.6% (5,309 → 2,943 MB median, ranges disjoint), post-sync idle anon -88% (4,794 → 574 MB), wall -5.5%, end hashes match, disk I/O unchanged.** Root cause of most of the baseline peak: glibc arena retention of freed ~200 MB FCMP++ working sets across 24 threads. | experiments/E004-verify-concurrency, evidence/E004e/ | **large** | CONFIRMED (passes the 40% target); min_mem + combined build pending |\n"
s += "| F14 | Side finding: the stressnet A/B window is a worst case. 851 of 1,044 txs have 128 inputs (the max); one FCMP++ proof covers all inputs, so a proof's stored verifier circuit is ~250 MB. 1-2 input txs need only a few MB. | evidence/window_inputs_3105401-3105440.txt | context | caveat for all results |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
new = open("/home/optimizer/work/research/.state_running.md").read()
s = re.sub(r"## Currently running\n.*?(?=## Watch)", new + "\n", s, count=1, flags=re.S)
s = re.sub(r"## In flight \(agents\)\n.*?(?=## Needs owner)", "## In flight (agents)\n- None. (The E007 agent finished at 00:20; its diff was reviewed by me; see experiments/E007-streaming-verifier.)\n\n", s, count=1, flags=re.S)
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-03 01:00", s, count=1)
open(p, "w").write(s)
PYEOF
rm -f .e004e_results.md .state_running.md
cat >> JOURNAL.md <<'JEOF_E004E'

## 2026-11-03 00:25-01:00 E004e CONFIRMED: -44.6% peak, -88% idle (check-in 00:47)
- Check-in 00:47: no shadow lanes. Load ~19 came from our own A/B node (24 verifier threads). 54 GB disk free.
- E004e A/B, 3 rounds, governor pinned:
  - peak RssAnon median 5,309 → 2,943 MB (-44.6%; ranges 5,154-5,347 vs 2,941-2,965, disjoint)
  - Private_Dirty -44.7%
  - post-idle RssAnon 4,794 → 574 MB (-88%)
  - wall 219 → 207 s (-5.5%)
  - writes unchanged, 6/6 hashes match
  - All three predictions held. The glibc retention hypothesis is confirmed: the arena-count cap (E004d) failed, while an explicit trim once per block works.
- Owner pinged (terminal notification).
- Chain e007 started building as soon as CHAIN_E004E_COMPLETE landed. The combo chain is queued behind it (tree monero-fcmp-combo = E004c + E004e + E001 fix + E007).
- New tool scripts/ab_stats.py prints a per-arm medians/ranges table and the deltas vs base.
JEOF_E004E
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E004e CONFIRMED: peak anon -44.6%, post-idle -88%, wall -5.5%; combo tree queued"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
