#!/bin/bash
# exits (printing why) when either sync process dies or reaches its target height
while true; do
  for f in ~/work/bench/mem/stagenet_sync_baseline.csv ~/work/bench/mem/stressnet_sync_beta31.csv; do
    if grep -q "^# process exited" $f; then echo "EXITED: $f"; tail -3 $f; exit 0; fi
    l=$(tail -1 $f); h=$(echo $l | cut -d, -f2); t=$(echo $l | cut -d, -f3)
    if [ -n "$h" ] && [ -n "$t" ] && [ "$t" -gt 0 ] && [ "$h" -ge "$t" ]; then echo "SYNCED: $f"; echo $l; exit 0; fi
    age=$(( $(date +%s) - $(echo $l | cut -d, -f1) ))
    if [ $age -gt 300 ]; then echo "SAMPLER STALE (${age}s): $f"; echo $l; exit 0; fi
  done
  sleep 60
done
