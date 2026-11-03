#!/bin/bash
# Record E009 (min cgroup memory), patch min_mem.sh v2 (poll memory.events in loop). Run on hydrogen.
set -eu
cd ~/work/research
A=~/work/research-artifacts
mkdir -p evidence/E009 experiments/E009-min-mem
cp $A/minmem/combo.csv $A/minmem/combo.summary $A/minmem/base.csv $A/minmem/base.summary evidence/E009/
cp $A/minmem.chain evidence/E009/chain.txt
sudo journalctl -k --since "2026-11-03 02:54" --until "2026-11-03 03:24" --no-pager | grep -E "oom_memcg=|Killed process" > evidence/E009/kernel_oom.txt
cp .E009.md experiments/E009-min-mem/README.md && rm .E009.md
python3 -I - <<'PYEOF'
import re
p = "scripts/min_mem.sh"; s = open(p).read()
a = "    [ -f $cg/memory.peak ] && peak=$(( $(cat $cg/memory.peak) / 1048576 ))\n"
assert s.count(a) == 1
s = s.replace(a, a + "    [ -f $cg/memory.events ] && ooms=$(awk '/^oom_kill /{print $2}' $cg/memory.events)  # v2: poll; the scope vanishes once monerod dies\n", 1)
b = "  local ooms=$(grep -oE \"oom_kill [0-9]+\" $cg/memory.events 2>/dev/null | awk '{print $2}')\n"
assert s.count(b) == 1
s = s.replace(b, "  [ -f $cg/memory.events ] && ooms=$(awk '/^oom_kill /{print $2}' $cg/memory.events)\n", 1)
c = "  local t0=$(date +%s) h=0 peak=0\n"
assert s.count(c) == 1
s = s.replace(c, "  local t0=$(date +%s) h=0 peak=0 ooms=0\n", 1)
s = s.replace("# Completion marker: last line of <outdir>/<label>.summary is MINMEM_COMPLETE.", "# Completion marker: last line of <outdir>/<label>.summary is MINMEM_COMPLETE.\n# v2 (2026-11-03): oom_kill count polled inside the loop (v1 read it after the scope was already gone -> always 0).", 1)
open(p, "w").write(s)

p = "FINDINGS.md"; s = open(p).read()
s = re.sub(r"^Status: .*$", "Status: **TARGET EXCEEDED.** Combined build (E008): peak anon -67%, post-sync idle -80%, minimum cgroup memory -67.5% (5,750 → 1,866 MB), sync 47% faster, all guardrails held. See reports/SUMMARY.md (in progress).", s, count=1, flags=re.M)
s += "| F19 | **E009 minimum cgroup MemoryMax (swap off, window must finish within 1.1x wall and match .22's hash): base 5,750 MB (largest fail 5,562) vs combo 1,866 MB (largest fail 1,765): -67.5% (bracket -66.5% to -69.3%).** Every fail is a memcg OOM kill with anon at about the limit, so the needed RAM is about peak anon + 100-200 MB; page cache is evictable at no wall-time cost. | experiments/E009-min-mem, evidence/E009/ | **large** | CONFIRMED |\n"
s += "| F20 | Harness bug: min_mem.sh v1 read memory.events after the monerod process died; systemd removes the empty scope at once, so oom_kills was always 0. The kernel log confirmed all 7 OOM kills. Fixed in v2 (polled in the loop). | experiments/E009-min-mem | harness | fixed |\n"
open(p, "w").write(s)

p = "STATE.md"; s = open(p).read()
s = s.replace("- **minmem chain** (scripts/run_minmem.sh)", "- minmem chain DONE 03:23 (E009: base 5,750 MB vs combo 1,866 MB minimum MemoryMax, -67.5%). Was: (scripts/run_minmem.sh)", 1)
i = s.index("B. When the minmem chain is done"); j = s.index("\n", i)
s = s[:i] + "B. (DONE 03:30: E009 written up; owner informed.)" + s[j:]
s = re.sub(r"Last updated: .*", "Last updated: 2026-11-03 03:35", s, count=1)
open(p, "w").write(s)
PYEOF
bash -n scripts/min_mem.sh && echo "min_mem.sh syntax OK"
grep -n "ooms" scripts/min_mem.sh
cat >> JOURNAL.md <<'JEOF_E9'

## 2026-11-03 03:23-03:35 E009 min cgroup memory: -67.5%
- min_mem chain (combo, then base; governor pinned): minimum passing MemoryMax is **combo 1,866 MB vs base 5,750 MB (-67.5%)**, bracket -66.5% to -69.3%. All passes match .22's hash and finish within the 1.1x wall limit; at the minimum, walls are unchanged (106 s, 219 s).
- All 7 fails are memcg OOM kills (kernel log), with anon at about the limit. Base near its limit first slowed as page cache was squeezed, then was killed. The A/B anon-peak metric and the cgroup metric agree (-67%).
- Harness bug F20: oom_kills was always 0, because memory.events was read after the scope vanished. Fixed in min_mem.sh v2.
- Owner asked (03:00) to be pinged when min_mem results were in. They were at the terminal, so PushNotification was suppressed as redundant and the result was reported in the chat.
JEOF_E9
git add -A
git -c user.name=optimizer -c user.email=optimizer@hydrogen commit -q -m "E009: min cgroup memory base 5,750 MB vs combo 1,866 MB (-67.5%); min_mem.sh v2 oom fix"
git log --oneline -1
git log -p -1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v -E "^(192\.168\.|127\.|0\.0\.0\.0)" | sort -u || true
