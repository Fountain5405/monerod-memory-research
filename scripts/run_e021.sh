#!/bin/bash
# E021: idle trim on top of adapt (monero-fcmp-idle = adapt 4a51d434d + e021_patch_idle_trim.py).
#   build ~/work/monero-fcmp-idle/build/beta31-idle (ninja -j10 daemon, ARCH=native, same recipe as e017/e020), then
#   (a) heavy window 3,105,401 -> 3,105,441: adapt vs idle, 3 alternating rounds -> e021_heavy/ (post-idle anon is the target metric)
#   (b) small-tx window 3,106,400 -> 3,107,400: adapt vs idle, 3 rounds        -> e021_small/ (wall must not move)
# Marker: CHAIN_E021_COMPLETE in e021.chain.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e021.chain
S=~/work/research/scripts
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
I=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
X="--block-sync-size 5"
echo "chain e021 start $(date -Is)" > $C
git -C ~/work/monero-fcmp-idle diff --stat >> $C
(
  source ~/.cargo/env
  mkdir -p ~/work/monero-fcmp-idle/build/beta31-idle && cd ~/work/monero-fcmp-idle/build/beta31-idle || exit 1
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e021.build.log 2>&1
)
echo "build $(tail -1 $A/e021.build.log) $(date -Is)" >> $C
tail -1 $A/e021.build.log | grep -q BUILD_OK || { echo CHAIN_E021_COMPLETE >> $C; exit 1; }
sha256sum $D $I >> $C
strings $I | grep -c "returned freed verifier memory" >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e021_heavy 3105441 900 3 "adapt|$D|$X" "idle|$I|$X"
echo "(a) heavy A/B done $(date -Is)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e021_small 3107400 3600 3 "adapt|$D|$X" "idle|$I|$X"
echo "(b) small-tx A/B done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
for d in e021_heavy e021_small; do echo "== $d" >> $C; python3 -I $S/ab_stats.py $A/$d/results.csv adapt >> $C 2>&1; done
echo "idle-trim log lines per run:" >> $C; grep -c "returned freed verifier memory" $A/e021_heavy/r*_idle.log $A/e021_small/r*_idle.log >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E021_COMPLETE >> $C
