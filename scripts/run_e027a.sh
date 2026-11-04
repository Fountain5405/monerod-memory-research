#!/bin/bash
# E027 part a, box81 (hostname moonpie): build the final v1 series natively and run the differential test at the heavy height.
# Why: E019 reproduced adapt on this second machine, but E021 and E022 came later, and every final-series figure is from hydrogen.
# Part a does not sync from .22: E026 is timing on hydrogen against the same peer until about 13:15. Part b (run_e027b.sh) runs after E026.
#   (a1) tree monero-fcmp-final = copy of monero-fcmp-adapt + git am of v1's published patches 0006 and 0007. Its tree hash must equal hydrogen's adbe70cf8 (fcbc96d34eee).
#   (a2) nice -n 10, ninja -j6, Release, ARCH=native, daemon only, as in E019
#   (a3) negdiff at 3,105,401 with hydrogen's case file (no .22 reads), arms base (oracle), final -> e027_neg/h3105401
# Expected, fixed before the run: tree hash matches, BUILD_OK, DIFF PASS on 135 cases. A miss is reported as a miss.
# Marker: E027A_COMPLETE in e027a.chain
set -u
A=/home/optimizer/work/research-artifacts; C=$A/e027a.chain; S=/home/optimizer/work/research/scripts; R=/home/optimizer/work/research
T=/home/optimizer/work/monero-fcmp-final; BD=$T/build/beta31-final
B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod; F=$BD/bin/monerod
W=$A/snapshots/stressnet_wedge_h3105401
source ~/.cargo/env
export CCACHE_BASEDIR=/home/optimizer/work
echo "chain e027a start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $C
rsync -a --exclude build /home/optimizer/work/monero-fcmp-adapt/ $T/
(
  cd $T || exit 1
  git -c user.name=optimizer -c user.email=optimizer@localhost am $R/patches/v1-E007-full-streaming/monerod/0006-E021-*.patch $R/patches/v1-E007-full-streaming/monerod/0007-E022-*.patch > $A/e027.am.log 2>&1 || { echo "GIT_AM_FAILED" >> $C; exit 1; }
)
TH=$(git -C $T rev-parse 'HEAD^{tree}')
echo "tree $TH expected fcbc96d34eeedaa3cabd69d3f14b89350c6448e4" >> $C
[ "$TH" = fcbc96d34eeedaa3cabd69d3f14b89350c6448e4 ] || { echo "TREE_MISMATCH"; echo E027A_COMPLETE; } >> $C
tail -1 $C | grep -q E027A_COMPLETE && exit 1
mkdir -p $BD; cd $BD || exit 1
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. \
  && nice -n 10 ninja -j6 daemon && echo BUILD_OK || echo BUILD_FAILED; } > /home/optimizer/work/e027_build_final.log 2>&1
r=$(tail -1 /home/optimizer/work/e027_build_final.log)
echo "build $r $(date -Is)" >> $C
[ "$r" = BUILD_OK ] || { echo E027A_COMPLETE >> $C; exit 1; }
sha256sum $B $F >> $C
df -h /home | tail -1 >> $C
mkdir -p $A/e027_neg/h3105401
$S/negdiff.sh $A/e027_neg/h3105401 $W 3105401 40 "base|$B" "final|$F"
echo "(a3) negdiff done $(date -Is): $(grep -E 'DIFF (PASS|FAIL)' $A/e027_neg/h3105401/summary.txt | tr '\n' ' ')" >> $C
echo E027A_COMPLETE >> $C
