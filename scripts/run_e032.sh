#!/bin/bash
# E032: validate v2final against base the way E023 validated final, because v2 is what would be presented upstream (owner, 2026-11-04). E018 and E020 measured v2 before its last two patches, and E025 compared v2final only with final. Hydrogen. Report only. Runs after E034.
#   (a) heavy window base vs v2final, 3 rounds -> e032_heavy/
#   (c) negative test at 3,105,424 and 3,105,414 (the second is E023's source for 8-input rejection evidence) -> e032_neg/
#   (d) cgroup minimum, warm cache, the same method as E023, so comparable with final's 1,866 MB: v2final lo 750 hi 4000 step 125; base lo 2000 hi 8000 step 250, as E009's figure has not been re-measured on this box -> e032_minmem/
#   (b) small-tx window base vs v2final, 5 rounds -> e032_small/
#   (e) long resync 3,105,401 -> 3,123,400, base vs v2final, 3 rounds -> e032_long/
# Expected, fixed before the run, from E023 (final vs base), E025 (v2final vs final) and E018: heavy peak -60 to -72%, heavy wall -30 to -40%, small-tx wall +6 to +11%, small-tx peak -20 to -30%, negative test all tampered rejected and all originals accepted, cgroup minimum at or below 2,000 MB, long peak -65 to -75%, long wall between -3% and +6%, no upward trend after 3,110,000, all hashes match. A miss is reported as a miss.
# Marker: CHAIN_E032_COMPLETE in e032.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e032.chain; S=/home/optimizer/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
V=/home/optimizer/work/monero-fcmp-v2final/build/beta31-v2final/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; H=$A/snapshots/stressnet_h3106400
X="--block-sync-size 5"
echo "chain e032 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
sha256sum $B $V >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
( while kill -0 $$ 2>/dev/null; do ps -eo comm | grep -qx shadow && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e032_heavy 3105441 900 3 "base|$B|$X" "v2final|$V|$X"
echo "(a) heavy done $(date -Is)" >> $C
$S/negtest.sh $A/e032_neg/h3105424 3105424 "v2final|$V"
$S/negtest.sh $A/e032_neg/h3105414 3105414 "v2final|$V"
echo "(c) negtest done $(date -Is): $(tail -2 $A/e032_neg/h3105424/summary.txt | head -1) / $(tail -2 $A/e032_neg/h3105414/summary.txt | head -1)" >> $C
ref() { python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e032_heavy/results.csv')) if r['arm']=='$1')))"; }
RV=$(ref v2final); RB=$(ref base); echo "min_mem ref walls v2final $RV s, base $RB s" >> $C
$S/min_mem.sh $A/e032_minmem v2final $V $RV 750 4000 125 $X
echo "(d) v2final done $(date -Is): $(tail -2 $A/e032_minmem/v2final.summary | head -1)" >> $C
$S/min_mem.sh $A/e032_minmem base $B $RB 2000 8000 250 $X
echo "(d) base done $(date -Is): $(tail -2 $A/e032_minmem/base.summary | head -1)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$H $S/ab_window.sh $A/e032_small 3107400 900 5 "base|$B|$X" "v2final|$V|$X"
echo "(b) small done $(date -Is)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e032_long 3123400 14400 3 "base|$B|$X" "v2final|$V|$X"
echo "(e) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for d in heavy small long; do python3 -I $S/ab_stats.py $A/e032_$d/results.csv base >> $C 2>&1; done
python3 -I $S/e023_wall.py $A/e032_heavy 3105406 3105441 base v2final >> $C 2>&1
python3 -I $S/e023_wall.py $A/e032_small 3106405 3107400 base v2final >> $C 2>&1
python3 -I $S/e023_wall.py $A/e032_long 3105406 3123400 base v2final >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E032_COMPLETE >> $C
