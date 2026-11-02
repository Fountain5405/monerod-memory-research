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
