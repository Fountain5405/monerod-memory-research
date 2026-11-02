#!/bin/bash
# E001 reproduction: sync wedge at height 3,105,401 on stressnet.
# usage: repro_e001.sh <monerod> <datadir at height 3105401> <outdir> <run_seconds>
# Run 1 ("bug"): default sync settings. Run 2 ("control"): --block-sync-size 5.
# Each run uses exclusive peer 192.168.1.22:28080 and makes net errors visible via set_log_categories.
# Writes <outdir>/summary.txt; its last line is "DONE".
set -u
BIN=$1; DD=$2; OUT=$3; SECS=$4
PORT=28081
mkdir -p $OUT
S=$OUT/summary.txt
echo "repro_e001 start $(date -Is) bin=$BIN datadir=$DD secs=$SECS" > $S
sha256sum $BIN >> $S
height() { curl -s -m 10 http://127.0.0.1:$PORT/get_info | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$'; }

run() {  # run <name> [extra args]
  local name=$1; shift
  local LOG=$OUT/$name.log
  $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
    --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 "$@" > $OUT/$name.stdout 2>&1 &
  local MP=$! h0= h1=
  for i in $(seq 1 60); do h0=$(height); [ -n "$h0" ] && break; sleep 1; done
  curl -s -m 10 http://127.0.0.1:$PORT/set_log_categories -d '{"categories":"*:WARNING,net:ERROR,net.cn:INFO,global:INFO"}' > /dev/null
  ~/work/research/scripts/sample.sh $MP $PORT $OUT/$name.mem.csv 5 $LOG &
  sleep $SECS
  h1=$(height)
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && kill $MP
  local nerr=$(grep -c "Maximum packet size exceed" $LOG)
  local sizes=$(grep -oE "packet header received [0-9]+" $LOG | awk '{print $4}' | sort | uniq -c | sort -rn | head -3 | tr '\n' ';')
  local reqs=$(grep -c "state: requesting objects" $LOG)
  echo "[$name] args='$*' start_height=$h0 end_height=$h1 oversize_errors=$nerr request_objects=$reqs oversize_sizes(count size)=$sizes" >> $S
}

run bug
run control --block-sync-size 5
echo DONE >> $S
