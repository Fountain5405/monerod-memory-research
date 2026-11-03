#!/bin/bash
# Generic chain: wait for a marker, build a monero tree (daemon only), then A/B base vs the new build.
# usage: chain_build_ab.sh <label> <tree dir> <wait file> <wait marker> [rounds=3] [extra args for both arms]
# Writes ~/work/research-artifacts/<label>.chain; last line CHAIN_<LABEL>_COMPLETE. A/B data goes to
# ~/work/research-artifacts/<label>/ (ab_window.sh).
# v2 (2026-11-03): CPU governor pinned to performance for the A/B only (CLAUDE.md hygiene), then restored.
set -u
L=$1; T=$2; WF=$3; WM=$4; ROUNDS=${5:-3}; EXTRA=${6:---block-sync-size 5}
C=~/work/research-artifacts/$L.chain
UL=$(echo $L | tr a-z A-Z)
echo "chain $L start $(date -Is) tree=$T wait=$WF:$WM rounds=$ROUNDS extra='$EXTRA'" > $C
until tail -1 $WF 2>/dev/null | grep -q "$WM"; do sleep 30; done
echo "wait satisfied $(date -Is)" >> $C
source ~/.cargo/env
mkdir -p $T/build/beta31-$L && cd $T/build/beta31-$L
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > ~/work/research-artifacts/$L.build.log 2>&1
tail -1 ~/work/research-artifacts/$L.build.log >> $C
if tail -1 ~/work/research-artifacts/$L.build.log | grep -q BUILD_OK; then
  B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
  E=$T/build/beta31-$L/bin/monerod
  sha256sum $E >> $C
  git -C $T log --oneline -3 >> $C
  OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
  sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
  ~/work/research/scripts/ab_window.sh ~/work/research-artifacts/$L 3105441 900 $ROUNDS "base|$B|$EXTRA" "$L|$E|$EXTRA"
  sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
  echo "A/B done $(date -Is)" >> $C
fi
echo CHAIN_${UL}_COMPLETE >> $C
