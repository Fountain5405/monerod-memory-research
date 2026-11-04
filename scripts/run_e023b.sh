#!/bin/bash
# E023b: attribute E023's small-tx wall miss (+6.6% against base, expected no more than +6%). E013 measured adapt at +4.0% on this window. Is the extra from the last two patches?
# adapt (E012, sha d6f93d06) vs final (adapt + E021 + E022, sha d779a522), small-tx window, 5 alternating rounds, wall from scripts/e023_wall.py over 3,106,405 -> 3,107,400.
# Reading, fixed before the run. Ranges overlapping and medians within 1.5%: the last two patches are not responsible, and the gap is adapt's own cost on this window.
# Ranges not overlapping with final slower by more than 1.5%: they do cost wall, and since E022 changes no block on this window, E021 is the suspect.
# Anything else: inconclusive, reported as such. E023's +6.6% stands as measured in every case.
# Marker: CHAIN_E023B_COMPLETE in e023b.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e023b.chain; S=/home/optimizer/work/research/scripts
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
echo "chain e023b start $(date -Is)" > $C
sha256sum $D $F >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa '[s]hadow' | grep -v 'bash -c' > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
START_H=3106400 REWIND_SNAPSHOT=$A/snapshots/stressnet_h3106400 $S/ab_window.sh $A/e023b_small 3107400 900 5 "adapt|$D|--block-sync-size 5" "final|$F|--block-sync-size 5"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 $S/ab_stats.py $A/e023b_small/results.csv adapt >> $C 2>&1
python3 $S/e023_wall.py $A/e023b_small 3106405 3107400 adapt final >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E023B_COMPLETE >> $C
