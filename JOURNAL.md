# monerod memory-optimization journal

Goal: real reduction (target 40%) in monerod memory. Metrics: peak/steady anon + private-dirty (from /proc), and min cgroup memory.max for a full sync.
Guardrails: same final chain state (top hash), no verification weakened, no cost shifted to disk/swap, wall time near baseline.

## 2026-11-02 setup
- Baseline builds: upstream master 3fd0f88c2 -> ~/work/monero/build/baseline ; FCMP++ v0.19.0.0-beta.3.1 (d80596ad1) -> ~/work/monero-fcmp/build/beta31 (daemon only, BUILD_TESTS=OFF).
- Syncs (fully verifying; no embedded block hashes on stagenet/testnet in either tree):
  - stagenet, master build, public peers: ~/work/chains/stagenet, trace ~/work/bench/mem/stagenet_sync_baseline.csv
  - stressnet (testnet nettype), beta31 build, exclusive peer 192.168.1.22:28080: ~/work/chains/stressnet, trace ~/work/bench/mem/stressnet_sync_beta31.csv
  - both started ~11:42/11:50 and run concurrently (CPU/page-cache contention; first-look traces only, not A/B numbers).
- Sampler: ~/work/bench/mem/sample.sh (10 s, /proc status + smaps_rollup + RPC height).

## Findings
- FCMP++ branch already calls rct::limitMaxMemArenas() from core::init (cryptonote_core.cpp:444): M_ARENA_MAX = max(2, nthreads) = 24 here. Upstream master lacks this. Do not count it as our win on stressnet.
- RandomX: 2 cache slots x 256 MB (main + secondary seed); full 2 GB dataset only with MONERO_RANDOMX_FULL_MEM.
- Block download queue cap BLOCK_QUEUE_SIZE_THRESHOLD = 100 MB (--block-download-max-size); levin max packet 100 MB.
- fcmp_pp TreeCache is wallet-only (not in monerod).
- Stagenet (master): anon 217 MB @105k -> 621 MB @126k -> 698 MB @128k while sync rate fell ~10x. Suspect heavy-block stretch + queue + glibc fragmentation. TODO: attribute with heaptrack.

## Backlog (later phases)
- WALLET (owner: "eventually do the wallet as well", daemon first): fcmp_pp/tree_cache.h LeafCache / TreeElemCache / locked-output maps have no explicit bound found (tree_cache.h:120-129). Profile wallet2 refresh memory after daemon work.

## 2026-11-02 12:2x research repo
- Owner asked to treat this as a full research project with notes and evidence. Created git repo ~/work/research (README: metrics/guardrails; FINDINGS; experiments/E000; scripts; evidence/env). Mirror on the control box: ~/research-mirror.
- Env: glibc 2.39, gcc 13.3, THP=madvise, nr_hugepages=0 (RandomX LARGE_PAGES attempt falls back), ptrace_scope=1 (heaptrack -p needs sudo), overcommit=0.
- 12:20 stagenet_sync_baseline: height /, anon 994 MB, peak anon so far 1475 MB
- 12:20 stressnet_sync_beta31: height 404461/3123061, anon 156 MB, peak anon so far 156 MB
- Stagenet (master) anon: 217 MB @105k -> ~1.45 GB peak @139-146k -> 994 MB @183k. Transient spike, not a leak; it falls back after the heavy stretch. Peak is the metric that sets the RAM a node needs. FINDINGS F2 updated.
- Harness bug: 30/192 stagenet samples have an empty height (get_info curl -m 5 times out while the node is busy). Memory columns are unaffected. Fix for the next sampler version: read the height from the "Synced N/M" log line as a fallback. The running sampler is left unchanged so the trace stays continuous.

## 2026-11-02 19:00-19:20 stagenet done; stressnet sync wedged at 3,105,401 (E001)
- Stagenet (master) synced to 2,242,240. Steady-state anon after sync: ~1.85 GB; peak anon 1.92 GB (near h=1,594,175).
- Harness bugs found:
  1. watch_syncs.sh missed "synced", because get_info returns target_height=0 once a node is synchronized (the script required target>0).
  2. sample.sh v1 column labels: /proc status lists VmHWM *before* VmRSS, so the v1 CSV columns 4 and 5 are swapped (col4 = VmHWM, col5 = VmRSS). RssAnon (col6) and later columns are correct. Fixed in sample.sh v2, which also adds a height fallback from the log.
  3. pgrep -f patterns that contain a path also used in the same `ssh bash -c` command line match the ssh shell itself. Use the PID instead.
- **Stressnet stall (E001):** stuck at 3,105,401 from 18:47 to 19:08 with 0 connections. With net.p2p:DEBUG enabled for 45 s, the log showed a loop every second: handshake OK, request objects, then
  `levin_protocol_handler_async.h:619 Maximum packet size exceed!, m_max_packet_size = 100000000, packet header received 134253303, command 2004`, close, reconnect.
  - command 2004 = BC_COMMANDS_POOL_BASE+4 = NOTIFY_RESPONSE_GET_OBJECTS (cryptonote_protocol_defs.h:273).
  - Requester sizing: core::get_block_sync_size (cryptonote_core.cpp:930) projects from max(weights of the last BLOCKS_MAX_WINDOW=100 blocks, queue average). If projected*100 < BATCH_MAX_WEIGHT (10 MB), it requests 100 blocks.
  - Responder: caps only by count (CURRENCY_PROTOCOL_MAX_OBJECT_REQUEST_COUNT, cryptonote_protocol_handler.inl:1177), not by bytes.
  - Chain data from .22 headers (get_block_header_by_height; the restricted get_block_headers_range returned nothing): all 100 blocks 3,105,302..3,105,401 are <1 kB. Blocks 3,105,402..3,105,501 total 162.4 MB / 1,793 txs (block_size field; the RPC may report weight). The largest are ~10.0 MB (3,105,434 and 3,105,437).
  - So: 100 empty blocks -> "tiny" estimate -> a 100-block request -> >100 MB response -> rejected at the levin layer -> retry with the identical estimate, because the chain has not advanced. This is a permanent wedge for any node syncing through this point with default settings, from any peer. Side effect: .22 built a ~134 MB response about once a second for ~20 min.
  - Open question: I expected the short-term block-weight median rules to forbid ~10 MB blocks 20-30 blocks after 100 empty ones. Either HF17/18 changed this or my recollection is wrong. Not needed for the stall explanation; check later.
- Workaround (config change, recorded): restarted the beta31 node at 19:09 with `--block-sync-size 5`; new trace ~/work/bench/mem/stressnet_sync_beta31_part2.csv (sampler v2). Sync resumed (3,105,401 -> 3,105,431 within ~2 min).
- **Big memory lead:** after the restart, anon went 318 MB -> 4.6 GB in ~16 s while processing blocks 3,105,402..3,105,421, which hold only 0.3 MB / 18 txs in total. It is still ~5.1-5.5 GB minutes later. So it is not block data or the download queue (the batch is now 5 blocks). Something initializes on first use and is retained. The first run's peak anon was 5.26 GB near the fork as well. Hypothesis to test first (E002): FCMP++ verification setup (per-thread or global precomputation in the Rust verifier, or tree-growth state) allocated on the first FCMP++ tx. Plan: heaptrack, plus a thread-count sweep (--max-concurrency) to see whether it scales per thread.

## 2026-11-02 19:30 reference peer RPC
- The owner opened .22:28081 (it was silently dropped before: TCP connect timed out from both hydrogen and the control box). It is unrestricted. Version 0.19.0.0-beta.3.1-release, the same tag as our beta31 build. Snapshot of get_info, get_version and hard_fork_info: evidence/env/peer_192.168.1.22_20261102_1930.json
- get_block_headers_range now works (unrestricted); use it instead of per-height calls.

## 2026-11-02 20:10 E001 follow-up: is the sync wedge known? why didn't other stressnet nodes break?
- **Bytes vs weight:** for post-fork FCMP++ blocks, the real wire bytes (block blob + tx blobs) are ~82-84% of the reported weight: 3,105,434 is 8,205,218 B vs weight 10,030,357 (0.818); 3,105,436 is 0.838 (scripts/peer_check.py). The 162.4 MB of weight in 3,105,402..3,105,501 x ~0.826 ≈ 134 MB, which matches the observed 134,253,303-byte NOTIFY_RESPONSE_GET_OBJECTS. So the failing request was the 100-block window 3,105,402..3,105,501.
- **Upstream:** master's get_block_sync_size has the same logic (only difference: an overflow-safe rewrite of the "tiny" comparison). Both trees have the same LEVIN_DEFAULT_MAX_PACKET_SIZE=100 MB and the same count-only cap on the responder. So this is upstream logic, not an FCMP++ regression. Whether mainnet can hit it depends on whether its block-weight rules allow >100 MB of bytes in 100 blocks right after 100 tiny ones (unverified).
- **Known?** I found no report of this exact failure: a web search for the error string, plus seraphis-migration issue titles. Closest: seraphis-migration#157 (open), the same 100 MB levin limit hit by the txpool-complement response, which causes peer disconnects. #390 (closed) is a different stressnet stall (incorrect miner tx); it mentions "new stressnet scaling", which may be why 10 MB blocks can follow empty ones (unverified).
- **Why other nodes are fine (reasoning, partly unverified):** (1) nodes online while those blocks were mined got each block individually by relay (<=10 MB each), never as a 100-block batch. (2) The wedge needs the 100 blocks before the request start to be tiny AND the next 100 to exceed 100 MB of bytes; 3,105,402 fits. (3) Our node had a single exclusive peer, so after each failure it reconnected and re-requested the same first span. With many peers, other spans may land and raise the queue-average estimate enough to shrink the retry (not verified).
- .22 currently has 19 peers: 17 at the tip, <external-peer> at 1.12M, and **192.168.1.116 at 2,097,439, syncing**. Natural experiment: watch .116's height via .22 get_connections (read-only) as it passes 3,105,401.
- Memory relevance: the responder builds the whole response in memory (~134 MB here, once a second while the requester was wedged). A byte cap on responses would also bound serving-side transient memory. Candidate for later.

## 2026-11-02 20:00-20:20 E002a result; pop_blocks slowdown (side finding)
- **E002a (heaptrack, synced node restarted, 600 s):** heaptrack peak heap 315.89 MB; peak RSS (including heaptrack) 397 MB; sampler peak RssAnon 316 MB. Top consumer: randomx::AlignedAllocator 281 MB (89%; the RandomX light cache plus VMs). No allocator gap at this state (heaptrack peak ≈ RssAnon). So a freshly restarted synced node needs ~0.32 GB, while the same DB after syncing through the window held ~3.9 GB. **H1 (startup init) is rejected; the GBs accumulate during sync.** Next: E002b, a replay of the window under heaptrack. Artifacts: ~/work/research-artifacts/E002a-restart-synced/ (peaks.txt).
- **pop_blocks slowdown:** popping the synced DB (3,123,281) toward 3,105,401 ran at 0-12 s per 1000 blocks, then stalled >10 min on one chunk at ~3,110,281. perf (10 s, single busy thread): tx_memory_pool::prune 20.8%, mdb_node_search 22.2%, mdb_mid2l_search 16.8%, mdb_cursor_set 12.3%, get_txpool_tx_meta 5.5%. Cause: the RPC `pop_blocks` uses `KV_SERIALIZE_OPT(keep_txs, true)` (core_rpc_server_commands_defs.h:2568), so every popped tx goes back to the txpool, and prune() costs more as the pool grows (quadratic-ish). After SIGTERM (clean exit), the DB had reached 3,109,537 with **85,841 txs in the pool**.
  - Fix in scripts/pop_to.sh v2: flush_txpool first (took ~65 s for 85,841 txs), then pop with keep_txs=false. That gives 3-6 s per 1000 blocks again.
  - Relevance: (a) this is how to rewind for experiments without a stale pool distorting memory; (b) candidate issue: pop_blocks/reorg with keep_txs on heavy blocks degrades super-linearly in tx_memory_pool::prune. Note for later; not pursued now.
- The first E001 builder agent was stopped (it was polling the stalled pop). A new builder agent handles: wait for RESULT, then snapshot stressnet_wedge_h3105401, then repro_e001.sh (60 s bug run plus 60 s control).

