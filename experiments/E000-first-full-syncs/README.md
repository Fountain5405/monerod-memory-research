# E000: first full verifying syncs (observational)

**Purpose:** get first memory traces across whole chains, produce local chain copies for snapshots, and find where memory peaks. Not an A/B experiment.

**Setup (2026-11-02):**
- stagenet: master 3fd0f88c2 build, public peers, started 11:42.
  `~/work/monero/build/baseline/bin/monerod --stagenet --data-dir ~/work/chains/stagenet --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --log-file ~/work/chains/stagenet_baseline.log --log-level 0`
- stressnet: beta31 build, exclusive LAN peer, started 11:50.
  `~/work/monero-fcmp/build/beta31/bin/monerod --testnet --data-dir ~/work/chains/stressnet --add-exclusive-node 192.168.1.22:28080 --non-interactive --no-igd --rpc-bind-ip 127.0.0.1 --log-file ~/work/chains/stressnet_beta31.log --log-level 0`
- Sampler: scripts/sample.sh at 10 s. Live traces: ~/work/bench/mem/{stagenet_sync_baseline,stressnet_sync_beta31}.csv (copied into evidence/ when the runs end).
- Both trees ship empty stagenet/testnet `*_blocks.dat`, so every block is fully verified.

**Confounders:** the two syncs run at the same time and share CPU and page cache, and the stagenet peer set is uncontrolled. Treat these numbers as qualitative.

**Observations:** see JOURNAL.md, 2026-11-02.

**Status:** running.
