#!/bin/bash
# E024: where does e020 (v2 alternative) spend its +28% wall over v1 on the heavy window? Flat perf profile (scripts/profile_window.sh, -F 199, no call graphs), 2 rounds alternating,
# e020 (sha checked below) and final. Profile only: wall under perf is not a timing result. e020's tree lacks v2's patches 0007/0008 (idle trim and threshold), neither of which is in the verifier's hot path on this window.
# Marker: CHAIN_E024_COMPLETE in e024.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e024.chain; S=/home/optimizer/work/research/scripts
E=/home/optimizer/work/monero-fcmp-e020/build/beta31-e020/bin/monerod
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
echo "chain e024 start $(date -Is)" > $C
sha256sum $E $F >> $C
pgrep -fa '[s]hadow' | grep -v 'bash -c' >> $C || echo "no shadow processes" >> $C
for r in "r1_e020|$E" "r1_final|$F" "r2_final|$F" "r2_e020|$E"; do
  IFS='|' read -r L BIN <<< "$r"
  $S/profile_window.sh $A/e024/$L $BIN $C "."
  echo "$L done $(date -Is): $(grep "window done" $A/e024/$L/summary.txt | tail -1 | cut -c1-120)" >> $C
done
echo CHAIN_E024_COMPLETE >> $C
