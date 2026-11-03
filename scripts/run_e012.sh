#!/bin/bash
# E012: adaptive batch cap + trim (patch_e012_adapt.py) on top of the combo tree, as one variant "adapt".
# E011 showed the combo's small-tx slowdown comes mainly from E004c (cap, +7%) and E004e (trim per block, +6%),
# and E007 adds only +2-3%. adapt = cap only when the largest proof in the call has >= 16 inputs; trim after
# heavy calls, else at most every 10 s.
#   (a) small-tx window 3,106,400 -> 3,107,400 (snapshot h3106400): base, combo, adapt.
#   (b) heavy window 3,105,401 -> 3,105,441 (wedge snapshot): combo, adapt, e007 (e007 = no cap and no trim).
# 3 alternating rounds each, all --block-sync-size 5, governor pinned. Marker: CHAIN_E012_COMPLETE in e012.chain.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e012.chain
S=~/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
X=/home/optimizer/work/monero-fcmp-combo/build/beta31-combo/bin/monerod
E7=/home/optimizer/work/monero-fcmp-e007/build/beta31-e007/bin/monerod
T=/home/optimizer/work/monero-fcmp-adapt
D=$T/build/beta31-adapt/bin/monerod
echo "chain e012 start $(date -Is)" > $C
until tail -1 $A/e011.chain 2>/dev/null | grep -q CHAIN_E011_COMPLETE; do sleep 30; done
echo "e011 complete; starting $(date -Is)" >> $C
if [ ! -x $D ]; then
  rsync -a --exclude build ~/work/monero-fcmp-combo/ $T/
  cd $T && git checkout -q -b combo-adapt && python3 -I $S/patch_e012_adapt.py >> $C 2>&1 \
    && git commit -q -am "E012: FCMP++ batch cap and malloc_trim adaptive to proof size" && git log --oneline -1 >> $C \
    || { echo "E012 patch/commit FAILED"; echo CHAIN_E012_COMPLETE; } >> $C
  tail -1 $C | grep -q CHAIN_E012_COMPLETE && exit 1
  git -C $T diff HEAD~1 > $A/e012.diff
  source ~/.cargo/env
  mkdir -p $T/build/beta31-adapt && cd $T/build/beta31-adapt
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e012.build.log 2>&1
  tail -1 $A/e012.build.log >> $C
  tail -1 $A/e012.build.log | grep -q BUILD_OK || { echo CHAIN_E012_COMPLETE >> $C; exit 1; }
fi
sha256sum $D >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e012_small 3107400 3600 3 \
  "base|$B|--block-sync-size 5" "combo|$X|--block-sync-size 5" "adapt|$D|--block-sync-size 5"
echo "small-tx A/B done $(date -Is)" >> $C
REWIND_SNAPSHOT=$A/snapshots/stressnet_wedge_h3105401 $S/ab_window.sh $A/e012_heavy 3105441 900 3 \
  "combo|$X|--block-sync-size 5" "adapt|$D|--block-sync-size 5" "e007|$E7|--block-sync-size 5"
echo "heavy A/B done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E012_COMPLETE >> $C
