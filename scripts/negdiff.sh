#!/bin/bash
# E015 differential negative test runner. usage: negdiff.sh <outdir> <snapshot dir> <height> <scan blocks> "<label>|<monerod>" ...
# Restores the working DB from <snapshot dir>, pops to/verifies <height> (pop_to.sh), then for each binary: start offline
# (log level 1), flush the pool, run negtest2.py with a shared cases file (identical cases for every binary), flush, stop.
# Then negdiff_compare.py checks that every binary gave the same (status, flags) for every case, with the first binary as
# the oracle. Marker: last line of <outdir>/summary.txt is NEGDIFF_COMPLETE.
set -u
OUT=$1; SNAP=$2; H=$3; SCAN=$4; shift 4
DD=/home/optimizer/work/chains/stressnet
POPBIN=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
PORT=28081
mkdir -p $OUT; S=$OUT/summary.txt
echo "negdiff start $(date -Is) snap=$SNAP H=$H scan=$SCAN" > $S
rm -f $DD/testnet/lmdb/lock.mdb; cp $SNAP/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb
~/work/research/scripts/pop_to.sh $POPBIN $DD $H $OUT/rewind.log
tail -1 $OUT/rewind.log >> $S
tail -1 $OUT/rewind.log | grep -q "RESULT OK" || { echo "rewind FAILED"; echo NEGDIFF_COMPLETE; } >> $S
tail -1 $S | grep -q NEGDIFF_COMPLETE && exit 1
wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
LABELS=()
for a in "$@"; do
  IFS='|' read -r L BIN <<< "$a"; LABELS+=($L)
  $BIN --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
    --log-file $OUT/$L.log --log-level 1 > $OUT/$L.stdout 2>&1 &
  MP=$!; wait_rpc
  curl -s -m 60 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"flush_txpool"}' > /dev/null
  t0=$(date +%s)
  echo "[$L] $(sha256sum $BIN | cut -c1-16) height=$(curl -s http://127.0.0.1:$PORT/get_height | grep -oE '"height": [0-9]+')" >> $S
  python3 -I ~/work/research/scripts/negtest2.py $PORT $OUT/cases.json $OUT/$L.json $SCAN >> $S 2>&1
  echo "[$L] $(( $(date +%s) - t0 )) s; log lines 'Failed to verify input FCMP++': $(grep -c 'Failed to verify input FCMP++' $OUT/$L.log)" >> $S
  curl -s -m 60 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"flush_txpool"}' > /dev/null
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 120); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && { kill -TERM $MP; sleep 20; }
done
python3 -I ~/work/research/scripts/negdiff_compare.py $(for L in "${LABELS[@]}"; do echo $OUT/$L.json; done) >> $S 2>&1
echo NEGDIFF_COMPLETE >> $S
