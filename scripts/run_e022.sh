#!/bin/bash
# E022: sweep adapt's HEAVY_PROOF_MIN_INPUTS (8 / 16 / 32) on top of the full series (idle tree, E021 included).
# Window 3,106,060 -> 3,106,112: per the E022a scan, 3,106,069-3,106,110 is contiguous, 37 blocks whose largest tx has 8 inputs
# and 5 whose largest has 16. Every other stretch of the chain trips all thresholds or none.
#   t8:  8- and 16-input blocks are heavy (cap at physical cores, trim per call)
#   t16: only the 16-input blocks are heavy (the current constant)
#   t32: neither is heavy
# Decision rule, fixed before the run: keep 16 unless another threshold is >=5% better on CPU or wall with peak not worse by
# more than 5%, or >=10% better on peak with wall within 3%. Medians of 5; overlapping ranges count as no difference.
# Marker: CHAIN_E022_COMPLETE in ~/work/research-artifacts/e022.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e022.chain; B=$A/e022_bins
S=/home/optimizer/work/research/scripts; T=/home/optimizer/work/monero-fcmp-idle; BD=$T/build/beta31-idle
F=$T/src/ringct/rctSigs.cpp
echo "chain e022 start $(date -Is)" > $C
mkdir -p $B
git -C $T status --short | grep -q . && { echo "idle tree dirty; abort" >> $C; exit 1; }
[ "$(grep -c 'HEAVY_PROOF_MIN_INPUTS = 16;' $F)" = 1 ] || { echo "constant not found; abort" >> $C; exit 1; }
cp $BD/bin/monerod $B/monerod-t16
source ~/.cargo/env
for t in 8 32; do
  sed -i "s/HEAVY_PROOF_MIN_INPUTS = [0-9]*;/HEAVY_PROOF_MIN_INPUTS = $t;/" $F
  if ! ninja -C $BD -j10 daemon > $A/e022.build.t$t.log 2>&1; then echo "BUILD_FAILED t$t" >> $C; git -C $T checkout -- src; exit 1; fi
  cp $BD/bin/monerod $B/monerod-t$t
  echo "built t$t $(date -Is) diff: $(git -C $T diff --stat | tail -1)" >> $C
done
git -C $T checkout -- src
ninja -C $BD -j10 daemon > $A/e022.build.restore.log 2>&1 && echo "tree restored and rebuilt, status lines: $(git -C $T status --short | wc -l)" >> $C
sha256sum $B/monerod-t8 $B/monerod-t16 $B/monerod-t32 >> $C
[ "$(sha256sum $B/monerod-t8 $B/monerod-t16 $B/monerod-t32 | cut -d' ' -f1 | sort -u | wc -l)" = 3 ] || { echo "binaries not distinct; abort" >> $C; exit 1; }

pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
START_H=3106060 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e022 3106112 900 5 \
  "t16|$B/monerod-t16|$X" "t8|$B/monerod-t8|$X" "t32|$B/monerod-t32|$X"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e022/results.csv t16 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E022_COMPLETE >> $C
