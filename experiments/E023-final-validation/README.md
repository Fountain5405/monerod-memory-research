# E023: validation of the final v1 series

**Status: done, with one miss. Heavy-window peak, negative test, cgroup minimum, long resync and all hashes meet the expectations fixed before the run. Small-tx wall does not: +6.6% against base, expected no more than +6%. E023b finds the last two patches are not responsible: the gap is adapt's own cost on this window, and E012's +4.0% understated it.**

**Why:** the recommended build gained E021 (idle trim) and E022 (threshold 8) after E013 validated it. E013's negative test, cgroup minimum and long resync all predated those patches, and carrying them over was an argument from the code, not a test.

**Setup:** hydrogen, 2026-11-04 05:10-08:12, `scripts/run_e023.sh`. Arms: **base** (sha 2d1e3e9c) and **final** (adapt + E021 + E022, tree `~/work/monero-fcmp-idle` at adbe70cf8, sha d779a522). `--block-sync-size 5` unless stated, DB restored from a snapshot before every run, single exclusive peer 192.168.1.22, governor `performance`, no shadow lanes. `--version` on final prints 4a51d434d, because the string is fixed at CMake configure; identify it by sha256.

**Expected, fixed in the script header before the run:**

| check | expected | measured | verdict |
|---|---|---|---|
| heavy peak against base | -60% or better | -68.5% | met |
| small-tx wall against base | no more than +6% | +6.6% from logs, +6.7% from the harness | **missed** |
| negative test | all tampered rejected, all originals accepted | 24/24 and 3/3 | met |
| cgroup minimum | no higher than 2,000 MB | 1,866 MB | met |
| growth over the long resync | none | no upward trend after 3,110,000; see (e) | met, with the numbers below |
| hashes | all match | 15/15 window runs | met |

## (a) Heavy window 3,105,401 -> 3,105,441, medians of 3 (min-max)

| arm | peak RssAnon MB | peak Private_Dirty MB | peak RSS MB | wall s | post-idle RssAnon MB | write MB | CPU s | hashes |
|---|---|---|---|---|---|---|---|---|
| base | 5,606 (5,405-5,634) | 5,613 (5,405-5,634) | 6,876 (6,699-6,907) | 221 (220-222) | 4,977 (4,672-5,248) | 466 | 4,229 (4,196-4,242) | 3/3 |
| final | 1,764 (1,613-1,797) | 1,786 (1,613-1,797) | 3,001 (2,948-3,023) | 112 (110-112) | 1,066 (1,037-1,102) | 466 | 914 (910-916) | 3/3 |

final vs base: peak anon **-68.5%**, private dirty -68.2%, RSS -56.4%, wall -49.3%, post-idle **-78.6%**, CPU -78.4%. Peak ranges do not overlap. E013's adapt had -68.2% peak and -72.6% post-idle in the same setup, so the two patches leave the peak alone and move idle.

## (b) Small-tx window 3,106,400 -> 3,107,400, medians of 3 (min-max)

| arm | peak RssAnon MB | peak Private_Dirty MB | wall s, harness | wall s, logs over 3,106,405-3,107,400 | post-idle RssAnon MB | CPU s | hashes |
|---|---|---|---|---|---|---|---|
| base | 1,095 (1,036-1,435) | 1,320 (1,188-1,572) | 149 (148-150) | 145.4 (144.4-145.8) | 1,095 (992-1,198) | 1,337 (1,327-1,342) | 3/3 |
| final | 807 (798-811) | 986 (979-996) | 159 (156-159) | 155.0 (153.3-155.3) | 709 (707-714) | 1,437 (1,435-1,437) | 3/3 |

final vs base: peak anon -26.3%, wall **+6.6%** on identical heights, CPU +7.5%, post-idle -35.3%. Wall ranges do not overlap, so the cost is real and it is above the +6% I expected. E012 measured adapt at +4.0% here (157 vs 151 s). Final's harness range of 156-159 s is the same as adapt's 156-159 s in E020, while base here ran 148-150 s against 151 s in E012, but those are comparisons across experiments. (b2) measures adapt against final directly.

## (b2) E023b: are the last two patches responsible? adapt vs final, same window, 5 alternating rounds (min-max)

| arm | wall s, logs over 3,106,405-3,107,400 | wall s, harness | peak RssAnon MB | post-idle RssAnon MB | CPU s | hashes |
|---|---|---|---|---|---|---|
| adapt | 154.4 (153.5-155.8) | 159 (157-161) | 807 (801-822) | 760 (756-778) | 1,448 (1,432-1,450) | 5/5 |
| final | 152.7 (152.2-155.5) | 157 (156-159) | 821 (805-823) | 721 (712-727) | 1,440 (1,435-1,446) | 5/5 |

final vs adapt: wall -1.1% with overlapping ranges, peak +1.7% with overlapping ranges, CPU -0.6%, post-idle -5.1%. `scripts/run_e023b.sh` fixed the reading before the run: ranges overlapping and medians within 1.5% means the last two patches are not responsible. **That is the case: the gap is adapt's own cost on this window.** It was there before E021 and E022.

