#!/bin/bash
# After the E005 chain completes: build E004c monerod, then A/B base vs e004c (3 rounds, default settings).
# Marker: last line of ~/work/research-artifacts/E004c.chain is CHAIN_E004C_COMPLETE.
set -u
C=~/work/research-artifacts/E004c.chain
echo "chain start $(date -Is)" > $C
until tail -1 ~/work/research-artifacts/E005.chain 2>/dev/null | grep -q CHAIN_E005_COMPLETE; do sleep 30; done
echo "E005 chain complete $(date -Is)" >> $C
source ~/.cargo/env
cd ~/work/monero-fcmp-e004c && mkdir -p build/beta31-e004c && cd build/beta31-e004c
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > ~/work/research-artifacts/E004c.build.log 2>&1
tail -1 ~/work/research-artifacts/E004c.build.log >> $C
if tail -1 ~/work/research-artifacts/E004c.build.log | grep -q BUILD_OK; then
  B=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
  E=/home/optimizer/work/monero-fcmp-e004c/build/beta31-e004c/bin/monerod
  sha256sum $E >> $C
  ~/work/research/scripts/ab_window.sh ~/work/research-artifacts/E004c 3105441 900 3 "base|$B|--block-sync-size 5" "e004c|$E|--block-sync-size 5"
  echo "A/B done $(date -Is)" >> $C
fi
echo CHAIN_E004C_COMPLETE >> $C
