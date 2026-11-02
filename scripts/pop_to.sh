#!/bin/bash
# usage: pop_to.sh <monerod> <datadir> <target_height> <logfile>
# Starts monerod --testnet --offline on <datadir>, pops blocks via RPC in chunks until
# get_info height == <target_height>, verifies our top block hash against 192.168.1.22
# at the same height, then stops the daemon. Last line of <logfile> is "RESULT OK" or "RESULT FAIL ...".
set -u
BIN=$1; DD=$2; T=$3; LOG=$4
CHUNK=1000
PORT=28081
rpc() { curl -s -m 7200 "http://127.0.0.1:$PORT$1" -d "${2:-{\}}"; }
height() { rpc /get_info | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$'; }
echo "pop_to start $(date -Is) bin=$BIN datadir=$DD target=$T" > $LOG
$BIN --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
  --log-file $LOG.monerod --log-level 0 > $LOG.stdout 2>&1 &
MP=$!
for i in $(seq 1 120); do h=$(height); [ -n "$h" ] && break; sleep 2; done
[ -z "${h:-}" ] && { echo "RESULT FAIL rpc never came up" >> $LOG; kill $MP; exit 1; }
echo "start height $h" >> $LOG
while [ "$h" -gt "$T" ]; do
  n=$(( h - T )); [ $n -gt $CHUNK ] && n=$CHUNK
  t0=$(date +%s)
  rpc /pop_blocks "{\"nblocks\":$n}" > /dev/null
  h=$(height)
  echo "$(date +%H:%M:%S) popped $n in $(( $(date +%s) - t0 ))s -> height $h" >> $LOG
  [ -z "$h" ] && { echo "RESULT FAIL lost rpc" >> $LOG; exit 1; }
done
ours=$(rpc /json_rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_last_block_header\"}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
theirs=$(curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":$(( T - 1 ))}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
echo "top block (index $(( T - 1 ))): ours=$ours  .22=$theirs" >> $LOG
rpc /stop_daemon > /dev/null
for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
kill -0 $MP 2>/dev/null && { echo "daemon did not stop; SIGTERM" >> $LOG; kill $MP; sleep 5; }
if [ "$h" = "$T" ] && [ -n "$ours" ] && [ "$ours" = "$theirs" ]; then echo "RESULT OK height $h" >> $LOG; else echo "RESULT FAIL height=$h hash_match=$([ "$ours" = "$theirs" ] && echo yes || echo no)" >> $LOG; fi
