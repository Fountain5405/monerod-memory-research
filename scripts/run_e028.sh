#!/bin/bash
# E028: where the small-tx wall cost lies. It is the recommended build's main cost (+6.6% vs base in E023, +5.5% on box81 in E027), E023b showed it is adapt's own, and E026 showed light-call trims are at most about 1.4% of wall.
# Arms, each one step from the last, small-tx window, 5 alternating rounds, wall from scripts/e023_wall.py over 3,106,405 -> 3,107,400:
#   base (v0.19.0.0-beta.3.1), e007 (base + streaming verifier, the E011 binary), inever (final with no light-call trim, the E026 binary), final (sha d779a522)
# Steps read from medians: e007 - base = the verifier; inever - e007 = the rest of adapt except light-call trims; final - inever = light-call trims. A step counts as a contribution only if the two arms' ranges do not overlap.
# Expected, fixed before the run: e007 about +3% over base (E011 +2.7%); inever within 1% of e007, from reading the code (light calls keep the full thread pool, and only about 4 blocks in this window are heavy); final about +1.4% over inever (E026); final about +6.6% over base (E023).
# These do not add up: +2.7% and +1.4% give about +4%, not +6.6%, so at least one must miss. Finding which is the point. Report only: no change to the recommended build follows from this run. A miss is reported as a miss.
# Marker: CHAIN_E028_COMPLETE in e028.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e028.chain; S=/home/optimizer/work/research/scripts
BASE=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
E7=/home/optimizer/work/monero-fcmp-e007/build/beta31-e007/bin/monerod
IN=$A/e026_bins/monerod-inever
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
X="--block-sync-size 5"
echo "chain e028 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
sha256sum $BASE $E7 $IN $F >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e028_small 3107400 900 5 "base|$BASE|$X" "e007|$E7|$X" "inever|$IN|$X" "final|$F|$X"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e028_small/results.csv base >> $C 2>&1
python3 $S/e023_wall.py $A/e028_small 3106405 3107400 base e007 >> $C 2>&1
python3 $S/e023_wall.py $A/e028_small 3106405 3107400 e007 inever | tail -2 >> $C 2>&1
python3 $S/e023_wall.py $A/e028_small 3106405 3107400 inever final | tail -2 >> $C 2>&1
python3 $S/e023_wall.py $A/e028_small 3106405 3107400 base final | tail -2 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E028_COMPLETE >> $C
