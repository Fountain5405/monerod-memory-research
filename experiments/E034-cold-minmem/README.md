# E034: the cgroup minimum with a cold page cache

**Status: done. The minimum holds on a cold cache: final 1,866 MB, the same result as warm, against base's 5,562 MB, -66.5%. The DB pages are charged to the node when it reads them, as E031 inferred, but the kernel reclaims them under the limit, and every failure is still an OOM kill. Two expectations narrowly missed. Report only.**

**Why:** E031 found the cgroup peak tracks anon, not RSS, and inferred that DB pages read outside the scope are charged elsewhere. That left open whether the minimums understate what a node starting cold needs.

**Change:** `COLD=1` in `scripts/min_mem.sh` evicts `data.mdb` from the page cache after each rewind (`posix_fadvise`, that file only, not system-wide). Default behaviour is unchanged.

**Setup:** hydrogen, 2026-11-05 02:28-03:18, `scripts/run_e034.sh`, chain log evidence/E034/e034.chain. Arms: final (sha d779a522), base (sha 2d1e3e9c). Heavy window, `--block-sync-size 5`, swap off in the scope, single peer 192.168.1.22, governor pinned, no lanes. `scripts/page_resident.py` confirmed 0 bytes of the DB resident before all 18 starts. Reference walls are the mean of two cold runs with an 8,000 MB limit: final 116 s, base 227 s. Pass = window end within 1.10 x that, on .22's hash. Each limit ran once.

## Result
| arm | cold minimum passing | largest failing | wall at the minimum | cgroup peak, 8,000 MB limit, cold | warm minimum | warm cgroup peak |
|---|---|---|---|---|---|---|
| final | **1,866 MB** | 1,765 MB | 120 s (ref 116) | 2,388-2,443 MB | 1,866 MB (E023) | 1,647 MB (E023, 4,000 MB limit) |
| base | **5,562 MB** | 5,375 MB | 229 s (ref 227) | 6,269-6,355 MB | 5,750 MB (E009) | not re-measured yet; E032 does |

**-66.5%** in one chain on a cold cache. From the brackets, between -65.3% and -68.3%. The published warm pair, -67.5%, is from two chains.

Base's two figures do not show cold is lower: 5,750 MB also passed here, and the warm search stepped from a different range and never tried 5,562 MB.

## What happens to the DB pages
At a generous limit, final's peak goes from 1,647 MB warm to about 2,400 MB cold, so about 750 MB of DB pages are now charged to the node. That supports E031's inference, which had not been tested.

Close to the limit they are reclaimed. Peak equals the limit in the final trials (1,968 at 1,968, 1,866 at 1,866), wall rises only 3-5% over the reference, and each failure is an OOM kill, at a limit near final's peak anon (1,613-1,797 MB in E023). So the requirement that sets the minimum is anon, plus a margin, whether the cache is warm or cold.

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| final's cgroup peak at the generous limit at least 2,500 MB | 2,388-2,443 MB | **miss**, narrowly; the direction and most of the size are as expected |
| final's cold minimum 1,866-3,000 MB | 1,866 MB | met, at the low end |
| base's cold minimum 5,750-7,500 MB | **5,562 MB** | **miss**, one bisection step under |
| reduction at least -50% | -66.5% | met |
| failures may be slowdowns rather than OOM kills | all 7 failures are OOM kills | no slowdown failures occurred |

## Reading
- **The headline survives the test I doubted it on.** E031's correction stays right on what the method measured, but the worry it raised, that a cold node needs much more, is not borne out on this window on this disk.
- **The metric is still not independent evidence.** Its limit is set by anon, warm or cold, so it mostly restates peak anon as a RAM requirement. The report should not count them as two confirmations.

## Limits
- **One SATA SSD.** Reclaiming and re-reading pages is cheap here. On a slower disk the 1.10 x wall limit could fail earlier, so a higher minimum is possible there. Not measured.
- **Heavy window only, cold only at the start.** The cache warms during the 40 blocks. A long run at the limit is not measured.
- Each limit ran once, so the brackets exclude trial-to-trial spread. Box81 has no cold figure.

## Guardrails
One change against the method, default unchanged, script hash in the chain. All passing trials ended on .22's hash. No lanes at the start, governor restored, box81 idle. E032 started as this chain ended. Evidence: evidence/E034 (chain, min_mem csv and summaries).
