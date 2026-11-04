# E029: stored-circuit verification for proofs under 8 inputs

**Status: done. Not adopted, reported as an option. Small-tx wall -5.2%, CPU -8.1%, peak anon +7.0%. It clears every part of the rule fixed before the run except the peak limit of +5%. The owner's decision (2026-11-04): keep final, report E029 as an option.**

**Why:** E028 left one candidate for the small-tx wall cost: streaming builds every circuit twice. The stored-circuit path already exists in the E007 tree as `verify_stored`, under `cfg(test)`. This routes small proofs to it.

**Change (10 insertions, 2 deletions, `scripts/e029_patch.py`, patch in `patches/options/E029-small-stored/`):** at the top of `Fcmp::verify`, proofs with fewer than 8 inputs return `self.verify_stored(...)`. `cfg(test)` is removed from `verify_stored` and from `Circuit::verify`. The routing is itself `#[cfg(not(test))]`, so crate tests keep testing streaming. No monerod source change: only the cargo `[patch]` paths point at the patched oxide tree.

**Setup:** hydrogen, 2026-11-04 17:22-20:17, `scripts/run_e029.sh`, chain log evidence/E029/e029.chain. Arms: final (sha d779a522) and e029 (final + this change, sha d93a9703). Base (2d1e3e9c) is also an arm in the differential test only. `ab_window.sh`, `--block-sync-size 5`, DB restored from the snapshot before each run, single peer 192.168.1.22, governor pinned, no shadow lanes. A first attempt stopped at the crate-test step on a compile error, because my patch had missed `Circuit::verify`. Nothing was measured in it (JOURNAL 17:22).

## Result
Wall from logs, `scripts/e023_wall.py`. Medians (min-max).

**Small-tx window 3,106,400 -> 3,107,400, 5 alternating rounds, 10/10 hashes**

| arm | wall s, logs, 3,106,405-3,107,400 | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| final | 154.3 (153.4-154.7) | 1,440 (1,430-1,446) | 809 (806-815) | 988 (973-1,012) | 3,920 (3,912-3,929) | 711 (706-715) |
| e029 | 146.2 (145.0-146.6) | 1,323 (1,323-1,326) | 866 (851-869) | 1,058 (1,041-1,065) | 3,999 (3,992-4,008) | 723 (707-734) |
| change | **-5.2%**, separate | **-8.1%**, separate | **+7.0%**, separate | +7.1%, separate | +2.0%, separate | +1.7%, overlap |

In absolute terms: 8.1 s less per 1,000 blocks for 57 MB more peak anon.

**Heavy window 3,105,401 -> 3,105,441, 3 alternating rounds, 6/6 hashes**

| arm | wall s, logs, 3,105,406-3,105,441 | CPU s | peak anon MB | peak private dirty MB | peak RSS MB | post-idle anon MB |
|---|---|---|---|---|---|---|
| final | 104.8 (104.3-106.3) | 910 (906-912) | 1,711 (1,632-1,912) | 1,711 (1,632-1,936) | 2,999 (2,967-3,045) | 1,118 (1,059-1,119) |
| e029 | 106.1 (105.4-107.0) | 905 (899-908) | 1,794 (1,745-1,845) | 1,814 (1,769-1,864) | 3,041 (2,957-3,070) | 1,126 (1,039-1,139) |
| change | +1.3%, overlap | -0.5%, overlap | +4.9%, overlap | +6.0%, overlap | +1.4%, overlap | +0.7%, overlap |

The harness polls every 2 s, so a run can overshoot the window end. Recomputing peak anon from the samplers, up to the window end only, gives the same figure for all 16 runs, so the +7.0% and +4.9% are not an overshoot effect.

**Differential test, base, final and e029:** DIFF PASS at both heights, on E025's case files (byte-identical). 135 cases at 3,105,401 (128-input proofs, streaming path) and 101 at 3,106,400 (2-input proofs, so these go through the new routing).

**Crate tests:** `cargo test --release -p full-chain-membership-proofs`: 14 passed, 0 failed.

## The rule, fixed before the run
| condition | result | |
|---|---|---|
| small-tx wall at least 2% below final, separate ranges | -5.2%, separate | met |
| small-tx peak anon not worse by more than 5% | **+7.0%, separate** | **not met** |
| heavy peak anon not worse by more than 5% | +4.9%, overlap | met, narrowly |
| all hashes match | 16/16 | met |
| DIFF PASS at both heights | yes | met |
| crate tests pass | yes | met |

The script says a larger peak is not traded for speed, since the project's goal is memory. So final stays. The owner confirmed this on the small-tx medians, before the heavy runs ended.

## Expectations, fixed before the run
| expectation | result | |
|---|---|---|
| crate tests pass, DIFF PASS at both heights, all hashes match | all so | met |
| small-tx wall 2-4% below final | -5.2% | **miss**, a larger gain than expected |
| small-tx CPU about -7% | -8.1% | met, on the high side |
| small-tx peak anon 5-15% above final | +7.0% | met |
| heavy unchanged within run-to-run spread | wall, CPU and peak all overlap | met |

## Reading
- **The verifier's CPU cost is the double build.** E028 put +8.0% CPU on the verifier, and removing the second build for small proofs takes off 8.1%. E011 had traced it there by profile; this removes it directly.
- **It saves more wall than E028 assigned to the verifier:** 8.1 s against 5.5 s. E028's two smaller steps (+1.2 s and +1.3 s) showed no CPU change and overlapping ranges, so some of that may depend on streaming rather than being separate costs. This run does not separate that.
- **Compared across chains, it looks like base's small-tx speed.** E028's base was 146.4 s and 1,337 s CPU, e029 here is 146.2 s and 1,323 s, with E028's base peak at 1,073 MB against 866 MB here. The final arm repeated closely between the two chains (154.4 vs 154.3 s, 1,443 vs 1,440 s CPU, 818 vs 809 MB), which supports comparing them, but base was not in this run. E030 measured it directly: wall +1.1% and CPU -0.7% (overlapping), peak anon -23.5% (separate).
- **The heavy peak is not attributed to the change.** Its proofs have 128 inputs and take the streaming path. Final's own range there is 1,632-1,912 MB, and 3 rounds cannot resolve 4.9%. I did not check whether those blocks also hold small proofs.

## Who might want the option
A node whose load is mostly small transactions and which values CPU above about 60 MB of peak: -8% CPU and -5% wall on those blocks, nothing lost on heavy blocks in this run. Patch: `patches/options/E029-small-stored/`. It applies on top of the v1 monero-oxide series and reproduces the measured tree's hash.

## Limits
- **Proofs of 3-7 inputs are not measured.** This small-tx window and the differential cases use 1-2-input proofs. Those sizes are also below the heavy threshold, so such calls keep the full thread pool, and each stores a larger circuit than the measured proofs. The peak on a stretch of them could be well above +7%. Anyone adopting this needs that measured first.
- **The routing runs only at the node.** It is compiled out of the crate tests, so its evidence is the 101 differential cases and the window hashes. `verify_stored` is compared with the streaming path in the crate tests, and "same transcript operations" is the code's own comment plus those tests, not an independent review. It moves a test-only path into production in security-critical, unaudited code.
- **Threshold 8 only, one box, two windows.** Not measured: long resync, cgroup minimum, box81.

## Guardrails
One change between arms, sha256 of each in the chain. 16/16 hashes. No lanes at the start. Governor restored. `~/work/monero-fcmp-idle` clean, final's sha still d779a522. box81 was idle. Evidence: evidence/E029 (chain, results.csv, summary.txt, per-run mem.csv, differential summaries and verdict JSONs).
