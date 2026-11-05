# E032: v2final against base

**Status: done. v2final holds the memory result: heavy peak anon -70.4%, long resync peak -70.2%, cgroup minimum 1,765 vs 5,562 MB (-68.3%). Speed: heavy wall -37.1%, long resync wall -1.4%, small-tx wall +7.9%. Negative test passed, 22/22 hashes. One narrow miss, on the good side: small-tx peak -30.5% against an expected -20 to -30%. Report only.**

**Why:** v2 is what would be presented upstream (owner, 2026-11-04). E018 and E020 measured v2 before its last two patches, and E025 compared v2final only with final. This is the validation E023 gave final.

**Setup:** hydrogen, 2026-11-05 03:17 to 08:35, `scripts/run_e032.sh`, chain log evidence/E032/e032.chain. Arms: base (sha 2d1e3e9c), v2final (sha a9969e61). Single peer 192.168.1.22, `--block-sync-size 5`, DB restored from the snapshot before each timed run, governor pinned and restored. No lanes at the start or in the once-a-minute check during the run. box81 synced nothing from .22 during it. Wall figures are from log timestamps.

## Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds
Medians (min-max). 6/6 hashes.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 218 (218-219) | 4,237 (4,232-4,244) | 5,576 (5,408-5,586) | 5,581 (5,414-5,592) | 6,857 (6,684-6,867) | 4,898 (4,676-5,115) |
| v2final | 137 (137-138) | 1,229 (1,222-1,230) | 1,653 (1,612-1,689) | 1,678 (1,632-1,714) | 2,860 (2,846-2,893) | 800 (774-836) |
| change | **-37.1%**, separate | -71.0%, separate | **-70.4%**, separate | -69.9%, separate | -58.3%, separate | **-83.7%**, separate |

## Small-tx window 3,106,405 -> 3,107,400, 5 alternating rounds
Medians (min-max). 10/10 hashes.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 146.3 (145.6-148.4) | 1,336 (1,326-1,343) | 1,153 (1,009-1,400) | 1,303 (1,192-1,639) | 4,198 (4,073-4,492) | 1,111 (987-1,400) |
| v2final | 157.8 (157.2-160.0) | 1,499 (1,490-1,503) | 801 (800-819) | 959 (943-969) | 3,930 (3,926-3,940) | 712 (709-724) |
| change | **+7.9%**, separate | +12.2%, separate | **-30.5%**, separate | -26.4%, separate | -6.4%, separate | -35.9%, separate |

Base's peak here is the soft figure it always is, so the percentage carries that spread.

## Cgroup minimum, warm cache, heavy window
`scripts/min_mem.sh`: bisect `MemoryMax` with swap off, pass = reaches the window end within 1.10 x the reference wall on .22's hash. Each limit was run once. All failures were OOM kills.

| arm | minimum passing | largest failing | cgroup peak at the generous limit |
|---|---|---|---|
| v2final | **1,765 MB** | 1,663 MB | 1,747 MB (limit 4,000) |
| base | **5,562 MB** | 5,375 MB | 5,978 MB (limit 8,000) |

-68.3%. The true minimums lie inside those brackets, so the reduction lies between -67.2% and -70.1%.

**This changes a headline figure.** The summary compared final's 1,866 MB with base's 5,750 MB from E009, -67.5%. Base re-measured warm gives 5,562 MB, the same as E034's cold figure, so final's reduction with this base is -66.5%. The difference is within the method's step size; the summary now uses the newer figure.

## Negative test
Single-bit tampering of real transactions at two heights, 8 tampered versions of each: a 128-input tx at 3,105,424, and 8-input and 2-input txs at 3,105,414. 24/24 tampered rejected, 3/3 originals accepted.

## Long resync 3,105,401 -> 3,123,400, 3 alternating rounds
Medians (min-max). 6/6 hashes, no swap in any run. Peak recomputed up to 3,123,400 from the samplers differs from the table by at most 1 MB.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 1,357.5 (1,352.5-1,358.2) | 13,601 (13,598-13,635) | 5,422 (5,393-5,559) | 5,423 (5,396-5,559) | 8,316 (8,311-8,525) | 4,286 (4,282-4,550) |
| v2final | 1,338.9 (1,338.3-1,339.8) | 11,553 (11,553-11,556) | 1,615 (1,605-1,688) | 1,640 (1,626-1,712) | 5,429 (5,410-5,487) | 1,056 (1,051-1,110) |
| change | **-1.4%**, separate | -15.1%, separate | **-70.2%**, separate | -69.8%, separate | -34.7%, separate | **-75.4%**, separate |

