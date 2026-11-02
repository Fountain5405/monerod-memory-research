#!/bin/bash
# E006: flat CPU profile of the baseline beta31 node syncing the FCMP++ window (3,105,401 -> 3,105,441).
# Waits for the E004c chain to finish (quiet box), rewinds, runs monerod (--block-sync-size 5), and records
# perf (-F 199, all threads, no call graphs) for the whole window. Then summarizes self time by symbol and
# by category (scripts/perf_classify.py). Marker: last line of ~/work/research-artifacts/E006/summary.txt
# is E006_COMPLETE.
set -u
D=~/work/research-artifacts/E006; mkdir -p $D
S=$D/summary.txt
BIN=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
DD=/home/optimizer/work/chains/stressnet
PORT=28081
echo "e006 queued $(date -Is)" > $S
until tail -1 ~/work/research-artifacts/E004c.chain 2>/dev/null | grep -q CHAIN_E004C_COMPLETE; do sleep 30; done
echo "start $(date -Is)" >> $S
pgrep -fa shadow | grep -v pgrep >> $S || echo "no shadow processes" >> $S
~/work/research/scripts/pop_to.sh $BIN $DD 3105401 $D/rewind.log
tail -1 $D/rewind.log >> $S
LOG=$D/monerod.log
$BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
  --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 --block-sync-size 5 > $D/stdout.txt 2>&1 &
MP=$!
for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && break; sleep 1; done
sudo perf record -q -F 199 -p $MP -o $D/perf.data > $D/perf_record.log 2>&1 &
PP=$!
t0=$(date +%s)
while :; do
  h=$(grep -oE "Synced [0-9]+/[0-9]+" $LOG | tail -1 | cut -d' ' -f2 | cut -d/ -f1); h=${h:-0}
  [ "$h" -ge 3105441 ] && break
  [ $(( $(date +%s) - t0 )) -ge 900 ] && break
  sleep 2
done
echo "window done h=$h after $(( $(date +%s) - t0 ))s" >> $S
sudo kill -INT $PP; wait $PP 2>/dev/null
curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
for i in $(seq 1 600); do kill -0 $MP 2>/dev/null || break; sleep 1; done
kill -0 $MP 2>/dev/null && kill -TERM $MP
sleep 5
sudo chown $(id -u):$(id -g) $D/perf.data
perf report -i $D/perf.data --stdio --no-children --sort symbol --percent-limit 0.05 2>/dev/null > $D/perf_symbols.txt
python3 -I ~/work/research/scripts/perf_classify.py $D/perf_symbols.txt >> $S
echo E006_COMPLETE >> $S
