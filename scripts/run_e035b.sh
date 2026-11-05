#!/bin/bash
# E035 part b, hydrogen: the window-aware E001 cap (owner approved 2026-11-05) on the real chain at default sync settings. Waits for E033. Report only. Part a (run_e035a.sh, box81) tests the cap against the real weight-limit code.
# On stressnet the limit is 20 MB, so the cap is 4 blocks as with the current cap, unless the largest recent block passes 11.25 MB. So this part is a regression test: it cannot exercise the step above 50 blocks. Part a does that.
#   Tree ~/work/monero-fcmp-e035 = final (adbe70cf8) + patches/options/E035-window-cap/. Tree hash must equal ced7116c. The arms differ by that patch only.
#   (b1) wedge control from 3,105,401, default settings, 120 s, logged: base, final, window -> e035_wedge/
#   (b2) long resync to 3,123,400, default settings, final vs window, 3 alternating rounds, harness logging -> e035_long/
#   (b3) the same resync logged at cn:INFO and net:ERROR, once per arm, untimed, for cap decisions and oversize errors -> e035_logged/
# Expected, fixed before the run: base makes no progress and logs oversize errors; final and window progress with 0 oversize errors and a matching hash. Long: 6/6 hashes; window vs final wall within 2% with overlapping ranges; peak anon ranges overlap. Logged: 0 oversize errors in both arms, every cap line says 4 blocks unless the largest recent block is at or above 11.25 MB, and at least one line has a largest recent block above 10 MB, which is where the window term decides the budget. A miss is reported as a miss.
# Marker: CHAIN_E035B_COMPLETE in e035b.chain
set -u
W0=/home/optimizer/work; R=$W0/research; A=$W0/research-artifacts; C=$A/e035b.chain; S=$R/scripts
T=$W0/monero-fcmp-e035; BD=$T/build/beta31-e035
B=$W0/monero-fcmp/build/beta31/bin/monerod; F=$W0/monero-fcmp-idle/build/beta31-idle/bin/monerod; E=$BD/bin/monerod
SNAP=$A/snapshots/stressnet_wedge_h3105401; DD=$W0/chains/stressnet; PORT=28081
echo "chain e035b waiting for E033 $(date -Is)" > $C
until tail -1 $A/e033.chain 2>/dev/null | grep -q CHAIN_E033_COMPLETE; do sleep 60; done
echo "chain e035b start $(date -Is) load $(cut -d' ' -f1-3 /proc/loadavg)" >> $C
source ~/.cargo/env
export CCACHE_BASEDIR=$W0
rsync -a --exclude build $W0/monero-fcmp-idle/ $T/
( cd $T || exit 1
  git -c user.name=optimizer -c user.email=optimizer@localhost am $R/patches/options/E035-window-cap/*.patch > $A/e035.am.log 2>&1 ) || { echo GIT_AM_FAILED >> $C; echo CHAIN_E035B_COMPLETE >> $C; exit 1; }
TH=$(git -C $T rev-parse 'HEAD^{tree}')
echo "tree $TH expected ced7116caa99fb6321fb48788b83f81370dc44fa" >> $C
[ "$TH" = ced7116caa99fb6321fb48788b83f81370dc44fa ] || { echo TREE_MISMATCH >> $C; echo CHAIN_E035B_COMPLETE >> $C; exit 1; }
mkdir -p $BD; cd $BD || exit 1
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && ninja -j10 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e035.build.log 2>&1
r=$(tail -1 $A/e035.build.log); echo "build $r $(date -Is)" >> $C
[ "$r" = BUILD_OK ] || { echo CHAIN_E035B_COMPLETE >> $C; exit 1; }
cd $A
sha256sum $B $F $E >> $C
df -h /home | tail -1 >> $C
sleep 60
ps -eo comm | grep -qx shadow && echo "lane running" >> $C || echo "no lanes" >> $C
( while kill -0 $$ 2>/dev/null; do ps -eo comm | grep -qx shadow && echo "SHADOW seen $(date -Is)" >> $C; sleep 60; done ) &
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $C
wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
log_height() { grep -oE "Synced [0-9]+/[0-9]+" "$1" | tail -1 | cut -d' ' -f2 | cut -d/ -f1; }
stop_node() { curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null; for i in $(seq 1 30); do kill -0 $1 2>/dev/null || return 0; sleep 1; done; kill -TERM $1 2>/dev/null; for i in $(seq 1 600); do kill -0 $1 2>/dev/null || return 0; sleep 1; done; kill -KILL $1; sleep 3; }
check_tip() { # <bin> <out>
  $1 --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $2/check.log --log-level 0 > /dev/null 2>&1 &
  local MP=$!; wait_rpc
  local x=$(curl -s -m 30 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"get_last_block_header"}')
  local idx=$(echo "$x" | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$')
  local ours=$(echo "$x" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  local theirs=$(curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":${idx:-0}}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  stop_node $MP
  echo "tip=$(( ${idx:--1} + 1 )) hash=$([ -n "$ours" ] && [ "$ours" = "$theirs" ] && echo yes || echo NO)"
}
logged() { # <out> <label> <bin> <end height or 0> <seconds>
  local O=$1 L=$2 BIN=$3 END=$4 SECS=$5 LOG=$1/$2.log; mkdir -p $O
  rm -f $DD/testnet/lmdb/lock.mdb; cp $SNAP/testnet/lmdb/data.mdb $DD/testnet/lmdb/data.mdb
  $S/pop_to.sh $B $DD 3105401 $O/$L.rewind.log
  tail -1 $O/$L.rewind.log | grep -q "RESULT OK" || { echo "[$L] rewind FAILED" >> $C; return 1; }
  $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 > $O/$L.stdout 2>&1 &
  local MP=$!; wait_rpc
  curl -s -m 10 http://127.0.0.1:$PORT/set_log_categories -d '{"categories":"*:WARNING,net:ERROR,net.cn:INFO,cn:INFO,global:INFO"}' > /dev/null
  local t0=$(date +%s) h=0
  while :; do
    h=$(log_height $LOG); h=${h:-0}
    [ "$END" -gt 0 ] && [ "$h" -ge "$END" ] && break
    [ $(( $(date +%s) - t0 )) -ge "$SECS" ] && break
    kill -0 $MP 2>/dev/null || break
    sleep 2
  done
  local dt=$(( $(date +%s) - t0 ))
  stop_node $MP
  local tip=$(check_tip $BIN $O)
  { echo "[$L] secs=$dt log_height=$h $tip oversize_errors=$(grep -c 'Maximum packet size exceed' $LOG) cap_lines=$(grep -c 'capping block sync size' $LOG) requests=$(grep -c 'state: requesting objects' $LOG)"
    grep -oE 'capping block sync size from [0-9]+ to [0-9]+ blocks' $LOG | sort | uniq -c | sort -rn | head -8
    grep -oE 'largest recent block [0-9]+' $LOG | awk '{print $4}' | awk 'BEGIN{m=0} {if($1>m)m=$1; if($1>10000000)a++; if($1>=11250000)b++} END{print "window cap lines: largest W",m,"above 10 MB:",a+0,"at or above 11.25 MB:",b+0}'
  } >> $C
  gzip -f $LOG
}
logged $A/e035_wedge base $B 0 120
logged $A/e035_wedge final $F 0 120
logged $A/e035_wedge window $E 0 120
echo "(b1) wedge control done $(date -Is)" >> $C
REWIND_SNAPSHOT=$SNAP $S/ab_window.sh $A/e035_long 3123400 14400 3 "final|$F|" "window|$E|"
echo "(b2) long done $(date -Is)" >> $C
logged $A/e035_logged final $F 3123400 3000
logged $A/e035_logged window $E 3123400 3000
echo "(b3) logged done $(date -Is)" >> $C
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored $OLDGOV" >> $C
python3 -I $S/ab_stats.py $A/e035_long/results.csv final >> $C 2>&1
python3 -I $S/e023_wall.py $A/e035_long 3105406 3123400 final window >> $C 2>&1
echo "done $(date -Is)" >> $C
echo CHAIN_E035B_COMPLETE >> $C
