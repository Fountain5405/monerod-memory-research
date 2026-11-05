# E036: another developer's sync-wedge patch, on the real chain and against lying peers

**Status: parts a, b and c4 done; part c5 (a peer that lies and then does not answer) queued after E037. Report only.**

**Why:** the owner put a patch in the home directory on 2026-11-05 as someone else's attempt at the E001 wedge, then asked: "but peers could advertise false block weights, right?" The patch is not in this repo until the owner says it may be. It is referred to as another developer's patch, sha256 8b038b26.

**The change:** `block_queue::reserve_span` gains a `max_weight` argument and stops adding blocks to a span once the block weights the peer advertised would pass `--batch-max-weight`, always taking at least one block. A peer that sends no weights keeps the count-only behaviour. +33/-4 lines in 6 files including its unit test.

**Builds (hydrogen):**
| name | what | sha256 |
|---|---|---|
| base | beta.3.1, d80596ad1 | 2d1e3e9c |
| final | the recommended build, adbe70cf8 | d779a522 |
| e036 | base + patch, tree e949bcaf | 153faa2d |
| fw | final - 0003 (`scripts/e036_no0003.patch`) + patch, tree b6dd69ea: what final would be if this patch replaced the E001 cap | c6751999 |

## Part a: compile and unit tests (box81, 12:01 to 12:05)
Applies cleanly to base. 10/10 tests pass in the `block_queue` and `node_server` filters, including its new one. Only those filters were run, not the whole suite. `evidence/E036/e036a.chain`.

## Part b: honest peer, real chain (hydrogen, 17:40 to 21:12, `scripts/run_e036b.sh`)
**Wedge control, from 3,105,401, 120 s, default settings unless shown. All as fixed beforehand.**
| arm | tip after 120 s | oversize errors | requests | hash |
|---|---|---|---|---|
| e036 default | 3,105,434 | 0 | 11 | yes |
| fw default | 3,105,451 | 0 | 28 | yes |
| e036 `--block-sync-size 100` | 3,105,434 | 0 | 11 | yes |
| final `--block-sync-size 100` | 3,105,401, stuck | 120 | 120 | yes |

An explicit size bypasses 0003's cap, so final wedges there and the patch does not.

**Long resync to 3,123,400, default settings, 3 alternating rounds, medians (min-max), 6/6 hashes.**
| arm | peak anon MB | private dirty MB | peak RSS MB | wall s | post-idle anon MB | write MB | CPU s |
|---|---|---|---|---|---|---|---|
| final | 1,607 (1,569-1,609) | 1,672 (1,668-1,679) | 5,604 (5,546-5,624) | 1,328 (1,325-1,336) | 1,179 (1,127-1,190) | 9,942 (9,939-9,994) | 10,984 (10,979-10,999) |
| fw | 1,100 (1,018-1,131) | 1,142 (1,136-1,177) | 5,178 (5,156-5,214) | 1,241 (1,235-1,243) | 753 (729-769) | 8,267 (8,264-8,276) | 11,048 (11,033-11,061) |
| fw vs final | **-31.5%** | -31.7% | -7.6% | **-6.6%** | **-36.1%** | -16.8% | +0.6% |

Every range separates. The expected ranges were wide because I had no model (peak -50 to +10%, wall -10 to +20%), so landing inside them says little.

**Wall by stretch (`scripts/e036_long.py`), from 3,105,425:** heavy to 3,105,441 109.7 vs 105.3 s, -4.0%; dense to 3,113,401 1,131.7 vs 1,087.5 s, -3.9%; near-empty tail to 3,123,400 82.0 vs 40.9 s, -50.1%. All separate.

**Requests (one logged, untimed run per arm; final's is E035 part b's):** final 4,648, fw 1,225, both 0 oversize errors. Final's cap holds it to 4 blocks per request wherever blocks are small enough for the estimate to exceed 4. On a chain with a 20 MB limit that cap costs requests, commits, writes and wall time. The window-aware cap (E035) equals it here, so it costs the same.

**Memory by stretch:** final 1,325-1,403 MB through the dense stretch and 1,236-1,318 MB in the tail; fw 928-975 and 821-878. The level is about 430 MB lower from the heavy window to the end. Sampler, round 1: final jumps from 373 to 1,176 MB during its one 4-block span of heavy blocks (3,105,425-28, 28 s), where fw takes those blocks one at a time and rises gradually.

**Cause: not established.** The obvious reading is that one 4-block span of 10 MB blocks raises the arena high-water mark and the gap never closes. That is a hypothesis. E037 tests it with `final --block-sync-size 1`, with its expectations fixed before the run.

**This changes what the headline may mean.** Base cannot pass the wedge at default settings, so every base figure in this project uses `--block-sync-size 5`, and base has never been measured at default. E037's e036 arm is the first base-family figure at default settings.

