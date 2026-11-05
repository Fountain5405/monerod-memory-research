#!/bin/bash
# E035 part a, box81 (hostname moonpie): the window-aware cap against the real weight-limit code. No timing, no .22.
#  (a1) tree monero-fcmp-e035 = monero-fcmp-final + the cap + a unit test; unit_tests built with stressnet's constants (F 10 MB at v17)
#  (a2) tree monero-fcmp-e035-625k = the same with F 625 kB at v17, the value in fcmp++-stage f25388d the issue uses. Test-only: this tree is never run on a network.
#  (a3) coarse grid, then the simulation's full grid (k step 1, A step F/200) on both
# Expected, fixed before the run: the "values" test passes; the real code reproduces the simulation's table (scripts/e001_batch_weight_sim.out.txt) to within 0.5 MB for the none, patch and window columns at HF 16 and at v17 with F 625 kB; the window cap's worst batch is at or under 90.5 MB in every cell, including F 10 MB. A miss is reported as a miss.
# Marker: E035A_COMPLETE in e035a.chain
set -u
W=/home/optimizer/work; A=$W/research-artifacts; C=$A/e035a.chain; I=$W/e035_in
T=$W/monero-fcmp-e035; T2=$W/monero-fcmp-e035-625k
source ~/.cargo/env
export CCACHE_BASEDIR=$W
echo "chain e035a start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
rsync -a --exclude build $W/monero-fcmp-final/ $T/
cd $T || exit 1
python3 -I $I/patch.py >> $C 2>&1 || { echo PATCH_FAILED >> $C; echo E035A_COMPLETE >> $C; exit 1; }
cp $I/block_sync_size_cap.cpp tests/unit_tests/
git add -A src tests
git -c user.name=optimizer -c user.email=optimizer@localhost commit -qm "E035: window-aware block sync size cap

The E001 cap bounded a batch by the current block weight limit alone. The limit can rise inside a batch, and the window can already hold blocks above the floor. Budget for max(limit, 2 * largest recent block) over the next 50 blocks and twice that after them (owner's analysis, 72a62f5). Adds a unit test driving Blockchain's real limit code."
git log --oneline -1 >> $C; git diff --numstat HEAD~1 HEAD >> $C; echo "tree $(git rev-parse HEAD^{tree})" >> $C
rsync -a --exclude build $T/ $T2/
grep -c "ZONE_V17   10000000" $T2/src/cryptonote_config.h >> $C
sed -i 's/ZONE_V17   10000000/ZONE_V17   625000/' $T2/src/cryptonote_config.h
grep -n "ZONE_V17 " $T2/src/cryptonote_config.h | cut -c1-90 >> $C
bt() {  # <tree> <label>
  mkdir -p $1/build/ut; cd $1/build/ut || return 1
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=ON -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && nice -n 10 ninja -j6 unit_tests && echo BUILD_OK || echo BUILD_FAILED; } > $A/e035_build_$2.log 2>&1
  echo "build $2 $(tail -1 $A/e035_build_$2.log) $(date -Is)" >> $C
  [ "$(tail -1 $A/e035_build_$2.log)" = BUILD_OK ]
}
run() {  # <tree> <label> <k step> <a div>
  ( cd $1/build/ut/tests/unit_tests && E035_K_STEP=$3 E035_A_DIV=$4 nice -n 10 ./unit_tests --gtest_filter='block_sync_size_cap.*' ) > $A/e035_ut_$2_$3_$4.txt 2>&1
  echo "run $2 k=$3 a=$4 exit $? $(date -Is)" >> $C
  grep -E "^\[  (PASSED|FAILED)" $A/e035_ut_$2_$3_$4.txt | cut -c1-80 >> $C
}
bt $T f10m || { echo E035A_COMPLETE >> $C; exit 1; }
run $T f10m 10 20
bt $T2 f625k || { echo E035A_COMPLETE >> $C; exit 1; }
run $T2 f625k 10 20
run $T f10m 1 200
run $T2 f625k 1 200
echo "done $(date -Is)" >> $C
echo E035A_COMPLETE >> $C
