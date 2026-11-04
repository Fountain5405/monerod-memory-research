#!/bin/bash
# Records cumulative CPU ticks against the log's sync height for the running A/B node, every 0.5 s, so CPU can be compared over
# identical heights. Writes <run>.cpu.csv next to the run's log. usage: cpu_watch.sh <parent pid>
P=$1
while kill -0 $P 2>/dev/null; do
  pid=$(pgrep -f "e022_bins/monerod-t[0-9]+ .*--add-exclusive-node" | head -1)
  if [ -n "$pid" ]; then
    log=$(tr '\0' '\n' < /proc/$pid/cmdline 2>/dev/null | grep -A1 -- '^--log-file$' | tail -1)
    if [ -n "$log" ] && [ -f "$log" ]; then
      h=$(grep -oE 'Synced [0-9]+' "$log" | tail -1 | cut -d' ' -f2)
      c=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null)
      [ -n "$c" ] && echo "$(date +%s.%N),${h:-0},$c" >> "${log%.log}.cpu.csv"
    fi
  fi
  sleep 0.5
done
