#!/bin/bash
# E036 part c4, victim side, hydrogen: one lying-peer case. Usage: e036_liar_case.sh <label> <bin> <seconds> <peer> [peer...]
# The liar is a TEST-ONLY base build (scripts/e036_liar_build.sh) on box81, started by the control box on port 28180 with E036_LIE=under (every advertised weight 1 byte) or over (every weight 200 MB), --hide-my-port, --out-peers 0. It serves real blocks and lies only about their weights.
# Expected, fixed before any case ran, each from 3,105,401, 600 s:
#   ref     .22 alone, e036: progress past the heavy window, 0 oversize errors. The rate the others are read against.
#   under1  under liar alone, e036: stuck at 3,105,401 or within one span of it, oversize errors, like base at the wedge. Under-reporting removes the patch's protection.
#   under2  under liar alone, final: progress, 0 oversize errors. Its cap uses no peer data.
#   under3  under liar + .22, e036: reaches heights past the window through .22, with oversize errors and dropped connections. Whether spans the liar sized get re-requested from .22 and take that connection down too is the question this case is for; I do not predict how much it slows, and a full stall would be the important result.
#   under4  under liar + .22, final: progress near ref, 0 oversize errors.
#   over1   over liar alone, e036: progress, 0 oversize errors, one block per request, so slower than ref once blocks are small.
#   over2   over liar + .22, e036: progress, 0 oversize errors, between ref and over1.
# Report only. Hydrogen's DB is restored from the snapshot before each case. These are not timing runs.
set -u
L=$1; BIN=$2; SECS=$3; shift 3
W0=/home/optimizer/work; R=$W0/research; A=$W0/research-artifacts; S=$R/scripts; O=$A/e036_liar; C=$A/e036liar.chain
B=$W0/monero-fcmp/build/beta31/bin/monerod; SNAP=$A/snapshots/stressnet_wedge_h3105401; DD=$W0/chains/stressnet; PORT=28081
mkdir -p $O; LOG=$O/$L.log
wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
log_height() { grep -oE "Synced [0-9]+/[0-9]+" "$1" | tail -1 | cut -d' ' -f2 | cut -d/ -f1; }
stop_node() { curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null; for i in $(seq 1 30); do kill -0 $1 2>/dev/null || return 0; sleep 1; done; kill -TERM $1 2>/dev/null; for i in $(seq 1 600); do kill -0 $1 2>/dev/null || return 0; sleep 1; done; kill -KILL $1; sleep 3; }
rm -f $DD/testnet/lmdb/lock.mdb; cp $SNAP/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb
$S/pop_to.sh $B $DD 3105401 $O/$L.rewind.log
tail -1 $O/$L.rewind.log | grep -q "RESULT OK" || { echo "[$L] rewind FAILED" >> $C; exit 1; }
P=(); for p in "$@"; do P+=(--add-exclusive-node "$p"); done
$BIN --testnet --data-dir $DD "${P[@]}" --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 > $O/$L.stdout 2>&1 &
MP=$!; wait_rpc
curl -s -m 10 http://127.0.0.1:$PORT/set_log_categories -d '{"categories":"*:WARNING,net:ERROR,net.cn:INFO,cn:INFO,global:INFO"}' > /dev/null
t0=$(date +%s); : > $O/$L.height.csv
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ] && kill -0 $MP 2>/dev/null; do
  sleep 30
  echo "$(( $(date +%s) - t0 )),$(curl -s -m 5 http://127.0.0.1:$PORT/get_height | grep -oE '"height": [0-9]+' | grep -oE '[0-9]+$'),$(curl -s -m 5 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"get_connections"}' | grep -c '"address"')" >> $O/$L.height.csv
done
H=$(curl -s -m 5 http://127.0.0.1:$PORT/get_height | grep -oE '"height": [0-9]+' | grep -oE '[0-9]+$')
HX=$(curl -s -m 30 http://127.0.0.1:$PORT/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":$(( ${H:-1} - 1 ))}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
TX=$(curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":$(( ${H:-1} - 1 ))}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
stop_node $MP
echo "[$L] secs=$SECS peers=$* height=$H hash=$([ -n "$HX" ] && [ "$HX" = "$TX" ] && echo yes || echo NO) oversize_errors=$(grep -c 'Maximum packet size exceed' $LOG) requests=$(grep -c 'state: requesting objects' $LOG) drops=$(grep -c -i 'dropping connection\|connection dropped' $LOG) oversize_22=$(grep 'Maximum packet size exceed' $LOG | grep -c '192.168.1.22:') $(date -Is)" | tee -a $C
gzip -f $LOG
