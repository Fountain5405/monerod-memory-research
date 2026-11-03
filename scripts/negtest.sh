#!/bin/bash
# Monerod-level FCMP++ negative test for several binaries. usage: negtest.sh <outdir> <pop height> "<label>|<monerod>" ...
# Rewinds the working DB to <pop height>, then for each binary: start offline, flush pool, run negtest.py, stop.
# The local log (level 1) records the rejection reasons. Marker: last line of <outdir>/summary.txt is NEGTEST_COMPLETE.
set -u
OUT=$1; H=$2; shift 2
DD=/home/optimizer/work/chains/stressnet
POPBIN=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
PORT=28081
mkdir -p $OUT; S=$OUT/summary.txt
echo "negtest start $(date -Is) pop=$H" > $S
~/work/research/scripts/pop_to.sh $POPBIN $DD $H $OUT/rewind.log
tail -1 $OUT/rewind.log >> $S
wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
for a in "$@"; do
  IFS='|' read -r L BIN <<< "$a"
  $BIN --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
    --log-file $OUT/$L.log --log-level 1 > $OUT/$L.stdout 2>&1 &
  MP=$!; wait_rpc
  curl -s -m 60 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"flush_txpool"}' > /dev/null
  echo "[$L] $(sha256sum $BIN | cut -c1-16) height=$(curl -s http://127.0.0.1:$PORT/get_height | grep -oE '"height": [0-9]+')" >> $S
  python3 -I ~/work/research/scripts/negtest.py $PORT $OUT/$L.json >> $S 2>&1
  curl -s -m 60 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"flush_txpool"}' > /dev/null
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 120); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && { kill -TERM $MP; sleep 20; }
done
echo NEGTEST_COMPLETE >> $S