## 2026-11-02 20:25 E001 reproduced
- Snapshot stressnet_wedge_h3105401 (18 GB; sha256 in evidence/ARTIFACTS.sha256), made by pop_to.sh v2 with a hash match against .22 at index 3,105,400.
- repro_e001.sh, 60 s each: **bug** (defaults) stayed at 3,105,401 with 59/59 requests failing on 134,253,303-byte responses (byte-identical to the original wedge). **control** (--block-sync-size 5) went to 3,105,431 with 0 errors. Evidence: evidence/E001/. The report draft has been updated.
- **Memory side result (feeds E002):** the control run went from ~0.3 GB to **4.98 GB RssAnon within 60 s / 30 blocks** (3,105,402..3,105,431, mostly near-empty plus a few ~10 MB blocks). The bug run, which processed no blocks, stayed at 306 MB. E002a (synced restart, no tx verification) stayed at 316 MB. Revised hypothesis: a one-time allocation of ~4.5 GB triggered by the first FCMP++ tx verification (per-thread or global precomputation?), not proportional to block data. E002b: heaptrack the same 30-block window from the wedge snapshot.

## 2026-11-02 20:40 E002b ran; harness race
- E002b heaptrack run finished cleanly: 359,316,557 allocations, 83.4M temporary, 400 MB trace (~/work/research-artifacts/E002b-window/). heaptrack_print analysis is in progress.
- **Harness bug:** e002b.sh copied run.txt's last lines (which end in "DONE") into its own summary, so the waiter (`tail -1 | grep DONE`) fired before heaptrack_print had run. Nothing was lost. Fix: e002b.sh v2 uses the marker E002B_COMPLETE and filters DONE out of the copied lines (saved as scripts/e002b.sh.v2 so the running v1 is not overwritten mid-run). Rule: every script gets its own unique completion marker.
- Started the E001-fix build: ~/work/monero-fcmp-e001fix/build/beta31-e001fix, daemon only, -j10 (no monerod running; heaptrack_print uses ~60 MB).

## 2026-11-02 20:47-21:05 check-in #1 (cron)
- Box: load ~8-10 (our runs only), no selfishmining lanes, 59 GB disk free.
- **E001-fix, first attempt (harness stuck, result still informative):** the patched binary (beta31 + 7dacc3156, sha256 67c33a8b…) synced on DEFAULT settings from 3,105,401 to **3,106,475 (+1,074 blocks) in ~7 min with 0 oversize errors**. Synced-line steps: 215x4, 49x2, 112x1 (4 = the cap: 90 MB / 20 MB block weight limit; the 1s and 2s are the existing estimator choosing fewer for heavy blocks). The harness itself got stuck: repro v2's get_last_block_header calls (RPC) block while the node verifies heavy blocks (blockchain lock), so the start loop never finished. Stopped via SIGTERM (clean). Evidence: ~/work/research-artifacts/E001/repro_fix_attempt1_harness_stuck/bug.log.
  - repro_e001.sh **v3**: heights from "Synced N/M" log lines; set_log at start; stop falls back to SIGTERM; end-hash check from an idle --offline restart against .22; rewind after each run. Relaunched at 20:48 (bug and control runs with the patched binary, 90 s each).
  - Side observation: core RPC (get_info, get_last_block_header) is unresponsive for long stretches while the node verifies heavy FCMP++ blocks. Monitoring and wallets depend on this RPC. Note for later.
- **E002b attribution (peak-weighted stacks, rustfilt-demangled; scripts/stack_attrib.py; evidence/E002b_stack_attrib.txt):** 4,331 MB (86.8%) of the 4.99 GB peak is inclusive under `rct::batchVerifyFcmpPpProofs` → `fcmp_pp::verify(vector)` → Rust `fcmp_pp_verify`. 2,314 MB (46%) is under `generalized_bulletproofs_ec_gadgets::dlog::divisor_challenge_eval`. Sync pipeline: handle_response_get_objects 553 MB inclusive; block_queue ~41 MB.
  - Code: `Blockchain::handle_block_to_main_chain` → `batch_verify_fcmp_pp_txs` (blockchain.cpp:4685) → `batch_ver_fcmp_pp_consensus` → `rct::batchVerifyFcmpPpProofs` (rctSigs.cpp:1667). Per block, every FCMP++ proof of the block is bin-packed by input count into **one batch per thread** (n_threads = threadpool concurrency = 24 here), and each thread runs `fcmp_pp::verify(batch)`.
  - Two models: (A) the batch verifier accumulates per-proof state for its whole batch, so memory ∝ proofs per block, ~thread-independent; (B) a transient per-proof circuit/divisor working set, so memory ∝ threads x per-proof. **E003 (thread sweep, fixed height window 3,105,401→3,105,440) discriminates them**; it is chained to start right after the E001-fix test.
- Harness note: stack_attrib.py's "owning frame" view printed nothing (it picks the wrong end of the folded stack). Only the inclusive view is valid; fix it before next use.

