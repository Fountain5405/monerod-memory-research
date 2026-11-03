#!/bin/bash
# After E013: E015 differential negative test (safety), then E014 thread-count sweep (does the win hold on small machines?).
# E015: negdiff.sh at H=3,105,401 (wedge snapshot; heavy txs, scan 40 blocks) and H=3,106,400 (snapshot h3106400;
#       small/mid txs, scan 400 blocks), oracle = base, candidate = adapt.
# E014: heavy window 3,105,401 -> 3,105,441, base vs adapt at --max-concurrency 4, 2, 1; 3 alternating rounds,
#       governor pinned, TO 1800 s. (Emulation caveat: the adapt cap uses the physical core count 12, so with a pool of
#       <= 4 the cap is inert; on a real 4-thread/2-core box it would cap at 2.)
# Markers: E015 -> each negdiff summary ends NEGDIFF_COMPLETE; chain log e015_e014.chain ends CHAIN_E015_E014_COMPLETE.
set -u
A=/home/optimizer/work/research-artifacts
C=$A/e015_e014.chain
S=~/work/research/scripts
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
echo "chain e015_e014 start $(date -Is)" > $C
until tail -1 $A/e013.chain 2>/dev/null | grep -q CHAIN_E013_COMPLETE; do sleep 30; done
echo "e013 complete; starting $(date -Is)" >> $C
$S/negdiff.sh $A/e015/h3105401 $W 3105401 40 "base|$B" "adapt|$D"
echo "E015 h3105401: $(grep -E 'DIFF (PASS|FAIL)' $A/e015/h3105401/summary.txt)" >> $C
$S/negdiff.sh $A/e015/h3106400 $A/snapshots/stressnet_h3106400 3106400 400 "base|$B" "adapt|$D"
echo "E015 h3106400: $(grep -E 'DIFF (PASS|FAIL)' $A/e015/h3106400/summary.txt)" >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e014 3105441 1800 3 \
  "base_c4|$B|--block-sync-size 5 --max-concurrency 4" "adapt_c4|$D|--block-sync-size 5 --max-concurrency 4" \
  "base_c2|$B|--block-sync-size 5 --max-concurrency 2" "adapt_c2|$D|--block-sync-size 5 --max-concurrency 2" \
  "base_c1|$B|--block-sync-size 5 --max-concurrency 1" "adapt_c1|$D|--block-sync-size 5 --max-concurrency 1"
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "E014 done $(date -Is)" >> $C
echo CHAIN_E015_E014_COMPLETE >> $C
