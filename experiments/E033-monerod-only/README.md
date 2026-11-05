# E033: the monerod patches alone against base, no verifier change

**Status: done. Every expectation met. With +71/-1 lines and the verifier untouched: heavy peak anon -47.7%, long resync peak -47.7%, cgroup minimum 3,000 vs 5,562 MB (-46.1%), post-idle -82.9% to -88.6%, heavy wall -7.3%, small-tx wall +0.2% (ranges overlap), long wall -1.5%. Negative test passed, 22/22 hashes. One machine. Report only.**

**Why:** this is the smallest memory change we have to show anyone: five patches in `rctSigs.cpp/.h` and `cryptonote_core.cpp/.h`, no Rust. E004e measured a non-adaptive ancestor of it. This measures the actual series against base with the same validation E032 gave v2final.

**Setup:** hydrogen, 2026-11-05 08:35 to 13:44, `scripts/run_e033.sh`, chain log evidence/E033/e033.chain. Tree `~/work/monero-fcmp-e033` = d80596ad1 + patches/options/E033-monerod-only/, tree hash e8d76fb5 as expected. Arms: base (sha 2d1e3e9c), e033 (sha 1ed829f0). Single peer 192.168.1.22, `--block-sync-size 5`, DB restored from the snapshot before each timed run, governor pinned and restored. No lanes at the start or in the once-a-minute check. Wall figures are from log timestamps. The harness's rounded heavy wall gives -6.3%; the log gives -7.3%.

## Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds
Medians (min-max). 6/6 hashes.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 219.6 (218.6-220.3) | 4,256 (4,239-4,280) | 5,582 (5,280-5,622) | 5,582 (5,302-5,622) | 6,855 (6,531-6,882) | 4,717 (4,613-4,769) |
| e033 | 203.6 (203.6-205.3) | 2,028 (2,017-2,045) | 2,919 (2,911-2,937) | 2,939 (2,936-2,962) | 4,130 (4,113-4,153) | 540 (517-547) |
| change | **-7.3%**, separate | -52.3%, separate | **-47.7%**, separate | -47.3%, separate | -39.8%, separate | **-88.6%**, separate |

## Small-tx window 3,106,405 -> 3,107,400, 5 alternating rounds
Medians (min-max). 10/10 hashes.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 146.1 (144.1-148.5) | 1,334 (1,324-1,339) | 1,139 (1,037-1,183) | 1,317 (1,184-1,325) | 4,071 (4,065-4,237) | 969 (957-1,139) |
| e033 | 146.3 (145.0-148.7) | 1,328 (1,327-1,336) | 861 (849-871) | 1,036 (1,024-1,073) | 3,962 (3,928-3,980) | 712 (709-728) |
| change | **+0.2%**, overlap | -0.4%, overlap | **-24.4%**, separate | -21.3%, separate | -2.7%, separate | -26.5%, separate |

No measurable cost on small-tx blocks. Base's peak here is the soft figure it always is.

## Cgroup minimum, warm cache, heavy window
`scripts/min_mem.sh`: bisect `MemoryMax` with swap off, pass = reaches the window end within 1.10 x the reference wall on .22's hash. Each limit was run once. All failures were OOM kills. Base's figures are E032's: same box, same method, same day, not re-run here.

| arm | minimum passing | largest failing | cgroup peak at the generous limits |
|---|---|---|---|
| e033 | **3,000 MB** | 2,875 MB | 2,896 MB (limit 6,000), 3,027 MB (limit 4,000) |
| base (E032) | **5,562 MB** | 5,375 MB | 5,978 MB (limit 8,000) |

-46.1%. The true minimums lie inside those brackets, so the reduction lies between -44.2% and -48.3%.

## Negative test
Single-bit tampering of real transactions at two heights, 8 tampered versions of each: a 128-input tx at 3,105,424, and 8-input and 2-input txs at 3,105,414. 24/24 tampered rejected, 3/3 originals accepted. The verifier is unchanged, but the batching around it is not, which is why this was run.

## Long resync 3,105,401 -> 3,123,400, 3 alternating rounds
Medians (min-max). 6/6 hashes, no swap in any run.

| arm | wall s | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| base | 1,358.6 (1,351.3-1,364.2) | 13,635 (13,605-13,646) | 5,610 (5,271-5,625) | 5,610 (5,271-5,625) | 8,412 (8,163-8,547) | 4,418 (4,112-4,594) |
| e033 | 1,338.4 (1,335.7-1,342.2) | 11,329 (11,310-11,351) | 2,935 (2,843-2,988) | 2,935 (2,868-2,988) | 5,119 (5,116-5,146) | 757 (757-814) |
| change | **-1.5%**, separate | -16.9%, separate | **-47.7%**, separate | -47.7%, separate | -39.1%, separate | **-82.9%**, separate |

| segment, from log timestamps | base s | e033 s | change |
|---|---|---|---|
| heavy, 3,105,406-3,105,441 | 218.5 | 204.8 | -6.3%, separate |
| dense small-tx, to 3,113,401 | 1,065.1 | 1,060.3 | -0.4%, overlap |
| near-empty tail, to 3,123,400 | 73.5 | 72.9 | -0.8%, overlap |

