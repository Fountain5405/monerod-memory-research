#!/bin/bash
# Record E004d result and E004e plan. Run on hydrogen.
set -eu
cd ~/work/research
mkdir -p evidence/E004d
cp ~/work/research-artifacts/e004d/results.csv ~/work/research-artifacts/e004d/summary.txt evidence/E004d/
cp ~/work/research-artifacts/e004d.chain evidence/E004d/chain.txt
python3 -I - <<'PYEOF'
import re
p = "experiments/E004-verify-concurrency/README.md"; s = open(p).read()
s = s.replace("- Prediction: peak RssAnon ≈ E004a c12 (~3.4 GB), wall ≈ 200 s.", """- Prediction: peak RssAnon ≈ E004a c12 (~3.4 GB), wall ≈ 200 s.

**Results E004d (2026-11-02 22:45-23:05, 3 alternating rounds, default settings, every end hash = .22):**

| round | arm | peak RssAnon MB | peak RSS MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,108 | 6,021 | 222 |
| 1 | e004d | 5,146 | 6,085 | 197 |
| 2 | e004d | 4,991 | 5,831 | 197 |
| 2 | base | 5,601 | 6,634 | 220 |
| 3 | base | 5,622 | 6,611 | 220 |
| 3 | e004d | 5,360 | 6,311 | 199 |

Median peak RssAnon: base 5,601 vs e004d 5,146 MB (-8%; ranges partly overlap: base min 5,108 < e004d max 5,360). Wall 220 → 197 s (-10%).

**Prediction failed.** Capping the arena count does not stop retention. With 24 pool threads sharing 12 arenas, two concurrently verifying threads can land in the same arena, whose high-water mark then becomes two working sets; total retention stays near 24 working sets. The variable that matters is how many distinct threads ever run FCMP++ work (E004a's --max-concurrency 12 made that 12), not the arena count. Evidence for retention as the mechanism: E000's idle node held 3.9 GB anon after sync, and a restart (E002a) brought it to 0.32 GB.

## E004e: E004c + malloc_trim(0) after each FCMP++ batch verification (prepared 23:15)
- Tree ~/work/monero-fcmp-e004e, branch e004e-malloc-trim (3ffb58c77 on top of 2e80c0685). `malloc_trim(0)` (glibc only) right after all batches of a batchVerifyFcmpPpProofs call finish (once per block). Diff vs beta31: evidence/E004e.diff.
- Harness v2 (scripts/ab_window.sh) adds post_idle_anon_MB: at END the peer is temporarily banned on OUR node (local RPC; the ban is lifted before stopping), and RssAnon is sampled after 45 s idle.
- Predictions: (1) peak ≈ 12 concurrent working sets + base ≈ 3.4-3.8 GB; (2) post-idle anon ≈ restart level (~0.3-0.6 GB) instead of multi-GB; (3) wall time within a few % of e004c (the trim costs madvise + re-faulting).
- The A/B runs once the box is quiet (after the E007 agent's cargo builds/tests).""")
open(p, "w").write(s)

p = "FINDINGS.md"; s = open(p).read()
s += "| F12 | E004d (FCMP++ batches + arenas capped at physical cores): -8% peak (5,601 → 5,146 MB median), -10% wall. Arena count does not bound retention (two threads per arena can co-peak). | experiments/E004-verify-concurrency, evidence/E004d/ | small | superseded by E004e (malloc_trim) |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-02 23:20", s, count=1)
s = re.sub(r"- \*\*E004d chain RUNNING\*\*.*?\n", "- E004d DONE (-8% peak, -10% wall; arena cap is not enough).\n- **E004e build** running at nice -j4 (~/work/research-artifacts/e004e.build.log ends with BUILD_OK/BUILD_FAILED). Its A/B (base vs e004e, 3 rounds, harness v2 with post_idle_anon) must run on a QUIET box, i.e. after the E007 agent's cargo work: `scripts/ab_window.sh ~/work/research-artifacts/e004e 3105441 900 3 \"base|<beta31 monerod>|--block-sync-size 5\" \"e004e|<e004e monerod>|--block-sync-size 5\"`.\n", s, count=1, flags=re.S)
open(p, "w").write(s)
PYEOF
cat >> JOURNAL.md <<'JEOF'

## 2026-11-02 23:05-23:20 E004d: arena cap not enough; E004e (malloc_trim) prepared
- E004d A/B: median peak 5,601 (base) → 5,146 MB (-8%), wall 220 → 197 s. The prediction (≈3.4 GB) failed: with 24 threads on 12 arenas, co-located working sets keep total retention near 24 working sets.
- The retention hypothesis is still consistent with everything (E000: 3.9 GB idle after sync; E002a: 0.32 GB after a restart). Direct test: E004e = E004c + malloc_trim(0) once per block after FCMP++ batch verification. Harness v2 adds a post-window idle RssAnon measurement (local temporary ban of the peer on our own node, lifted afterwards).
- Owner pinged with the E004d result (terminal notification; Remote Control inactive).
- Process slip (23:10): nested heredocs with the same `EOF` delimiter truncated a script; its tail ran harmlessly on the control box. Fixed by committing the partial edits. Rule: unique heredoc delimiters, or write files with the editor tool.
JEOF
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E004d: arena cap -8% only; E004e malloc_trim prepared; harness v2 post-idle memory"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
