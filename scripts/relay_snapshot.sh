#!/bin/bash
# Control-box relay: stream hydrogen's unpruned wedge snapshot (18.9 GB data.mdb) to box81 during E018's build phase
# (box81 cannot reach hydrogen directly). Waits for the "starting" line in hydrogen's e018.chain, streams with nice
# on the hydrogen side, checks sizes, makes the box81 working copy, writes the e019.db marker that run_e019.sh waits on.
set -u
L=/tmp/claude-1004/-home-optimizer/8df9b52f-f5cd-4ba5-9266-b5baabbb51ec/scratchpad/e019/relay_snapshot.log
SRC=/home/optimizer/work/research-artifacts/snapshots/stressnet_wedge_h3105401/testnet/lmdb/data.mdb
DST=/home/optimizer/work/research-artifacts/snapshots/stressnet_wedge_h3105401/testnet/lmdb
WRK=/home/optimizer/work/chains/stressnet/testnet/lmdb
echo "relay waiting for E018 build start $(date -Is)" > $L
until ssh hydrogen 'grep -q starting ~/work/research-artifacts/e018.chain' < /dev/null 2>/dev/null; do sleep 60; done
echo "E018 build started; streaming $(date -Is)" >> $L
SZ=$(ssh hydrogen "stat -c %s $SRC" < /dev/null)
ssh box81 "mkdir -p $DST $WRK" < /dev/null
ssh hydrogen "nice -n 19 cat $SRC" < /dev/null | ssh box81 "cat > $DST/data.mdb" < /dev/null
RSZ=$(ssh box81 "stat -c %s $DST/data.mdb" < /dev/null)
echo "streamed $(date -Is): src $SZ bytes, dst $RSZ bytes" >> $L
if [ "$SZ" = "$RSZ" ]; then
  ssh box81 "cp $DST/data.mdb $WRK/data.mdb && df -h /home | tail -1 && echo \"wedge snapshot h3105401 unpruned, $RSZ bytes, streamed from hydrogen $(date -Is); working copy made\" > /home/optimizer/work/research-artifacts/e019.db" < /dev/null >> $L 2>&1
  echo "RELAY_OK $(date -Is)" >> $L
else
  echo "RELAY_FAILED size mismatch" >> $L
fi
