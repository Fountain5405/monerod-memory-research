#!/bin/bash
# usage: run_heaptrack.sh <label> <duration_s> <monerod> <datadir> [extra monerod args...]
# Runs a testnet monerod (exclusive peer 192.168.1.22:28080) under heaptrack for <duration_s>,
# samples /proc every 5 s, then stops it via RPC and waits for heaptrack to finish writing.
# Artifacts -> ~/work/research-artifacts/<label>/ ; "DONE" is the last line of run.txt when finished.
set -u
L=$1; DUR=$2; BIN=$3; DD=$4; shift 4
A=~/work/research-artifacts/$L; mkdir -p $A
LOG=$A/monerod.log
{
  echo "start $(date -Is) label=$L dur=$DUR bin=$BIN datadir=$DD extra=$*"
  sha256sum $BIN
  heaptrack --version
  uptime; free -m | sed -n 2p
  pgrep -fa shadow | grep -v pgrep || echo "no shadow processes"
} > $A/run.txt
heaptrack -o $A/heaptrack.$L $BIN --testnet --data-dir $DD --add-exclusive-node 192.168.1.22:28080 \
  --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --log-file $LOG --log-level 0 "$@" > $A/stdout.txt 2>&1 &
HT=$!
PID=
for i in $(seq 1 60); do
  for p in $(pgrep -x monerod); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "--data-dir $DD" && PID=$p; done
  [ -n "$PID" ] && break; sleep 1
done
if [ -z "$PID" ]; then echo "monerod PID not found; FAILED" >> $A/run.txt; echo DONE >> $A/run.txt; exit 1; fi
echo "monerod pid=$PID heaptrack wrapper pid=$HT" >> $A/run.txt
~/work/research/scripts/sample.sh $PID 28081 $A/mem.csv 5 $LOG &
sleep $DUR
echo "stopping $(date -Is)" >> $A/run.txt
curl -s -m 60 http://127.0.0.1:28081/stop_daemon -d '{}' >> $A/run.txt; echo >> $A/run.txt
for i in $(seq 1 600); do kill -0 $PID 2>/dev/null || break; sleep 1; done
if kill -0 $PID 2>/dev/null; then echo "monerod did not exit after 600 s; sending SIGTERM" >> $A/run.txt; kill $PID; fi
wait $HT
echo "heaptrack wrapper exit=$? $(date -Is)" >> $A/run.txt
ls -la $A >> $A/run.txt
echo DONE >> $A/run.txt
