#!/bin/bash
# E025: close the two remaining validation gaps left by E023. The v2 series with patches 0007 + 0008 has never been built, and the differential test E015 predates E021 and E022.
#   (a) build v2final: copy of ~/work/monero-fcmp-e020 (without its build dir, including its local Cargo.toml repoint to monero-oxide-e020) + git am of v2 patches 0007 and 0008
#   (b) negdiff at 3,105,401 (scan 40) and 3,106,400 (scan 400), arms base (oracle), final, v2final -> e025_neg/
#   (c) heavy window A/B final vs v2final, 3 rounds -> e025_heavy/
#   (d) small-tx window A/B final vs v2final, 3 rounds -> e025_small/
# Expected, fixed before the run: DIFF PASS at both heights, all hashes match, v2final's peak anon within 5% of final on both windows, heavy wall about as in E020 (+28%, e020 vs adapt), small-tx wall about +3%. A miss is reported as a miss.
# Marker: CHAIN_E025_COMPLETE in e025.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e025.chain; S=/home/optimizer/work/research/scripts; R=/home/optimizer/work/research
T=/home/optimizer/work/monero-fcmp-v2final; BD=$T/build/beta31-v2final
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
V=$BD/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; H=$A/snapshots/stressnet_h3106400
echo "chain e025 start $(date -Is)" > $C
rsync -a --exclude build /home/optimizer/work/monero-fcmp-e020/ $T/
(
  cd $T || exit 1
  git am $R/patches/v2-E017-minimal/monerod/0007-E021-*.patch $R/patches/v2-E017-minimal/monerod/0008-E022-*.patch > $A/e025.am.log 2>&1 || { echo "GIT_AM_FAILED" >> $C; exit 1; }
  git log --oneline -3 >> $C
  git status --short >> $C
  source ~/.cargo/env
  mkdir -p $BD && cd $BD || exit 1
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e025.build.log 2>&1
)
echo "build $(tail -1 $A/e025.build.log 2>/dev/null) $(date -Is)" >> $C
tail -1 $A/e025.build.log 2>/dev/null | grep -q BUILD_OK || { echo CHAIN_E025_COMPLETE >> $C; exit 1; }
sha256sum $B $F $V >> $C
grep -n "HEAVY_PROOF_MIN_INPUTS = " $T/src/ringct/rctSigs.cpp >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa '[s]hadow' | grep -v 'bash -c' > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
$S/negdiff.sh $A/e025_neg/h3105401 $W 3105401 40 "base|$B" "final|$F" "v2final|$V"
$S/negdiff.sh $A/e025_neg/h3106400 $H 3106400 400 "base|$B" "final|$F" "v2final|$V"
echo "(b) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e025_neg/h3105401/summary.txt | tr '\n' ' ') / $(grep -E 'DIFF (PASS|FAIL)' $A/e025_neg/h3106400/summary.txt | tr '\n' ' ')" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e025_heavy 3105441 900 3 "final|$F|$X" "v2final|$V|$X"
echo "(c) heavy done $(date -Is)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$H $S/ab_window.sh $A/e025_small 3107400 900 3 "final|$F|$X" "v2final|$V|$X"
echo "(d) small done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for w in heavy small; do python3 $S/ab_stats.py $A/e025_$w/results.csv final >> $C 2>&1; done
python3 $S/e023_wall.py $A/e025_small 3106405 3107400 final v2final >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E025_COMPLETE >> $C
