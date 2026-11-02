#!/bin/bash
# E001 reproduction: sync wedge at height 3,105,401 on stressnet.
# usage: repro_e001.sh <monerod> <datadir at height 3105401> <outdir> <run_seconds>
# Run 1 ("bug"): default sync settings. Run 2 ("control"): --block-sync-size 5. Each run is followed
# by a rewind back to 3,105,401 so that both runs start from the same state.
# v3 (2026-11-02): while a node verifies heavy blocks its RPC can block on the blockchain lock, so
#   heights come from "Synced N/M" log lines; logging is set right at start; stop falls back to SIGTERM;
#   the end hash is checked against .22 from an idle --offline restart. Completion marker: REPRO_COMPLETE.
set -u
BIN=$1; DD=$2; OUT=$3; SECS=$4
PORT=28081
POP=~/work/research/scripts/pop_to.sh
mkdir -p $OUT
S=$OUT/summary.txt
echo "repro_e001 v3 start $(date -Is) bin=$BIN datadir=$DD secs=$SECS" > $S
sha256sum $BIN >> $S

wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
log_height() { grep -oE "Synced [0-9]+/[0-9]+" "$1" | tail -1 | cut -d' ' -f2 | cut -d/ -f1; }
stop_node() {  # stop_node <pid>
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 30); do kill -0 $1 2>/dev/null || return 0; sleep 1; done
  kill -TERM $1 2>/dev/null
  for i in $(seq 1 600); do kill -0 $1 2>/dev/null || return 0; sleep 1; done
  echo "  (SIGKILL after 630 s)" >> $S; kill -KILL $1; sleep 3
}
check_tip() {  # offline restart; prints "<height> <match yes/NO> <ourhash>"
  $BIN --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
    --log-file $OUT/check.log --log-level 0 > /dev/null 2>&1 &
  local MP=$!
  wait_rpc
  local r=$(curl -s -m 30 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"get_last_block_header"}')
  local idx=$(echo "$r" | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$')
  local ours=$(echo "$r" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  local theirs=$(curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":${idx:-0}}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  stop_node $MP
  echo "$(( ${idx:--1} + 1 )) $([ -n "$ours" ] && [ "$ours" = "$theirs" ] && echo yes || echo NO) ${ours:-none}"
}

run() {  # run <name> [extra args]
  local name=$1; shift
  local LOG=$OUT/$name.log
  $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
    --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 "$@" > $OUT/$name.stdout 2>&1 &
  local MP=$!
  wait_rpc || echo "  [$name] rpc never came up" >> $S
  curl -s -m 10 http://127.0.0.1:$PORT/set_log_categories -d '{"categories":"*:WARNING,net:ERROR,net.cn:INFO,cn:INFO,global:INFO"}' > /dev/null
  local h0=$(curl -s -m 5 http://127.0.0.1:$PORT/get_height | grep -oE '"height": [0-9]+' | grep -oE '[0-9]+$')
  ~/work/research/scripts/sample.sh $MP $PORT $OUT/$name.mem.csv 5 $LOG &
  local t0=$(date +%s)
  sleep $SECS
  local h1=$(log_height $LOG); h1=${h1:-$h0}
  stop_node $MP
  local tip=$(check_tip)
  local nerr=$(grep -c "Maximum packet size exceed" $LOG)
  local sizes=$(grep -oE "packet header received [0-9]+" $LOG | awk '{print $4}' | sort | uniq -c | sort -rn | head -3 | tr '\n' ';')
  local reqs=$(grep -c "state: requesting objects" $LOG)
  local caps=$(grep -c "capping block sync size" $LOG)
  local capex=$(grep -m1 -oE "capping block sync size from [0-9]+ to [0-9]+ blocks \(block weight limit [0-9]+ bytes\)" $LOG)
  local peak=$(awk -F, 'NR>1 && $6>m {m=$6} END {print int(m/1024)}' $OUT/$name.mem.csv)
  echo "[$name] args='$*' start_height=$h0 end_height(log)=$h1 blocks=$(( ${h1:-0} - ${h0:-0} )) in ${SECS}s | tip_after_stop(height match hash)=$tip | oversize_errors=$nerr request_objects=$reqs cap_lines=$caps first_cap='$capex' | peak_RssAnon_MB=$peak | oversize_sizes(count size)=$sizes" >> $S
  $POP $BIN $DD 3105401 $OUT/$name.rewind.log
  echo "  [$name] rewind: $(tail -1 $OUT/$name.rewind.log)" >> $S
}

run bug
run control --block-sync-size 5
echo REPRO_COMPLETE >> $S