## Part c4: lying peers (hydrogen victim, box81 liar, 21:14 to 22:53, `scripts/e036_liar_case.sh`)
The liar is a TEST-ONLY base build that overwrites `m_block_weights` in its chain responses: 1 byte for every block ("under") or 200 MB ("over"). Each case runs 600 s from 3,105,401 and restores the DB first. **These are single runs, not timing runs**, and hydrogen was the only test node. Heights are for reading progress, not for ranking arms.

| case | peers | victim | height at 600 s | oversize errors | requests | expected | met |
|---|---|---|---|---|---|---|---|
| ref | .22 | e036 | 3,107,836 | 0 | 467 | past the window, 0 | yes |
| under1 | under liar | e036 | 3,105,401, stuck | 595 | 595 | stuck, oversize errors | yes |
| under2 | under liar | final | 3,108,123 | 0 | 791 | progress, 0 | yes |
| under3 | under liar + .22 | e036 | 3,107,916 | 1 | 645 | past the window through .22, oversize errors and drops | past the window yes; 1 error, and .22's connection did not drop |
| under4 | under liar + .22 | final | 3,108,569 | 0 | 1,211 | near ref, 0 | yes |
| over1 | over liar | e036 | 3,107,554 | 0 | 2,155 | progress, one block per request, slower than ref | yes |
| over2 | over liar + .22 | e036 | 3,107,879 | 0 | 876 | progress, 0, between ref and over1 | progress and 0 yes; narrow miss on between, 43 blocks above ref in one run |

All hashes matched .22 at the height reached.

**Reading:**
- **A patched node whose only peer under-reports is wedged, as base is at the same point.** Under1 is the same failure as E001, 595 attempts in 600 s. That peer could also stall it by not serving blocks at all, so in that position lying gives it nothing new, but a final node passes this case and an e036 node does not.
- **With one honest peer, one under-reporting liar did almost nothing.** Under3 had one oversize error, at 0.12 s, on the liar's connection. The span was erased when that connection closed, and .22 carried on. The .22 connection did not drop during the run.
- **But the liar was given only one chance.** Its lie only matters when its span reaches the heavy blocks, and none of its 17 later requests came back oversize. One run of one race does not bound how often that happens.
- **Over-reporting costs requests, not safety.** Over1 asked for one block per request (2,155 requests, about 2,150 blocks). That cost about 12% of the height gained against ref (2,153 vs 2,435 blocks in 600 s), on a fast LAN link. Over a slower link the per-request round trip would cost more. Not measured.
- **Final's cap uses no peer data,** so under2 and under4 behave as if nobody lied.

**Two corrections to my harness, neither changes the table:**
- `drops=1` in the ref, under3 and over1 chain lines is not a liar effect. Each is a "Failure in prepare_handle_incoming_blocks" followed by "dropping connections" within 2 s of the stop at the end of the run, on whichever peer was active. The script counted it as a drop. Real in-run drops: none, apart from the oversize close itself.
- The "liar connections" lines in the orchestrator and the connection column in `*.height.csv` are empty or 0 because I queried `/get_connections`, which is a JSON-RPC method. So the check that only hydrogen connected to the liar did not run. The isolation in c4 rests on its flags (`--hide-my-port`, `--out-peers 0`, unadvertised port, exclusive node 127.0.0.1:1), which were the point of the design, but I did not observe it. Fixed for c5.

## Part c5: a peer that lies and then does not answer (queued after E037)
C4's liar answers at once, so its oversized span dies with its connection in 0.12 s. From reading the code, a liar that holds the span keeps it scheduled, since a kick for not answering leaves the span in place until the score runs out, and another peer can be asked for that span after 5-30 s (`should_download_next_span`). That request would be oversize on the honest peer's connection and close it. This has not been run. `scripts/e036_c5_run.sh` holds the cases and the expectations.

## Decision so far
Report only, and the patch stays out of this repo pending the owner.
- **Against the wedge with honest peers, the patch beats 0003 on every measured axis on this chain.** Wall -6.6%, peak -31.5%, and an explicit `--block-sync-size` cannot defeat it.
- **Against lying peers it is weaker than 0003 in one measured case:** a sole under-reporting peer wedges it (under1).
- Nothing about fw yet covers a negative test, a cgroup minimum or a second machine. The cgroup minimum comes in E037.

## Guardrails
- One change per arm: fw differs from final by removing 0003 and adding the patch; hashes in `evidence/E036/e036b.chain`.
- 6/6 long hashes, 4/4 wedge, 7/7 lying-peer. No shadow lanes. Governor pinned for the timed runs.
- The liar never joined a network; see the correction above for what was and was not observed.
- Evidence: `evidence/E036/`: chains, long summary and results, per-stretch output, per-case height files, the under3 liar trace. No raw logs, and no copy of the patch.
