#!/bin/bash
# E037, hydrogen: what bounding spans by weight does to memory, and why. Waits for E036's lying-peer cases. Report only. Why: in E036 part b, fw (final without the E001 cap, with another developer's weight-bounded spans, patch sha 8b038b26) had peak anon -31.5%, post-idle -36.1%, wall -6.6%, writes -16.8% against final at default settings, with the level about 430 MB lower from the heavy window to the end of the run. The sampler shows final jumping from 373 to about 1,170 MB during its one 4-block span of 10 MB blocks (3,105,425-28), where fw takes those blocks singly. My hypothesis is that one span causes the lasting difference, and that is not established.
# This also matters for the headline. Base has never been measured at default settings, because it cannot pass the wedge, so every base figure uses --block-sync-size 5, which batches heavy blocks. The patch lets us measure a base that is fixed but otherwise unchanged.
#   Trees, built here: e033fw = E033 tree + patch. v2fw = v2final - 0003 (scripts/e036_no0003.patch) + patch. e036 and fw exist from E036.
#   Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds per set:
#   (B) final default, final --block-sync-size 1, fw default -> e037_b/. The mechanism check, no new code: final with single-block spans throughout.
#   (A) base --block-sync-size 5, e036 default -> e037_a/
#   (C) e033 --block-sync-size 5, e033fw default -> e037_c/
#   (D) v2final default, v2fw default -> e037_d/
#   Cgroup minimum, warm cache, heavy window, e036, fw, e033fw, v2fw at default settings -> e037_minmem/. Compared with E032's base 5,562 and v2final 1,765, E033's 3,000, E023's final 1,866, all at --block-sync-size 5 or, for final, E023's settings.
# Expected, fixed before the run. (B) fw vs final peak -25 to -35%, post-idle -30 to -50%. If the one-span hypothesis is right, final --block-sync-size 1 is within 10% of fw on peak and post-idle; if it is not, the hypothesis is wrong and I say so. (A) e036 vs base, no model, so wide: peak -40 to +5%, wall -15 to +10%. (C) e033fw vs e033 peak -5 to -40%. (D) v2fw vs v2final peak -15 to -35%, wall -5 to +5%. Cgroup minimums: e036 at or under 5,562 MB, fw under 1,866 MB, e033fw under 3,000 MB, v2fw under 1,765 MB. All hashes match. No oversize errors at any default-settings arm except that none is expected at all. A miss is reported as a miss.
# Mining on box81 relays through .22 throughout, as in E035 and E036. Marker: CHAIN_E037_COMPLETE in e037.chain
set -u
W0=/home/optimizer/work; R=$W0/research; A=$W0/research-artifacts; C=$A/e037.chain; S=$R/scripts
PATCH=$W0/e036_wedge.patch; PATCHSHA=8b038b26
B=$W0/monero-fcmp/build/beta31/bin/monerod; F=$W0/monero-fcmp-idle/build/beta31-idle/bin/monerod
E=$W0/monero-fcmp-e036/build/beta31-e036/bin/monerod; X=$W0/monero-fcmp-e036fw/build/beta31-e036fw/bin/monerod
E33=$W0/monero-fcmp-e033/build/beta31-e033/bin/monerod; V2=$W0/monero-fcmp-v2final/build/beta31-v2final/bin/monerod
T3=$W0/monero-fcmp-e033fw; E3=$T3/build/beta31-e033fw/bin/monerod
T4=$W0/monero-fcmp-v2fw; V4=$T4/build/beta31-v2fw/bin/monerod
SNAP=$A/snapshots/stressnet_wedge_h3105401
GIT="git -c user.name=optimizer -c user.email=optimizer@localhost"
echo "chain e037 waiting for E036 lying-peer cases $(date -Is)" > $C
until tail -1 $A/e036liar.chain 2>/dev/null | grep -q CHAIN_E036LIAR_COMPLETE; do sleep 60; done
echo "chain e037 start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" >> $C
sha256sum $PATCH | grep -q "^$PATCHSHA" || { echo PATCH_HASH_MISMATCH >> $C; echo CHAIN_E037_COMPLETE >> $C; exit 1; }
free_gb() { df --output=avail -BG /home | tail -1 | tr -dc 0-9; }
[ "$(free_gb)" -ge 23 ] || { echo "NOT_ENOUGH_DISK $(free_gb) GB" >> $C; echo CHAIN_E037_COMPLETE >> $C; exit 1; }
source ~/.cargo/env
export CCACHE_BASEDIR=$W0
rsync -a --exclude build $W0/monero-fcmp-e033/ $T3/
( cd $T3 && $GIT am $PATCH > $A/e037.am.log 2>&1 ) || { echo GIT_AM_FAILED_E033FW >> $C; echo CHAIN_E037_COMPLETE >> $C; exit 1; }
rsync -a --exclude build $W0/monero-fcmp-v2final/ $T4/
( cd $T4 && $GIT am $S/e036_no0003.patch $PATCH >> $A/e037.am.log 2>&1 ) || { echo GIT_AM_FAILED_V2FW >> $C; echo CHAIN_E037_COMPLETE >> $C; exit 1; }
echo "trees e033fw $(git -C $T3 rev-parse 'HEAD^{tree}') v2fw $(git -C $T4 rev-parse 'HEAD^{tree}')" >> $C
git -C $T3 diff --stat $(git -C $W0/monero-fcmp-e033 rev-parse HEAD) HEAD | tail -1 >> $C
git -C $T4 diff --stat $(git -C $W0/monero-fcmp-v2final rev-parse HEAD) HEAD | tail -1 >> $C
for pair in "$T3 beta31-e033fw" "$T4 beta31-v2fw"; do
  set -- $pair; mkdir -p $1/build/$2; cd $1/build/$2 || exit 1
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e037.$2.build.log 2>&1
  r=$(tail -1 $A/e037.$2.build.log); echo "build $2 $r $(date -Is)" >> $C
  [ "$r" = BUILD_OK ] || { echo CHAIN_E037_COMPLETE >> $C; exit 1; }
