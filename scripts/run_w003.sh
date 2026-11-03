#!/bin/bash
# W003: wallet refresh memory vs --max-concurrency (the wallet's parallel-job thread count, default = hardware threads).
# Same setup as W002 (adapt node serving the synced snapshot offline, fresh wallet 3,105,000 -> 3,123,270), arms
# alternated per round, sampler at 1 s; VmHWM is the exact peak RSS. Marker: W003_COMPLETE in w003.chain.
# usage: run_w003.sh <rounds> "<label>|<extra wallet args>" ["<label>|..."]
set -u
ROUNDS=$1; shift; ARMS=("$@")
A=/home/optimizer/work/research-artifacts; O=$A/w003; C=$A/w003.chain
S=/home/optimizer/work/research/scripts
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
WC=/home/optimizer/work/monero-fcmp/build/beta31/bin/monero-wallet-cli
DD=/home/optimizer/work/chains/stressnet
PORT=28081
RH=${RH:-3105000}
mkdir -p $O/wallets
echo "w003 start $(date -Is) restore_height=$RH rounds=$ROUNDS arms=${ARMS[*]}" > $C
sha256sum $D $WC >> $C
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
# the DB is the synced snapshot (left by W002); verify the node comes up at its height
$D --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
  --log-file $O/monerod.log --log-level 0 > $O/monerod.stdout 2>&1 &
MP=$!; h=0
for i in $(seq 1 600); do
  h=$(curl -s -m 5 http://127.0.0.1:$PORT/get_info | grep -o '"height": [0-9]*' | grep -o '[0-9]*$')
  [ "${h:-0}" -ge 3123270 ] && break; sleep 2
done
echo "node up height=${h:-?} pid=$MP $(date -Is)" >> $C
if [ "${h:-0}" -lt 3123270 ]; then echo "W003_NODE_FAIL" >> $C; exit 1; fi
$S/sample.sh $MP $PORT $O/monerod.mem.csv 2 $O/monerod.log &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
R=$O/results.csv
echo "round,arm,restore_height,wall_s,peak_anon_MB,peak_rss_MB,vmhwm_MB,peak_privdirty_MB,threads_max,exit,blocks_received,cpu_s" > $R

run_wallet() {  # <tag> <arm label> <extra wallet args...>
  local tag=$1 arm=$2; shift 2
  rm -f $O/wallets/$tag $O/wallets/$tag.keys $O/wallets/$tag.address.txt
  $WC --testnet --generate-new-wallet $O/wallets/$tag --password "" --mnemonic-language English \
    --daemon-address 127.0.0.1:$PORT --trusted-daemon --log-file $O/$tag.create.log --log-level 1 \
    --command set refresh-from-block-height $RH < /dev/null > /dev/null 2>&1
  local t0=$(date +%s)
  $WC --testnet --wallet-file $O/wallets/$tag --password "" --daemon-address 127.0.0.1:$PORT --trusted-daemon \
    --log-file $O/$tag.wallet.log --log-level 1 "$@" --command refresh < /dev/null > $O/$tag.stdout 2>&1 &
  local WP=$! P=
  for i in $(seq 1 120); do
    for p in $(pgrep -f -- "--wallet-file $O/wallets/$tag "); do grep -q "^Name:.monero-wallet-c" /proc/$p/status 2>/dev/null && P=$p; done
    [ -n "$P" ] && break; kill -0 $WP 2>/dev/null || break; sleep 0.2
  done
  echo "[$tag] started $(date -Is) pid=${P:-none} arm=$arm extra=$*" >> $C
  if [ -n "$P" ]; then
    $S/sample.sh $P 0 $O/$tag.mem.csv 1 &
    ( while kill -0 $P 2>/dev/null; do c=$(awk '{print ($14+$15)/100}' /proc/$P/stat 2>/dev/null); [ -n "$c" ] && echo $c > $O/$tag.cpu; sleep 0.5; done ) &
  fi
  wait $WP; local ex=$?
  local t1=$(date +%s); sleep 2
  local pa=$(awk -F, 'NR>1 && $6+0>m{m=$6+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local pr=$(awk -F, 'NR>1 && $5+0>m{m=$5+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local hw=$(awk -F, 'NR>1 && $4+0>m{m=$4+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local pd=$(awk -F, 'NR>1 && $11+0>m{m=$11+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local th=$(awk -F, 'NR>1 && $10+0>m{m=$10+0} END{printf "%d", m}' $O/$tag.mem.csv 2>/dev/null)
  local br=$(grep -o "blocks received: [0-9]*" $O/$tag.wallet.log | tail -1 | grep -o "[0-9]*$")
  echo "$tag,$arm,$RH,$((t1-t0)),${pa:-},${pr:-},${hw:-},${pd:-},${th:-},$ex,${br:-0},$(cat $O/$tag.cpu 2>/dev/null)" >> $R
  echo "[$tag] done wall=$((t1-t0)) exit=$ex vmhwm=${hw}MB anon=${pa}MB threads=${th} blocks=${br:-0}" >> $C
}
for r in $(seq 1 $ROUNDS); do
  for a in "${ARMS[@]}"; do
    label=${a%%|*}; extra=${a#*|}
    run_wallet r${r}_$label $label $extra
  done
done
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
echo "== results" >> $C; cat $R >> $C
echo "done $(date -Is)" >> $C
echo W003_COMPLETE >> $C
