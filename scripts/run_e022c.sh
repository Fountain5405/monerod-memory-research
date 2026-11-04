#!/bin/bash
# E022 replication: t8 vs t16 on two independent stretches where the arms really differ (the small-tx guard had none, so it was an A/A).
#   A: 3,105,080 -> 3,105,106, largest tx 8 inputs on 3,105,089-3,105,101, those txs nearly all 8-input
#   B: 3,106,260 -> 3,106,286, largest tx 8 inputs on 3,106,268-3,106,280, about a third of the txs 8-input
# 5 alternating rounds each. Wall from log timestamps and CPU from cpu_watch.sh, both over identical heights.
# Criterion, fixed before the run. On BOTH windows: t8's CPU at least 5% lower with non-overlapping ranges, wall no more than +5%,
# peak anon not worse by more than 5%, all hashes match. Then threshold 8 becomes a one-line patch. Otherwise 16 stays.
# Marker: CHAIN_E022C_COMPLETE in ~/work/research-artifacts/e022c.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e022c.chain; B=$A/e022_bins; S=/home/optimizer/work/research/scripts
echo "chain e022c start $(date -Is)" > $C
sha256sum $B/monerod-t8 $B/monerod-t16 >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa '[s]hadow' | grep -v 'bash -c' > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
bash $S/cpu_watch.sh $$ &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
START_H=3105080 REWIND_SNAPSHOT=$A/snapshots/stressnet_wedge_h3105401 $S/ab_window.sh $A/e022c_a 3105106 900 5 "t16|$B/monerod-t16|$X" "t8|$B/monerod-t8|$X"
echo "(A) done $(date -Is)" >> $C
START_H=3106260 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e022c_b 3106286 900 5 "t16|$B/monerod-t16|$X" "t8|$B/monerod-t8|$X"
echo "(B) done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for w in a b; do python3 $S/ab_stats.py $A/e022c_$w/results.csv t16 >> $C 2>&1; done
echo "done $(date -Is)" >> $C
echo CHAIN_E022C_COMPLETE >> $C
