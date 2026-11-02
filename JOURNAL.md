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