So the whole long-run wall gain is the heavy window.

Largest RssAnon by height, MB, r1 / r2 / r3:

| heights | base | e033 |
|---|---|---|
| 3,105,401-3,105,441 | 5,271 / 5,625 / 5,610 | 2,843 / 2,988 / 2,936 |
| 3,105,441-3,108,000 | 5,271 / 5,517 / 5,527 | 824 / 833 / 882 |
| 3,108,000-3,110,000 | 4,199 / 4,658 / 4,414 | 1,039 / 1,074 / 1,027 |
| 3,110,000-3,113,401 | 4,199 / 4,677 / 4,457 | 1,048 / 1,078 / 1,038 |
| 3,113,401-3,116,000 | 4,151 / 4,637 / 4,457 | 987 / 1,037 / 988 |
| 3,116,000-3,118,000 | 4,112 / 4,637 / 4,418 | 873 / 935 / 878 |
| 3,118,000-3,120,000 | 4,112 / 4,594 / 4,418 | 919 / 977 / 919 |
| 3,120,000-3,122,000 | 4,112 / 4,594 / 4,418 | 871 / 982 / 859 |
| 3,122,000-3,123,400 | 4,112 / 4,594 / 4,418 | 872 / 931 / 871 |

No upward trend after 3,110,000 in either arm. The peak is the heavy window in every run. 18,000 blocks does not exclude slow growth over a much longer sync.

### Mining overlapped part of this
W006 started mining on box81 at 12:21, so .22 was relaying our mined blocks during r2_base, r3_base and r3_e033, and not during r1_base, r1_e033 and r2_e033. Heavy, small-tx, negative test and cgroup minimum all finished before that. Base's long wall in E032, with no mining, was 1,357.5 s, and here it is 1,358.6 s. Walls did rise by round in both arms (base 1,351 / 1,359 / 1,364, e033 1,336 / 1,338 / 1,342), but r2_e033 rose before mining began, and the rise is under 1%. Paired by round the change is -1.2%, -1.5%, -1.6%, so the unbalanced overlap does not change the reading. An effect of mining of about 0.5% on wall is not excluded.

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| heavy peak -40 to -50% | -47.7% | met |
| heavy post-idle -75 to -90% | -88.6% | met |
| heavy wall -2 to -9% | -7.3% | met |
| small-tx wall -1 to +3% | +0.2% | met |
| small-tx peak -5 to -25% | -24.4% | met, near the edge |
| all tampered rejected, all originals accepted | 24/24, 3/3 | met |
| cgroup minimum 3,000 to 3,800 MB | 3,000 MB | met, at the edge |
| long peak -35 to -50% | -47.7% | met |
| long wall -5 to +4% | -1.5% | met |
| no upward trend after 3,110,000 | none | met |
| all hashes match | 22/22 | met |

## Reading: what the verifier change adds
Against base, same box and peer, a few hours apart. E032 for v2final. Size is what would have to be reviewed, tests included.

| against base | e033 (+71/-1, monerod only) | v2final (+985/-121, includes monero-oxide) |
|---|---|---|
| heavy peak anon | -47.7% | -70.4% |
| long peak anon | -47.7% | -70.2% |
| cgroup minimum | -46.1% (3,000 MB) | -68.3% (1,765 MB) |
| small-tx peak anon | -24.4% | -30.5% |
| heavy post-idle anon | -88.6% (540 MB) | -83.7% (800 MB) |
| long post-idle anon | -82.9% (757 MB) | -75.4% (1,056 MB) |
| heavy wall | -7.3% | -37.1% |
| heavy CPU | -52.3% | -71.0% |
| small-tx wall | +0.2% | +7.9% |
| long wall | -1.5% | -1.4% |

- **e033 alone clears the owner's 40% target on this box, on peak and on the cgroup minimum, at about 7% of v2's line count, with no measured small-tx cost.** The verifier change is what takes peak from about -48% to about -70%, and it is also what costs the +7.9% on small-tx blocks.
- **e033 idles lower than v2final,** in absolute terms, on both comparisons. I did not look into why, and these are separate experiments, so treat it as an observation.
- Heavy CPU falls by half while wall falls 7%. I did not profile this run, so I am not attributing that.

This does not change the owner's decision that v2 is what would go upstream. It does mean there is a smaller option to show first, or instead, if that decision is revisited.

## Not covered
- **It does not fix the E001 wedge.** The series has no 0003, so a default-settings node still needs its own fix to pass 3,105,401, and every run here used `--block-sync-size 5`.
- One machine. box81 has compiled this series but not measured it.
- No cold-cache cgroup minimum. E034 suggests it would match the warm one, but that is not measured.
- The differential test was not run. The verifier code is the same as base's, but batching around it differs, and only this run's smaller negative test covers that.
- The trims are glibc-only, so other allocators get the cap and not the idle figures.
- Presenting it: published 0006 depends on 0003 for one include in its context, so this series carries a 0006 with that context line removed. What it adds is the same.

## Guardrails
The arms differ by this series only, sha256 of both binaries in the chain. No lanes. Governor restored. Evidence: evidence/E033 (chain, results.csv, summary.txt, per-run mem.csv, min_mem csv and summary, negative test summaries; no raw logs).
