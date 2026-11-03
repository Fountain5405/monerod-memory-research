#!/bin/bash
# Flat CPU profile of a monerod build syncing the FCMP++ window (3,105,401 -> 3,105,441); generalized from e006_profile.sh.
# usage: profile_window.sh <outdir> <monerod> <wait file> <wait marker>
# perf -F 199, all threads, no call graphs. Output: perf_symbols.txt (self time by symbol). Marker: last line of
# <outdir>/summary.txt is PROFILE_COMPLETE.
set -u
D=$1; BIN=$2; WF=$3; WM=$4
mkdir -p $D; S=$D/summary.txt
DD=/home/optimizer/work/chains/stressnet
PORT=28081
echo "profile queued $(date -Is) bin=$BIN $(sha256sum $BIN | cut -c1-16)" > $S
until tail -1 $WF 2>/dev/null | grep -q "$WM"; do sleep 30; done
echo "start $(date -Is)" >> $S
pgrep -fa shadow | grep -v pgrep >> $S || echo "no shadow processes" >> $S
OLDGOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
sudo cpupower frequency-set -g performance > /dev/null && echo "governor $OLDGOV -> performance" >> $S
~/work/research/scripts/pop_to.sh /home/optimizer/work/monero-fcmp/build/beta31/bin/monerod $DD 3105401 $D/rewind.log
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
sudo cpupower frequency-set -g $OLDGOV > /dev/null && echo "governor restored to $OLDGOV" >> $S
sudo chown $(id -u):$(id -g) $D/perf.data
perf report -i $D/perf.data --stdio --no-children --sort symbol --percent-limit 0.05 2>/dev/null > $D/perf_symbols.txt
perf report -i $D/perf.data --stdio --no-children --sort dso --percent-limit 0.5 2>/dev/null > $D/perf_dso.txt
echo "samples: $(grep -m1 -oE 'of event .cycles.*|Samples: [0-9KM]+' $D/perf_symbols.txt)" >> $S
echo PROFILE_COMPLETE >> $S
