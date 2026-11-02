#!/bin/bash
# usage: micro.sh <build_dir> <label> [filter]
set -u
B=$1; L=$2; F=${3:-"*"}
OUT=~/work/bench/results/micro_${L}_$(date +%Y%m%d_%H%M%S).txt
{ echo "# build=$B label=$L filter=$F commit=$(git -C ~/work/monero rev-parse --short HEAD)"; uptime; pgrep -fa "shadow|monerod" | grep -v pgrep; cpupower frequency-info -p | tail -1; } > $OUT
cd $B/tests/performance_tests && taskset -c 2 ./performance_tests --stats --filter "$F" >> $OUT 2>&1
echo "DONE $(date)" >> $OUT
echo $OUT