So E012's +4.0% (157 vs 151 s) understated it. adapt at 154.4 s here against base at 145.4 s in (b) is about +6%, but those two come from different chains (one hour apart, same box and setup), so that figure is indicative. The miss stands: my +6% line was set from E012's number, and the build does not meet it.

Why the cost is larger on this window than on the dense stretch of the long resync (+4.1%, one run) was not investigated.

## (c) Negative test
PASS at both heights: 128-, 8- and 2-input txs, 8 tampered copies of each rejected, the 3 originals accepted. evidence/E023/neg. The differential test E015 (236 cases against base as the oracle) was **not** rerun. E021 and E022 do not touch verification, so the argument that it carries over is from the code.

## (d) Minimum cgroup MemoryMax
**1,866 MB** passes; the largest failing limit is 1,765 MB, on a 125 MB bisection step (reference wall 112 s). Same result as E013. Against base's 5,750 MB from E009 that is -67.5%; base was not re-measured here.

## (e) Long resync 3,105,401 -> 3,123,400, 1 run per arm

| arm | blocks | wall s | peak RssAnon MB | post-idle MB | write MB | CPU s | hash |
|---|---|---|---|---|---|---|---|
| base_bss5 | 18,169 | 1,360 | 5,369 | 4,190 | 9,409 | 13,618 | yes |
| final_bss5 | 18,189 | 1,287 (-5.4%) | 1,650 (-69.3%) | 1,400 (-66.6%) | 9,411 | 10,910 | yes |
| final_default | 18,023 | 1,342 (-1.3%) | 1,511 (-71.9%) | 1,025 (-75.5%) | 9,961 (+5.9%) | 11,042 | yes |

| segment, from log timestamps | base_bss5 | final_bss5 | final_default |
|---|---|---|---|
| heavy, to 3,105,441 | 219 s | 106 s | 115 s |
| dense small-tx, to ~3,113,400 | 1,062 s | 1,106 s (+4.1%) | 1,141 s |
| near-empty tail, to 3,123,400 | 76 s | 72 s | 83 s |

RssAnon per height segment, median MB (max), scripts/mem_segments.py:

| segment | base_bss5 | final_bss5 | final_default |
|---|---|---|---|
| 3,105,401-3,105,441 | 5,015 (5,369) | 1,352 (1,650) | 1,052 (1,512) |
| 3,105,441-3,107,000 | 4,265 (5,312) | 1,296 (1,418) | 948 (1,235) |
| 3,107,000-3,110,000 | 3,982 (4,230) | 1,317 (1,595) | 1,182 (1,253) |
| 3,110,000-3,113,400 | 4,230 (4,230) | 1,559 (1,614) | 1,187 (1,246) |
| 3,113,400-3,118,000 | 4,191 (4,230) | 1,470 (1,568) | 1,130 (1,233) |
| 3,118,000-3,123,401 | 4,191 (4,191) | 1,469 (1,499) | 1,122 (1,155) |

**Growth:** both final arms rise early (final_bss5 by about 260 MB in median, up to 3,113,400; final_default by about 240 MB, up to 3,107,000), then stay flat or fall, and neither passes its heavy-window peak afterwards. That is no upward trend over the last 13,000 blocks, but it is one run per arm over 18,000 blocks, so slow growth over a much longer sync is not excluded.

**Idle trim on a long run:** it fired once per run and released only **70 MB** on final_bss5 (1,470 -> 1,400) and **79 MB** on final_default (1,104 -> 1,025), against 231-234 MB after the heavy window. final_bss5's 1,400 MB idle is no lower than E013's adapt_bss5 at 1,379 MB. So E021's -17% holds for a sync burst that ends right after heavy blocks, not as a general idle saving. The last verified blocks here are small, and light calls trim every 10 s, so less is waiting to be released. That reason is an inference, not a measurement.

**Base moved between experiments:** peak 5,369 here, 5,613 in E013; post-idle 4,190 here, 4,642 in E013. These are single runs, so the percentages in this table carry that spread.

## Reading
- **The recommended build holds its memory result:** -68.5% peak on the heavy window, about -69% to -72% over the long resync, the same cgroup minimum, tampered proofs still rejected, and the chain state still identical.
- **The heavy-window idle gain does not generalise:** -78.6% after the heavy window, -66.6% after a long sync ending in small blocks on the same sync settings.
- **Small-tx wall is the price, and the +6% line was crossed.** Over the dense stretch of the long resync the gap is +4.1%, in one run. On the short small-tx window it is +6.6%, in three. The report now gives both. E023b shows this comes from adapt, not from E021 or E022.

## Guardrails
- Binaries identified by sha256 in the chain log; final is byte-identical to the t8 measured in E022.
- 15/15 window runs matched .22's hash. No shadow lanes during the chain. Governor restored. No swap in the long runs (VmSwap 0).
- Not rerun: E015 differential test, E014 thread sweep, E019 second machine. v2's 0007 + 0008 have not been built.
- Evidence: evidence/E023 (chain log, results.csv, summary.txt and per-run mem.csv for each window; negative test and min_mem summaries).
