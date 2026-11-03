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

**Results (2026-11-03 05:00; 1 run per arm; every end hash matches .22; no shadow lanes; governor pinned):**

| arm | blocks | wall s | peak RssAnon MB | peak Private_Dirty MB | post-idle RssAnon MB | write MB |
|---|---|---|---|---|---|---|
| base_bss5 | 18,059 | 1,365 | 5,603 | 5,603 | 4,376 | 9,394 |
| combo_bss5 | 18,149 | 1,414 (**+3.6%**) | 1,503 (**-73.2%**) | 1,530 (-72.7%) | 1,085 (**-75.2%**) | 9,405 (+0.1%) |
| combo_default | 18,125 | 1,446 (+5.9%) | 1,588 (-71.7%) | 1,637 (-70.8%) | 1,301 (-70.3%) | 10,027 (+6.7%) |

The end heights differ slightly because the loop stops on the first log line at or above 3,123,400. In the near-empty tail that overshoot costs well under a second.

**Per-segment seconds** (scripts/segment_rates.py, from the `Synced H/T` log lines; evidence/E010/segments.txt):

| segment | blocks | base_bss5 | combo_bss5 | combo_default |
|---|---|---|---|---|
| window (to 3,105,441; 82% of txs 128-input) | 40 | 217 | 108 (-50%) | 113 (-48%) |
| dense small-tx stretch 3,105,441..3,113,400 (8 segments) | 7,959 | 1,071 | 1,230 (**+14.8%**) | 1,247 (+16.4%) |
| near-empty tail 3,113,400..3,123,400 | 10,000 | 73 | 73 (0%) | 83 (+14%) |
| total | | 1,362 | 1,411 | 1,442 |

Every one of the 8 dense 1,000-block segments is slower in combo (+13% to +19% each), so this is systematic, not noise. Net for combo_bss5: -109 s in the window, +159 s on small-tx blocks, 0 s in the tail.

**Memory over the run** (scripts/mem_segments.py; evidence/E010/mem_segments.txt):
- All three arms peak inside the window: combo at 3,105,431-436, base at 3,105,441.
- After the window, combo plateaus: 0.8-1.1 GB for bss5, 1.0-1.3 GB for default. There are one or two ~250 MB step-ups and then it stays flat; there is no trend over 18,000 blocks. **No leak or growth from the per-block trim or the accumulator.**
- Base stays at 4.3-4.5 GB the whole way: arena retention, as in E004.

**Predictions:**
- Peak set by the window: **held** (base 5.6 GB; combo 1.5-1.6 GB).
- Post-idle: base multi-GB (4.4 GB), combo < 1.2 GB: **held** for bss5 (1,085 MB). Default was 1,301 MB, just over, within the 673-1,301 MB run-to-run range seen so far.
- Wall combo < base: **FALSIFIED.** Combo is 3.6% slower overall. The window's 2x gain is outweighed by a ~15% slowdown on the ~8,000 small-tx blocks. This prices the small-input cost that queue item E was asking about: it is real, and too large to dismiss. **E011 attributes it per change**: base vs e004c (thread cap), e004e (adds the trim), e007 (double build) and combo, over 3,106,400 → 3,107,400 with 3 alternating rounds.
- Overall wall stays within the ~10% guardrail (+3.6%). The small-tx regression is a trade-off to report, not a guardrail failure.

**E001 fix at length:** with default sync settings, combo_default synced all 18,125 blocks without wedging. Base wedges at 3,105,401 with default settings (E001).
- Batch sizes (Synced increments):
  - In the window: 1-block ×12 and 4-block ×6. Upstream adaptive sizing drops to 1 block while heavy blocks are in its lookback.
  - Afterwards: 4-block ×4,471, 2-block ×49, 1-block ×103.
- Cost of default sizing vs an explicit `--block-sync-size 5`: window +5% (113 vs 108 s), small-tx stretch +1.4%, tail +14% (+10 s), disk writes +6.7% (more, smaller DB commits).
- The 03:37 worry (1-block batches at ~7 s/block) turned out minor over the whole run.

Evidence: evidence/E010/ (results.csv, summary.txt, the three mem.csv files, segments.txt, mem_segments.txt, batch_increments.txt). The raw logs (0.5-0.7 MB each) stay on hydrogen under ~/work/research-artifacts/e010/.
