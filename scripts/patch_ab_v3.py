#!/usr/bin/env python3
"""ab_window.sh v3: optional REWIND_SNAPSHOT=<snapshot dir>: copy its testnet/lmdb/data.mdb over the working DB before
pop_to.sh (which then verifies height/hash 3,105,401 against .22). For long resyncs where popping is slow. Also log
the oom/ban-free post-idle as before. Run from ~/work/research."""
p = "scripts/ab_window.sh"
s = open(p).read()
old = "    ~/work/research/scripts/pop_to.sh $POPBIN $DD 3105401 $OUT/$tag.rewind.log\n"
assert s.count(old) == 1
new = ("    if [ -n \"${REWIND_SNAPSHOT:-}\" ]; then  # v3: restore from snapshot (fast for long resyncs), then pop_to verifies\n"
       "      rm -f $DD/testnet/lmdb/lock.mdb; cp $REWIND_SNAPSHOT/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb\n"
       "      echo \"[$tag] restored DB from $REWIND_SNAPSHOT $(date -Is)\" >> $S\n"
       "    fi\n" + old)
s = s.replace(old, new, 1)
s = s.replace("# Completion marker: last line of <outdir>/summary.txt is AB_COMPLETE.",
              "# Completion marker: last line of <outdir>/summary.txt is AB_COMPLETE.\n# v3 (2026-11-03): env REWIND_SNAPSHOT=<dir> restores the DB from a snapshot before each run (then pop_to.sh verifies).", 1)
open(p, "w").write(s)
print("patched ab_window.sh v3")
