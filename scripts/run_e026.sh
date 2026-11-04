#!/bin/bash
# E026: sweep the light-call trim interval, the last tuning constant never swept. SUMMARY lists it as a judgment call, and small-tx wall (+6.6% vs base, E023) is the build's main cost.
# Arms on the final tree, differing only in the constant in `now_ms - s_fcmp_last_trim_ms ... >= 10000` in rctSigs.cpp: i10 (10 s, the final binary), i60 (60 s), inever (about 30 years, so no light-call trim; a bound, never a candidate).
# Heavy calls and the idle trim are unchanged. Small-tx window, 5 alternating rounds, wall from scripts/e023_wall.py over 3,106,405 -> 3,107,400.
# Rule, fixed before the run. Adopt i60 only if its wall is at least 2% below i10 with non-overlapping ranges, peak anon not worse by more than 5%, and all hashes match. Otherwise 10 s stays.
# inever only says how much of the wall gap light-call trims can account for at all.
# Marker: CHAIN_E026_COMPLETE in e026.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e026.chain; S=/home/optimizer/work/research/scripts; B=$A/e026_bins
T=/home/optimizer/work/monero-fcmp-idle; BD=$T/build/beta31-idle; F=$T/src/ringct/rctSigs.cpp
echo "chain e026 queued $(date -Is)" > $C
until tail -1 $A/e025.chain 2>/dev/null | grep -q CHAIN_E025_COMPLETE; do sleep 30; done
echo "start $(date -Is)" >> $C
git -C $T status --short | grep -q . && { echo "tree dirty; abort" >> $C; echo CHAIN_E026_COMPLETE >> $C; exit 1; }
[ "$(grep -c 's_fcmp_last_trim_ms.load(std::memory_order_relaxed) >= 10000)' $F)" = 1 ] || { echo "constant not found; abort" >> $C; echo CHAIN_E026_COMPLETE >> $C; exit 1; }
mkdir -p $B
cp $BD/bin/monerod $B/monerod-i10
source ~/.cargo/env
for p in "i60 60000" "inever 1000000000000"; do
  set -- $p
  sed -i "s/s_fcmp_last_trim_ms.load(std::memory_order_relaxed) >= 10000)/s_fcmp_last_trim_ms.load(std::memory_order_relaxed) >= $2)/" $F
  if ! ninja -C $BD -j10 daemon > $A/e026.build.$1.log 2>&1; then echo "BUILD_FAILED $1" >> $C; git -C $T checkout -- src; echo CHAIN_E026_COMPLETE >> $C; exit 1; fi
  cp $BD/bin/monerod $B/monerod-$1
  echo "built $1 $(date -Is) diff: $(git -C $T diff --stat | tail -1)" >> $C
  git -C $T checkout -- src
done
ninja -C $BD -j10 daemon > $A/e026.build.restore.log 2>&1 && echo "tree restored and rebuilt, status lines: $(git -C $T status --short | wc -l)" >> $C
sha256sum $B/monerod-i10 $B/monerod-i60 $B/monerod-inever $BD/bin/monerod >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa '[s]hadow' | grep -v 'bash -c' > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e026_small 3107400 900 5 "i10|$B/monerod-i10|$X" "i60|$B/monerod-i60|$X" "inever|$B/monerod-inever|$X"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e026_small/results.csv i10 >> $C 2>&1
python3 $S/e023_wall.py $A/e026_small 3106405 3107400 i10 i60 >> $C 2>&1
python3 $S/e023_wall.py $A/e026_small 3106405 3107400 i10 inever | tail -2 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E026_COMPLETE >> $C
