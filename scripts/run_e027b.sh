#!/bin/bash
# E027 part b, box81 (hostname moonpie): base vs final on this second machine. Start only after E026 has finished on hydrogen, so the two boxes do not share .22 during E026's timing. Needs part a's marker.
#   (b1) heavy window 3,105,401 -> 3,105,441, 3 alternating rounds, DB restored from the snapshot before each run -> e027_heavy/
#   (b2) prep, untimed: base syncs once to 3,106,400 -> e027_prep/
#   (b3) small-tx window 3,106,400 -> 3,107,400, 3 alternating rounds, in-place rewind as in E019 -> e027_small/
#   (b4) negdiff at 3,106,400 with hydrogen's case file, arms base, final -> e027_neg/h3106400. SNAP is the working DB, so negdiff's cp fails harmlessly and pop_to rewinds in place, avoiding a third 18 GB copy on a shared disk.
# Expected, fixed before the run, from E019's adapt figures on this box: heavy peak anon about -60% (E019 -61.5%), post-idle at least -71% (E019 -70.9%, E021 adds a trim), wall about -43%; small-tx peak about -33%, post-idle at least -18.5%, wall +5% to +7% (E019 +5.4%, hydrogen's final +6.6%); all hashes match, VmSwap 0, DIFF PASS on 101 cases. Compared only with base on this box, never with hydrogen. A miss is reported as a miss.
# Marker: CHAIN_E027_COMPLETE in e027b.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e027b.chain; S=/home/optimizer/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
F=/home/optimizer/work/monero-fcmp-final/build/beta31-final/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; DD=/home/optimizer/work/chains/stressnet
X="--block-sync-size 5"
echo "chain e027b start $(date -Is)" > $C
tail -1 $A/e027a.chain | grep -q E027A_COMPLETE || { echo "part a not complete"; echo CHAIN_E027_COMPLETE; } >> $C
tail -1 $C | grep -q CHAIN_E027_COMPLETE && exit 1
sha256sum $B $F >> $C
for i in $(seq 1 60); do l=$(cut -d' ' -f1 /proc/loadavg); awk -v l=$l 'BEGIN{exit !(l<0.5)}' && break; sleep 30; done
echo "idle check $(date -Is): load $(cut -d' ' -f1-3 /proc/loadavg); users: $(who | awk '{print $1}' | sort | uniq -c | tr '\n' ' ')" >> $C
ps -eo user,pcpu,comm --sort=-pcpu | awk 'NR>1 && $2>5' | head -5 >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e027_heavy 3105441 1800 3 "base|$B|$X" "final|$F|$X"
echo "(b1) heavy done $(date -Is)" >> $C
$S/ab_window.sh $A/e027_prep 3106400 3600 1 "base_prep|$B|$X"
echo "(b2) prep done $(date -Is): $(tail -2 $A/e027_prep/summary.txt | head -1 | cut -c1-120)" >> $C
START_H=3106400 $S/ab_window.sh $A/e027_small 3107400 3600 3 "base|$B|$X" "final|$F|$X"
echo "(b3) small done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
mkdir -p $A/e027_neg/h3106400
$S/negdiff.sh $A/e027_neg/h3106400 $DD 3106400 400 "base|$B" "final|$F"
echo "(b4) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e027_neg/h3106400/summary.txt | tr '\n' ' ')" >> $C
for d in e027_heavy e027_small; do
  echo "== $d" >> $C
  python3 -I $S/ab_stats.py $A/$d/results.csv base 2>&1 | tail -6 >> $C
  for f in $A/$d/r*.mem.csv; do printf "%s max VmSwap kB %s\n" "$(basename $f .mem.csv)" "$(awk -F, 'NR>1 && ($9+0)>m {m=$9+0} END {print m+0}' $f)"; done >> $C
done
python3 -I $S/e023_wall.py $A/e027_heavy 3105406 3105441 base final >> $C 2>&1
python3 -I $S/e023_wall.py $A/e027_small 3106405 3107400 base final >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E027_COMPLETE >> $C
