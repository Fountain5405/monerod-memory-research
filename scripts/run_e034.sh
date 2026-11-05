#!/bin/bash
# E034: the cgroup minimum with a cold page cache. E031 found that the cgroup peak tracks anon, not RSS: the DB is read outside the scope (snapshot cp, pop_to), so its pages are likely charged elsewhere, and earlier minimums (E009, E013, E018, E023, E031) are close to an anon requirement on a warm cache. Here the DB is evicted from the page cache (posix_fadvise on data.mdb only, not system-wide) after each rewind, so what the node reads is charged to it. One change against the existing method: COLD=1 in min_mem.sh. Hydrogen, heavy window, final and base. Report only.
# (a) Reference: for each arm, min_mem with a limit of 8,000 and 7,999 MB, passing on any wall under 30 min: two cold walls and the cold cgroup peak. Reference wall = their mean.
# (b) Bisect: final lo 750 hi 4000 step 125; base lo 2000 hi 8000 step 250. Pass = window end within 1.10 x the cold reference on .22's hash.
# Expected, fixed before the run: at the 8,000 MB limit, the cgroup peak is well above the warm figure (final at least 2,500 MB against 1,647 warm). If it is not, the inference in E031 is wrong, and that is reported. Cold minimums are at or above the warm ones: final 1,866-3,000 MB, base 5,750-7,500 MB, reduction at least -50%. Failures may be slowdowns rather than OOM kills. Each limit runs once. A miss is reported as a miss.
# Marker: CHAIN_E034_COMPLETE in e034.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e034.chain; S=/home/optimizer/work/research/scripts; O=$A/e034_minmem
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; DD=/home/optimizer/work/chains/stressnet
X="--block-sync-size 5"
echo "chain e034 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
sha256sum $B $F $S/min_mem.sh >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
rm -f $DD/testnet/lmdb/lock.mdb; cp $W/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb; echo "DB restored $(date -Is)" >> $C
export COLD=1
meanwall() { python3 -I -c "import csv; v=[float(r['wall_s']) for r in csv.DictReader(open('$O/$1.csv')) if r['result']=='PASS']; print(int(sum(v)/len(v)))"; }
for arm in final base; do
  [ $arm = final ] && BIN=$F || BIN=$B
  $S/min_mem.sh $O ref_$arm $BIN 1800 7999 8000 1000 $X
  echo "(a) ref_$arm done $(date -Is): $(tail -n +2 $O/ref_$arm.csv | tr '\n' ' ')" >> $C
done
RF=$(meanwall ref_final); RB=$(meanwall ref_base); echo "cold reference walls final $RF s, base $RB s" >> $C
$S/min_mem.sh $O final $F $RF 750 4000 125 $X
echo "(b) final done $(date -Is): $(tail -2 $O/final.summary | head -1)" >> $C
$S/min_mem.sh $O base $B $RB 2000 8000 250 $X
echo "(b) base done $(date -Is): $(tail -2 $O/base.summary | head -1)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
echo "done $(date -Is)" >> $C
echo CHAIN_E034_COMPLETE >> $C
