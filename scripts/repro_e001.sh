#!/bin/bash
# E001 reproduction: sync wedge at height 3,105,401 on stressnet.
# usage: repro_e001.sh <monerod> <datadir at height 3105401> <outdir> <run_seconds>
# Run 1 ("bug"): default sync settings. Run 2 ("control"): --block-sync-size 5.
# Each run uses exclusive peer 192.168.1.22:28080 and makes net errors visible via set_log_categories.
# v2 (2026-11-02): end height/hash from get_last_block_header (with retries) and checked against .22;
#   logs cn:INFO so the E001-fix "capping block sync size" lines are visible; completion marker REPRO_COMPLETE.
# Writes <outdir>/summary.txt; its last line is "REPRO_COMPLETE".
set -u
BIN=$1; DD=$2; OUT=$3; SECS=$4
PORT=28081
mkdir -p $OUT
S=$OUT/summary.txt
echo "repro_e001 v2 start $(date -Is) bin=$BIN datadir=$DD secs=$SECS" > $S
sha256sum $BIN >> $S
tip() {  # prints "<height> <hash>" of our top block (height = index + 1), retrying while the node is busy
  local r
  for i in 1 2 3 4 5 6; do
    r=$(curl -s -m 20 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"get_last_block_header"}')
    local idx=$(echo "$r" | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$')
    local hash=$(echo "$r" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
    if [ -n "$idx" ] && [ -n "$hash" ]; then echo "$((idx + 1)) $hash $idx"; return; fi
    sleep 5
  done
  echo "? ? ?"
}
peer_hash() { curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":$1}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4; }

run() {  # run <name> [extra args]
  local name=$1; shift
  local LOG=$OUT/$name.log
  $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
    --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 "$@" > $OUT/$name.stdout 2>&1 &
  local MP=$!
  local t0 t1
  for i in $(seq 1 60); do t0=$(tip); [ "${t0%% *}" != "?" ] && break; sleep 1; done
  curl -s -m 10 http://127.0.0.1:$PORT/set_log_categories -d '{"categories":"*:WARNING,net:ERROR,net.cn:INFO,cn:INFO,global:INFO"}' > /dev/null
  ~/work/research/scripts/sample.sh $MP $PORT $OUT/$name.mem.csv 5 $LOG &
  sleep $SECS
  t1=$(tip)
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && kill $MP
  local h0=${t0%% *} h1=${t1%% *}
  local idx1=$(echo $t1 | cut -d' ' -f3) ours=$(echo $t1 | cut -d' ' -f2)
  local theirs=$( [ "$idx1" != "?" ] && peer_hash $idx1 )
  local match=$([ -n "$theirs" ] && [ "$ours" = "$theirs" ] && echo yes || echo NO)
  local nerr=$(grep -c "Maximum packet size exceed" $LOG)
  local sizes=$(grep -oE "packet header received [0-9]+" $LOG | awk '{print $4}' | sort | uniq -c | sort -rn | head -3 | tr '\n' ';')
  local reqs=$(grep -c "state: requesting objects" $LOG)
  local caps=$(grep -c "capping block sync size" $LOG)
  local capex=$(grep -m1 -oE "capping block sync size from [0-9]+ to [0-9]+ blocks \(block weight limit [0-9]+ bytes\)" $LOG)
  echo "[$name] args='$*' start_height=$h0 end_height=$h1 blocks=$(( ${h1:-0} - ${h0:-0} )) end_hash_matches_peer=$match oversize_errors=$nerr request_objects=$reqs cap_lines=$caps first_cap='$capex' oversize_sizes(count size)=$sizes" >> $S
}

run bug
run control --block-sync-size 5
echo REPRO_COMPLETE >> $S
