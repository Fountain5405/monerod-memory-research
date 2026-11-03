#!/usr/bin/env python3
"""min_mem.sh v2b: after each trial, take the OOM-kill count from the kernel log as the authoritative source
(the scope's memory.events may vanish before the 2 s poll sees the kill). Run from ~/work/research."""
p = "scripts/min_mem.sh"
s = open(p).read()
b = "  [ -f $cg/memory.events ] && ooms=$(awk '/^oom_kill /{print $2}' $cg/memory.events)\n"
assert s.count(b) == 1, s.count(b)
add = ('  local kk=$(sudo journalctl -k --since @$t0 --no-pager 2>/dev/null | grep -c "oom_memcg=/system.slice/$unit.scope")  # authoritative: kernel log\n'
       '  [ "${kk:-0}" -gt "${ooms:-0}" ] && ooms=$kk\n')
s = s.replace(b, b + add, 1)
open(p, "w").write(s)
print("patched")
