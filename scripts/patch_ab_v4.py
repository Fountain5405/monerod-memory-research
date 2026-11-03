#!/usr/bin/env python3
"""ab_window.sh v4: env START_H (default 3105401) = rewind/verify height for pop_to.sh, so windows can start
elsewhere (E011 small-tx stretch from a 3,106,400 snapshot); new last column cpu_s = monerod utime+stime at the
end of the sync loop (before the post-idle wait). ab_stats.py prints cpu_s when present. Run from ~/work/research."""
p = "scripts/ab_window.sh"
s = open(p).read()
old = "    ~/work/research/scripts/pop_to.sh $POPBIN $DD 3105401 $OUT/$tag.rewind.log\n"
assert s.count(old) == 1
s = s.replace(old, "    ~/work/research/scripts/pop_to.sh $POPBIN $DD ${START_H:-3105401} $OUT/$tag.rewind.log\n", 1)
old = "tip_height,hash_match,post_idle_anon_MB\" > $R"
assert s.count(old) == 1
s = s.replace(old, "tip_height,hash_match,post_idle_anon_MB,cpu_s\" > $R", 1)
old = "    t1=$(date +%s)\n"
assert s.count(old) == 1
s = s.replace(old, old + "    cpu=$(awk -v hz=$(getconf CLK_TCK) '{print int(($14+$15)/hz)}' /proc/$MP/stat 2>/dev/null)  # v4\n", 1)
old = ",${tip#* },${post:-}\" >> $R"
assert s.count(old) == 1
s = s.replace(old, ",${tip#* },${post:-},${cpu:-}\" >> $R", 1)
i = s.index("\n", s.index("# usage: ab_window.sh")) + 1  # comment goes right after the usage line
s = s[:i] + "# v4 (2026-11-03): env START_H=<height> (default 3105401) for pop_to.sh; results.csv gains cpu_s (utime+stime at sync end).\n" + s[i:]
open(p, "w").write(s)
q = "scripts/ab_stats.py"
t = open(q).read()
old = '("write_MB", "write MB")]'
assert t.count(old) == 1
t = t.replace(old, '("write_MB", "write MB")]\nif rows and "cpu_s" in rows[0]: cols.append(("cpu_s", "CPU s"))', 1)
open(q, "w").write(t)
print("patched ab_window.sh v4 and ab_stats.py")
