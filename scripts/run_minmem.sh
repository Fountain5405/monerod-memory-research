#!/bin/bash
# Chain: after the combo profile, minimum cgroup memory for base and combo (scripts/min_mem.sh).
# Governor pinned to performance for the whole chain, restored afterwards.
# Reference walls = the A/B medians (combo chain): base 220 s, combo 117 s. FACTOR 1.10.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/minmem.chain
echo "minmem chain start $(date -Is)" > $C
until tail -1 $A/profile_combo/summary.txt 2>/dev/null | grep -q PROFILE_COMPLETE; do sleep 30; done
echo "wait satisfied $(date -Is)" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
~/work/research/scripts/min_mem.sh $A/minmem combo /home/optimizer/work/monero-fcmp-combo/build/beta31-combo/bin/monerod 117 750 4000 125 --block-sync-size 5
echo "combo done $(date -Is): $(tail -2 $A/minmem/combo.summary | head -1)" >> $C
~/work/research/scripts/min_mem.sh $A/minmem base /home/optimizer/work/monero-fcmp/build/beta31/bin/monerod 220 2000 8000 250 --block-sync-size 5
echo "base done $(date -Is): $(tail -2 $A/minmem/base.summary | head -1)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo CHAIN_MINMEM_COMPLETE >> $C
