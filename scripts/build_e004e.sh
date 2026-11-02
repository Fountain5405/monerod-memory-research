#!/bin/bash
source ~/.cargo/env
cd ~/work/monero-fcmp-e004e && mkdir -p build/beta31-e004e && cd build/beta31-e004e
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. > /dev/null && nice -n 15 ninja -j4 daemon && echo BUILD_OK || echo BUILD_FAILED; } > ~/work/research-artifacts/e004e.build.log 2>&1
