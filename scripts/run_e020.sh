#!/bin/bash
# E020: node-level measurement of the two-build v2 verifier (monero-oxide e020-two-builds) against adapt (v1) and e017 (v2).
# Waits for the e020 monerod build marker ~/work/research-artifacts/e020.build (BUILD_OK).
#   (a) heavy window 3,105,401 -> 3,105,441: adapt, e017, e020; 3 alternating rounds      -> e020_heavy/
#   (b) small-tx window 3,106,400 -> 3,107,400: adapt, e017, e020; 3 rounds              -> e020_small/
#   (c) negdiff vs base at 3,105,401 (scan 40) and 3,106,400 (scan 400), e020            -> e020_neg/
# All with --block-sync-size 5, governor pinned for timing parts. Marker: CHAIN_E020_COMPLETE in e020.chain.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e020.chain
S=~/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
E=/home/optimizer/work/monero-fcmp-e017/build/beta31-e017/bin/monerod
F=/home/optimizer/work/monero-fcmp-e020/build/beta31-e020/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
X="--block-sync-size 5"
echo "chain e020 start $(date -Is)" > $C
until grep -q BUILD_OK $A/e020.build 2>/dev/null; do sleep 30; done
echo "e020 build present; starting $(date -Is)" >> $C
git -C ~/work/monero-oxide-e020 log --oneline -1 >> $C
sha256sum $D $E $F >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e020_heavy 3105441 900 3 "adapt|$D|$X" "e017|$E|$X" "e020|$F|$X"
echo "(a) heavy A/B done $(date -Is)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e020_small 3107400 3600 3 "adapt|$D|$X" "e017|$E|$X" "e020|$F|$X"
echo "(b) small-tx A/B done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
$S/negdiff.sh $A/e020_neg/h3105401 $W 3105401 40 "base|$B" "e020|$F"
$S/negdiff.sh $A/e020_neg/h3106400 $A/snapshots/stressnet_h3106400 3106400 400 "base|$B" "e020|$F"
echo "(c) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e020_neg/h3105401/summary.txt) / $(grep -E 'DIFF (PASS|FAIL)' $A/e020_neg/h3106400/summary.txt)" >> $C
for d in e020_heavy e020_small; do echo "== $d" >> $C; python3 -I $S/ab_stats.py $A/$d/results.csv adapt >> $C 2>&1; done
echo "done $(date -Is)" >> $C
echo CHAIN_E020_COMPLETE >> $C
