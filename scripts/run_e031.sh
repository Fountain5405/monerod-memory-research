#!/bin/bash
# E031: the two measurements of the final series not yet repeated on the second machine (box81, hostname moonpie): the cgroup minimum, one of the project's stated metrics, and the long resync. E027 repeated the heavy and small-tx windows and the differential test only. base's cgroup minimum (5,750 MB, E009) has also never been re-measured against final, so both arms are measured here in one chain. Report only: no change to the recommended build follows. box81 figures are compared only with box81 figures.
#   (a) min_mem on the heavy window: final (lo 750, hi 4000, step 125), base (lo 1500, hi 7000, step 250), reference walls from E027's harness medians on this box, as min_mem always uses, --block-sync-size 5 -> e031_minmem/
#   (b) long resync 3,105,401 -> 3,123,400, base vs final, --block-sync-size 5, 3 alternating rounds, DB restored from the snapshot before each run -> e031_long/ (E023 ran 1 per arm on hydrogen)
# Expected, fixed before the run, from E023 on hydrogen and E027 on this box: final's minimum at or below 2,000 MB; base's 3,500-5,000 MB; so about -50 to -65%. Long resync: peak anon about -55 to -65%, post-idle at least -60%, wall between -8% and +3%, no upward memory trend after 3,110,000, all hashes match. A miss is reported as a miss.
# Marker: CHAIN_E031_COMPLETE in e031.chain. Other users' load is sampled to e031.load every 5 min; timing with sustained foreign load is flagged, not rerun silently.
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e031.chain; S=/home/optimizer/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
F=/home/optimizer/work/monero-fcmp-final/build/beta31-final/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; DD=/home/optimizer/work/chains/stressnet
X="--block-sync-size 5"
echo "chain e031 start $(date -Is)" > $C
sha256sum $B $F >> $C
for i in $(seq 1 60); do l=$(cut -d' ' -f1 /proc/loadavg); awk -v l=$l 'BEGIN{exit !(l<0.5)}' && break; sleep 30; done
echo "idle check $(date -Is): load $(cut -d' ' -f1-3 /proc/loadavg); users: $(who | awk '{print $1}' | sort | uniq -c | tr '\n' ' ')" >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
( while :; do echo "$(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg) others: $(ps -eo user,pcpu,comm --sort=-pcpu | awk 'NR>1 && $1!="optimiz+" && $1!="optimizer" && $1!="root" && $2>20' | head -3 | tr '\n' ';')"; sleep 300; done > $A/e031.load ) &
LOADP=$!
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
rm -f $DD/testnet/lmdb/lock.mdb; cp $W/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb; echo "DB restored $(date -Is)" >> $C
ref() { python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$A/e027_heavy/results.csv')) if r['arm']=='$1')))"; }
RF=$(ref final); RB=$(ref base); echo "reference walls final $RF s, base $RB s" >> $C
$S/min_mem.sh $A/e031_minmem final $F $RF 750 4000 125 $X
echo "(a1) final done $(date -Is): $(tail -2 $A/e031_minmem/final.summary | head -1)" >> $C
$S/min_mem.sh $A/e031_minmem base $B $RB 1500 7000 250 $X
echo "(a2) base done $(date -Is): $(tail -2 $A/e031_minmem/base.summary | head -1)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e031_long 3123400 14400 3 "base|$B|$X" "final|$F|$X"
echo "(b) long resync done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
kill $LOADP 2>/dev/null
python3 -I $S/ab_stats.py $A/e031_long/results.csv base >> $C 2>&1
python3 -I $S/e023_wall.py $A/e031_long 3105406 3123396 base final >> $C 2>&1
echo "foreign load samples: $(grep -c 'others: [a-z]' $A/e031.load) of $(wc -l < $A/e031.load)" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E031_COMPLETE >> $C
