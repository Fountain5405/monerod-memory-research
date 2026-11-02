#!/bin/bash
# E003: does the FCMP++ verification peak scale with thread count (model B: transient per-proof
# circuit x concurrent threads) or with proofs per block (model A: accumulating batch verifier)?
# For each concurrency C: rewind to 3,105,401, then sync with the BASELINE beta31 binary,
# --block-sync-size 5 --max-concurrency C, until the log height reaches END (or TIMEOUT s).
# Records peak RssAnon over the same height window. Completion marker: E003_COMPLETE.
# usage: e003_sweep.sh <END height> <TIMEOUT s> <C1> [C2 ...]   (C=0 means the default, no flag)
set -u
END=$1; TO=$2; shift 2
BIN=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
DD=/home/optimizer/work/chains/stressnet
D=~/work/research-artifacts/E003; mkdir -p $D
S=$D/summary.txt
PORT=28081
echo "e003 start $(date -Is) end=$END timeout=$TO concurrencies=$* nproc=$(nproc)" > $S
sha256sum $BIN >> $S
log_height() { grep -oE "Synced [0-9]+/[0-9]+" "$1" | tail -1 | cut -d' ' -f2 | cut -d/ -f1; }
for C in "$@"; do
  tag=c$C; [ "$C" = 0 ] && tag=cdefault
  ~/work/research/scripts/pop_to.sh $BIN $DD 3105401 $D/$tag.rewind.log
  if ! tail -1 $D/$tag.rewind.log | grep -q "RESULT OK"; then echo "[$tag] rewind FAILED" >> $S; continue; fi
  extra="--block-sync-size 5"; [ "$C" != 0 ] && extra="$extra --max-concurrency $C"
  LOG=$D/$tag.log
  $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
    --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 $extra > $D/$tag.stdout 2>&1 &
  MP=$!
  for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && break; sleep 1; done
  ~/work/research/scripts/sample.sh $MP $PORT $D/$tag.mem.csv 2 $LOG &
  t0=$(date +%s); h=0
  while :; do
    h=$(log_height $LOG); h=${h:-0}
    [ "$h" -ge "$END" ] && break
    [ $(( $(date +%s) - t0 )) -ge "$TO" ] && break
    kill -0 $MP 2>/dev/null || break
    sleep 2
  done
  t1=$(date +%s)
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 30); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && kill -TERM $MP
  for i in $(seq 1 600); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && { echo "[$tag] SIGKILL" >> $S; kill -KILL $MP; sleep 3; }
  sleep 3
  thr=$(awk -F, 'NR>1 {t=$10} END {print t}' $D/$tag.mem.csv)
  peak=$(awk -F, -v e=$END 'NR>1 && $6>m {m=$6} END {print int(m/1024)}' $D/$tag.mem.csv)
  echo "[$tag] args='$extra' reached=$h in $((t1 - t0))s peak_RssAnon_MB=$peak threads=$thr" >> $S
done
echo E003_COMPLETE >> $S
