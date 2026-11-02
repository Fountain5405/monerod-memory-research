# E002: attribute the multi-GB heap in the FCMP++ (beta31) daemon

**Observation:** the beta31 node on stressnet holds ~3.9 GB anon when synced (master on stagenet: ~1.85 GB). After a restart at 3,105,401, anon went from 318 MB to 4.6 GB within ~16 s while processing 20 nearly empty blocks (E001 / JOURNAL 2026-11-02 19:10). Run 1 peaked at 5.26 GB near h ≈ 3,103,110, i.e. after HF17 (3,102,800) and before HF18 (3,103,520).

**Hypotheses:**
- H1: something is initialized on startup or first use and retained (FCMP++/curve-tree state, verifier precomputation, RandomX), independent of the sync workload.
- H2: it is sync-specific (tree growth over the HF17/HF18 window, batch state) and only shows when replaying that window.
- H3: it is allocator retention (freed but not returned to the OS); heaptrack's live-heap peak would then be far below RssAnon.

## E002a: restart the synced node under heaptrack
- DB: ~/work/chains/stressnet at height 3,123,270 (synced). A pristine copy is in ~/work/research-artifacts/snapshots/stressnet_synced_h3123270.
- Binary: beta31 (sha256 in run.txt). Same flags as E000 plus `--block-sync-size 5` (the E001 workaround), under heaptrack 1.5.0, for 600 s, then stopped via stop_daemon.
- Command: `scripts/run_heaptrack.sh E002a-restart-synced 600 ~/work/monero-fcmp/build/beta31/bin/monerod ~/work/chains/stressnet --block-sync-size 5`
- Prediction: if anon jumps to multiple GB again → H1, and heaptrack names the allocator. If not → H2, so go to E002b.

## E002b (if needed): replay the HF17/HF18 window under heaptrack
Copy the snapshot, pop back to before 3,102,800, then sync forward under heaptrack.

**Results:** (pending)
