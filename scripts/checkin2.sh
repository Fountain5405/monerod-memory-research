#!/bin/bash
# Check-in #2 bookkeeping (2026-11-02 22:50). Run on hydrogen.
set -eu
cd ~/work/research
python3 -I - <<'PYEOF'
import re
p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-02 22:55 (check-in #2)", s, count=1)
s = s.replace("1f. After E004c and E005: a COMBINED build", "1f. min_mem.sh is READY (cgroup v2 scope self-test OK: runs as optimizer, MemoryMax honored, swap off). Run it on a quiet box: base (ref wall 220 s) and the best candidate (ref = its own A/B median wall). Suggested bounds: lo 1500, hi 8000, tol 250 MB. After E004d: a COMBINED build")
s = s.replace("(scripts/min_mem.sh, still to write)", "(scripts/min_mem.sh)")
s = s.replace("1h. **E007 streaming verifier (design + prototype):**", "1h. (feasibility review by a Plan agent in progress since 22:52) **E007 streaming verifier (design + prototype):**")
open(p, "w").write(s)
PYEOF
cat >> JOURNAL.md <<'EOF'

## 2026-11-02 22:47-22:55 check-in #2 (cron)
- Box: load ~14 (E004d A/B only), no selfishmining lanes, 56 GB disk free, 12 GB RAM available.
- E004d: build OK (sha256 61517c0a…); A/B running. Round 1 base = 5,108 MB / 222 s, hash match; e004d run in progress.
- E007: a Plan agent is reviewing the 3-pass streaming design against the code (transcript cloneability, the order of transcript ops during circuit building, constraint validation, other consumers, risks).
- Wrote scripts/min_mem.sh: binary search over a systemd-run scope MemoryMax (swap off) for the smallest limit that syncs the window within 1.1x the reference wall and ends on .22's hash; records the cgroup memory.peak and oom_kill count. Self-test of the scope mechanics passed. Not run yet (it needs a quiet box, after E004d).
EOF
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "Check-in #2: E004d A/B running; min_mem.sh ready (cgroup scope self-test OK)"
git log --oneline -1