## 2026-11-02 21:10 E001-fix PASSED (repro v3)
- Patched binary (sha256 67c33a8b…), rewind to 3,105,401 before each run, 90 s each. **bug (defaults):** 3,105,401→3,105,431 (+30), tip at stop 3,105,432 with **hash = .22**, **0 oversize errors**, 7 cap lines "capping block sync size from 100 to 4 blocks (block weight limit 20000000 bytes)". **control (--block-sync-size 5):** +30, hash = .22, 0 errors, no cap lines (explicit size respected). Peak RssAnon 5.3 / 4.9 GB (FCMP++ verification, E002).
- Same throughput in this window (verification-bound). The issue text (reports/E001-sync-wedge-ISSUE.md) now has a "Proposed fix (prototype, tested)" section with the diff, results, trade-offs and assumptions. **Ready for the owner to paste upstream.**
- Note: the evidence/E001/*.mem.csv files from repro v3 (bug.mem.csv, control.mem.csv) overwrote the v1 repro CSVs of the same names. The v1 copies are still in ~/work/research-artifacts/E001/repro/.

## 2026-11-02 21:15 E003 concurrency sweep → model B
- 1/4/12/24 threads: peak RssAnon 1,232 / 2,033 / 3,302 / 5,400 MB; window wall time 844 / 279 / 199 / 220 s (same 40 blocks, n=1 each). **Peak scales with concurrent verifier threads** (~170-270 MB each, on top of ~1 GB base). 12 threads (physical cores) were faster than 24. See experiments/E003-concurrency-sweep/README.md.
- Started E004a: a 3-round alternating A/B of c24 vs c12 with the new scripts/ab_window.sh (rewind, fixed window, peak anon/private-dirty/RSS, /proc io, end-hash check from an offline restart).

## 2026-11-02 21:35 verifier code reading; E005 prepared
- Rust sources (scout): monero-oxide @ 31c26d96 in ~/.cargo/git/checkouts/monero-oxide-3366610e7b6e517d/31c26d9/. Per-proof circuits are built in `Fcmp::verify` (crypto/fcmps/src/lib.rs:938); constraints are stored as `LinComb`s; `ArithmeticCircuitStatement::verify` only folds them by z powers into dense vectors. Streaming is blocked by transcript interleaving (see experiments/E005-lincomb-shrink/README.md; deferred to E007).
- E005 (LinComb shrink_to_fit at constrain time) prepared: ~/work/monero-oxide-e005 + ~/work/monero-fcmp-e005 (cargo [patch]); cargo check passes. Two prep-script slips, both caught before building: the cargo checkout already has a .git (init/commit aborted), and the first lincomb insert landed outside the impl block. Build waits for E004a to finish (RAM).

## 2026-11-02 21:45-21:55 E004a CONFIRMED; E004c prepared
- E004a (3 alternating rounds, c24 vs c12): median peak RssAnon 5,614 → 3,393 MB (**-39.6%**), RSS 6,434 → 4,481 MB, wall 221 → 197 s (-10.9%), disk writes unchanged (~466 MB), every end hash = .22. Full table: experiments/E004-verify-concurrency/README.md, evidence/E004a/.
- E004c: targeted patch in rct::batchVerifyFcmpPpProofs, min(pool, boost::thread::physical_concurrency()) batches (commit 2e80c0685 in ~/work/monero-fcmp-e004c; evidence/E004c.diff). rctSigs.cpp syntax-checked with the baseline compile command. Build + A/B chained after the E005 chain (so no build runs during the E005 timing runs).
- The waiter task "failed" with exit 1 only because its final `grep SIGKILL|FAILED` matched nothing. Harmless.

## 2026-11-02 22:20 E005 rejected; per-verifier working set analysed; next E006/E007
- E005 A/B: median peak 5,350 (base) vs 5,380 MB (e005); wall 220 vs 220 s. No effect.
- Peak-stack reading: the biggest stack is growth of `constraints: Vec<LinComb>` in Circuit::mul (two constraints per gate). The working set is the constraint/term COUNT. Options: bound concurrency (E004c, in progress) or stop storing the circuit (E007, a multi-pass streaming verifier). E006 will first measure the CPU share of circuit building.
- Process slip: another ssh-quoting failure (an apostrophe in a heredoc inside ssh '...'). Nothing executed. Re-done via a script file (scripts/record_e005.sh). Rule reaffirmed: prose goes into files, never into ssh one-liners.

## 2026-11-02 22:35-22:50 E004c surprise; E006 profile; E004d chained
- E004c A/B: wall 220 → 201 s (-9%), but peak RssAnon 5,600 → 5,527 MB (-1.3%). Explanation: glibc arena retention; M_ARENA_MAX = pool size (24), and all 24 pool threads run FCMP++ batches over time, so each arena keeps its high-water working set. E004d = E004c + arenas capped at physical cores; built and A/B'd via the new generic scripts/chain_build_ab.sh.
- E006 perf profile: ~52% of CPU in ArithmeticCircuitStatement::verify (folding + IPA), ~36% curve math, ~5% circuit construction. So E007 (streaming, 3-pass) costs ~+10% CPU. perf_classify.py misattributed the 50% symbol (regex 'Circuit' matched ArithmeticCircuitStatement); corrected manually. Fix the script before reuse.
- Harness note: an ssh launching a nohup'd chain did not return (stdin probably not redirected); TaskStop'd the local ssh and the remote chain survived. Use `< /dev/null` for remote nohup launches.

## 2026-11-02 22:47-22:55 check-in #2 (cron)
- Box: load ~14 (E004d A/B only), no selfishmining lanes, 56 GB disk free, 12 GB RAM available.
- E004d: build OK (sha256 61517c0a…); A/B running. Round 1 base = 5,108 MB / 222 s, hash match; e004d run in progress.
- E007: a Plan agent is reviewing the 3-pass streaming design against the code (transcript cloneability, the order of transcript ops during circuit building, constraint validation, other consumers, risks).
- Wrote scripts/min_mem.sh: binary search over a systemd-run scope MemoryMax (swap off) for the smallest limit that syncs the window within 1.1x the reference wall and ends on .22's hash; records the cgroup memory.peak and oom_kill count. Self-test of the scope mechanics passed. Not run yet (it needs a quiet box, after E004d).

## 2026-11-02 23:00-23:10 E007 feasibility: FEASIBLE WITH CHANGES; implementation started
- Plan-agent review (details in experiments/E007-streaming-verifier/README.md): the transcript is trivially cloneable; circuit building only derives challenges (no proof reads); constraints are deterministic; validation can be done per constraint; and no transcript op after (y, z) depends on the folded weights. That allows a 2-build plan (Discard build on the real transcript; both statements' transcript phases; one replay build on a clone folding c1 and c2; apply). Expected: per-verifier ~200 MB → O(n) dense vectors; ~+5% CPU.
- Implementation delegated to an agent with a strict spec (soundness guards, determinism checks, bounds checks, equivalence/rejection tests). It must not compile until the E004d timing runs finish. My diff review is mandatory before any monerod build.

## 2026-11-02 23:05-23:20 E004d: arena cap not enough; E004e (malloc_trim) prepared
- E004d A/B: median peak 5,601 (base) → 5,146 MB (-8%), wall 220 → 197 s. The prediction (≈3.4 GB) failed: with 24 threads on 12 arenas, co-located working sets keep total retention near 24 working sets.
- The retention hypothesis is still consistent with everything (E000: 3.9 GB idle after sync; E002a: 0.32 GB after a restart). Direct test: E004e = E004c + malloc_trim(0) once per block after FCMP++ batch verification. Harness v2 adds a post-window idle RssAnon measurement (local temporary ban of the peer on our own node, lifted afterwards).
- Owner pinged with the E004d result (terminal notification; Remote Control inactive).
- Process slip (23:10): nested heredocs with the same `EOF` delimiter truncated a script; its tail ran harmlessly on the control box. Fixed by committing the partial edits. Rule: unique heredoc delimiters, or write files with the editor tool.

## 2026-11-03 00:20-00:30 E007 implemented and reviewed; E004e A/B running; window is 128-input txs
- The E007 agent finished. The streaming verifier is in monero-oxide-e007 at c215a805a; all tests pass, plus 9 new equivalence and tamper tests. I reviewed the full non-test diff: transcript and RNG order are unchanged, z is bound to the real transcript, every path fails closed. Verdict OK for an experimental build. Details are in experiments/E007-streaming-verifier.
- The agent's micro-measurement showed stored constraints at only ~2 MB per input, which looked too small to explain ~200 MB per thread. scripts/window_inputs.py resolves it: 851 of the window's 1,044 txs have 128 inputs (mean 104.8). One proof covers all inputs, so a proof stores about 250 MB. Report caveat: this window is a worst case (max-input txs).
- The E004e A/B started at 00:25 (scripts/run_e004e.sh), with the governor pinned to performance and restored afterwards. **Hygiene note:** the E003-E004d macro runs used the default schedutil governor. Their A/B comparisons are internal, since both arms ran under the same governor and alternated, but wall times are not comparable across governor settings. chain_build_ab.sh v2 now pins the governor too.
- Chain e007 is queued (build ~/work/monero-fcmp-e007, then a 3-round A/B vs base) and waits for CHAIN_E004E_COMPLETE.

## 2026-11-03 00:25-01:00 E004e CONFIRMED: -44.6% peak, -88% idle (check-in 00:47)
- Check-in 00:47: no shadow lanes. Load ~19 came from our own A/B node (24 verifier threads). 54 GB disk free.
- E004e A/B, 3 rounds, governor pinned:
  - peak RssAnon median 5,309 → 2,943 MB (-44.6%; ranges 5,154-5,347 vs 2,941-2,965, disjoint)
  - Private_Dirty -44.7%
  - post-idle RssAnon 4,794 → 574 MB (-88%)
  - wall 219 → 207 s (-5.5%)
  - writes unchanged, 6/6 hashes match
  - All three predictions held. The glibc retention hypothesis is confirmed: the arena-count cap (E004d) failed, while an explicit trim once per block works.
- Owner pinged (terminal notification).
- Chain e007 started building as soon as CHAIN_E004E_COMPLETE landed. The combo chain is queued behind it (tree monero-fcmp-combo = E004c + E004e + E001 fix + E007).
- New tool scripts/ab_stats.py prints a per-arm medians/ranges table and the deltas vs base.

## 2026-11-03 02:47-03:00 Check-in: E007 -59% peak / -50% wall; combo -67% peak; negative test PASS
- Box: no shadow lanes, idle, 53 GB free.
- Both chains finished while I was away (e007 at 01:18, combo at 01:44), all hashes matching:
  - **E007** (streaming verifier only): peak 5,582 → 2,291 MB (-59%), wall 218 → 108 s (-50%).
  - **E008 combo** (E004c + E004e + E007 + E001 fix): peak 5,289 → 1,751 MB (-67%), post-idle 4,850 → 993 MB (-80%), wall 220 → 117 s (-47%).
- The 2x speed-up contradicts the agent's +40% micro-benchmark. Explanation: the old verify's CG fold is O(c·q). That is cheap for 1-8 inputs and dominant for 128 inputs (the window is 82% 128-input txs). A profile of the combo build is running to confirm.
- Because a 2x speed-up on crypto code is the classic sign of skipped work, I ran a **monerod-level negative test** (scripts/negtest.sh): bit-flipped FCMP++ proofs submitted to our own offline node. Base and combo each rejected 24/24 at "Failed to verify input FCMP++ signatures" and accepted 3/3 originals (128-, 8- and 2-input txs).
- Harness bug found and fixed: the peak awk compared strings (F18). One RSS value was corrected; all anon peaks re-verified.
- Owner pinged with the combo headline.
- Queued: the combo CPU profile, then the min_mem chain (combo, then base) with the governor pinned.
- 02:56 profile_combo done: the baseline 50% hotspot (ArithmeticCircuitStatement::verify) is gone; the top is now curve/field math (Selene add 19%, Montgomery 18%, mul_wide 12%). This confirms the O(c·q) explanation. The min_mem chain started right after (combo first).

## 2026-11-03 03:23-03:35 E009 min cgroup memory: -67.5%
- min_mem chain (combo, then base; governor pinned): minimum passing MemoryMax is **combo 1,866 MB vs base 5,750 MB (-67.5%)**, bracket -66.5% to -69.3%. All passes match .22's hash and finish within the 1.1x wall limit; at the minimum, walls are unchanged (106 s, 219 s).
- All 7 fails are memcg OOM kills (kernel log), with anon at about the limit. Base near its limit first slowed as page cache was squeezed, then was killed. The A/B anon-peak metric and the cgroup metric agree (-67%).
- Harness bug F20: oom_kills was always 0, because memory.events was read after the scope vanished. Fixed in min_mem.sh v2.
- Owner asked (03:00) to be pinged when min_mem results were in. They were at the terminal, so PushNotification was suppressed as redundant and the result was reported in the chat.

## 2026-11-03 03:31-03:40 E010 long resync started
- Chain density from .22's headers (read-only): 3,105,401..3,113,400 holds 190k txs (1.9 GB of weight), after which blocks are nearly empty up to the tip (3,123,5xx). This is long enough to validate the result on a mixed, mostly small-tx workload.
- ab_window.sh v3 adds REWIND_SNAPSHOT: the DB is restored from snapshots/stressnet_wedge_h3105401 (a 1-2 min copy) instead of popping 18k blocks, and pop_to.sh then verifies the hash at 3,105,400 (RESULT OK).
- Arms: combo_default, base_bss5, combo_bss5. combo_default is syncing in 4-block batches from the start, which is the E001 cap at work. At log level 0 the cap message itself is not printed; the 4-block Synced increments are the evidence.
- Owner was told the min_mem result in chat (03:30).
- 03:37 Drafted reports/SUMMARY.md (owner-facing: headline table, mechanisms, guardrails, negatives, side findings, caveats, upstreamability). E010 marked pending.
- 03:37 Observation (E010, combo_default): the E001 cap gives 4-block batches only while the last 100 blocks are light. Once heavy FCMP++ blocks enter the lookback, upstream adaptive sizing drops to 1-block requests, at ~7 s/block vs ~2.9 s/block with --block-sync-size 5 in the window A/B. combo_default vs combo_bss5 in E010 will quantify this. It may be a second sync-sizing issue to note in the E001 write-up (default sizing is slow for heavy blocks). Timestamp fix: an earlier note said "03:50", but the box clock read 03:37; corrected.
- ~03:45 W001 (wallet track, step 1): a scout agent mapped the FCMP++ TreeCache. It is bounded by the 100-block reorg window except m_registered_outputs (~50-80 B per owned output, negligible). The likely wallet peaks are refresh-time transients (whole parsed_blocks batch, CacheStateChange). W002 will measure, after E010.

## 2026-11-03 04:47-04:52 Check-in: E010 2/3 arms done; a small-tx slowdown found; E011 queued
- Box: no shadow lanes, 53 GB free, load ~5 (our E010 node).
- E010 so far (1 run each, 3,105,401 -> >=3,123,400, all hashes match .22):
  - combo_default: wall 1,446 s, peak anon 1,588 MB, post-idle 1,301 MB.
  - base_bss5: wall 1,365 s, peak anon 5,603 MB, post-idle 4,376 MB.
  - combo_bss5: running (3,110,906 at 04:50).
- **Surprise: on the long run, combo is not faster than base overall.** scripts/segment_rates.py (new; per-segment seconds from the Synced log lines) shows why:
  - The window (to 3,105,441): combo 108-113 s vs base 217 s, as in E008.
  - Each later 1,000-block segment of small txs: combo 155-172 s vs base 137-146 s, i.e. **combo is +15-19% slower on small-tx blocks**.
  - combo_default vs combo_bss5 differ by only ~2%, so the batch size is not the cause.
- Candidates: E007's double circuit build (Discard pass + Accumulate pass; the old fold was cheap at low input counts), E004c's thread cap (SMT may help small proofs), or E004e's per-block malloc_trim (fixed cost × many blocks). The 40-block window could not see any of these, since it is 82% 128-input txs.
- E011 queued to separate them (see STATE). ab_window.sh v4 is applied only after E010 finishes, because editing a running bash script is unsafe.

## 2026-11-03 04:58-05:03 E010 DONE: memory holds over 18k blocks; wall +3.6% (small-tx +15%)
- combo_bss5 finished at 04:58. All three arms match .22's hash.
- Combo vs base (both bss5):
  - peak 5,603 → 1,503 MB (-73.2%)
  - post-idle 4,376 → 1,085 MB (-75.2%)
  - writes unchanged
  - wall 1,365 → 1,414 s (+3.6%)
  - combo_default (no bss flag) synced all 18,125 blocks: peak 1,588, wall 1,446.
- Per segment:
  - window 217 → 108 s
  - dense small-tx stretch 1,071 → 1,230 s (+14.8%; all 8 segments +13-19%)
  - near-empty tail 73 → 73 s
- No memory growth after the window: combo stays flat at 0.8-1.1 GB.
- My wall prediction (combo < base) was falsified. The small-input cost is real. E011 (5 arms, one change each) is running to attribute it.
- E011 hiccup:
  - The first start (04:58) died at the v4 patch: my comment anchor did not exist, because v3's comment replace had silently not matched.
  - All writes come after the assertions, so ab_window.sh was untouched (md5 checked).
  - I fixed the anchor (insert after the usage line), dry-ran the patch on a copy (diff + bash -n), and restarted at 04:59. The old chain log is kept as e011.chain.failed-v4patch.
- New scripts:
  - segment_rates.py: per-segment seconds from Synced lines.
  - mem_segments.py: RssAnon per height segment.
- Owner pinged with the E010 result (as requested).
- Timestamp fix (05:03): I had pre-written 05:05 into STATE and this heading before the work finished. The box clock read 05:02 at commit, so I corrected them. Rule: take times from the box clock, never estimate ahead.
- E011 at 05:02: prep is running (wedge snapshot restored, base syncing to 3,106,400). 56 GB free.

## 2026-11-03 06:47-06:51 Check-in: E011 12/15 runs; slowdown is the cap + trim, not E007; E012 queued
- Box: no shadow lanes, 42 GB free (the working snapshot h3106400 took 18 GB), load ~2-3 (our node).
- E011 prep:
  - Snapshot h3106400 made 05:15; pop_to RESULT OK.
  - Input mix of 3,106,400..3,107,399: 28,891 txs, mean 2.01 inputs (2-input 28,186; 1-input 685). Only 4 blocks hold a proof with >= 16 inputs.
- E011 interim (12 of 15 runs; walls in s for 1,000 blocks; cpu_s = utime + stime):
  - base 151/150/147, cpu ~1,320
  - e004c 161/160/161 (**+7%**), cpu ~832 (-37%)
  - e004e 170/170 (**+13%** vs base, so the trim adds +6% on top of the cap), cpu ~848
  - e007 157/154 (**+3%**), cpu ~1,435 (+8.5%)
  - combo 172/172 (+15%), cpu ~930
- Reading:
  - The combo's small-tx regression is mostly the two cheap fixes, which were designed for the old stored verifier: the batch cap (SMT helps small proofs, so the cap loses wall even though it saves CPU seconds) and the per-block trim (~9 ms per block, from the trim call and/or re-faulting).
  - E007's double build costs only ~3% wall here.
  - CPU seconds are not comparable across thread counts, because SMT siblings inflate CPU time; wall is the metric.
  - Small-tx window memory: base 1.0-1.5 GB, e004c 1.2-1.5, e004e 0.72, e007 0.92, combo 0.72-0.73 GB.
- Next: E012 makes the cap and the trim adaptive to proof size (patch dry-run clean, see STATE). The goal is to keep the window memory win and lose the small-tx cost.

## 2026-11-03 07:08-07:09 E011 DONE: small-tx cost = cap +7%, trim +6%, streaming +3%
- All 15 runs are done; all hashes match .22; no shadow lanes. The chain ended at 07:07:51 (governor restored).
- Medians for 1,000 blocks of 2-input txs:
  - base 150 s
  - e004c 161 s (+7.3%)
  - e004e 170 s (+13.3%)
  - e007 154 s (+2.7%)
  - combo 172 s (+14.7%)
- Ranges are ≤ 4 s. The effects add up. Peak anon: base 1,178, e004c 1,284, e004e 724, e007 918, combo 722 MB.
- Written up in experiments/E011-small-tx-attribution (F23); SUMMARY updated.
- E012 started on its own at 07:08: tree committed 4a51d434d, cargo/ninja build running.

## 2026-11-03 08:47-08:48 Check-in: E012 small-tx result (adapt +4% vs combo +15%); E013 queued
- Box: no shadow lanes, 35 GB free, load ~2-4 (our node).
- E012 build OK at 4a51d434d. Small-tx A/B (3 rounds, all hashes match):
  - base 149/151/151 s, 1,152-1,226 MB
  - combo 174/173/180 s, 728-735 MB
  - **adapt 155/157/157 s (+4%), 816-829 MB (-30% vs base)**
  - The adaptive cap and trim recover ~3/4 of the slowdown. The rest is about E007's +2.7%.
  - adapt costs ~90 MB more than combo on these light blocks, because it trims at most every 10 s.
- Heavy-window A/B, 4 of 9 runs:
  - combo 110 s / 1,769 MB
  - adapt 111 s / 1,697 MB
  - e007 111/111 s, 2,111/2,340 MB
  - So the cap and the trim are worth ~20-25% of peak on top of E007, and the cap no longer speeds up the heavy window once E007 is in. Its 9% gain in E004c was for the stored verifier.
  - adapt's post-idle (1,333 MB vs combo 1,087) is higher: it does not trim when idle after light calls. Note for E012.
- Queued E013 (STATE) to validate adapt as the recommended build: headline A/B vs base, negtest, min_mem, long resync. It is gated on the full E012 numbers.

## 2026-11-03 09:15-09:16 E012 DONE: adapt keeps the memory win and drops most of the small-tx cost
- E012 is complete: 18 runs, all hashes match .22.
- Small-tx window:
  - base 151 s / 1,167 MB
  - combo 174 s (+15.2%) / 732 MB
  - **adapt 157 s (+4.0%) / 822 MB (-30%)**
- Heavy window:
  - combo 110 s / 1,861 MB
  - **adapt 109 s / 1,639 MB**
  - e007 111 s / 2,338 MB
- adapt's 12% lower heavy peak vs the combo has disjoint ranges, but I have no mechanism for it (same code path on heavy calls), so I record it as "no worse".
- Post-idle is adapt 1,333 vs combo 1,107 MB: no idle trim.
- E013's gate passed at 09:15:55; its heavy-window A/B base vs adapt is running.
- Written up in experiments/E012-adaptive-cap-trim (F24); SUMMARY updated.

## 2026-11-03 10:47-10:48 Check-in: E013 (a)-(c) done; adapt holds the headline; long resync running
- Box: no shadow lanes, 35 GB free, load ~5 (our node).
- (a) Heavy-window A/B, base vs adapt, 3 rounds, all 6 hashes match:
  - peak RssAnon 5,600 (5,403-5,617) → 1,780 (1,762-1,816) MB: **-68.2%**
  - Private_Dirty -67.8%
  - post-idle 4,993 → 1,368 MB: -72.6%
  - wall 222 → 111 s: -50.0%
  - CPU s -78.8%
  - writes unchanged
  - adapt's peak here (1,780) is above its E012 median (1,639). So the 12% gap vs the combo in E012 was session variance, as suspected; adapt ≈ combo on the heavy window (combo medians 1,751 in E008, 1,861 in E012).
- (b) negtest PASS:
  - 128-input tx at 3,105,424: 8/8 tampered rejected.
  - 8- and 2-input txs at 3,105,414: 16/16 rejected.
  - Every rejection logged "Failed to verify input FCMP++ signatures"; all originals accepted.
  - The whole step took only 23 s, which I checked: the log counts are 8 and 16.
- (c) min_mem adapt = 1,866 MB (largest fail 1,765, tol 125). That is the same grid point as the combo: at 125 MB resolution they are equal, and -67.5% vs base. All fails were OOM kills.
- (d) Long resync: base_bss5 1,345 s / 5,613 MB (E010: 1,365 / 5,603). adapt_default was at 3,107,463 at 10:47; adapt_bss5 comes after it.

## 2026-11-03 11:15-11:25 Owner question "how real is ~70%?"; E015 (safety) and E014 (small machines) queued
- 11:15: adapt_default long resync done: 1,305 s vs base_bss5 1,345 s (-3%), peak 1,663 vs 5,613 MB (-70%), post-idle 1,267 vs 4,642 (-73%), hash yes. adapt_bss5 is running.
- The owner asked how real the ~70% is. My answer:
  - Solid: it reproduces across sessions; two metrics agree (anon peak and the minimum cgroup limit); the guardrails held; the mechanisms are understood.
  - Limits:
    - It is a worst-case window: 2-input blocks give ~-30%.
    - One 24-thread machine: the base peak scales with threads.
    - About 2/3 of the win is unaudited crypto (E007).
    - glibc-only trim; FCMP++ is still a beta.
- The owner then asked for 'the next thing that needs doing to show this works and is safe'. Queued:
  - E015 safety: a differential negtest with the base as the oracle. Many more cases (32 flips per proof, proof swaps, a mix of input counts), and the same cases for both builds.
  - E014: a thread-count sweep, to see whether the win holds on 1-4 thread machines.

## 2026-11-03 11:26 Owner commit merged (E001 mainnet analysis)
- The GitHub push was rejected: the owner had pushed 72a62f5 at 11:13 ("E001: mainnet block-weight analysis, corrected cap, batch-weight sim": reports/E001-sync-wedge-ISSUE.md, scripts/e001_batch_weight_sim.py and its output).
- Their findings:
  - Today's mainnet rules do not allow the wedge at the default --batch-max-weight. They do above ~33 MB, and post-FCMP++ (F = 625 kB) they do at the default.
  - My proposed cap (0.9 × 100 MB / limit) ignores the doubling of the limit after 51 blocks: 116 MB worst case at v17. They propose a window-aware cap with a worst case ≤ 90 MB in their simulation.
  - On stressnet both caps give 4, so E008-E013 are unaffected.
- Merged with --no-ff in the mirror (no rebase, no force-push), pushed to GitHub, and fast-forwarded hydrogen via a temporary owner-sync branch. All three are at bc35b9b. The sync procedure is now in STATE.

## 2026-11-03 11:29-11:32 E013 DONE: adapt is the recommended build
- (d) Long resync, 1 run each, all hashes match .22:
  - base_bss5 1,345 s / 5,613 MB / idle 4,642
  - **adapt_bss5 1,283 s (-4.6%) / 1,657 MB (-70.5%) / idle 1,379**
  - adapt_default 1,305 s / 1,663 MB
- Segments: window 219 → 108 s; dense small-tx 1,051 → 1,099 s (+4.6%; the combo was +14.8%); tail 73 → 72 s.
- No memory growth: adapt sits at 1.3-1.6 GB after the window, ~0.3-0.4 GB above the combo (it trims less often).
- With (a)-(c), adapt passes everything:
  - -68.2% heavy peak, -50% wall (3 rounds)
  - negtest PASS
  - min_mem 1,866 MB
- Written up in experiments/E013-validate-adapt (F25). reports/SUMMARY.md is rewritten around adapt (headline table, long run, a 'How real is this?' section, build history, the owner's E001 correction).
- Owner pinged. E015 (the differential negtest) started at 11:29:47.

## 2026-11-03 11:45-11:47 E015 PASS; review of the 70% finding; owner asks for a Fable review of E007
- E015 DIFF PASS: 236 cases, 0 disagreements between base and adapt; 4 of 229 rejections were at parsing (offset 51,679 bit 4 in each 128-input proof), the rest at the FCMP++ check. Written up (F26).
- Review (reports/REVIEW-70pct.md, F27):
  - The 2 s sampler sees adapt's peak only briefly (3-5 samples ≥ 90% of peak vs 18-24 for base); the cgroup test bounds the true peak to [1,816, 1,866] MB, so the headline is -66.8% to -68.4% either way.
  - O(c·q) confirmed in the base source. Equivalence tests run on real proofs and compare full verifier state.
  - Decomposition: ~40 points from halving concurrency; the verifier change gives the rest and the 2x speed.
  - Open: unaudited crypto by the same author, one machine, the remaining 1.7 GB is unattributed.
- The owner asked for a dive into the ~1,000-line monero-oxide change with a Fable agent. Launched (see In flight).
- 11:51 Owner asked for an explanation of the optimization in the repo, technical and plain-language: reports/HOW-IT-WORKS.md and reports/HOW-IT-WORKS-plain.md, linked from SUMMARY and README.

## 2026-11-03 12:00 Fable-tier crypto review of E007: no defect found; one test gap
- An independent frugal:sage (Fable 5.1) agent reviewed the E007 change statically against the unmodified crates: ~8 min, 19 tool uses, 178k tokens. Report: reports/E007-crypto-review.md (F28).
- Verdict: the streaming path checks the same relation as the base verifier for all proofs, including malformed ones; every base structural check is reproduced with the same error precedence; all MSM terms match; no path returns Ok without a fully applied accumulator; no new attacker-reachable panic (relevant because the FFI builds with panic=abort); prover byte-identical; no unsafe.
- Findings: F1 medium, the FCMP-level equivalence test compares against the refactored stored path, not the base verifier (base equivalence rests on legacy_verify over small random instances). F2/F3 low hardening. F4-F6 notes.
- Corrected one claim in my E007 notes ("old stored path kept").
- Queued E016 (STATE, F2) to close F1 with a verbatim-base equivalence test and a differential fuzz, after E014 frees the box.
- 12:02 Owner asked where the code is. Added patches/ (git format-patch series from both trees, with a README on how to rebuild) and linked it from README and SUMMARY.
- 12:10 Owner: the E007 patch is too large for human reviewers of crates under audit; can it shrink? Analysis: 1,004 non-test lines, 570 of them restructuring the audited verify. Proposed E017 (experiments/E017-minimal-streaming): leave verify untouched and pre-fold each circuit into one constraint (z * sum z^k c_k = sum z^(k+1) c_k; verify does not hash constraints or q), three builds, est. 150-200 lines. Queued ahead of E016, after E014 (2/18 runs at 12:10, est. done ~14:35).
- 12:30 E017 code written and committed (not compiled): monero-oxide worktree e017-folded-verify, 7e32894 + d9a5329. Design as planned: GBP verify byte-identical; +1 derive(Clone) on VerifierTranscript and an additive peek_z (24 lines); circuit-abstraction gains Discarded/Folded constraint modes, a FoldedConstraints accumulator (dense per-wire and per-commitment weights, z^k per constraint, emitted as one LinComb through the public term() API) and a CircuitStatementError; fcmps builds the circuits three times (discard; fold c1 with peeked z1; verify c1; fold c2 with peeked z2; verify c2) with a replay check (muls, constraint counts, transcript challenge bytes). Tests: folded vs stored (the stored path is the unchanged stock verify) on 8 shapes; 64 random bit flips per shape plus swapped inputs; the two new error paths. Sizes: non-test +513/-54 (92/33 of it pure code motion in the first commit; a good share is doc comments), tests +228. My 150-200 estimate was low, but the audited verify is untouched and GBP is +25 additive. Mistake caught: a stable-toolchain cargo fmt reformatted 9 unrelated files (the repo uses nightly options); reset and recommitted without fmt. Owner approved E017 at ~12:1x and asked to keep E007 as v1 (done: patches/v1-E007-full-streaming).
- 12:41 Owner added box81 (see STATE). Followed its README-FIRST: baseline build finished 12:35 with no FAILED; monerod v0.18.1.0-3fd0f88c2 runs; 233 unit tests PASS. Cloned upstream monero-oxide at 31c26d9 there; the two E017 patches apply cleanly with git am.
- E017 compile round 1 (box81, nice -j6): 12 errors, one cause: cloning PointWithDlog / TranscriptedInput for the rebuilds needs Clone bounds the curve-parameter types lack. Fix: do not clone; recompute the layout per build (verifier_layout(tree, layers, n_inputs), the same structure E007 used), so the refactor commit now moves the tape-bookkeeping block too (programmatically, verbatim). Round 2 compiling.
- Harness bug of my own: the 12:30 STATE edit used s[len(a):] instead of the item remainder and duplicated the whole file; repaired at 12:41 (993deab). All record scripts assert anchors, but this one asserted and then sliced wrongly.
- 12:45 E017 compile round 2 OK on box81 (fix: recompute the layout per build). **test_folded_verify_matches_stored PASS**: the folded path leaves the batch verifier bit-identical to the UNCHANGED stock verify on 8 shapes (134 s on box81). test_discarded_and_folded_circuit_statements PASS. The tampered-proof test failed in my harness (random_params(3) = 1,536 generators; the test generators must be a power of two), fixed to random_params(4); re-running with the GBP/circuit-abstraction suites and a counting-allocator peak-heap benchmark (stored vs folded, 1-128 inputs).

## 2026-11-03 12:47-12:48 Check-in: E014 6/18; E017 tests passing on box81; E018 armed
- hydrogen: no shadow lanes, 34 GB free, load ~1.4 (E014 at --max-concurrency 1). E014 round 1: base 1,351/1,348/1,260 MB at c4/c2/c1 (the stock peak barely moves with thread count below 4), adapt 1,064/884 at c4/c2 (-21%/-34%); adapt_c1 running.
- box81: E017 tampered-proof test PASS after the harness fix (random_params(4)); error-path test PASS. GBP integration tests failed to build without the crate feature tests (pre-existing requirement, not E017); will rerun with --features tests after the memory benchmark finishes (one heavy job at a time on the shared box).
- E018 chain written and armed on hydrogen (see STATE): node-level measurement of E017 against base and adapt, gated on E014 completion and a go-marker.
- 12:59 E017 crate-level results recorded in experiments/E017: equivalence and tampered tests PASS; peak heap per verify -79% to -81% at 1-16 inputs; about 2x CPU per verify at those sizes. GBP suites (lib 2/2, integration 3/3 with the tests feature) PASS; circuit-abstraction has no tests of its own. The benchmark stops at 16 inputs because the test tree helper allows at most 18 paths.
- 13:05 E017 crate test suite complete on box81 (final tree, commits a0ff587 + cb3bafa; on hydrogen 4bf0c13 + b180679 from the same mbox): existing fcmps tests test_single_input, test_multiple_inputs, proof_sizes PASS (403 s) and test_malleated_proofs PASS (259 s); GBP lib 2/2 and integration 3/3 PASS (with the crate feature tests); new tests: equivalence with the unchanged stock verify PASS, tampered PASS, error paths PASS. Nothing failed. The crypto review's F1 gap (the FCMP-level comparator was no longer the base verifier) does not exist in v2: verify_stored IS the stock verifier, so E016 is unnecessary if v2 is adopted. E018 (node level) starts automatically after E014; go-marker set at 13:00.
- 13:20 Same-box v1 vs v2 micro-benchmark on box81 (E007 tree built there with the identical counting-allocator test): per proof v2 uses ~25% less heap than v1 (-79..-81% vs stock, v1 -73..-74%) and ~40% more CPU than v1 at 1-16 inputs (three builds vs two). Recorded in experiments/E017.

## 2026-11-03 14:47 Check-in: E014 15/18, E018 waiting behind it
- hydrogen: no shadow lanes, 34 GB free, load ~1.9 (E014 at --max-concurrency 2), 14.5 GB available. box81 idle since 13:20 (its E017 crate work is done; nothing queued there). Repo clean at 3a3c350, mirror in sync, no new owner commits on GitHub.
- 13:33 the owner asked whether things were still moving since both boxes looked idle. They were: E014 was between runs restoring the 2 GB snapshot with cp (IO-bound) and the arm that had just finished was --max-concurrency 1 (one core of 24). Answered with the timeline below; the standing request is a ping when E017 is measured.
- 13:35 E018 inputs verified on hydrogen without compiling: `cargo metadata --offline` in monero-fcmp-e017/src/fcmp_pp/fcmp_pp_rust resolves generalized-bulletproofs and circuit-abstraction to ~/work/monero-oxide-e017 (4bf0c13 + b180679), all five [patch] paths exist, build dir build/beta31-e017 absent (fresh configure). Did not pre-build on hydrogen (would disturb E014 timing) or box81 (disk floor; binaries do not cross boxes anyway).
- E014 at 15/18 (r3_adapt_c2 running since 14:45). Observation for the write-up: the stock build's peak is run-dependent at the same thread count (base_c4 1,351 / 2,193 / 2,020 MB; base_c2 1,348 / 1,077 / 1,246) whereas adapt is tight (c4 1,050-1,064; c2 884-941; c1 893-912). Likely the number of block batches in flight when the heavy blocks arrive, which depends on peer timing; medians with spread in the write-up. All 15 hashes match. Est. E014 done ~15:35; then E018: build ~40 min, heavy A/B ~17:30, small-tx ~20:00, negdiff / min_mem / long resync to ~23:00.
- Peer watch: 192.168.1.116 not among .22's connections at 14:47 (last seen syncing at 2,097,439 on 2026-11-02 20:10).
- Next: when the waiter reports CHAIN_E015_E014_COMPLETE, write experiments/E014 (ab_stats per thread count, medians with spread) and fill SUMMARY 'How real' for small machines; when E018's heavy + small-tx + negdiff are in, ping the owner with E017's numbers.

## 2026-11-03 15:17 E019: box81 becomes the second machine
- 15:0x the owner questioned "nothing node-level can run there" and said box81 was meant to be the second system the review (reports/REVIEW-70pct.md verdict) asked for. They were right; my statement was too strong: the only blocker was disk (21 GB free, shared, vs an 18 GB snapshot plus a working copy). While I prepared a pruned-copy route (beta tree's monero-blockchain-prune copies the FCMP++ tables leaves/layers/tree_edges/tree_meta/locked_outputs/timelocked_outputs, so it is viable), the owner freed space to 80 GB, so the unpruned snapshot is used and the pruning job was cancelled (15:17).
- Setup on box81 (all under /home/optimizer): the three monerod trees relayed from hydrogen (15:09, 11 s, build dirs excluded); research repo copied from the control-box mirror; monero-oxide-e007's uncommitted benchmark append stashed so the v1 tree is clean for the adapt build; builds base/adapt/e017 daemon-only Release ARCH=native with CCACHE_BASEDIR (base BUILD_OK 15:15 in 3.5 min, sha bac70623...). run_e019.sh armed 15:16 (waits for builds + DB). The snapshot (18.9 GB) streams during E018's build phase via the control box (relay_snapshot.sh) so no hydrogen timing run is disturbed.
- Harness notes: ab_window.sh/pop_to.sh/sample.sh run unchanged on box81 (same paths, port 28081 free, curl present, sudo cpupower works); sample.sh already records VmSwap, reported per run since box81's 4 GB swap stays on. monerod opens a pruned DB without --prune-blockchain (cryptonote_core.cpp:736 only acts when the flag is set).
- Gotcha: `pkill -f run_e019_prune.sh` inside an ssh command killed the ssh shell itself (self-match, exit 255); use a bracketed pattern `[r]un_...`. Also `nohup ... &` inside ssh needs `< /dev/null` and a subshell or the session hangs.

## 2026-11-03 16:47 Check-in: E018 heavy done, small-tx running; E019 heavy 5/9 on box81
- hydrogen: no shadow lanes, 34 GB free, load ~8 (E018 small-tx r1_adapt at default threads). box81: 44 GB free, load ~11 (E019 r2_base), 4 sessions of `user` but idle at the 15:44 check (load 0.38), swap 51 MB system-wide as before.
- E018 (a) heavy A/B complete 16:33, 9/9 hashes: base 5,410 (5,400-5,609) / adapt 1,590 (1,370-1,754) / e017 1,631 (1,626-1,654) MB peak; post-idle 4,917 / 1,280 / 1,071; wall 222 / 110 / 157 s; CPU 4,244 / 903 / 1,404 s. So v2 (E017) keeps v1's peak (-70% vs base, within 3% of adapt) and idles lower, at +55% CPU over v1 (still -29% wall and -67% CPU vs base). The v1-vs-v2 call waits for (b) small-tx wall and (c) negdiff. Caveat recorded: the 18.9 GB snapshot stream to box81 read hydrogen's SSD 15:26-15:35 (about 37 MB/s, it shared the disk with E018's first restore), overlapping r1_base; base's three walls are 222-224 s, so the effect looks nil, but r1 is flagged.
- E019 (box81) heavy 5/9: base 3,379 MB / 238 s (12 threads on 6 cores), adapt 1,296-1,357 MB / 136 s, e017 1,207-1,270 MB / 213 s. Same picture as hydrogen on different hardware. Prep sync and small-tx rounds follow.
- E014 written up at 15:29 (e40c6fe, F29). Owner 16:3x: keep going, ping when E018 and E019 are both in (STATE, 0664a85).

## 2026-11-03 18:00 E019 in: box81 reproduces the headline
- E019 chain on box81 finished 17:56 (started 15:44): heavy 9/9 + prep + small 9/9, 18/18 hashes, VmSwap 0 kB in every sample, governor restored. Evidence copied via the control box into evidence/E019 (results, check logs, samplers, per-run logs, chain and build markers; stdout and the rewind monerod logs left on box81).
- Heavy: base 3,379 / adapt 1,302 / e017 1,207 MB peak, idle 3,095 / 902 / 851, wall 238 / 136 / 213 s, CPU 2,407 / 660 / 1,075 s. Small-tx: 1,091 / 729 / 721 MB, wall 149 / 157 / 174 s, CPU 969 / 1,063 / 1,218 s. Written up in experiments/E019-box81-reproduction (F30). Percentages line up with hydrogen's E018 (adapt heavy -61.5% vs -70.6%, small -33.2% vs -32.6%, wall cost +5.4% vs +6.0%); the stock peak is smaller on box81 because it runs 12 threads, not 24.
- v2 note for the E018 decision: on both machines e017 equals or beats adapt on memory but costs +43-57% wall on the heavy window and +6-11% on small-tx blocks over adapt. The E017 plan's "wall within ~5% of adapt" is falsified at both sites.
- E018 on hydrogen at this point: (a)-(c) done ((c) negdiff DIFF PASS / DIFF PASS at 17:54), (d) min_mem for e017 running (ref wall 157 s), (e) long resync after it. The E018 write-up and the v1/v2 call follow when (e) ends; the owner is pinged then.

## 2026-11-03 18:07 HOW-IT-WORKS: v2 / E017 explained
- Owner asked for an explanation of the reduced line count of the v2 (E017) verifier in the HOW-IT-WORKS files. Added section 2.1b to reports/HOW-IT-WORKS.md (the one-constraint identity, the three builds, why the diff is +513/-88 with +25 additive lines in the audited verifier against v1 +1,004/-134 with +570 inside it, the four reviewer checks, measured memory and CPU cost from E017/E018/E019, the two-build follow-up idea), a v2 row in the section 3 table and v2 pointers in section 4; and part 1b to reports/HOW-IT-WORKS-plain.md plus the two-machine caveat.

## 2026-11-03 18:15 Docs: second box recorded in SUMMARY and REVIEW-70pct
- Owner (18:2x) pointed out SUMMARY.md still said "Machine: hydrogen" and asked that the docs record the second box. SUMMARY: header date, Machines line (hydrogen + box81, native builds, percentages only across boxes), a "Solid" bullet for E019, the caveat line; REVIEW-70pct: status updates on weakness 2 and the verdict (second machine done, external review remains). HOW-IT-WORKS-plain already says two machines (73d9d26).

## 2026-11-03 18:20 HOW-IT-WORKS: speed trade-off and piece-by-piece attribution
- Owner asked for the memory-vs-speed answer in the HOW-IT-WORKS files and whether the 70% is attributed piece by piece. Technical: section 3 now states the overlap (verifier alone -59%, cap+trim -45%, max-concurrency 12 -40%, all three -68%; idle from the trim) and section 3.1 (adapt: no trade, 2x on heavy, +5-6% small-tx, -4.6% long resync; v2 trades speed for diff size, memory equal, cgroup min 1,765 MB). Plain: new Piece by piece table and Does it cost speed section.

## 2026-11-03 18:24 Prior art survey (owner question: has this been floated upstream?)
- Searched GitHub (seraphis-migration/monero, monero-oxide, monero-project/monero, xmrack/monero-review) and the stressnet release notes, read-only. Upstream worked the problem Oct-Dec 2025: #202 (valgrind: 1.2 GB per 128-input verification; kayabaNerve -> 790 MB -> ~250 MB; suggestions to bound inputs in flight or split at 16 inputs; j-berman's limit branch 2-3x slower on 2 threads), #224 (one batch per thread, assumes n_threads x 250 MB, RSS not returned to OS), #229 (M_ARENA_MAX), alpha.1.5 notes, monero-oxide#136 (small allocations). Nothing found on not storing the circuit, trimming, or the O(c x q) fold. Written up in reports/PRIOR-ART.md, linked from SUMMARY and README. Matrix/IRC not searched.
- Owner also asked why --block-sync-size 5: answered in chat (E001 wedge control value; same flag on every arm so the A/B is fair; adapt_default in E013 shows the result without it).

## 2026-11-03 18:39 E018 in: v2 at the node, decision v1 stays recommended
- Chain ended 18:37 (CHAIN_E018_COMPLETE). (d) min_mem e017 = 1,765 MB (largest fail 1,663; adapt 1,866, base 5,750). (e) long resync e017_bss5: 18,309 blocks, 1,414 s (+5.1% vs base 1,345, +10.2% vs adapt 1,283), peak 1,553 MB (-72%), post-idle 1,218, CPU 12,524 s, hash yes; segments 159 / 1,177 / 73 s vs base 219 / 1,051 / 73 and adapt 108 / 1,099 / 72: the whole loss is on the dense small-tx stretch (+12% vs base); memory plateau 1.2-1.36 GB, no trend.
- Decision against the pre-registered acceptance (experiments/E017 README): peak within 10% of adapt MET, hashes MET, negdiff identical MET, wall within 5% of adapt NOT MET on either machine. v1/adapt stays the recommended build; v2 is the alternative for a reviewer who values the small diff and the untouched verifier. Cause: with the O(c x q) fold gone, circuit construction dominates, and v2 builds three times. Follow-ups: E016 (v1 base-equivalence test) back on the queue; E020 candidate = v2 with both z's peeked after the discard build so c1 and c2 fold in one pass.
- Written up: experiments/E018-node-level-v2 (README, results.csv with heavy/small/long rows), evidence/E018 (chain, build log, results, check logs, samplers, negdiff json/summaries, minmem, long segments). SUMMARY ('Still running / next', build-history row for e017, E016/E020 lines), FINDINGS F31, patches/README v2 headers (0004+0006 not squashed), STATE, this entry. Owner pinged: E018 and E019 both in.

## 2026-11-03 19:38 E016 done: streaming verifier equals the verbatim base verifier
- Check-in 18:47: both boxes idle, nothing running, 34 / 44 GB free, no shadow lanes. Started E016 on hydrogen (branch e016-base-equivalence on ~/work/monero-oxide-e007, one commit on c215a80).
- Method: `verify_base` copies of the 31c26d9 `ArithmeticCircuitStatement::verify` (164 lines, feature `tests`) and `Fcmp::verify` (227 lines, cfg(test)) extracted by line range with a script (/tmp/e016/inject.py on hydrogen; copy in the scratchpad); first attempt took the wrong end line and pulled `read`/`write` along (duplicate definitions), fixed by cutting at the "/// Read an FCMP." marker. Both compiled unchanged against the E007 tree. Tests: matches_base (8 shapes), matches_base_on_tampered_proofs (regions helper shared with the existing test), matches_base_under_random_mutation (2 x 128 byte XORs). All PASS first run, 148 s release; errors identical too (Debug compared). Suites: fcmps 14/14 (release, 2,625 s including the benchmarks), generalized-bulletproofs 9/9 with the tests feature, clippy clean except one warning that predates E016 (InconsistentWitness never constructed).
- Recorded: experiments/E016-base-equivalence, F32, patches/v1 0002 + README row, SUMMARY (solid list, limits line, upstreamability row, next list, review paragraph), E007-crypto-review F1 CLOSED, HOW-IT-WORKS (both) "how we know" lines, STATE (F2 done, NEXT E020).
- Next: E020, v2 with two builds (both z's peeked after the discard build, one fold pass). Verify the transcript order first: z2 is drawn after c1's AI/AO/S are read, which happen after c1's `verify` begins; whether the c2 peek can precede the c1 fold depends on whether c1's `verify` transcript operations can be replayed on a clone before the real call.

## 2026-11-03 19:55 E020 crate work done, node chain armed
- Owner 19:4x: keep going without waiting, ping when E020 is in (STATE, memory). E020 = v2 with two circuit builds: skip_verify_transcript (GBP, +57 lines additive) lets z2 be peeked past c1 proof on a clone after the discard build; one Fold rebuild with both z; real transcript after c1 verify checked against the skipped clone (InconsistentCircuitReplay otherwise). Commit on branch e020-two-builds in ~/work/monero-oxide-e020. Crate tests: GBP suite with the tests feature PASS (fuzz test now also asserts the skip lands where verify lands); fcmps folded-vs-stored tests PASS (3/3, 150 s). A first monerod build was started without -DARCH=native by mistake and killed before it compiled; the correct build (ARCH=native, ccache) runs in the background with the crate memory benchmark for e020 and e017 before it. scripts/run_e020.sh armed: heavy and small-tx A/B adapt vs e017 vs e020 x3, negdiff e020 vs base at both heights; waits for the e020.build marker.

## 2026-11-03 20:47 Check-in: E020 heavy round 1 in
- hydrogen: no shadow lanes, 37 GB free, load ~2-3 (E020 chain, r2_e020 heavy running). E020 heavy r1: adapt 110 s / 1,456 MB peak / 1,210 idle, e017 156 s / 1,550 / 915, e020 136 s / 1,654 / 1,013, 3/3 hashes. First read: the second build removed about a third of e017's wall gap to adapt (156 -> 136 vs 110) at +7% peak (both folded constraints live at once, as the crate benchmark predicted). Rounds 2-3, small-tx and negdiff follow; ETA ~22:00.

## 2026-11-03 22:50 Check-in: E020 done, written up; v1 stays recommended
- hydrogen quiet (no shadow lanes, load 0.4, 33 GB free). E020 chain finished 22:46: heavy A/B 20:24-21:26, small-tx 21:26-22:33, negdiff 22:33-22:46, all 18 hashes match, DIFF PASS at both heights.
- Results (medians of 3): heavy adapt 109 s / 1,607 MB peak / 1,352 idle; e017 159 / 1,589 / 1,050; e020 140 / 1,623 / 1,013. Small-tx adapt 156 s / 810 MB; e017 169 / 801; e020 161 / 805. e020 vs adapt: heavy wall +28% (e017 +46%), small-tx +3% (e017 +8%), peak +1% / -1%, idle -25% / +1%. The second build removed ~40% of the heavy gap and ~60% of the small gap; the crate benchmark's +20% per-proof heap does not show at the node.
- Decision per the pre-registered rule: heavy within 10% NOT met, so v1/adapt stays recommended; the v2 alternative is now patches 0001-0003. The remaining +28% is unprofiled (candidate: the per-constraint fold accumulator in circuit-abstraction vs v1's in-verifier fold); a perf profile is the next step only if v2 is pushed further.
- Recorded: experiments/E020-two-builds (README, results.csv), evidence/E020 (chain, build marker, both windows' results/check/mem.csv, negdiff json+summaries), FINDINGS F33, patch 0003 (format-patch of bde81f4) + patches README rows, SUMMARY (build history, next), HOW-IT-WORKS 2.1b / 3 table / 3.1, plain "Does it cost speed?", STATE. Owner pinged (E020 in).
- Queue next: W002 wallet refresh measurement against our node.

## 2026-11-03 22:53 W002 launched
- Built monero-wallet-cli / monero-wallet-rpc in the base tree (ninja, 39 steps, ~5 min; marker w002.build). Launched scripts/run_w002.sh: synced snapshot served by the adapt node offline, fresh wallet refresh 3,105,000 -> 3,123,270, smoke + 3 sampled runs + 1 heaptrack run. First results at the next check-in.

## 2026-11-03 23:07 W002 attempt 1 killed, attempt 2 launched; owner note on wallet sync
- Attempt 1 smoke: "Refresh starting from block 3123270 ... blocks received: 0": monero-wallet-cli applies --restore-height only when restoring (m_restoring), not for --generate-new-wallet (simplewallet.cpp:4363 sets the new wallet's refresh height to the daemon's tip). Also the pid-search loop waited its full 120 s because the 0-block refresh had already exited. Fix: step 1 creates the wallet with `--command set refresh-from-block-height <h>` (persisted), step 2 opens it with --wallet-file and `--command refresh` under the sampler; the loop stops when the wrapper exits; the smoke requires "blocks received" > 0. Relaunched 23:07 (w002.chain; attempt-1 log kept as w002.chain.attempt1).
- Owner relayed a community-chat comment: beta.3.1 ~6x wallet sync speedup, subaddress PR ~2x more, "lots of low hanging fruit", spam wallets syncable in under a minute vs over an hour. Recorded in reports/PRIOR-ART.md (Wallet sync) with what it means for W002 (speedup already in our baseline; bigger batches can raise refresh-time transients; spam-wallet case needs a seed from the owner).

## 2026-11-03 23:12 W002 done and written up; W003 running, W004 armed
- W002 (attempt 3, 23:07-23:09): fresh wallet refresh 3,105,000 -> 3,123,270 in 14-16 s, VmHWM 1,037 / 1,173 / 1,260 MB, ~175 CPU s, 25 threads; heaptrack: peak heap 349 MB vs peak RSS 1.20 GB, top outputs_to_leaves 115 MB (tree extension on threadpool threads), strings ~70 MB, Rb_tree copies 22 MB. Node 396-408 MB while serving. Evidence sanitized (no wallet stdout/logs in the repo: they print the seed; refresh_lines.txt excerpt instead).
- W003 launched 23:10 (concurrency 24/12/4/1 x 3). First points: c24 1,100 MB VmHWM / 15 s; c12 909 MB / 23 s. W004 armed (MALLOC_ARENA_MAX 1 / 2, arena1+c12 x 3) and starts when W003 completes.

## 2026-11-03 23:30 W003 and W004 done: wallet refresh peak is arena retention; MALLOC_ARENA_MAX=2 gives -67% at +7% wall
- W003 (23:10-23:21, --max-concurrency 24/12/4/1 x 3): VmHWM 1,100 / 909 / 510 / 357 MB, wall 16 / 23 / 55 / 105 s, CPU 184 / 109 / 107 / 104 s; 12/12 full refreshes. Linear in threads, 1-thread peak = live heap.
- W004 (23:21-23:28, env arms x 3): default 1,132 MB / 15 s; MALLOC_ARENA_MAX=1 352 MB / 17 s / CPU +17%; =2 370 MB / 16 s / CPU +4%; =1 + c12 352 MB / 24 s. 12/12 full refreshes. Spread 1 MB at arena 1 vs ~190 MB default.
- Recorded F35, F36, SUMMARY wallet + zero-code lines, READMEs, sanitized evidence (no wallet stdout/logs). Box free, governor schedutil. Owner not pinged (no named milestone; they were active in chat at 23:0x).

## 2026-11-03 23:35 E021 (idle trim) launched
- Design from E012's own note (post-idle 1,333 vs combo 1,107 MB: after the last light call nothing trims). Patch: scripts/e021_patch_idle_trim.py on a copy of the adapt tree (~/work/monero-fcmp-idle); `rct::idleTrimFcmpPp(5000)` from `core::on_idle` via a 2 s `once_a_time_seconds`; the verify path stores its timestamp before deciding its own trim so the idle trim never repeats a trim already done. Build + heavy/small A/B adapt vs idle x3 running (scripts/run_e021.sh). Handoff note refreshed (~/.claude/HANDOFF.md on the control box).

## 2026-11-04 00:58 E021 done: idle trim takes adapt's post-idle memory -19%, adopted as patch 0006
- Chain 23:33-00:58: build OK (ccache, 3 min), heavy A/B x3 (23:36-00:13), small-tx A/B x3 (00:14-00:58). Heavy: post-idle 1,349 -> 1,087 MB (-19.4%), peak anon 1,807 vs 1,713 (ranges overlap), wall 110 vs 111 s, CPU 911 vs 910 s. Small-tx: wall 155 vs 157 s, post-idle 750 vs 721 MB, peak 813 vs 822 MB. 12/12 hashes. The sampler shows the drop in one 6 s step (r1 idle: 1,349 -> 1,113 MB at the logged trim); exactly one trim line per idle run (6/6).
- Adopted: committed the idle tree, format-patch -> patches/v1 monerod 0006 and v2 monerod 0007; patches README, SUMMARY (caveat, upstreamability row, next list), HOW-IT-WORKS 2.3, F37. E013's negtest/min_mem/long-resync were run on 0001-0005; 0006 changes only when malloc_trim is called.
- Box: governor restored to schedutil by the chain, no shadow lanes, ~32 GB free. Next: E022 threshold sweep.

## 2026-11-04 01:04 E021 write-up corrected after an audit against the evidence
- Commit 94f570b was published with errors, all mine: kB/1000 in the sampler table (1,349 -> 1,113 should be 1,317 -> 1,086) plus a wrong sample interval; -19% headlined without the overlap of the post-idle ranges; an unmeasured attribution of the remaining idle memory; "no new code during the window"; v2 and stock comparisons not labelled as unmeasured or cross-experiment. The 00:58 entry above carries the wrong table figure.
- New: scripts/e021_paired.py measures the release across each trim. Heavy 231 / 231 / 234 MB, small 37 / 43 / 41 MB, adapt 0-4 MB. Replaces -19% with about -17% everywhere. Decision unchanged (adopted), with the validation gap stated.
- Code read: only the block path reaches batchVerifyFcmpPpProofs; pool txs use the single-proof call at tx_verification_utils.cpp:719. So at the tip the trim fires at most once per block, and its MGINFO line needs demoting before upstream use. Not measured.

## 2026-11-04 01:20 E022a scan done, E022 threshold sweep launched
- Scan of 3,080,000-3,123,269 on our offline node: 762,594 txs, 99.6% with 1-2 inputs (759,840), 1,339 with 3-15, 148 with 16-63, 1,267 with 64 or more. Blocks by largest tx: 34,507 empty, 8,535 at 1-2, 43 at 3-7, 83 at 8-15, 21 at 16-31, 17 at 32-63, 64 at 64+. So only 104 of 43,270 blocks (0.24%) change behaviour for a threshold of 8, 16 or 32. Stressnet's mix is synthetic; it says nothing about how often mid-size proofs would occur on mainnet.
- Contiguous stretch 3,106,069-3,106,110 (37 blocks at 8 inputs, 5 at 16) makes a targeted sweep cheap, with no new snapshot (pop_to from h3106400). t8 / t16 / t32 on the idle tree, 5 rounds because wall resolution is 2 s on a short window. Decision rule written into run_e022.sh before the data.

## 2026-11-04 02:40 E022 window done: the pre-set rule selects threshold 8; guard running
- 15/15 hashes. t8 vs t16: peak anon 471 vs 506 MB, CPU 157 vs 199 s, both with non-overlapping ranges. t32: no benefit, on just 5 differing blocks.
- Caught before write-up: the harness wall and CPU columns are not like for like here, because arms overshot the end by 0-15 blocks (t8 most). Harness wall read +8.3%; on identical heights from log timestamps it is +2.8% (whole window) and +4.0% (8-input blocks). My first segment script also mislabelled a 2-input batch as the 16-input one (Synced N means up to index N-1); fixed before anything was recorded.
- Cap and trim are switched together by heavy_call, so which gives the CPU saving is not separated. Below 8 is untestable on this chain. Guard launched: small-tx window x3, criterion in run_e022b.sh.

## 2026-11-04 02:47 Check-in: E022 guard progressing
- Run 1 of 6 (t16) syncing, no results yet, ETA ~03:25. Box quiet: no shadow lanes, 32 GB free, governor pinned for the chain. Peer watch: 192.168.1.116 is among .22's connections at h=2204719, state=normal, connected 614s (still below the 3,105,401 wedge height).

## 2026-11-04 03:26 E022 guard was an A/A; replication launched on real 8-input stretches
- Guard passed its criterion (wall -0.2% from logs, CPU +0.6%, peak +1.0%, 6/6 hashes), but the window has no block with a largest tx of 8-15 inputs, so the arms behave identically. My mistake: I picked the window as the standard guard without checking it against the scan. Not counted as support for threshold 8; useful only as a noise floor.
- Replication launched: 13 sensitive blocks on each of two independent stretches, 5 rounds each. New scripts/cpu_watch.sh closes the CPU overshoot gap. Criterion fixed in run_e022c.sh: both windows or 16 stays.

## 2026-11-04 04:47 Check-in: E022 replication progressing, window A complete
- Window A finished 04:15 (10 runs); window B is in round 4 of 5, 6 of its 10 runs have CPU files. ETA ~05:05 from A's 49 min, revised from ~05:30. The chain has reported no failure so far; hashes not yet read.
- Interim, from scripts/e022c_segments.py, not a decision. A, medians over 5 rounds, t8 vs t16: wall 8.45 vs 8.20 s (+3.0%, ranges 8.32-8.59 vs 8.14-8.28, no overlap), CPU 47.1 vs 67.9 s (-30.5%, no overlap). B so far, 3 rounds: wall +4.4%, CPU -29.8%. B's wall is close to the +5% limit, so it is not settled.
- A's peak anon in results.csv: t8 470 vs t16 478 MB (medians; t8 ranges 428-484, t16 475-483). Those peaks come from runs that overshot the window by different amounts (80-90 blocks recorded), so they are not on identical heights.
- Box: no shadow lanes, 35 GB free, governor pinned by the chain. Peer watch: 192.168.1.116 is among .22's connections at h=2221815, state=normal, up 17,096 blocks in 2 h from 2204719, still below the 3,105,401 wedge height.

## 2026-11-04 05:10 E022 done: threshold 8 passes on both windows and is adopted; E023 validation launched
- Replication finished 05:04, 20/20 hashes. A: CPU -30.5%, wall +3.0%. B: CPU -29.9%, wall +3.7%. CPU ranges do not overlap. Passes the criterion fixed before the run.
- Checked peak on identical heights because the harness peak includes overshoot (new scripts/e022c_peak.py): t8 -11.2% and -5.6% inside the windows on 5 samples per run; whole-run -1.7% and -1.4%, overlapping. Reading: memory falls only while 8-15 input blocks verify, and larger proofs set a run's peak. So this is a CPU change, not a memory one; SUMMARY, F38 and the patch message say so.
- Correction to my own note: I assumed window A had no blocks at 16 or more inputs. The scan shows 3,105,102-3,105,104 do. Both arms treat them alike, so they dilute rather than inflate.
- Committed adbe70cf8; rebuild is byte-identical to the measured t8 (sha d779a522). Patches 0007 v1, 0008 v2 (v2 apply check only, not built).
- Launched E023 ahead of the optional e020 profile: the recommended build's negative test, min_mem and long resync all predate its last two patches, which matters more than the profile. Expected results written into run_e023.sh before the run.

## 2026-11-04 06:47 Check-in: E023 progressing, first three parts done, no miss so far
- Heavy A/B x3, base vs final (medians): peak anon 5,606 vs 1,764 MB (-68.5%), post-idle 4,977 vs 1,066 MB (-78.6%), wall 221 vs 112 s (-49%), CPU 4,229 vs 914 s. 6/6 hashes. Inside the expected -60%.
- Negative test PASS at both heights (128-, 8- and 2-input txs, tampered 8/8 rejected per tx, originals accepted). min_mem 1,866 MB (largest failing 1,765, step 125), the same result as E013 and under the expected 2,000 MB.
- Small-tx in round 3 of 3, interim: base 150 / 149 / 148 s, final 156 / 159 s so far. Not read as a result yet. Long resync not started.
- Box: no shadow lanes, 32 GB free, governor pinned by the chain. Peer watch: 192.168.1.116 is among .22's connections at h=2245813, state=normal, up 23,998 blocks in 2 h, still below the 3,105,401 wedge height.

## 2026-11-04 08:16 E023 done with one miss; E023b launched to attribute it
- Met: heavy peak -68.5%, negtest 24/24 and 3/3, min_mem 1,866 MB, 15/15 hashes, no upward memory trend over the last 13,000 blocks (one run per arm).
- Missed: small-tx wall +6.6% from logs on identical heights, +6.7% from the harness, expected no more than +6%. Ranges do not overlap. Kept as a miss. The dense stretch of the long resync shows +4.1%, in one run.
- Found: the idle trim releases only 70-79 MB after a long resync, against 231-234 MB after the heavy window, and final_bss5's 1,400 MB idle is no lower than E013's 1,379 MB. So F37's -17% is specific to a burst ending on heavy blocks. Recorded in F39, SUMMARY, HOW-IT-WORKS and the E021 README.
- SUMMARY's headline tables now carry E023, including a less flattering long-run idle figure (-66.6%, was -70.3%).
- E023b launched: adapt vs final, small-tx window, 5 rounds. Reading fixed in the script header. E023's figure stands whatever it finds.

## 2026-11-04 08:47 Check-in: E023b progressing
- 4 of 10 runs recorded, round 3 under way, ETA ~09:35. Interim wall from logs: adapt 155.2 and 155.8 s, final 152.7 and 155.1 s. Too few runs to read; the reading waits for all 5 rounds.
- Box: no shadow lanes, 42 GB free, governor pinned by the chain. Peer watch: 192.168.1.116 is among .22's connections at h=2268310, state=normal, up 22,497 blocks in 2 h, still below the 3,105,401 wedge height.

## 2026-11-04 09:32 E023b done: the small-tx miss comes from adapt, not from the last two patches; E024 launched
- adapt vs final, 5 rounds, 10/10 hashes: wall 154.4 (153.5-155.8) vs 152.7 (152.2-155.5) s, -1.1%, ranges overlapping. Under the reading fixed in run_e023b.sh, the last two patches are not responsible. E023's miss stands: +6.6%. I set the +6% line from E012's +4.0%, which understated the cost.
- Annotated SUMMARY's +4% lines rather than rewriting history: the E012/E013 result stays, marked with the later figures. Why the dense stretch of the long resync shows only +4.1% is not investigated.
- E024 launched: flat perf profile of e020 vs final on the heavy window, the last item in the queue.

## 2026-11-04 09:44 E024 done; E025 and E026 launched
- Profile of e020 vs final, 2 rounds per arm: e020 +36.5% cycles. Field multiplication is 56% of the difference, symbols only e020 has are 34%, memmove + memset 3.8%. So E020's copying candidate explains little. Callers of the multiplication are inferred, because the profile has no call graphs. Going further depends on whether the owner wants v2.
- The queue was otherwise empty, so I added the gaps I had been reporting as open. E025: the published v2 series with 0007 + 0008 has never been built, and E015's differential test predates the last two patches. E026: the 10 s trim interval is the last unswept tuning constant, and small-tx wall is the build's main cost. Expectations and the rule are in the script headers, written before the runs.
- Slip: the profile script's shadow check matched my own launch shell, because the command text contained the word. No lanes ran; the chain's own check says so.

## 2026-11-04 10:47 Check-in: E025 progressing
- Build OK (v2final sha a9969e61). Differential test: DIFF PASS at both heights. Heavy window, 3 rounds, 6/6 reached the window end: final wall 111 s, v2final 140 s (harness figures, medians); peak anon 1,803 vs 1,675 MB; post-idle 1,129 vs 795 MB. Interim until the small-tx part is in and the log-based wall is read.
- Small-tx round 1 of 3 running, E026 still waiting on the marker. Both ETAs still estimates, E025 about 11:10-11:25.
- Box: no lanes, 32 GB free, governor pinned by the chain. Peer watch: 192.168.1.116 is among .22's connections at h=2291408, state=normal, up 23,098 blocks in 2 h, still below the 3,105,401 wedge height.

## 2026-11-04 11:40 E025 done
- Differential test on final and v2final: 236/236 identical to base. The case files are E015's by sha256, so this is the same test on the later builds.
- v2final vs final, 12/12 hashes: heavy wall +27.5% from logs, small-tx +2.7% with overlapping ranges, CPU +34.1% and +3.6%. Post-idle after heavy 795 vs 1,129 MB, separate ranges; after small-tx no difference. Why v2 holds less after heavy blocks is not investigated.
- One literal miss: heavy peak -7.1%, outside the 5% band I set, on the favourable side. Final's peak range is wide and overlaps, so I do not read it as a v2 win.
- Limit: the 236 cases are 128- and 2-input only. E022's 8-input path is covered by E023's negative test, not this one.
- Also fixed the FINDINGS status line, which still named adapt as recommended and listed E014 and E015 as pending.
- E026 started by itself at 11:29.

## 2026-11-04 12:00 E027 started on box81 at the owner's prompt
- The owner asked whether anything useful could run on moonpie, which is box81's hostname. It was idle with 44 GB free. I had listed a second-machine rerun of the final series as not planned, and that was the wrong call: E019 only covers adapt, and every final-series figure is from hydrogen.
- Part a (build from the published patches, tree hash check, differential test at the heavy height with hydrogen's case file) does not sync from .22, so it runs now. Part b (A/B) waits for E026, so the two boxes do not share .22 while E026 decides on a 2% wall rule.

## 2026-11-04 12:10 E027 part a done on box81
- Built in about 3 minutes (ccache). The tree hash equals hydrogen's adbe70cf8, so the published patches reproduce the final source exactly. Binary sha a9a22c46, native to that box.
- Differential test at 3,105,401: 135 cases, 0 disagreements with base, DIFF PASS, with the same 127 rejections at the FCMP++ check as on hydrogen. All three expectations for part a met.
- Part b waits for E026 (5 of 15 runs at 12:09).

## 2026-11-04 12:47 Check-in: E026 at 10 of 15 runs
- 10 of 15 runs recorded, all on the expected heights, ETA about 13:25. Interim harness walls are all 156-161 s, with no arm standing out. Not read as a result: the rule uses log-based wall over all 5 rounds.
- E027 part b not started: it waits for E026. box81 is idle (load 0.00), 43 GB free.
- Box: no lanes, 37 GB free, governor pinned by the chain.
- Peer watch: 192.168.1.116 is among .22's connections at h=2295360, state=normal, live 153 s, up only 3,952 blocks in 2 h against about 23,000 in earlier intervals, still below the 3,105,401 wedge height. The short connection age suggests a reconnect or restart in the interval; cause not known from here. Watch it at the next check-in.

## 2026-11-04 13:30 E026 done, 10 s stays; E027 part b launched
- i60 vs i10: wall -0.8% from logs, ranges overlap, peak +4.4%, separate. Rule needed at least -2% with separate ranges. Not adopted, no patch. inever: wall -1.4%, overlap, peak +4.6%. 15/15 hashes.
- So light-call trims are not what the small-tx wall gap is made of. The remainder of E023's +6.6% is not attributed.
- Tree restored and clean, binary back at d779a522.
- E027 part b started on box81 once E026's marker appeared. Hydrogen is idle.

## 2026-11-04 14:47 Check-in: E027 part b on its last small-tx run
- Heavy window and prep sync done on box81. Small-tx 5 of 6 runs, then the differential test at 3,106,400. ETA about 15:00. Interim, harness figures, hashes yes on all so far: heavy peak base 3,342 vs final 1,303 MB, wall 236 vs 137 s. Read when complete.
- Box81: 43 GB free, 4 idle `user` sessions, nothing else using CPU. Hydrogen: idle, no lanes, 31 GB free.
- Peer watch: 192.168.1.116 is among .22's connections at h=2297963, state=normal, live 23 s, up 2,603 blocks in 2 h. This is the second slow interval (3,952 before, about 23,000 earlier), and again the connection is very young. Below the 3,105,401 wedge height. Cause not known from here: I only see .22's side, and I do not touch that node.

## 2026-11-04 14:51 E027 done with one miss; E028 launched
- Final on box81, base vs final: heavy peak -61.0%, post-idle -76.3%, wall -42.3%; small-tx wall +5.5%, post-idle -27.9%; 13/13 hashes, no swap, differential test 236/236 on natively compiled binaries. Published patches give hydrogen's exact tree.
- Miss: small-tx peak -18.8%, expected about -33%. Final's figure is where adapt's was (734 vs 729 MB). Base's moved (904 vs 1,091 MB, separate ranges, same binary and harness). I set -33% from one 3-run median of a figure known to vary. Cause of the shift not investigated.
- E028 launched on hydrogen. The queue was otherwise empty, and the small-tx wall cost is the recommended build's main cost and is still unattributed after E026. The fixed expectations cannot all hold, because +2.7% and +1.4% do not add up to +6.6%. Report only.

## 2026-11-04 16:47 Check-in: E028 at 15 of 20 runs
- All hashes match so far. ETA about 17:20. Harness walls so far: base 149-151 s, e007 154-157 s, inever 156-157 s, final 157-159 s. Not read as a result: the reading uses log-based wall over all 5 rounds.
- Box: no lanes, 31 GB free, governor pinned by the chain. box81 idle, nothing of ours running.
- Peer watch: 192.168.1.116 was not among .22's connections at this check, on two looks a few seconds apart. It has been absent at an earlier check too, then came back. Last seen at h=2297963 at 14:47. It had already been showing very young connections, so this says little by itself. Cause not known from here.

## 2026-11-04 17:30 E028 done
- Small-tx wall from logs, 5 rounds, 20/20 hashes: base 146.4, e007 151.9, inever 153.1, final 154.4 s. Verifier +3.8%, separate ranges, and all the CPU cost (+8.0%). Rest of adapt +0.8% and light-call trims +0.8%, overlapping, no visible CPU change.
- Miss: the total was expected at about +6.6% from E023, measured +5.5%, the same as box81. E023's figure stays as measured, and SUMMARY now gives both.
- No swept constant is left to recover the cost. What remains is the double circuit build.

## 2026-11-04 17:21 E029 launched
- E028 left one candidate for the small-tx wall cost: the second circuit build. The stored-circuit path already exists in the E007 tree as verify_stored, under cfg(test). So this is a small change: 8 lines route proofs under 8 inputs to it.
- It may well raise the small-tx peak, since E028 shows the verifier also gives -15.6% there. The goal is memory, so the rule fixed in the script refuses to trade more than 5% of peak for speed. If it fails the rule it is reported as an option, not adopted.
- The crate tests compile the routing out, so they keep testing streaming. The routing itself is exercised at the node, by negdiff and the window hashes.

## 2026-11-04 17:22 E029 first attempt stopped at compile; patch fixed and restarted
- The chain stopped at its crate-test step, 8 s in, on a compile error: Circuit::verify in circuit.rs is also cfg(test), and my patch only opened verify_stored. No test ran and nothing was measured. The chain stopped as intended and nothing downstream started.
- Patch now opens that one function too. It was the only other gate on this path, by grep and by the compiler's two errors. Removed the 1-minute-old monero-oxide-e029 tree so the chain could recreate it. Restarted.

## 2026-11-04 18:47 Check-in: E029 on small-tx, run 4 of 10
- Crate tests passed (14 passed, 0 failed, rc=0; they took 44 min of the chain). Build OK, sha d93a9703. Differential test DIFF PASS at both heights: 135 cases at 3,105,401 (128-input, so streaming) and 101 at 3,106,400 (2-input, so these go through the new routing).
- Small-tx 3 of 10 runs, all hashes yes. Harness figures, not read as a result: final 158 s, 806 MB; e029 148-151 s, 861-866 MB. The reading uses log wall over all 5 rounds. Heavy window still to come. ETA about 20:30 stands as an estimate.
- Box: no lanes, 45 GB free. box81: load 0.00, nothing of ours running, 43 GB free.
- Peer watch: 192.168.1.116 is back among .22 connections at h=2303879, state=normal, live 558 s. Up 5,916 since 14:47 (4 h), after being absent at 16:47. Still below the 3,105,401 wedge height. Cause of the slow rate not known from here.

## 2026-11-04 19:58 Owner decision: keep final, E029 is an option
- Owner, after seeing the small-tx medians (wall -5.7% harness, peak +7.0%, CPU -8.0%): "keep final, report e029 as an option". This matches the rule fixed in the script. The chain keeps running so the option is written up with the heavy window and log walls.

## 2026-11-04 20:20 E029 done: an option, final stays; E030 launched
- Small-tx, 5 rounds, log wall: final 154.3 s, e029 146.2 s (-5.2%, separate). CPU -8.1%. Peak anon 809 -> 866 MB (+7.0%, separate). Heavy, 3 rounds: wall +1.3%, peak +4.9%, CPU -0.5%, all overlapping. 16/16 hashes, DIFF PASS at both heights, 14 crate tests pass.
- The peak fails the +5% limit fixed in the script, and the owner has decided: keep final, report E029 as an option. Patch in patches/options/, reproducing the measured tree hash.
- Miss: wall was expected 2-4% below final. It saves 8.1 s, more than the 5.5 s E028 gave the verifier, so E028's two smaller steps may not be independent of streaming. Not separated here.
- Checked: peak recomputed from the samplers up to the window end gives the same figures for all 16 runs, so the +7.0% is not a harness overshoot.
- Limit I want on record: proofs of 3-7 inputs are not measured at all. They stay below the heavy threshold, so they keep the full thread pool while each stores a bigger circuit.
- E030 launched: e029 against base directly on small-tx. E029 only has this across chains (146.2 vs E028 base 146.4 s), and it is the option's main claim. Report only.

## 2026-11-04 20:47 Check-in: E030 on run 4 of 10
- 3 runs finished, all hashes yes. Harness figures, not read as a result: base 148 s, 1,295 MB; e029 151-153 s, 863-870 MB. The reading uses log wall over all 5 rounds. ETA about 21:35 stands as an estimate.
- Box: no lanes, 30 GB free. box81: load 0.00, nothing of ours running, 43 GB free.
- Peer watch: 192.168.1.116 is not among .22 connections at this check. Last seen at h=2303879 at 18:47. It has been absent before and come back. Cause not known from here.

## 2026-11-04 21:33 E030 done: all expectations met; queue empty
- e029 vs base, small-tx, 5 rounds, 10/10 hashes, log wall: 147.1 vs 145.5 s (+1.1%, overlap). CPU -0.7% (overlap). Peak anon 870 vs 1,137 MB (-23.5%, separate). Post-idle 729 vs 977 MB (-25.4%, separate).
- So the E029 option removes most of final's +5.5% wall cost on these blocks. Final stays, per the owner: its peak is lower, and proofs of 3-7 inputs remain unmeasured on the option.
- Nothing is running. The queue is empty except Needs owner. box81 idle. Hydrogen on schedutil, no lanes.

## 2026-11-04 21:33 E030 README correction; E029 limit made concrete
- E030 README said peak RSS ranges overlap. They do not (base 4,116-4,313, e029 4,050-4,108 MB). Corrected before anyone relied on it.
- E029 limit: E022 already recorded only 43 blocks with a largest tx of 3-7 inputs, no usable window. So the unmeasured sizes cannot be measured at the node on this chain.

## 2026-11-04 22:49 Check-in: nothing running, E031 launched on box81
- Hydrogen idle since E030, no lanes, 30 GB free. box81 load 0.00, 43 GB free.
- Queue empty except Needs owner, so I took the largest remaining gap in the report: final's cgroup minimum and long resync have only been measured on hydrogen, and base's minimum has not been re-measured against final since E009. E031 does both on box81, with long resync at 3 rounds rather than E023's 1. It uses an idle machine and does not change the recommendation. The owner asked earlier for box81 to be used for useful work.
- Not started: anything on the E029 option (owner keeps final), the window-aware E001 cap (owner's call).
- Peer watch: 192.168.1.116 not among .22 connections on two looks, second check in a row. Last seen at h=2303879 at 18:47. Cause not known from here.
