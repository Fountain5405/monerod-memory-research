#!/bin/bash
# E004e A/B: base vs e004e (E004c batch cap + malloc_trim after each FCMP++ batch verify).
# Governor pinned to performance for the run (CLAUDE.md hygiene), restored afterwards.
set -u
OUT=/home/optimizer/work/research-artifacts/e004e
C=/home/optimizer/work/research-artifacts/e004e.chain
mkdir -p $OUT
echo "chain e004e start $(date -Is)" > $C
sha256sum /home/optimizer/work/monero-fcmp-e004e/build/beta31-e004e/bin/monerod >> $C
git -C /home/optimizer/work/monero-fcmp-e004e log --oneline -3 >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
/home/optimizer/work/research/scripts/ab_window.sh $OUT 3105441 900 3 \
  "base|/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod|--block-sync-size 5" \
  "e004e|/home/optimizer/work/monero-fcmp-e004e/build/beta31-e004e/bin/monerod|--block-sync-size 5"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "A/B done $(date -Is)" >> $C
echo CHAIN_E004E_COMPLETE >> $C
