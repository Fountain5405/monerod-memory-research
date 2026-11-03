#!/bin/bash
# Record the E007 implementation, review, and window tx-input distribution. Run on hydrogen.
set -eu
cd ~/work/research
mkdir -p evidence/E007
cp ~/work/research-artifacts/window_inputs.txt evidence/window_inputs_3105401-3105440.txt
[ -f evidence/E007_monero-oxide.diff ] || git -C ~/work/monero-oxide-e007 diff 31c26d96 c215a805a > evidence/E007_monero-oxide.diff
git -C ~/work/monero-fcmp-e007 diff d80596ad1 bfd179a6a > evidence/E007/monero-fcmp-e007.diff
cp ~/work/e007-logs/test_final.log ~/work/e007-logs/measure.log evidence/E007/ 2>/dev/null || true
cp ~/work/e007-logs/measure_append.rs evidence/E007/ 2>/dev/null || true
python3 -I - <<'PYEOF'
import re
p = "experiments/E007-streaming-verifier/README.md"; s = open(p).read()
impl = open("/home/optimizer/work/research/.e007_impl.md").read()
assert "**Results:** (pending)" in s
s = s.replace("**Results:** (pending)", impl + "\n**Results (monerod window A/B):** queued as chain e007 (scripts/chain_build_ab.sh v2, waits for CHAIN_E004E_COMPLETE).", 1)
open(p, "w").write(s)
p = "STATE.md"; s = open(p).read()
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-03 00:30", s, count=1)
open(p, "w").write(s)
PYEOF
rm -f .e007_impl.md
cat >> JOURNAL.md <<'JEOF_E007'

## 2026-11-03 00:20-00:30 E007 implemented and reviewed; E004e A/B running; window is 128-input txs
- The E007 agent finished. The streaming verifier is in monero-oxide-e007 at c215a805a; all tests pass, plus 9 new equivalence and tamper tests. I reviewed the full non-test diff: transcript and RNG order are unchanged, z is bound to the real transcript, every path fails closed. Verdict OK for an experimental build. Details are in experiments/E007-streaming-verifier.
- The agent's micro-measurement showed stored constraints at only ~2 MB per input, which looked too small to explain ~200 MB per thread. scripts/window_inputs.py resolves it: 851 of the window's 1,044 txs have 128 inputs (mean 104.8). One proof covers all inputs, so a proof stores about 250 MB. Report caveat: this window is a worst case (max-input txs).
- The E004e A/B started at 00:25 (scripts/run_e004e.sh), with the governor pinned to performance and restored afterwards. **Hygiene note:** the E003-E004d macro runs used the default schedutil governor. Their A/B comparisons are internal, since both arms ran under the same governor and alternated, but wall times are not comparable across governor settings. chain_build_ab.sh v2 now pins the governor too.
- Chain e007 is queued (build ~/work/monero-fcmp-e007, then a 3-round A/B vs base) and waits for CHAIN_E004E_COMPLETE.
JEOF_E007
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E007 implemented + reviewed; window is 128-input txs; governor pinning in chain v2"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
