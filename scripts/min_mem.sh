#!/bin/bash
# Minimum-memory test: binary search for the smallest cgroup MemoryMax (swap disabled) at which the
# FCMP++ window (3,105,401 -> END) still syncs within FACTOR x the reference wall time and ends on
# .22's block hash. cgroup memory includes page cache (LMDB pages, dirty pages), so this measures the RAM
# the node really needs, not just its heap.
# usage: min_mem.sh <outdir> <label> <monerod> <ref_wall_s> <lo_MB> <hi_MB> <tol_MB> [extra monerod args]
#   lo should FAIL, hi should PASS (both are verified first). FACTOR=1.10 (env FACTOR overrides).
# Output: <outdir>/<label>.csv (limit_MB,result,wall_s,end_h,hash_match,peak_cgroup_MB,oom_kills)
# Completion marker: last line of <outdir>/<label>.summary is MINMEM_COMPLETE.
# v2 (2026-11-03): oom_kill count polled inside the loop (v1 read it after the scope was already gone -> always 0).
set -u
OUT=$1; L=$2; BIN=$3; REF=$4; LO=$5; HI=$6; TOL=$7; shift 7; EXTRA="$*"
FACTOR=${FACTOR:-1.10}
END=3105441; TO=900
DD=/home/optimizer/work/chains/stressnet
POPBIN=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
PORT=28081
mkdir -p $OUT
CSV=$OUT/$L.csv; S=$OUT/$L.summary
echo "limit_MB,result,wall_s,end_h,hash_match,peak_cgroup_MB,oom_kills" > $CSV
echo "min_mem $L start $(date -Is) bin=$BIN ref=$REF factor=$FACTOR lo=$LO hi=$HI tol=$TOL extra='$EXTRA'" > $S
sha256sum $BIN >> $S
MAXWALL=$(python3 -c "print(int($REF*$FACTOR))")

wait_rpc() { for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:$PORT/get_height | grep -q '"height"' && return 0; sleep 1; done; return 1; }
log_height() { grep -oE "Synced [0-9]+/[0-9]+" "$1" | tail -1 | cut -d' ' -f2 | cut -d/ -f1; }

check_tip() {
  $POPBIN --testnet --data-dir $DD --offline --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT \
    --log-file $OUT/check.log --log-level 0 > /dev/null 2>&1 &
  local MP=$!; wait_rpc
  local r=$(curl -s -m 30 http://127.0.0.1:$PORT/json_rpc -d '{"jsonrpc":"2.0","id":0,"method":"get_last_block_header"}')
  local idx=$(echo "$r" | grep -oE '"height": [0-9]+' | head -1 | grep -oE '[0-9]+$')
  local ours=$(echo "$r" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  local theirs=$(curl -s -m 30 http://192.168.1.22:28081/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_block_header_by_height\",\"params\":{\"height\":${idx:-0}}}" | grep -oE '"hash": "[0-9a-f]+"' | head -1 | cut -d'"' -f4)
  curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
  for i in $(seq 1 120); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  kill -0 $MP 2>/dev/null && kill -TERM $MP
  echo "$(( ${idx:--1} + 1 )) $([ -n "$ours" ] && [ "$ours" = "$theirs" ] && echo yes || echo NO)"
}

trial() {  # trial <limit_MB> -> prints PASS|FAIL, appends to CSV
  local lim=$1 tag=${L}_${1}MB
  ~/work/research/scripts/pop_to.sh $POPBIN $DD 3105401 $OUT/$tag.rewind.log
  if ! tail -1 $OUT/$tag.rewind.log | grep -q "RESULT OK"; then echo "$lim,REWIND_FAIL,,,,," >> $CSV; echo FAIL; return; fi
  local unit=minmem-$L-$lim-$$
  local LOG=$OUT/$tag.log
  sudo systemd-run --quiet --scope --unit=$unit -p MemoryMax=${lim}M -p MemorySwapMax=0 --uid=$(id -u) --gid=$(id -g) \
    $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd \
    --rpc-bind-ip 127.0.0.1 --rpc-bind-port $PORT --log-file $LOG --log-level 0 $EXTRA > $OUT/$tag.stdout 2>&1 < /dev/null &
  local SP=$!
  local MP=
  for i in $(seq 1 60); do
    for p in $(pgrep -x monerod); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "--log-file $LOG" && MP=$p; done
    [ -n "$MP" ] && break; sleep 1
  done
  local cg=/sys/fs/cgroup/system.slice/$unit.scope
  local t0=$(date +%s) h=0 peak=0 ooms=0
  wait_rpc
  while :; do
    h=$(log_height $LOG); h=${h:-0}
    [ -f $cg/memory.peak ] && peak=$(( $(cat $cg/memory.peak) / 1048576 ))
    [ -f $cg/memory.events ] && ooms=$(awk '/^oom_kill /{print $2}' $cg/memory.events)  # v2: poll; the scope vanishes once monerod dies
    [ "$h" -ge "$END" ] && break
    [ $(( $(date +%s) - t0 )) -ge $MAXWALL ] && break
    kill -0 $MP 2>/dev/null || break
    sleep 2
  done
  local t1=$(date +%s)
  [ -f $cg/memory.events ] && ooms=$(awk '/^oom_kill /{print $2}' $cg/memory.events)
  if kill -0 $MP 2>/dev/null; then
    curl -s -m 30 http://127.0.0.1:$PORT/stop_daemon -d '{}' > /dev/null
    for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
    kill -0 $MP 2>/dev/null && kill -TERM $MP
    for i in $(seq 1 300); do kill -0 $MP 2>/dev/null || break; sleep 1; done
  fi
  wait $SP 2>/dev/null
  sudo systemctl stop $unit.scope 2>/dev/null
  local tip=$(check_tip)
  local wall=$((t1 - t0)) res=FAIL
  if [ "$h" -ge "$END" ] && [ $wall -le $MAXWALL ] && [ "${tip#* }" = yes ]; then res=PASS; fi
  echo "$lim,$res,$wall,$h,${tip#* },$peak,${ooms:-0}" >> $CSV
  echo "[$lim MB] $res wall=${wall}s h=$h hash=${tip#* } cgroup_peak=${peak}MB oom_kills=${ooms:-0}" >> $S
  echo $res
}

r=$(trial $HI); [ "$r" = PASS ] || { echo "hi=$HI did not pass; aborting search" >> $S; echo MINMEM_COMPLETE >> $S; exit 0; }
r=$(trial $LO); [ "$r" = FAIL ] || { echo "lo=$LO passed; minimum is <= $LO" >> $S; echo MINMEM_COMPLETE >> $S; exit 0; }
while [ $((HI - LO)) -gt $TOL ]; do
  MID=$(( (LO + HI) / 2 ))
  r=$(trial $MID)
  if [ "$r" = PASS ]; then HI=$MID; else LO=$MID; fi
done
echo "RESULT: minimum passing MemoryMax for $L = $HI MB (largest failing = $LO MB, tol $TOL MB)" >> $S
echo MINMEM_COMPLETE >> $S
