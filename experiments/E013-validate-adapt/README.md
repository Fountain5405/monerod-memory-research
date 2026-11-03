# E013: validate "adapt" (E012) as the recommended build

**Why:** E012's adapt build (the combo with an adaptive batch cap and trim) kept the combo's heavy-window memory and dropped most of its small-tx cost. Before calling it the recommended build, it gets the same validation the combo got.

**Gate** (scripts/gate_e012.py, on the E012 data; PASSED 09:15): heavy peak adapt 1,639 vs combo 1,861 MB (-11.9%, at most 1.10x allowed); small-tx wall adapt 157 vs base 151 s (+4.0%, at most 1.08x allowed); n = 3.

Chain: scripts/run_e013.sh (log evidence/E013/e013.chain.txt). The governor was pinned for the timing parts and no shadow lanes ran.

## (a) Heavy-window A/B, base vs adapt, 3 alternating rounds (3,105,401 → 3,105,441, `--block-sync-size 5`)

| metric (median, min-max) | base | adapt | change |
|---|---|---|---|
| peak RssAnon MB | 5,600 (5,403-5,617) | 1,780 (1,762-1,816) | **-68.2%**, ranges disjoint |
| peak Private_Dirty MB | 5,601 | 1,804 | -67.8% |
| peak RSS MB | 6,883 | 2,987 | -56.6% |
| post-window idle RssAnon MB | 4,993 (4,462-5,000) | 1,368 (1,354-1,398) | -72.6% |
| wall s | 222 (221-222) | 111 (110-112) | **-50.0%** |
| CPU s | 4,258 | 904 | -78.8% |
| write MB | 466 | 466 | 0 |
| hashes match .22 | 3/3 | 3/3 | |

adapt's peak here (1,780) is above its E012 median (1,639). So the 12% gap vs the combo seen in E012 was session variance; on heavy blocks adapt ≈ combo (combo medians: 1,751 in E008, 1,861 in E012).

## (b) Negative test (scripts/negtest.sh): PASS
- At 3,105,424, a 128-input tx: 8/8 tampered rejected, original accepted.
- At 3,105,414, an 8-input and a 2-input tx: 16/16 tampered rejected, originals accepted.
- adapt's log shows "Failed to verify input FCMP++ signatures" 8 + 16 times, so every rejection happened at the proof check.
- The step took 23 s; it is fast because adapt verifies a 128-input proof in ~2 s.

## (c) Minimum cgroup MemoryMax (scripts/min_mem.sh; ref wall 109 s, factor 1.10, swap off)

| limit MB | result | wall s | cgroup peak MB | OOM kills |
|---|---|---|---|---|
| 4,000 | PASS | 116 | 1,673 | 0 |
| 750 | FAIL | 4 | 368 | 1 |
| 2,375 | PASS | 105 | 1,912 | 0 |
| 1,562 | FAIL | 51 | 1,464 | 1 |
| 1,968 | PASS | 108 | 1,846 | 0 |
| 1,765 | FAIL | 48 | 1,609 | 1 |
| 1,866 | PASS | 108 | 1,856 | 0 |

**Minimum = 1,866 MB** (largest fail 1,765). This is the same grid point as the combo (E009), so at 125 MB resolution they are equal. That is **-67.5% vs base's 5,750 MB**. Every fail is an OOM kill, and at the minimum the wall is unchanged.

## (d) Long resync 3,105,401 → 3,123,400, 1 run per arm (DB restored from the wedge snapshot each run)

| arm | blocks | wall s | peak RssAnon MB | post-idle MB | write MB | CPU s | hash |
|---|---|---|---|---|---|---|---|
| base_bss5 | 18,234 | 1,345 | 5,613 | 4,642 | 9,412 | 13,581 | yes |
| adapt_bss5 | 18,289 | 1,283 (**-4.6%**) | 1,657 (**-70.5%**) | 1,379 (-70.3%) | 9,419 | 10,931 | yes |
| adapt_default | 18,063 | 1,305 (-3.0%) | 1,663 (-70.4%) | 1,267 (-72.7%) | 10,020 (+6.5%) | 10,962 | yes |

Per segment (scripts/segment_rates.py):

| segment | base_bss5 | adapt_bss5 | adapt_default |
|---|---|---|---|
| heavy window (to 3,105,441) | 219 s | 108 s | 111 s |
| dense small-tx 3,105,441..3,113,400 | 1,051 s | 1,099 s (**+4.6%**; the combo was +14.8% in E010) | 1,111 s |
| near-empty tail to 3,123,400 | 73 s | 72 s | 80 s |

Memory per segment (scripts/mem_segments.py):
- adapt peaks in the window (1,657-1,664 MB).
- After it, adapt stays at 1.3-1.6 GB (medians 1,300-1,455) with no upward trend over 18,000 blocks.
- This is ~0.3-0.4 GB above the combo's 0.8-1.1 GB in E010, because adapt trims at most every 10 s on light blocks.
- Base stays at 4.5-4.7 GB.

**Base reproducibility:** base_bss5 gave 1,345 s / 5,613 MB here and 1,365 s / 5,603 MB in E010.

## Conclusion
adapt passes every guardrail and keeps the full memory win:
- heavy-window peak -68%;
- long-run peak -70%;
- minimum cgroup -67.5%.

The combo's speed regression is gone: the long resync is 4.6% faster than base. **adapt is the recommended build.** Remaining validation: E015, a differential negative test with base as the oracle and many more cases; E014, whether the win holds at 1-4 threads.
