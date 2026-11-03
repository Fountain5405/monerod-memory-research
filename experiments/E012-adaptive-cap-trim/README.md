# E012: make the batch cap and the trim adaptive to proof size ("adapt")

**Why:** E011 showed that the combo's +15% on small-tx blocks comes mostly from the two cheap fixes:
- the batch cap at physical cores: +7.3%;
- the per-block malloc_trim: +6.0%.

Both were designed around the old stored verifier's ~250 MB per-proof working set. On 2-input proofs memory is small anyway, and SMT siblings help.

**Change** (one variant; tree ~/work/monero-fcmp-adapt, branch combo-adapt, commit 4a51d434d on top of the combo; diff in evidence/E012/e012.diff, ~20 lines in `rct::batchVerifyFcmpPpProofs`):
- `heavy_call` = the largest proof in the call has ≥ 16 inputs. The inputs are already sorted by input count, descending, so this reads `front()`.
- Cap at physical cores only for heavy calls. Light calls use the whole pool, as base does.
- Trim after every heavy call. Otherwise trim at most once every 10 s (steady_clock, relaxed atomic).
- The verification logic is untouched: the same batches are verified and their results AND-ed. Only the thread count and the trim timing change.
- The threshold of 16 is a judgment call; it was not swept. In the small-tx window only 4 of 1,000 blocks hold a proof with ≥ 16 inputs. In the heavy window 82% of txs have 128 inputs.

**Method:**
- `--block-sync-size 5` everywhere, 3 alternating rounds, governor pinned, no shadow lanes.
- (a) Small-tx window 3,106,400 → 3,107,400 (snapshot h3106400): base, combo, adapt.
- (b) Heavy window 3,105,401 → 3,105,441 (wedge snapshot): combo, adapt, e007. Here e007 means the streaming verifier with no cap and no trim.

**Results** (medians of 3, min-max; all 18 hashes match .22; evidence/E012/ab_stats_*.txt):

(a) Small-tx window, 1,000 blocks:

| arm | wall s | vs base | peak RssAnon MB | post-idle MB | CPU s |
|---|---|---|---|---|---|
| base | 151 (149-151) | | 1,167 (1,152-1,226) | 1,110 | 1,325 |
| combo | 174 (173-180) | +15.2% | 732 (728-735), -37% | 725 | 931 |
| **adapt** | **157 (155-157)** | **+4.0%** | **822 (816-829), -30%** | 767 | 1,431 |

(b) Heavy window, 40 blocks of mostly 128-input txs:

| arm | wall s | peak RssAnon MB | post-idle MB | CPU s |
|---|---|---|---|---|
| combo | 110 (110-111) | 1,861 (1,769-1,893) | 1,107 | 904 |
| **adapt** | **109 (106-111)** | **1,639 (1,607-1,697)**, -12% vs combo | 1,333 (+20%) | 902 |
| e007 (no cap, no trim) | 111 (111-111) | 2,338 (2,111-2,340), +26% vs combo | 2,300 | 1,759 |

**Reading:**
- **adapt recovers about 3/4 of the small-tx slowdown** (+4.0% vs +15.2%). What is left is about E007's double-build cost (+2.7% in E011). It gives up ~90 MB of the combo's small-block memory saving, because it trims at most every 10 s, but stays 30% below base there.
- **On the heavy window adapt is no worse than the combo** (wall 109 vs 110 s). Its peak was even 12% lower, with disjoint ranges. I do not have a mechanism for that, since both builds take the same path on heavy calls. It may be glibc arena-placement variance across sessions (the combo's window peak was 1,751 median in E008 and 1,861 here). Treat it as "no worse", not as a gain.
- **With E007 in, the cap no longer speeds up the heavy window** (e007 111 s vs combo 110 s). It still halves CPU seconds (1,759 → 904: half the SMT siblings sit idle) and, together with the trim, cuts the window peak ~20-30% below E007 alone (2,338 → 1,639-1,861 MB).
- **Post-idle is higher for adapt** (1,333 vs 1,107 MB): after the last light calls nothing triggers a trim while idle. Possible refinement: one trim when sync goes idle (e.g. on the switch to synchronized), or a timer. Not pursued yet; it is still -72% vs base's ~4.8 GB idle.

**Decision:** adapt is the candidate recommended build. It passed the E013 gate: heavy peak ≤ 1.10x the combo's, small-tx wall ≤ 1.08x base's. E013 validates it the same way the combo was validated: a heavy-window A/B vs base, the negtest, min_mem, and the long resync.
