# E011: where does the combo's small-tx slowdown come from? (one change per arm)

**Why:** E010 found the combo build +14.8% slower than base on the ~8,000 dense small-tx blocks after the window (F22), although it is 2x faster on the 128-input window. The combo has three performance-relevant changes:
- E004c: FCMP++ batch count capped at physical cores.
- E004e: malloc_trim(0) after every batch-verify call (once per block).
- E007: streaming verifier, which builds every circuit twice.

**Window:** 3,106,400 → 3,107,400 (1,000 blocks). Input mix via .22 RPC reads (evidence/E011/window_inputs_3106400-3107399.txt):
- 28,891 txs, mean 2.01 inputs: 28,186 2-input, 685 1-input, 2 4-input, 6 8-input, 5 16-input, 1 64-input, 6 128-input.
- Only 4 blocks hold a proof with ≥ 16 inputs.

**Method:**
- Each run restores the working DB from snapshots/stressnet_h3106400, a deletable working snapshot made by syncing base from the wedge snapshot and popping to exactly 3,106,400. pop_to.sh verified the hash against .22: RESULT OK.
- All arms use `--block-sync-size 5`. An explicit size bypasses the E001 cap, so the E001 fix is inert here.
- 3 alternating rounds (ABCDE / EDCBA / ABCDE), governor pinned, no shadow lanes (watcher logged none).
- ab_window.sh v4 adds START_H and a cpu_s column (monerod utime + stime at the end of the sync).

**Arms:**
- base: beta.3.1
- e004c: cap
- e004e: cap + trim
- e007: streaming verifier alone
- combo: all of the above + E001 fix

**Results** (medians of 3, min-max; all 15 hashes match .22; evidence/E011/ab_stats.txt):

| arm | wall s | vs base | CPU s | peak RssAnon MB | post-idle RssAnon MB |
|---|---|---|---|---|---|
| base | 150 (147-151) | | 1,322 | 1,178 (1,036-1,461) | 1,106 |
| e004c (cap) | 161 (160-161) | **+7.3%** | 832 (-37%) | 1,284 (1,194-1,459), overlaps base | 1,113 |
| e004e (cap + trim) | 170 (166-170) | **+13.3%** | 845 | 724 (721-729), -38.5% | 721 |
| e007 (streaming) | 154 (154-157) | **+2.7%** | 1,435 (+8.5%) | 918 (918-934), -22% | 918 |
| combo | 172 (172-172) | **+14.7%** | 930 | 722 (720-733), -38.7% | 714 |

All ranges are tight (≤ 4 s), so every step is well outside the noise.

**Attribution of the combo's +22 s per 1,000 small-tx blocks:**

| change | cost | evidence |
|---|---|---|
| cap | +11 s | e004c − base |
| trim | +9 s | e004e − e004c; ~9 ms per block |
| streaming verifier (on top of c+e) | +2 s | combo − e004e; alone +4 s |

The effects are close to additive. **The streaming verifier's double build is a minor cost here (~3%). Most of the regression comes from the two cheap fixes.** Those were designed around the old stored verifier, whose per-proof working set is ~250 MB on 128-input proofs.

**Interpretation:**
- **The cap.** On 2-input proofs, SMT siblings do help. Base finishes faster with 24 batches than the cap does with 12, even though it burns 37% more CPU seconds. CPU seconds are not comparable across thread counts, because a hyperthread's time counts in full while it shares a core, so wall is the metric. On 128-input proofs the cap was 9% *faster* (E004c), plausibly because the huge vectors thrash the cache an SMT pair shares. So the right cap depends on proof size.
- **The trim.** ~9 ms per block. Some of that is the malloc_trim call itself, which walks every arena and madvises free pages. Some of it is the re-faulting of pages the next block allocates again. E011 cannot separate the two. Either way, trimming after every light block buys little: memory is already small there.
- **The memory picture on small txs.** Base sits at 1.0-1.5 GB. The cap alone does not reduce it, because retention is per arena (as in E004c). The trim brings it to ~0.72 GB. E007 alone gives 0.92 GB.

**Next:** E012 makes the cap and the trim adaptive to proof size:
- cap only when the largest proof in the call has ≥ 16 inputs;
- trim after such heavy calls, and otherwise at most once every 10 s.

It is measured on this window and on the heavy window. The goal is to keep the combo's window memory win and drop the small-tx cost.
