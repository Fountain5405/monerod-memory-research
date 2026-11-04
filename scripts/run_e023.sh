#!/bin/bash
# E023: validate the final v1 series (adapt + E021 idle trim + E022 threshold 8), the build the report recommends. E013's validation predates the last two patches.
#   (a) heavy-window A/B base vs final, 3 rounds            -> e023_heavy/
#   (b) small-tx window A/B base vs final, 3 rounds         -> e023_small/
#   (c) negative test at 3,105,424 and 3,105,414            -> e023_neg/
#   (d) minimum cgroup MemoryMax for final (ref wall = (a)) -> e023_minmem/
#   (e) long resync 3,105,401 -> 3,123,400, 1 run each: base_bss5, final_default, final_bss5 -> e023_long/
# Run order: (a), (c), (d), (b), (e), so the negative test pops from the heavy window as in E013 rather than across the small-tx window.
# Expected, fixed before the run. The final build should keep E013's result within run-to-run spread: heavy peak -60% or better against base,
# small-tx wall no more than +6% against base, negative test all tampered rejected and all originals accepted, min_mem no higher than 2,000 MB
# (E013: 1,866 MB with a 125 MB bisection step), no growth over the long resync, all hashes match. Any miss is reported as a miss, not re-run away.
# Marker: CHAIN_E023_COMPLETE in e023.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e023.chain; S=/home/optimizer/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; H=$A/snapshots/stressnet_h3106400
echo "chain e023 start $(date -Is)" > $C
sha256sum $B $D >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa '[s]hadow' | grep -v 'bash -c' > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
X="--block-sync-size 5"
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e023_heavy 3105441 900 3 "base|$B|$X" "final|$D|$X"
echo "(a) heavy done $(date -Is)" >> $C
$S/negtest.sh $A/e023_neg/h3105424 3105424 "final|$D"
$S/negtest.sh $A/e023_neg/h3105414 3105414 "final|$D"
echo "(c) negtest done $(date -Is): $(tail -2 $A/e023_neg/h3105424/summary.txt | head -1) / $(tail -2 $A/e023_neg/h3105414/summary.txt | head -1)" >> $C
REF=$(python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e023_heavy/results.csv')) if r['arm']=='final')))")
echo "min_mem ref wall $REF s" >> $C
$S/min_mem.sh $A/e023_minmem final $D $REF 750 4000 125 $X
echo "(d) min_mem done $(date -Is): $(tail -2 $A/e023_minmem/final.summary | head -1)" >> $C
START_H=3106400 REWIND_SNAPSHOT=$H $S/ab_window.sh $A/e023_small 3107400 900 3 "base|$B|$X" "final|$D|$X"
echo "(b) small done $(date -Is)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e023_long 3123400 14400 1 "base_bss5|$B|$X" "final_default|$D|" "final_bss5|$D|$X"
echo "(e) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for w in heavy small; do python3 $S/ab_stats.py $A/e023_$w/results.csv base >> $C 2>&1; done
echo "done $(date -Is)" >> $C
echo CHAIN_E023_COMPLETE >> $C
