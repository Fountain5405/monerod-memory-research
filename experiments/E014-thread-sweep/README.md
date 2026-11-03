# E014: thread sweep, does the adapt win hold on small machines?

**Why:** the headline (E013: -68% peak) was measured with the stock node's default 24 verification threads on a 12c/24t box, and about 40 of those 68 points can be had by halving concurrency on the stock binary (reports/REVIEW-70pct.md). A node on a 1-4 thread machine never runs 24 threads, so this experiment measures base vs adapt with `--max-concurrency 4`, `2` and `1` on the same heavy window. With the pool at or below 12, adapt's concurrency cap is inert, so whatever remains is the streaming verifier (E007) and the trim (E012).

**Setup:** hydrogen, 2026-11-03 11:30-15:26, scripts/run_e015_e014.sh (chain log evidence/E014/e015_e014.chain.txt). Heavy window 3,105,401 -> 3,105,441 (40 blocks, 64 x 128-input FCMP++ txs per block), `--block-sync-size 5`, DB restored from the wedge snapshot before every run, 3 rounds, order alternated per round, governor pinned, no shadow lanes. base = v0.19.0.0-beta.3.1 (`monero-fcmp/build/beta31`), adapt = `monero-fcmp-adapt` 4a51d434d. Six arms, 18 runs, **all 18 end-hash checks against .22 pass**.

## Results (median of 3, min-max in brackets; MB are RssAnon from the 2 s sampler)

| threads | metric | base | adapt | change |
|---|---|---|---|---|
| 4 | peak anon MB | 2,020 (1,351-2,193) | 1,060 (1,050-1,064) | **-47.5%** |
| 4 | post-idle anon MB | 1,997 (1,313-2,193) | 675 (667-692) | **-66.2%** |
| 4 | wall s | 281 (261-289) | 223 (210-232) | -20.6% |
| 4 | CPU s | 988 (953-1,001) | 738 (719-756) | -25.3% |
| 2 | peak anon MB | 1,246 (1,077-1,348) | 928 (884-941) | **-25.5%** |
| 2 | post-idle anon MB | 1,194 (960-1,314) | 609 (592-628) | **-49.0%** |
| 2 | wall s | 506 (498-507) | 379 (361-379) | -25.1% |
| 2 | CPU s | 960 (947-963) | 707 (678-709) | -26.4% |
| 1 | peak anon MB | 1,253 (1,252-1,260) | 893 (879-912) | **-28.7%** |
| 1 | post-idle anon MB | 1,203 (1,195-1,229) | 621 (602-621) | **-48.4%** |
| 1 | wall s | 850 (840-852) | 612 (609-612) | -28.0% |
| 1 | CPU s | 846 (836-848) | 608 (606-608) | -28.1% |

Peak RSS (anon + file-backed LMDB pages, not our metric): 3,371 -> 2,290 (-32%) at 4 threads, 2,564 -> 2,122 (-17%) at 2, 2,584 -> 2,136 (-17%) at 1. Reads and writes are identical per arm (9 MB / 466 MB). Raw rows: results.csv; per-run logs and samplers in evidence/E014/.

For scale, the same window at the default 24 threads (E013): base 5,600 MB, adapt 1,780 MB.

## What it says

1. **The win shrinks with the thread count but does not vanish.** At 4 threads adapt removes about half of the stock peak (-47.5%), at 1-2 threads about a quarter (-26..-29%). The idle footprint after the window is halved or better at every thread count (-48..-66%). The owner's 40% target is met at 4 threads and above, and not met for the peak at 1-2 threads, where the stock node is already small (1.25 GB).
2. **With the cap inert, the remaining gain is the verifier and the trim.** At 1 thread nothing runs in parallel, so the -29% peak is the streaming verifier's smaller per-proof heap (E007: -73% per proof at the crate level) diluted by everything else in the process (LMDB, blocks in flight, the pool), and the -48% post-idle is the trim returning freed arenas.
3. **adapt is 21-28% faster and uses 25-28% less CPU at every thread count.** This is the O(c x q) fold the stock verifier performs per Pedersen commitment (arithmetic_circuit_proof.rs:779-783), which E007 removes; the wall gain is largest at 1 thread (-28%) because there is nothing else to hide it behind. At 24 threads (E013) the wall gain was -50%, the extra coming from less contention.
4. **The stock node's peak is run-dependent, adapt's is not.** base_c4 peaked at 1,351 / 2,193 / 2,020 MB and base_c2 at 1,348 / 1,077 / 1,246 MB across the three rounds, while adapt stayed within 15 MB of itself at 4 threads (1,050-1,064) and within 33 MB at 1-2 threads. The stock peak depends on how many 8 MB blocks' worth of constraints are materialised at once, which depends on how the peer delivers the window; the streaming verifier materialises none of them, so adapt's peak is set by the proof count, not by timing. Medians are reported for that reason; the per-thread ranges do not overlap between base and adapt anywhere.
5. **Caveat: this is a 24-thread box pretending to be small.** `--max-concurrency` limits the verification pool only; the DB, networking and RPC pools, and a 3900X's cache, are unchanged. A real small machine is measured in E019 (box81, Ryzen 5 5600G 6c/12t, 14 GB), base vs adapt vs e017 on the same windows.

## Guardrails
- End hash equal to .22 at 3,105,441 in all 18 runs; no run timed out; no rewind failed.
- Verification is unchanged in adapt relative to E013/E015 (same binary 4a51d434d; E015 differential negtest DIFF PASS).
- No shift to disk or swap: identical read/write bytes per arm; swap off on hydrogen.
- Quiet box: no shadow lanes for the whole chain (chain log), governor `performance` for all 18 runs.
