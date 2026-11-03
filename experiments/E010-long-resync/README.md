# E010: long resync 3,105,401 → 3,123,400 (18,000 blocks), base vs combo

**Why:** the 40-block window is a worst case (82% of txs are 128-input). After the window come about 8,000 more dense blocks (190k txs, 1.9 GB of block weight in 3,105,401..3,113,400), mostly smaller txs (~9-18 KB each), then nearly empty blocks up to the tip. This run checks that:
- (1) the memory win holds over a long, mixed workload, with no growth or leak from the trim or the accumulator;
- (2) E007's double build does not make small-input-heavy blocks slower (queue item E, at macro level);
- (3) the E001 fix lets the combo build sync with DEFAULT settings, where base wedges at 3,105,401.

**Arms (1 run each; a validation run, not the headline A/B):**
- combo_default: no `--block-sync-size`. The E001 cap gives 4-block batches; the log shows Synced increments of 4 from the start.
- base_bss5: `--block-sync-size 5`, because base's defaults wedge (E001).
- combo_bss5: same settings as base.

Every run restores the working DB from snapshots/stressnet_wedge_h3105401 (ab_window.sh v3, REWIND_SNAPSHOT), then pop_to.sh verifies the hash at 3,105,400 against .22. Governor pinned. Per-run timeout 4 h. Chain: scripts/run_e010.sh; log ~/work/research-artifacts/e010.chain.

**Prediction:**
- Peak anon is set by the window: base ~5.3 GB, combo ~1.8 GB.
- Post-idle at the end: base multi-GB, combo < 1.2 GB.
- Wall: combo < base. Most of the remaining work is small-input txs, so expect the ratio to be much smaller than 2x. If combo turns out slower on the small-tx stretch, that prices E007's double build.

**Results:** (pending)