| segment, from log timestamps | base s | v2final s | change |
|---|---|---|---|
| heavy, 3,105,406-3,105,441 | 218.5 | 136.9 | -37.3%, separate |
| dense small-tx, to 3,113,401 | 1,063.1 | 1,128.7 | +6.2%, separate |
| near-empty tail, to 3,123,400 | 74.9 | 73.1 | -2.5%, separate |

Largest RssAnon by height, MB, r1 / r2 / r3:

| heights | base | v2final |
|---|---|---|
| 3,105,401-3,105,441 | 5,423 / 5,560 / 5,393 | 1,688 / 1,616 / 1,605 |
| 3,105,441-3,108,000 | 5,423 / 5,490 / 5,354 | 1,118 / 1,041 / 1,061 |
| 3,108,000-3,110,000 | 4,618 / 4,330 / 4,396 | 1,321 / 1,263 / 1,272 |
| 3,110,000-3,113,401 | 4,589 / 4,330 / 4,367 | 1,326 / 1,270 / 1,265 |
| 3,113,401-3,116,000 | 4,589 / 4,349 / 4,353 | 1,297 / 1,252 / 1,248 |
| 3,116,000-3,118,000 | 4,551 / 4,287 / 4,325 | 1,216 / 1,162 / 1,158 |
| 3,118,000-3,120,000 | 4,551 / 4,287 / 4,325 | 1,238 / 1,183 / 1,185 |
| 3,120,000-3,122,000 | 4,551 / 4,287 / 4,282 | 1,239 / 1,158 / 1,187 |
| 3,122,000-3,123,400 | 4,551 / 4,287 / 4,282 | 1,212 / 1,158 / 1,157 |

No upward trend after 3,110,000 in either arm, and in v2final no later stretch passes the heavy window's peak. 18,000 blocks does not exclude slow growth over a much longer sync.

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| heavy peak -60 to -72% | -70.4% | met |
| heavy wall -30 to -40% | -37.1% | met |
| small-tx wall +6 to +11% | +7.9% | met |
| small-tx peak -20 to -30% | **-30.5%** | **narrow miss, lower than expected** |
| all tampered rejected, all originals accepted | 24/24, 3/3 | met |
| cgroup minimum at or below 2,000 MB | 1,765 MB | met |
| long peak -65 to -75% | -70.2% | met |
| long wall -3% to +6% | -1.4% | met |
| no upward trend after 3,110,000 | none | met |
| all hashes match | 22/22 | met |

## Reading: what v2 gives up against v1
Same box, same peer, but different days, and final's long run was a single run. E025 is the direct comparison on the windows.

| against base | final, v1 (E023, E028) | v2final (E032) |
|---|---|---|
| heavy peak anon | -68.5% | -70.4% |
| heavy post-idle anon | -78.6% | -83.7% |
| heavy wall | -49.3% | -37.1% |
| heavy CPU | -78.4% | -71.0% |
| small-tx wall | +5.5% | +7.9% |
| long peak anon | -69.3% | -70.2% |
| long wall | -5.4% | -1.4% |
| cgroup minimum | -66.5% (1,866 MB) | -68.3% (1,765 MB) |

So on memory v2 is at least as good as v1, and the peak differences are inside the run-to-run spread. It costs speed: about 25 s on the heavy window and about 2.4 points on small-tx blocks. That is the trade the owner chose, and with E032 it is measured against base rather than inferred through final.

## Not covered
- One machine. box81 has no v2final figures with the last two patches; that is queued after E033.
- The differential test was not repeated here: E025 has v2final matching base on all 236 cases with this binary's source. This run's negative test is the smaller one.
- No cold-cache cgroup minimum for v2final. E034 suggests it would match the warm one, but that is not measured.
- v2's verifier code has had no independent review. E007's crypto review covered v1.

## Guardrails
The arms differ by the v2 series only, sha256 of both binaries in the chain. No lanes. Governor restored. Evidence: evidence/E032 (chain, results.csv, summary.txt, per-run mem.csv, min_mem csv and summaries, negative test summaries; no raw logs).
