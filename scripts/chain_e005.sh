#!/bin/bash
# After E004a completes: build E005 monerod, then A/B base vs e005 (3 rounds, default concurrency).
# Marker: last line of ~/work/research-artifacts/E005.chain is CHAIN_E005_COMPLETE.
set -u
C=~/work/research-artifacts/E005.chain
echo "chain start $(date -Is)" > $C
until tail -1 ~/work/research-artifacts/E004a/summary.txt 2>/dev/null | grep -q AB_COMPLETE; do sleep 20; done
echo "E004a complete $(date -Is)" >> $C
source ~/.cargo/env
cd ~/work/monero-fcmp-e005 && mkdir -p build/beta31-e005 && cd build/beta31-e005
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > ~/work/research-artifacts/E005.build.log 2>&1
tail -1 ~/work/research-artifacts/E005.build.log >> $C
if tail -1 ~/work/research-artifacts/E005.build.log | grep -q BUILD_OK; then
  B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
  E=/home/optimizer/work/monero-fcmp-e005/build/beta31-e005/bin/monerod
  sha256sum $E >> $C
  ~/work/research/scripts/ab_window.sh ~/work/research-artifacts/E005 3105441 900 3 "base|$B|--block-sync-size 5" "e005|$E|--block-sync-size 5"
  echo "A/B done $(date -Is)" >> $C
fi
echo CHAIN_E005_COMPLETE >> $C
