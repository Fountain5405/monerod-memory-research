#!/bin/bash
# E036 part c4, box81: switches the node on W006's DB between the TEST-ONLY lying peer and W006's mining node. Usage: e036_liar_node.sh under|over|stop|w006
# The liar listens on an unadvertised port with --hide-my-port and makes no outbound connections, so only the hydrogen test node ever talks to it.
set -u
W=/home/optimizer/work; D=$W/w006; DD=$W/chains/stressnet; LP=28181; NP=28081; A=$W/research-artifacts; C=$A/e036liar.chain
L=$W/monero-fcmp-e036-liar/build/liar/bin/monerod; M=$W/monero-fcmp-final/build/beta31-final/bin/monerod
stop_port() { local pid=$(ss -ltnp 2>/dev/null | grep ":$1 " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2); [ -n "$pid" ] || return 0
  curl -s -m 30 http://127.0.0.1:$1/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 120); do kill -0 $pid 2>/dev/null || return 0; sleep 1; done; kill -TERM $pid; for i in $(seq 1 120); do kill -0 $pid 2>/dev/null || return 0; sleep 1; done; echo "STOP_FAILED $pid" >> $C; return 1; }
wait_rpc() { for i in $(seq 1 180); do curl -s -m 3 http://127.0.0.1:$1/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
stop_port $NP || exit 1; stop_port $LP || exit 1
case "$1" in
  stop) ;;
  siltruth|silunder)
    # part c5: silent peer, true weights or under-reporting. E036_LIE must be unset for true weights.
    rm -f $DD/testnet/lmdb/lock.mdb
    LIE=""; [ "$1" = silunder ] && LIE="E036_LIE=under"
    (env E036_SILENT=1 $LIE setsid nohup nice -n 5 $L --testnet --data-dir $DD --p2p-bind-port 28180 --hide-my-port --out-peers 0 --in-peers 4 --add-exclusive-node 127.0.0.1:1 --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $LP --log-file $D/liar_$1.log --log-level 0 > $D/liar_$1.stdout 2>&1 < /dev/null &)
    wait_rpc $LP && echo "liar $1 up $(date -Is) height $(curl -s http://127.0.0.1:$LP/get_height | grep -oE '"height": [0-9]+')" >> $C || { echo "LIAR_NOT_UP $1" >> $C; exit 1; }
    ;;
  under|over)
    rm -f $DD/testnet/lmdb/lock.mdb
    (E036_LIE=$1 setsid nohup nice -n 5 $L --testnet --data-dir $DD --p2p-bind-port 28180 --hide-my-port --out-peers 0 --in-peers 4 --add-exclusive-node 127.0.0.1:1 --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $LP --log-file $D/liar_$1.log --log-level 0 > $D/liar.stdout 2>&1 < /dev/null &)
    wait_rpc $LP && echo "liar $1 up $(date -Is) height $(curl -s http://127.0.0.1:$LP/get_height | grep -oE '"height": [0-9]+')" >> $C || { echo "LIAR_NOT_UP $1" >> $C; exit 1; }
    ;;
  w006)
    rm -f $DD/testnet/lmdb/lock.mdb
    (setsid nohup nice -n 19 $M --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $NP --log-file $D/node.log --log-level 0 > $D/node.stdout 2>&1 < /dev/null &)
    wait_rpc $NP || { echo "W006_NODE_NOT_UP" >> $C; exit 1; }
    pgrep -f "rpc-bind-port $NP" | head -1 > $D/node.pid
    for i in $(seq 1 300); do curl -s -m 5 http://127.0.0.1:$NP/get_info | grep -q '"synchronized": true' && break; sleep 2; done
    curl -s -m 30 http://127.0.0.1:$NP/start_mining -d "{\"do_background_mining\":false,\"ignore_battery\":true,\"miner_address\":\"$(cat $D/address)\",\"threads_count\":6}" | grep -oE '"status": "[^"]+"' >> $C
    echo "w006 node and mining restored $(date -Is)" >> $C
    ;;
esac
