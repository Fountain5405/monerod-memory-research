#!/bin/bash
# E022 guard: t8 vs t16 on the standard small-tx window, 3 alternating rounds.
# Pass, fixed before the run: all hashes match, and t8's median wall, CPU and peak anon are each within 3% of t16's or better.
# Pass -> threshold 8 becomes a one-line monerod patch. Fail -> 16 stays, and E022 records why.
# Heavy window not rerun: its only block that differs between these arms is 3,105,414.
# Marker: CHAIN_E022B_COMPLETE in ~/work/research-artifacts/e022b.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e022b.chain; B=$A/e022_bins; S=/home/optimizer/work/research/scripts
echo "chain e022b start $(date -Is)" > $C
sha256sum $B/monerod-t8 $B/monerod-t16 >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e022_small 3107400 3600 3 "t16|$B/monerod-t16|$X" "t8|$B/monerod-t8|$X"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e022_small/results.csv t16 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E022B_COMPLETE >> $C
