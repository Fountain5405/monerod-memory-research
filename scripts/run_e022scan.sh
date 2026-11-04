#!/bin/bash
# E022a: input-count scan over 3,080,000..3,123,270 on our offline adapt node serving the synced snapshot.
# Marker: E022SCAN_COMPLETE in ~/work/research-artifacts/e022scan.chain. Output: e022scan/chain_inputs.csv
set -u
A=/home/optimizer/work/research-artifacts; O=$A/e022scan; C=$A/e022scan.chain
S=/home/optimizer/work/research/scripts
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
DD=/home/optimizer/work/chains/stressnet
SNAP=$A/snapshots/stressnet_synced_h3123270
PORT=28081
mkdir -p $O
echo "e022scan start $(date -Is)" > $C
pgrep -fa "monerod" | grep -v pgrep | grep -q "$DD" && { echo "a monerod already uses $DD; abort" >> $C; exit 1; }
rm -f $DD/testnet/lmdb/lock.mdb; cp $SNAP/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb
echo "restored synced snapshot $(date -Is)" >> $C
$D --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
  --log-file $O/monerod.log --log-level 0 > $O/monerod.stdout 2>&1 &
MP=$!
h=0
for i in $(seq 1 600); do
  h=$(curl -s -m 5 http://127.0.0.1:$PORT/get_info | grep -o '"height": [0-9]*' | grep -o '[0-9]*$')
  [ "${h:-0}" -ge 3123270 ] && break; sleep 2
done
echo "node up height=${h:-?} pid=$MP $(date -Is)" >> $C
RPC=http://127.0.0.1:$PORT python3 $S/chain_inputs.py 3080000 3123270 $O/chain_inputs.csv >> $C 2>&1
echo "scan rc=$? $(date -Is) lines=$(wc -l < $O/chain_inputs.csv)" >> $C
curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon > /dev/null
for i in $(seq 1 120); do kill -0 $MP 2>/dev/null || break; sleep 2; done
kill -0 $MP 2>/dev/null && { kill $MP; echo "node killed" >> $C; }
echo "node stopped $(date -Is)" >> $C
echo "E022SCAN_COMPLETE" >> $C
