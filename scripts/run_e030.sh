#!/bin/bash
# E030: e029 against base directly on the small-tx window. E029 compared e029 only with final; its comparison with base is across chains (E028's base 146.4 s, 1,337 s CPU, 1,073 MB against e029's 146.2 s, 1,323 s, 866 MB). The owner has decided to keep final and report e029 as an option, and this is the option's main claim, so measure it. Report only: nothing about the recommended build follows from this run.
# Arms: base, e029. Small-tx window, 5 alternating rounds, wall from scripts/e023_wall.py over 3,106,405 -> 3,107,400.
# Expected, fixed before the run: e029 wall within 1.5% of base; CPU within 2% of base; peak anon below base with separate ranges, about -15 to -25%, base's peak being the soft figure it always is; post-idle anon about -25 to -30%; all hashes match. A miss is reported as a miss.
# Marker: CHAIN_E030_COMPLETE in e030.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e030.chain; S=/home/optimizer/work/research/scripts
BASE=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
E=/home/optimizer/work/monero-fcmp-e029/build/beta31-e029/bin/monerod
X="--block-sync-size 5"
echo "chain e030 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
sha256sum $BASE $E >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e030_small 3107400 900 5 "base|$BASE|$X" "e029|$E|$X"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e030_small/results.csv base >> $C 2>&1
python3 $S/e023_wall.py $A/e030_small 3106405 3107400 base e029 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E030_COMPLETE >> $C
