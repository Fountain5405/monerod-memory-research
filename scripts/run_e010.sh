#!/bin/bash
# E010: long resync 3,105,401 -> END=3,123,400 (18k blocks, 190k txs, 1.9 GB of block weight), one run per arm:
#   combo with DEFAULT sync settings (exercises the E001 fix), base with --block-sync-size 5 (its defaults wedge, E001),
#   and combo with --block-sync-size 5 (same settings as base).
# Each run restores the working DB from the wedge snapshot (REWIND_SNAPSHOT, ab_window.sh v3) instead of popping 18k blocks.
# Governor pinned for the chain. Marker: last line of e010.chain is CHAIN_E010_COMPLETE.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e010.chain
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
X=/home/optimizer/work/monero-fcmp-combo/build/beta31-combo/bin/monerod
echo "chain e010 start $(date -Is)" > $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$A/snapshots/stressnet_wedge_h3105401 ~/work/research/scripts/ab_window.sh $A/e010 3123400 14400 1 \
  "combo_default|$X|" "base_bss5|$B|--block-sync-size 5" "combo_bss5|$X|--block-sync-size 5"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E010_COMPLETE >> $C
