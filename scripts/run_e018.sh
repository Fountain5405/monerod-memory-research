#!/bin/bash
# E018: node-level measurement of the E017 "folded" verifier (adapt's monerod changes + monero-oxide e017-folded-verify).
# Waits for CHAIN_E015_E014_COMPLETE (hydrogen timing runs) AND for the go-marker ~/work/research-artifacts/e018.go
# (touched once ~/work/monero-oxide-e017 is synced to the final box81 commits).
#   build:  ~/work/monero-fcmp-e017/build/beta31-e017 (ninja -j10 daemon)
#   (a) heavy window 3,105,401 -> 3,105,441: base, adapt, e017; 3 alternating rounds   -> e018_heavy/
#   (b) small-tx window 3,106,400 -> 3,107,400: base, adapt, e017; 3 rounds           -> e018_small/
#   (c) negdiff vs base at 3,105,401 (scan 40) and 3,106,400 (scan 400)               -> e018_neg/
#   (d) min_mem e017 (ref wall = e017's heavy median)                                 -> e018_minmem/
#   (e) long resync 3,105,401 -> 3,123,400, e017_bss5, 1 run                          -> e018_long/
# All with --block-sync-size 5, governor pinned for timing parts. Marker: CHAIN_E018_COMPLETE in e018.chain.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e018.chain
S=~/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
T=/home/optimizer/work/monero-fcmp-e017
E=$T/build/beta31-e017/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
echo "chain e018 start $(date -Is)" > $C
until tail -1 $A/e015_e014.chain 2>/dev/null | grep -q CHAIN_E015_E014_COMPLETE && [ -f $A/e018.go ]; do sleep 30; done
echo "e014 complete and go-marker present; starting $(date -Is)" >> $C
git -C ~/work/monero-oxide-e017 log --oneline -2 >> $C
if [ ! -x $E ]; then
  source ~/.cargo/env
  mkdir -p $T/build/beta31-e017 && cd $T/build/beta31-e017
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e018.build.log 2>&1
  tail -1 $A/e018.build.log >> $C
  tail -1 $A/e018.build.log | grep -q BUILD_OK || { echo CHAIN_E018_COMPLETE >> $C; exit 1; }
fi
sha256sum $E >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e018_heavy 3105441 900 3 \
  "base|$B|--block-sync-size 5" "adapt|$D|--block-sync-size 5" "e017|$E|--block-sync-size 5"
echo "(a) heavy A/B done $(date -Is)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e018_small 3107400 3600 3 \
  "base|$B|--block-sync-size 5" "adapt|$D|--block-sync-size 5" "e017|$E|--block-sync-size 5"
echo "(b) small-tx A/B done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null
$S/negdiff.sh $A/e018_neg/h3105401 $W 3105401 40 "base|$B" "e017|$E"
$S/negdiff.sh $A/e018_neg/h3106400 $A/snapshots/stressnet_h3106400 3106400 400 "base|$B" "e017|$E"
echo "(c) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e018_neg/h3105401/summary.txt) / $(grep -E 'DIFF (PASS|FAIL)' $A/e018_neg/h3106400/summary.txt)" >> $C
sudo cpupower frequency-set -g performance > /dev/null
REF=$(python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e018_heavy/results.csv')) if r['arm']=='e017')))")
echo "min_mem ref wall $REF s" >> $C
$S/min_mem.sh $A/e018_minmem e017 $E $REF 750 4000 125 --block-sync-size 5
echo "(d) min_mem done $(date -Is): $(tail -2 $A/e018_minmem/e017.summary | head -1)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e018_long 3123400 14400 1 "e017_bss5|$E|--block-sync-size 5"
echo "(e) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E018_COMPLETE >> $C
