#!/bin/bash
# E033: the monerod patches alone against base, with no verifier change. Why: if anything is presented upstream, the smallest piece is this one (+71/-1 lines in monerod, four files, no Rust). E004e measured a non-adaptive cap + trim at -44.6% peak; the adaptive form with the idle trim and the 8-input threshold has never been measured without a verifier change. Hydrogen. Report only. Waits for E032, because both are timing runs on this box.
#   Tree ~/work/monero-fcmp-e033 = d80596ad1 + patches/options/E033-monerod-only/ (v1's monerod 0001, 0002, 0005, 0006, 0007; no 0003 E001 fix, no 0004 verifier glue; 0006 with the one context line that comes from 0003 removed). Tree hash must equal the box81 compile check's e8d76fb5.
#   (a) heavy window base vs e033, 3 rounds -> e033_heavy/
#   (c) negative test at 3,105,424 and 3,105,414 -> e033_neg/. The verifier is unchanged, but the batching around it is not.
#   (d) cgroup minimum, warm cache, e033 only, lo 2000 hi 6000 step 125 -> e033_minmem/. Base's is E032's 5,562 MB, same box, same method.
#   (b) small-tx window base vs e033, 5 rounds -> e033_small/
#   (e) long resync 3,105,401 -> 3,123,400, base vs e033, 3 rounds -> e033_long/
# Expected, fixed before the run, from E004e (-44.6% peak, -88.0% post-idle, -5.5% wall, non-adaptive) and E028, and E034's cgroup-to-peak ratio: heavy peak -40 to -50%, heavy post-idle -75 to -90%, heavy wall -2 to -9%, small-tx wall -1 to +3%, small-tx peak -5 to -25% (ranges may overlap, base's small-tx peak is soft), negative test all tampered rejected and all originals accepted, cgroup minimum 3,000 to 3,800 MB, long peak -35 to -50%, long wall -5 to +4%, no upward trend after 3,110,000, all hashes match. A miss is reported as a miss.
# Marker: CHAIN_E033_COMPLETE in e033.chain
set -u
W0=/home/optimizer/work; R=$W0/research; A=$W0/research-artifacts; C=$A/e033.chain; S=$R/scripts
T=$W0/monero-fcmp-e033; BD=$T/build/beta31-e033
B=$W0/monero-fcmp/build/beta31/bin/monerod; E=$BD/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; H=$A/snapshots/stressnet_h3106400
X="--block-sync-size 5"
echo "chain e033 waiting for E032 $(date -Is)" > $C
until tail -1 $A/e032.chain 2>/dev/null | grep -q CHAIN_E032_COMPLETE; do sleep 60; done
echo "chain e033 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" >> $C
source ~/.cargo/env
export CCACHE_BASEDIR=$W0
rsync -a --exclude build $W0/monero-fcmp/ $T/
( cd $T || exit 1
  git -c user.name=optimizer -c user.email=optimizer@localhost am $R/patches/options/E033-monerod-only/*.patch > $A/e033.am.log 2>&1 ) || { echo GIT_AM_FAILED >> $C; echo CHAIN_E033_COMPLETE >> $C; exit 1; }
TH=$(git -C $T rev-parse 'HEAD^{tree}')
echo "tree $TH expected e8d76fb5404d57ff7c09dce8acf7c5ec0adbb827" >> $C
[ "$TH" = e8d76fb5404d57ff7c09dce8acf7c5ec0adbb827 ] || { echo TREE_MISMATCH >> $C; echo CHAIN_E033_COMPLETE >> $C; exit 1; }
mkdir -p $BD; cd $BD || exit 1
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e033.build.log 2>&1
r=$(tail -1 $A/e033.build.log); echo "build $r $(date -Is)" >> $C
[ "$r" = BUILD_OK ] || { echo CHAIN_E033_COMPLETE >> $C; exit 1; }
cd $A
sha256sum $B $E >> $C
df -h /home | tail -1 >> $C
sleep 60
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
( while kill -0 $$ 2>/dev/null; do ps -eo comm | grep -qx shadow && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e033_heavy 3105441 900 3 "base|$B|$X" "e033|$E|$X"
echo "(a) heavy done $(date -Is)" >> $C
$S/negtest.sh $A/e033_neg/h3105424 3105424 "e033|$E"
$S/negtest.sh $A/e033_neg/h3105414 3105414 "e033|$E"
echo "(c) negtest done $(date -Is): $(tail -2 $A/e033_neg/h3105424/summary.txt | head -1) / $(tail -2 $A/e033_neg/h3105414/summary.txt | head -1)" >> $C
RE=$(python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e033_heavy/results.csv')) if r['arm']=='e033')))")
echo "min_mem ref wall e033 $RE s" >> $C
$S/min_mem.sh $A/e033_minmem e033 $E $RE 2000 6000 125 $X
echo "(d) e033 done $(date -Is): $(tail -2 $A/e033_minmem/e033.summary | head -1)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$H $S/ab_window.sh $A/e033_small 3107400 900 5 "base|$B|$X" "e033|$E|$X"
echo "(b) small done $(date -Is)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e033_long 3123400 14400 3 "base|$B|$X" "e033|$E|$X"
echo "(e) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for d in heavy small long; do python3 -I $S/ab_stats.py $A/e033_$d/results.csv base >> $C 2>&1; done
python3 -I $S/e023_wall.py $A/e033_heavy 3105406 3105441 base e033 >> $C 2>&1
python3 -I $S/e023_wall.py $A/e033_small 3106405 3107400 base e033 >> $C 2>&1
python3 -I $S/e023_wall.py $A/e033_long 3105406 3123400 base e033 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E033_COMPLETE >> $C
