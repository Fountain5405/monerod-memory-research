#!/bin/bash
# W002: wallet refresh memory. A fresh wallet (no owned outputs) refreshes 3,105,000 -> 3,123,270 against OUR local
# adapt node (offline, serving the synced snapshot), 3 runs sampled every 2 s, then 1 run under heaptrack.
# Waits for the wallet build marker ~/work/research-artifacts/w002.build (BUILD_OK). Marker: W002_COMPLETE in w002.chain.
set -u
A=/home/optimizer/work/research-artifacts; O=$A/w002; C=$A/w002.chain
S=/home/optimizer/work/research/scripts
D=/home/optimizer/work/monero-fcmp-adapt/build/beta31-adapt/bin/monerod
WC=/home/optimizer/work/monero-fcmp/build/beta31/bin/monero-wallet-cli
DD=/home/optimizer/work/chains/stressnet
SNAP=$A/snapshots/stressnet_synced_h3123270
PORT=28081
RH=${RH:-3105000}
mkdir -p $O/wallets
echo "w002 start $(date -Is) restore_height=$RH" > $C
until grep -q BUILD_OK $A/w002.build 2>/dev/null; do
  grep -q BUILD_FAIL $A/w002.build 2>/dev/null && { echo "W002_BUILD_FAIL" >> $C; exit 1; }
  sleep 30
done
echo "wallet build present $(date -Is)" >> $C
sha256sum $D $WC >> $C
$WC --version >> $C 2>&1
pgrep -fa shadow | grep -v pgrep >> $C || echo "no shadow processes" >> $C
( while kill -0 $$ 2>/dev/null; do pgrep -fa shadow | grep -v pgrep > /dev/null && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &

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
$S/sample.sh $MP $PORT $O/monerod.mem.csv 2 $O/monerod.log &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C

R=$O/results.csv
echo "run,restore_height,wall_s,peak_anon_MB,peak_rss_MB,vmhwm_MB,peak_privdirty_MB,exit,refresh_done,cpu_s" > $R

# run_wallet <tag> <restore height> [wrapper command...]
run_wallet() {
  local tag=$1 rh=$2; shift 2
  rm -f $O/wallets/$tag $O/wallets/$tag.keys $O/wallets/$tag.address.txt
  local t0=$(date +%s)
  "$@" $WC --testnet --generate-new-wallet $O/wallets/$tag --password "" --mnemonic-language English \
    --restore-height $rh --daemon-address 127.0.0.1:$PORT --trusted-daemon \
    --log-file $O/$tag.wallet.log --log-level 1 --command refresh < /dev/null > $O/$tag.stdout 2>&1 &
  local WP=$! P=
  for i in $(seq 1 120); do
    for p in $(pgrep -x monero-wallet-cli); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "wallets/$tag " && P=$p; done
    [ -n "$P" ] && break; sleep 1
  done
  echo "[$tag] started $(date -Is) pid=${P:-none} wrapper=$WP rh=$rh" >> $C
  local cpu=
  if [ -n "$P" ]; then
    $S/sample.sh $P 0 $O/$tag.mem.csv 2 &
    ( while kill -0 $P 2>/dev/null; do c=$(awk '{print ($14+$15)/100}' /proc/$P/stat 2>/dev/null); [ -n "$c" ] && echo $c > $O/$tag.cpu; sleep 1; done ) &
  fi
  wait $WP; local ex=$?
  local t1=$(date +%s)
  sleep 3
  local pa=$(awk -F, 'NR>1 && $6+0>m{m=$6+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local pr=$(awk -F, 'NR>1 && $5+0>m{m=$5+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local hw=$(awk -F, 'NR>1 && $4+0>m{m=$4+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local pd=$(awk -F, 'NR>1 && $11+0>m{m=$11+0} END{printf "%d", m/1024}' $O/$tag.mem.csv 2>/dev/null)
  local done_n=$(grep -c -i "Refresh done" $O/$tag.stdout $O/$tag.wallet.log 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
  cpu=$(cat $O/$tag.cpu 2>/dev/null)
  echo "$tag,$rh,$((t1-t0)),${pa:-},${pr:-},${hw:-},${pd:-},$ex,$done_n,${cpu:-}" >> $R
  echo "[$tag] done $(date -Is) wall=$((t1-t0)) exit=$ex peak_anon=${pa}MB vmhwm=${hw}MB refresh_done=$done_n" >> $C
  ls -la $O/wallets/ | grep " $tag" >> $C
}

# smoke: 270 blocks, must report a refresh
run_wallet smoke 3123000
if ! grep -q "^smoke,3123000,[0-9]*,[0-9]*,[0-9]*,[0-9]*,[0-9]*,0,[1-9]" $R; then
  echo "W002_SMOKE_FAIL (see $O/smoke.stdout, $O/smoke.wallet.log)" >> $C
  tail -20 $O/smoke.stdout >> $C
  sudo cpupower frequency-set -g $OLDGOV > /dev/null
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  exit 1
fi
for r in 1 2 3; do run_wallet r$r $RH; done
run_wallet ht $RH heaptrack -o $O/heaptrack.w002
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $C
echo "node anon peak during W002: $(awk -F, 'NR>1 && $6+0>m{m=$6+0} END{printf "%d MB", m/1024}' $O/monerod.mem.csv)" >> $C
curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
echo "== results" >> $C; cat $R >> $C
echo "done $(date -Is)" >> $C
echo W002_COMPLETE >> $C
