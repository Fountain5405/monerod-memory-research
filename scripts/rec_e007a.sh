#!/bin/bash
set -eu
cd ~/work/research
python3 -I - <<'PYEOF'
import re
p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-02 23:10", s, count=1)
s = s.replace("1h. (feasibility review by a Plan agent in progress since 22:52) **E007 streaming verifier (design + prototype):**", "1h. (FEASIBLE WITH CHANGES; 2-build plan; implementation delegated to an agent at 23:05, no cargo builds until e004d is done; see experiments/E007-streaming-verifier/README.md) **E007 streaming verifier (design + prototype):**")
s = s.replace("## Needs owner (do not act on these alone)", "## In flight (agents)\n- E007 implementation agent: monero-oxide-e007 + monero-fcmp-e007, with tests. When it reports: REVIEW THE DIFF YOURSELF (soundness guards, z binding, determinism checks, bounds checks), then build and A/B.\n\n## Needs owner (do not act on these alone)")
open(p, "w").write(s)
PYEOF
cat >> JOURNAL.md <<'EOF'

## 2026-11-02 23:00-23:10 E007 feasibility: FEASIBLE WITH CHANGES; implementation started
- Plan-agent review (details in experiments/E007-streaming-verifier/README.md): the transcript is trivially cloneable; circuit building only derives challenges (no proof reads); constraints are deterministic; validation can be done per constraint; and no transcript op after (y, z) depends on the folded weights. That allows a 2-build plan (Discard build on the real transcript; both statements' transcript phases; one replay build on a clone folding c1 and c2; apply). Expected: per-verifier ~200 MB → O(n) dense vectors; ~+5% CPU.
- Implementation delegated to an agent with a strict spec (soundness guards, determinism checks, bounds checks, equivalence/rejection tests). It must not compile until the E004d timing runs finish. My diff review is mandatory before any monerod build.
