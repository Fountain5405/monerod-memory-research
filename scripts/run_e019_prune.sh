#!/bin/bash
# E019 prep on hydrogen: a pruned copy of the wedge snapshot for box81 (the 18 GB unpruned DB does not fit there:
# 21 GB free on a shared volume). Runs during E018's build phase so no timing run is disturbed: waits for the
# "starting" line in e018.chain, builds monero-blockchain-prune in the beta31 tree (nice -n 19, -j3; only
# blockchain_utilities compiles, the libs exist), prunes via a scratch data dir whose testnet/lmdb is a symlink to
# the snapshot (the tool opens the source MDB_RDONLY and writes <data-dir>/testnet/lmdb-pruned), then moves the
# result to snapshots/stressnet_wedge_h3105401_pruned. The baseline snapshot is never written to (only its
# lock.mdb reader table). Marker ~/work/research-artifacts/e019.prune ends PRUNE_OK or PRUNE_FAILED.
set -u
A=/home/optimizer/work/research-artifacts
M=$A/e019.prune
SNAP=$A/snapshots/stressnet_wedge_h3105401
OUT=$A/snapshots/stressnet_wedge_h3105401_pruned
SCR=$A/e019_prune_scratch
BD=/home/optimizer/work/monero-fcmp/build/beta31
echo "prune prep start $(date -Is); waiting for the E018 build to start" > $M
until grep -q "starting" $A/e018.chain 2>/dev/null; do sleep 30; done
echo "E018 build started; building monero-blockchain-prune $(date -Is)" >> $M
source ~/.cargo/env
( cd $BD && nice -n 19 ninja -j3 monero-blockchain-prune ) > $A/e019.prune.build.log 2>&1 \
  || { echo "tool build FAILED (see e019.prune.build.log)" >> $M; echo PRUNE_FAILED >> $M; exit 1; }
echo "tool built $(date -Is)" >> $M
rm -rf $SCR; mkdir -p $SCR/testnet; ln -s $SNAP/testnet/lmdb $SCR/testnet/lmdb
df -h /home | tail -1 >> $M
nice -n 19 $BD/bin/monero-blockchain-prune --testnet --data-dir $SCR > $A/e019.prune.log 2>&1
rc=$?
echo "prune rc=$rc $(date -Is)" >> $M
tail -3 $A/e019.prune.log | cut -c1-200 >> $M
if [ $rc = 0 ] && [ -f $SCR/testnet/lmdb-pruned/data.mdb ]; then
  mkdir -p $OUT/testnet && mv $SCR/testnet/lmdb-pruned $OUT/testnet/lmdb && rm -rf $SCR
  echo "pruned copy: $(du -sh $OUT | cut -f1) on disk, $(ls -l $OUT/testnet/lmdb/data.mdb | awk '{printf "%.1f GB", $5/1e9}') apparent, at $OUT" >> $M
  df -h /home | tail -1 >> $M
  echo PRUNE_OK >> $M
else
  echo PRUNE_FAILED >> $M
fi
