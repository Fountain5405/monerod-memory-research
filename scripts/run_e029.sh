#!/bin/bash
# E029: give the wall back on small proofs. E028 put +3.8% of the +5.5% small-tx wall cost, and all of its +8% CPU, on the streaming verifier's second circuit build. Small proofs have small circuits, so that build may buy little memory there.
# Change (scripts/e029_patch.py): Fcmp::verify sends proofs with fewer than 8 inputs to the existing verify_stored, which the code documents as doing the same transcript operations and randomness; 8 and up keep streaming. 8 matches HEAVY_PROOF_MIN_INPUTS and no other value is tried. Everything else is final.
#   (a) trees monero-oxide-e029 (copy of e007 + patch) and monero-fcmp-e029 (copy of idle, cargo [patch] repointed); crate tests for fcmps; build
#   (b) negdiff at 3,105,401 and 3,106,400 with the case files of E015/E025, arms base (oracle), final, e029 -> e029_neg/
#   (c) small-tx window A/B final vs e029, 5 rounds -> e029_small/
#   (d) heavy window A/B final vs e029, 3 rounds -> e029_heavy/
# Expected, fixed before the run: crate tests pass, DIFF PASS at both heights, all hashes match; small-tx wall 2-4% below final, CPU about -7%, peak anon 5-15% above final; heavy window unchanged within run-to-run spread, since its proofs have 128 inputs.
# Adoption rule, fixed before the run. Adopt as a new patch only if small-tx wall is at least 2% below final with non-overlapping ranges, small-tx peak anon is not worse by more than 5%, heavy peak anon is not worse by more than 5%, all hashes match, DIFF PASS at both heights, crate tests pass. The project's goal is memory, so a larger peak is not traded for speed here: otherwise the result is reported as an option for the owner and final stays. A miss is reported as a miss.
# Marker: CHAIN_E029_COMPLETE in e029.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e029.chain; S=/home/optimizer/work/research/scripts
O=/home/optimizer/work/monero-oxide-e029; T=/home/optimizer/work/monero-fcmp-e029; BD=$T/build/beta31-e029
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
F=/home/optimizer/work/monero-fcmp-idle/build/beta31-idle/bin/monerod
V=$BD/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401; H=$A/snapshots/stressnet_h3106400
X="--block-sync-size 5"
source ~/.cargo/env
fail() { echo "$1"; echo CHAIN_E029_COMPLETE; } >> $C
echo "chain e029 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
rsync -a --exclude target /home/optimizer/work/monero-oxide-e007/ $O/
( cd $O && git checkout -q -b e029-small-stored && python3 $S/e029_patch.py && git -c user.name=optimizer -c user.email=optimizer@localhost commit -q -am "E029: verify proofs with fewer than 8 inputs on the stored-circuit path" ) >> $C 2>&1 || { fail PATCH_FAILED; exit 1; }
git -C $O log --oneline -1 >> $C
( cd $O && nice -n 10 cargo test --release -j 10 -p full-chain-membership-proofs ) > $A/e029.test.log 2>&1; rc=$?
echo "crate tests rc=$rc $(date -Is): $(grep -E '^test result' $A/e029.test.log | tr '\n' ' ' | cut -c1-220)" >> $C
[ $rc = 0 ] || { fail CRATE_TESTS_FAILED; exit 1; }
rm -rf $O/target
rsync -a --exclude build /home/optimizer/work/monero-fcmp-idle/ $T/
sed -i 's#/home/optimizer/work/monero-oxide-e007/#/home/optimizer/work/monero-oxide-e029/#' $T/src/fcmp_pp/fcmp_pp_rust/Cargo.toml
git -C $T diff --stat | tail -1 >> $C
mkdir -p $BD; cd $BD || exit 1
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e029.build.log 2>&1
r=$(tail -1 $A/e029.build.log); echo "build $r $(date -Is)" >> $C
[ "$r" = BUILD_OK ] || { fail BUILD_FAILED; exit 1; }
cd /home/optimizer/work
sha256sum $B $F $V >> $C
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
for h in h3105401 h3106400; do mkdir -p $A/e029_neg/$h; cp $A/e025_neg/$h/cases.json $A/e029_neg/$h/cases.json; done
$S/negdiff.sh $A/e029_neg/h3105401 $W 3105401 40 "base|$B" "final|$F" "e029|$V"
$S/negdiff.sh $A/e029_neg/h3106400 $H 3106400 400 "base|$B" "final|$F" "e029|$V"
echo "(b) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e029_neg/h3105401/summary.txt | tr '\n' ' ') / $(grep -E 'DIFF (PASS|FAIL)' $A/e029_neg/h3106400/summary.txt | tr '\n' ' ')" >> $C
START_H=3106400 REWIND_SNAPSHOT=$H $S/ab_window.sh $A/e029_small 3107400 900 5 "final|$F|$X" "e029|$V|$X"
echo "(c) small done $(date -Is)" >> $C
REWIND_SNAPSHOT=$W $S/ab_window.sh $A/e029_heavy 3105441 900 3 "final|$F|$X" "e029|$V|$X"
echo "(d) heavy done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
for d in e029_small e029_heavy; do python3 $S/ab_stats.py $A/$d/results.csv final >> $C 2>&1; done
python3 $S/e023_wall.py $A/e029_small 3106405 3107400 final e029 >> $C 2>&1
python3 $S/e023_wall.py $A/e029_heavy 3105406 3105441 final e029 >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E029_COMPLETE >> $C
