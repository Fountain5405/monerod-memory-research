#!/bin/bash
# usage: sample.sh <pid> <rpc_port> <outfile> [interval_s]
P=$1; PORT=$2; OUT=$3; I=${4:-10}
echo "ts,height,target,VmRSS_kB,VmHWM_kB,RssAnon_kB,RssFile_kB,RssShmem_kB,VmSwap_kB,threads,priv_dirty_kB" > $OUT
while kill -0 $P 2>/dev/null; do
  info=$(curl -s -m 5 http://127.0.0.1:$PORT/get_info 2>/dev/null)
  h=$(echo "$info" | grep -o "\"height\": [0-9]*" | head -1 | grep -o "[0-9]*$")
  t=$(echo "$info" | grep -o "\"target_height\": [0-9]*" | grep -o "[0-9]*$")
  s=$(awk "/^(VmRSS|VmHWM|RssAnon|RssFile|RssShmem|VmSwap|Threads):/{printf \"%s,\", \$2}" /proc/$P/status 2>/dev/null)
  pd=$(awk "/^Private_Dirty:/{print \$2}" /proc/$P/smaps_rollup 2>/dev/null)
  echo "$(date +%s),${h:-},${t:-},${s}${pd:-}" >> $OUT
  sleep $I
done
echo "# process exited $(date)" >> $OUT
