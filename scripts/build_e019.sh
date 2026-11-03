#!/bin/bash
# E019 builds on box81: base (v0.19.0.0-beta.3.1 = hydrogen ~/work/monero-fcmp), adapt (hydrogen monero-fcmp-adapt,
# the recommended build) and e017 (monero-fcmp-e017, adapt + the folded verifier). Sources relayed from hydrogen
# 15:09 (build dirs excluded). Daemon-only, Release, ARCH=native, ccache with CCACHE_BASEDIR so identical sources hit
# across the three trees. box81 rules: nice -n 10, -j6. Per-arm logs ~/work/e019_build_<arm>.log; marker
# ~/work/research-artifacts/e019.builds ends BUILDS_OK or BUILDS_FAILED.
set -u
source ~/.cargo/env
export CCACHE_BASEDIR=/home/optimizer/work
A=/home/optimizer/work/research-artifacts; mkdir -p $A
M=$A/e019.builds
echo "builds start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" > $M
ok=1
for spec in "base|monero-fcmp|beta31" "adapt|monero-fcmp-adapt|beta31-adapt" "e017|monero-fcmp-e017|beta31-e017"; do
  IFS='|' read -r arm tree bdir <<< "$spec"
  T=/home/optimizer/work/$tree; B=$T/build/$bdir
  echo "[$arm] $(git -C $T log --oneline -1 | cut -c1-80) start $(date -Is)" >> $M
  mkdir -p "$B" && cd "$B" || { ok=0; continue; }
  { cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. \
    && nice -n 10 ninja -j6 daemon && echo BUILD_OK || echo BUILD_FAILED; } > /home/optimizer/work/e019_build_$arm.log 2>&1
  r=$(tail -1 /home/optimizer/work/e019_build_$arm.log)
  echo "[$arm] $r $(date -Is) sha=$(sha256sum "$B/bin/monerod" 2>/dev/null | cut -c1-16) $("$B/bin/monerod" --version 2>/dev/null | head -1)" >> $M
  [ "$r" = BUILD_OK ] || ok=0
done
ccache -s 2>/dev/null | grep -iE "hits|misses" | head -4 >> $M
df -h /home | tail -1 >> $M
[ $ok = 1 ] && echo BUILDS_OK >> $M || echo BUILDS_FAILED >> $M