done
cd $A
sha256sum $B $F $E $X $E33 $E3 $V2 $V4 >> $C
df -h /home | tail -1 >> $C
[ "$(free_gb)" -ge 21 ] || { echo "NOT_ENOUGH_DISK $(free_gb) GB after builds" >> $C; echo CHAIN_E037_COMPLETE >> $C; exit 1; }
sleep 60
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
( while kill -0 $$ 2>/dev/null; do ps -eo comm | grep -qx shadow && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
export REWIND_SNAPSHOT=$SNAP
$S/ab_window.sh $A/e037_b 3105441 900 3 "final|$F|" "finalbss1|$F|--block-sync-size 1" "fw|$X|"
echo "(B) done $(date -Is)" >> $C
$S/ab_window.sh $A/e037_a 3105441 900 3 "base|$B|--block-sync-size 5" "e036|$E|"
echo "(A) done $(date -Is)" >> $C
$S/ab_window.sh $A/e037_c 3105441 900 3 "e033|$E33|--block-sync-size 5" "e033fw|$E3|"
echo "(C) done $(date -Is)" >> $C
$S/ab_window.sh $A/e037_d 3105441 900 3 "v2final|$V2|" "v2fw|$V4|"
echo "(D) done $(date -Is)" >> $C
ref() { python3 -I -c "import csv,statistics; print(int(statistics.median(float(r['wall_s']) for r in csv.DictReader(open('$1')) if r['arm']=='$2')))"; }
$S/min_mem.sh $A/e037_minmem e036 $E $(ref $A/e037_a/results.csv e036) 1500 7000 125; echo "minmem e036: $(tail -2 $A/e037_minmem/e036.summary | head -1)" >> $C
$S/min_mem.sh $A/e037_minmem fw $X $(ref $A/e037_b/results.csv fw) 750 3000 125; echo "minmem fw: $(tail -2 $A/e037_minmem/fw.summary | head -1)" >> $C
$S/min_mem.sh $A/e037_minmem e033fw $E3 $(ref $A/e037_c/results.csv e033fw) 750 4000 125; echo "minmem e033fw: $(tail -2 $A/e037_minmem/e033fw.summary | head -1)" >> $C
$S/min_mem.sh $A/e037_minmem v2fw $V4 $(ref $A/e037_d/results.csv v2fw) 500 3000 125; echo "minmem v2fw: $(tail -2 $A/e037_minmem/v2fw.summary | head -1)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 -I $S/ab_stats.py $A/e037_b/results.csv final >> $C 2>&1
python3 -I $S/ab_stats.py $A/e037_a/results.csv base >> $C 2>&1
python3 -I $S/ab_stats.py $A/e037_c/results.csv e033 >> $C 2>&1
python3 -I $S/ab_stats.py $A/e037_d/results.csv v2final >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E037_COMPLETE >> $C
