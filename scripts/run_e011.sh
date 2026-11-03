#!/bin/bash
# E011: attribute the combo build's slowdown on the small-tx stretch (seen in E010: +15-19% s/1000 blocks
# after the window). One change per arm vs base, all with --block-sync-size 5 (explicit bss bypasses the E001 cap),
# window 3,106,400 -> 3,107,400 (1,000 small-tx blocks), 3 alternating rounds, governor pinned.
#   base   = beta.3.1
#   e004c  = batch cap at physical cores
#   e004e  = e004c + malloc_trim per block   (e004e - e004c = trim cost)
#   e007   = streaming verifier alone        (e007 - base = double-build cost)
#   combo  = e004c + e004e + E001 fix + e007
# Prep: restore the wedge snapshot, sync to >= 3,106,400 with the base build, pop to exactly 3,106,400
# (pop_to.sh verifies the hash vs .22), copy the DB to snapshots/stressnet_h3106400 (a deletable working snapshot,
# NOT a baseline). Marker: last line of e011.chain is CHAIN_E011_COMPLETE.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e011.chain
S=~/work/research/scripts
DD=/home/optimizer/work/chains/stressnet
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
X=/home/optimizer/work/monero-fcmp-combo/build/beta31-combo/bin/monerod
E4C=/home/optimizer/work/monero-fcmp-e004c/build/beta31-e004c/bin/monerod
E4E=/home/optimizer/work/monero-fcmp-e004e/build/beta31-e004e/bin/monerod
E7=/home/optimizer/work/monero-fcmp-e007/build/beta31-e007/bin/monerod
SNAP=$A/snapshots/stressnet_h3106400
echo "chain e011 start $(date -Is)" > $C
until tail -1 $A/e010.chain 2>/dev/null | grep -q CHAIN_E010_COMPLETE; do sleep 30; done
echo "e010 complete; starting $(date -Is)" >> $C
mkdir -p $A/e011/prep
grep -q START_H $S/ab_window.sh || (cd ~/work/research && python3 -I scripts/patch_ab_v4.py >> $C 2>&1)
grep -q START_H $S/ab_window.sh || { echo "v4 patch FAILED"; echo CHAIN_E011_COMPLETE; } >> $C
grep -q START_H $S/ab_window.sh || exit 1
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
if [ ! -f $SNAP/testnet/lmdb/data.mdb ]; then
  REWIND_SNAPSHOT=$A/snapshots/stressnet_wedge_h3105401 $S/ab_window.sh $A/e011/prep 3106400 3600 1 "prep_base|$B|--block-sync-size 5"
  $S/pop_to.sh $B $DD 3106400 $A/e011/prep/pop_3106400.log
  tail -1 $A/e011/prep/pop_3106400.log >> $C
  tail -1 $A/e011/prep/pop_3106400.log | grep -q "RESULT OK" || { echo "prep pop FAILED"; echo CHAIN_E011_COMPLETE; } >> $C
  tail -1 $A/e011/prep/pop_3106400.log | grep -q "RESULT OK" || exit 1
  mkdir -p $SNAP/testnet/lmdb && rm -f $DD/testnet/lmdb/lock.mdb && cp $DD/testnet/lmdb/data.mdb $SNAP/testnet/lmdb/data.mdb
  echo "snapshot $SNAP made $(date -Is); df: $(df -h ~ | tail -1)" >> $C
fi
python3 -I $S/window_inputs.py 3106400 3107400 > $A/e011/window_inputs_3106400-3107399.txt 2>&1
tail -1 $A/e011/window_inputs_3106400-3107399.txt >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
START_H=3106400 REWIND_SNAPSHOT=$SNAP $S/ab_window.sh $A/e011 3107400 3600 3 \
  "base|$B|--block-sync-size 5" "e004c|$E4C|--block-sync-size 5" "e004e|$E4E|--block-sync-size 5" \
  "e007|$E7|--block-sync-size 5" "combo|$X|--block-sync-size 5"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E011_COMPLETE >> $C
