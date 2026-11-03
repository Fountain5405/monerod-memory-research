#!/bin/bash
# E013: validate the E012 "adapt" build (combo with an adaptive cap and trim) as the recommended build.
# Gate (gate_e012.py): heavy peak <= 1.10 x combo and small-tx wall <= 1.08 x base, else stop.
#   (a) heavy-window A/B base vs adapt, 3 rounds (headline numbers for adapt)  -> e013_ab/
#   (b) negative test at 3,105,424 and 3,105,414 (128-, 8- and 2-input txs)  -> e013_neg/
#   (c) minimum cgroup MemoryMax for adapt (ref wall = adapt's E012 heavy median) -> e013_minmem/
#   (d) long resync 3,105,401 -> 3,123,400: base_bss5, adapt_default, adapt_bss5, 1 run each -> e013_long/
# Governor pinned for timing parts. Marker: CHAIN_E013_COMPLETE in e013.chain.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e013.chain
S=~/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
echo "chain e013 start $(date -Is)" > $C
until tail -1 $A/e012.chain 2>/dev/null | grep -q CHAIN_E012_COMPLETE; do sleep 30; done
echo "e012 complete; starting $(date -Is)" >> $C
python3 -I $S/gate_e012.py $A/e012_small/results.csv $A/e012_heavy/results.csv >> $C 2>&1
tail -1 $C | grep -q "GATE PASS" || { echo CHAIN_E013_COMPLETE >> $C; exit 0; }
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e013_ab 3105441 900 3 "base|$B|--block-sync-size 5" "adapt|$D|--block-sync-size 5"
echo "(a) A/B done $(date -Is)" >> $C
$S/negtest.sh $A/e013_neg/h3105424 3105424 "adapt|$D"
$S/negtest.sh $A/e013_neg/h3105414 3105414 "adapt|$D"
echo "(b) negtest done $(date -Is): $(tail -2 $A/e013_neg/h3105424/summary.txt | head -1) / $(tail -2 $A/e013_neg/h3105414/summary.txt | head -1)" >> $C
REF=$(python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e012_heavy/results.csv')) if r['arm']=='adapt')))")
echo "min_mem ref wall $REF s" >> $C
$S/min_mem.sh $A/e013_minmem adapt $D $REF 750 4000 125 --block-sync-size 5
echo "(c) min_mem done $(date -Is): $(tail -2 $A/e013_minmem/adapt.summary | head -1)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e013_long 3123400 14400 1 \
  "base_bss5|$B|--block-sync-size 5" "adapt_default|$D|" "adapt_bss5|$D|--block-sync-size 5"
echo "(d) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E013_COMPLETE >> $C
