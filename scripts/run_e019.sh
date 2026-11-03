#!/bin/bash
# E019: independent reproduction on box81 (Ryzen 5 5600G 6c/12t Zen3, 14 GB, 4 GB swap file that stays on).
# NOT timing-comparable with hydrogen; everything here is box81 vs box81. Arms: base (v0.19.0.0-beta.3.1),
# adapt (recommended build), e017 (adapt + folded verifier), all built natively here (marker e019.builds).
# DB: hydrogen's wedge snapshot at 3,105,401, unpruned, streamed here during E018's build phase (marker e019.db).
# Heavy runs restore it from the local snapshot copy as on hydrogen; the small-tx runs rewind in place with
# pop_blocks (one DB copy less). Default thread count (12 here).
#   (a) heavy window 3,105,401 -> 3,105,441: base/adapt/e017, 3 alternating rounds, TO 1800   -> e019_heavy/
#   (b) prep, untimed: base syncs once to 3,106,400                                             -> e019_prep/
#   (c) small-tx window 3,106,400 -> 3,107,400: base/adapt/e017, 3 rounds, TO 3600 (START_H)  -> e019_small/
# Idle check first (shared box), governor pinned for (a) and (c) and restored after. Marker: e019.chain ends
# CHAIN_E019_COMPLETE. Guardrails as on hydrogen: hash match vs .22 per run, VmSwap max per run reported.
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e019.chain; S=/home/optimizer/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
E=/home/optimizer/work/monero-fcmp-e017/build/beta31-e017/bin/monerod
X="--block-sync-size 5"
echo "chain e019 start $(date -Is)" > $C
until tail -1 $A/e019.builds 2>/dev/null | grep -q BUILDS_OK && [ -f $A/e019.db ]; do sleep 60; done
echo "builds and DB present $(date -Is)" >> $C
cat $A/e019.db >> $C
for b in $B $D $E; do sha256sum $b | cut -c1-16 >> $C; done
# idle check: wait up to 30 min for 1-min load < 0.5 (other users share this box), then proceed and record.
for i in $(seq 1 60); do l=$(cut -d' ' -f1 /proc/loadavg); awk -v l=$l 'BEGIN{exit !(l<0.5)}' && break; sleep 30; done
echo "idle check $(date -Is): load $(cut -d' ' -f1-3 /proc/loadavg); users: $(who | awk '{print $1}' | sort | uniq -c | tr '\n' ' ')" >> $C
ps -eo user,pcpu,comm --sort=-pcpu | awk 'NR>1 && $2>5' | head -5 >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$A/snapshots/stressnet_wedge_h3105401 $S/ab_window.sh $A/e019_heavy 3105441 1800 3 "base|$B|$X" "adapt|$D|$X" "e017|$E|$X"
echo "(a) heavy A/B done $(date -Is)" >> $C
$S/ab_window.sh $A/e019_prep 3106400 3600 1 "base_prep|$B|$X"
echo "(b) prep sync to 3,106,400 done $(date -Is): $(tail -2 $A/e019_prep/summary.txt | head -1 | cut -c1-120)" >> $C
START_H=3106400 $S/ab_window.sh $A/e019_small 3107400 3600 3 "base|$B|$X" "adapt|$D|$X" "e017|$E|$X"
echo "(c) small-tx A/B done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
for d in e019_heavy e019_small; do
  echo "== $d" >> $C
  python3 -I $S/ab_stats.py $A/$d/results.csv base 2>&1 | tail -6 >> $C
  for f in $A/$d/r*.mem.csv; do printf "%s max VmSwap kB %s\n" "$(basename $f .mem.csv)" "$(awk -F, 'NR>1 && ($9+0)>m {m=$9+0} END {print m+0}' $f)"; done >> $C
done
df -h /home | tail -1 >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E019_COMPLETE >> $C
