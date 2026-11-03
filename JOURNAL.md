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
