#!/bin/bash
# Record E007 + E008 (combo) results and the negative test; update STATE/FINDINGS/JOURNAL. Run on hydrogen.
set -eu
cd ~/work/research
A=~/work/research-artifacts
mkdir -p evidence/E007 evidence/E008 evidence/negtest experiments/E008-combined
cp $A/e007/results.csv $A/e007/results.raw.csv $A/e007/summary.txt evidence/E007/
cp $A/e007.chain evidence/E007/chain.txt
python3 -I scripts/ab_stats.py $A/e007/results.csv base > evidence/E007/stats.md
cp $A/combo/results.csv $A/combo/summary.txt evidence/E008/
cp $A/combo.chain evidence/E008/chain.txt
python3 -I scripts/ab_stats.py $A/combo/results.csv base > evidence/E008/stats.md
git -C ~/work/monero-fcmp-combo log --oneline -6 > evidence/E008/tree_log.txt
for d in h3105424 h3105414; do
  mkdir -p evidence/negtest/$d
  cp $A/negtest/$d/summary.txt $A/negtest/$d/base.json $A/negtest/$d/combo.json evidence/negtest/$d/
  for l in base combo; do
    grep -E "Failed to verify input FCMP\+\+ signatures|tx used wrong inputs|on_send_raw_tx" $A/negtest/$d/$l.log > evidence/negtest/$d/$l.rejections.log || true
  done
done
cp .E008.md experiments/E008-combined/README.md
python3 -I - <<'PYEOF'
import re
p = "experiments/E007-streaming-verifier/README.md"; s = open(p).read()
res = open(".e007_results.md").read()
old = "**Results (monerod window A/B):** queued as chain e007 (scripts/chain_build_ab.sh v2, waits for CHAIN_E004E_COMPLETE)."
assert old in s
s = s.replace(old, res, 1)
open(p, "w").write(s)

p = "FINDINGS.md"; s = open(p).read()
s += "| F15 | **E007 streaming FCMP++ verifier (fold constraints while building; build twice; never store the circuit): peak RssAnon -59.0% (5,582 → 2,291 MB), wall -50.5% (218 → 108 s), hashes match, 24/24 tampered txs rejected at the FCMP++ check.** Faster because the old verify folds CG weights in c passes over all q constraints (O(c·q), quadratic in inputs for 128-input proofs). | experiments/E007-streaming-verifier, evidence/E007/, evidence/negtest/ | **large** | CONFIRMED (unaudited crypto code) |\n"
s += "| F16 | **E008 combined build (E004c + E004e + E007 + E001 fix): peak RssAnon -66.9% (5,289 → 1,751 MB), post-sync idle -79.5% (4,850 → 993 MB), wall -46.8% (220 → 117 s).** Best build so far. | experiments/E008-combined, evidence/E008/ | **largest** | CONFIRMED; min_mem pending |\n"
s += "| F17 | Side finding: generalized-bulletproofs `ArithmeticCircuitStatement::verify` costs O(c·q) (one pass over all constraints per vector commitment). For max-input FCMP++ proofs this is ~52% of sync CPU. Folding in one pass (E007's accumulator, or an indexed fold inside the stored verifier) removes it. This is a pure CPU fix, separable from the memory change. | experiments/E006-cpu-profile, experiments/E007-streaming-verifier | CPU | candidate upstream note |\n"
s += "| F18 | Harness bug: ab_window.sh peak awk compared strings, so a short sampler row ('...,,log') could win. Only r1_e007's RSS was affected (0 → 3,083 MB). Fixed with numeric comparisons. | experiments/E007-streaming-verifier | harness | fixed |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
new = open(".state_running2.md").read()
s = re.sub(r"## Currently running\n.*?(?=## Watch)", new + "\n", s, count=1, flags=re.S)
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-03 03:00", s, count=1)
open(p, "w").write(s)
PYEOF
rm -f .E008.md .e007_results.md .state_running2.md
cat >> JOURNAL.md <<'JEOF_E78'

## 2026-11-03 02:47-03:00 Check-in: E007 -59% peak / -50% wall; combo -67% peak; negative test PASS
- Box: no shadow lanes, idle, 53 GB free.
- Both chains finished while I was away (e007 at 01:18, combo at 01:44), all hashes matching:
  - **E007** (streaming verifier only): peak 5,582 → 2,291 MB (-59%), wall 218 → 108 s (-50%).
  - **E008 combo** (E004c + E004e + E007 + E001 fix): peak 5,289 → 1,751 MB (-67%), post-idle 4,850 → 993 MB (-80%), wall 220 → 117 s (-47%).
- The 2x speed-up contradicts the agent's +40% micro-benchmark. Explanation: the old verify's CG fold is O(c·q). That is cheap for 1-8 inputs and dominant for 128 inputs (the window is 82% 128-input txs). A profile of the combo build is running to confirm.
- Because a 2x speed-up on crypto code is the classic sign of skipped work, I ran a **monerod-level negative test** (scripts/negtest.sh): bit-flipped FCMP++ proofs submitted to our own offline node. Base and combo each rejected 24/24 at "Failed to verify input FCMP++ signatures" and accepted 3/3 originals (128-, 8- and 2-input txs).
- Harness bug found and fixed: the peak awk compared strings (F18). One RSS value was corrected; all anon peaks re-verified.
- Owner pinged with the combo headline.
- Queued: the combo CPU profile, then the min_mem chain (combo, then base) with the governor pinned.
JEOF_E78
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E007 -59% peak/-50% wall; E008 combo -67% peak/-80% idle/-47% wall; negtest PASS; harness awk fix"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
du -sh evidence/negtest
