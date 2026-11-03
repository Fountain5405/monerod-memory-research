# STATE: read this first on every check-in

Last updated: 2026-11-03 03:40

## Goal (one line)
A real, verified reduction in monerod memory (owner's target: 40%), measured as peak and steady anon/private-dirty memory, plus the minimum cgroup memory.max for a fixed sync window, against the FCMP++ v0.19.0.0-beta.3.1 baseline on stressnet. See README.md for metrics and guardrails.

## Currently running
- Done so far:
  - E004a: -39.6% peak with the `--max-concurrency 12` config.
  - E004c: wall -9%.
  - E004d: -8%.
  - E005: rejected.
  - E006: profile.
  - E004e: -44.6% peak, -88% idle.
  - **E007: -59% peak, -50% wall.**
  - **E008 combo: -66.9% peak (5,289 → 1,751 MB), -79.5% post-idle, -46.8% wall.**
  - **Negative test PASS for base and combo** (24/24 tampered rejected at the FCMP++ check, 3/3 originals accepted).
- **profile_combo** (scripts/profile_window.sh): perf profile of the combo build over the window, to confirm why E007 is 2x faster. Output ~/work/research-artifacts/profile_combo/ (summary.txt ends PROFILE_COMPLETE; perf_symbols.txt).
- minmem chain DONE 03:23 (E009: base 5,750 MB vs combo 1,866 MB minimum MemoryMax, -67.5%). Was: (scripts/run_minmem.sh): waits for PROFILE_COMPLETE, then runs min_mem.sh for combo (ref 117 s, lo 750, hi 4000, tol 125) and base (ref 220 s, lo 2000, hi 8000, tol 250). Governor pinned for the chain. Log ~/work/research-artifacts/minmem.chain, ending CHAIN_MINMEM_COMPLETE; per-label csv/summary in ~/work/research-artifacts/minmem/.
- **E010 long resync RUNNING** (started 03:31; scripts/run_e010.sh): 3,105,401 → 3,123,400, arms combo_default, base_bss5, combo_bss5 (1 run each, DB restored from the wedge snapshot each run). Log ~/work/research-artifacts/e010.chain (ends CHAIN_E010_COMPLETE); data in ~/work/research-artifacts/e010/. Est. 2-5 h in total.
- Snapshots: stressnet_synced_h3123270 (pristine), stressnet_wedge_h3105401.

## Queue (do the first item that is unblocked)
A. (DONE 02:56: the 50% verify hotspot is gone from the combo profile; recorded in E007.)
B. (DONE 03:30: E009 written up; owner informed.)
C. (RUNNING as E010; see Currently running.) When done: write experiments/E010-long-resync results (peak, post-idle, wall per arm, hash; per-segment block rate from the Synced log lines, to compare the small-tx stretch), then ping the owner.
D. reports/SUMMARY.md DRAFTED 03:37; fill in E010 results when done, plus the small-input CPU cost (E).
E. Small-input regression check for E007: a window or microbench with 1-2-input proofs only (e.g. the agent's measure harness at inputs = 1, 2), to price the double-build CPU cost honestly.
F. Fix the perf_classify.py regex and the stack_attrib.py owning-frame view (low priority).
G. Later: wallet (tree_cache), stagenet/master comparison, monerosim scenarios.

## Watch (read-only)
- 192.168.1.116 (owner LAN node) was syncing at 2,097,439 at 20:10 on 2026-11-02. On each check-in, look up its height in .22 `get_connections` (scripts/peer_check.py). Does it pass 3,105,401 with multiple peers, or wedge there? Record in E001 notes.

## In flight (agents)
- None. (The E007 agent finished at 00:20; its diff was reviewed by me; see experiments/E007-streaming-verifier.)

## Needs owner (do not act on these alone)
- E001 upstream filing: READY (tested fix included, 2026-11-02 21:10). The owner will paste reports/E001-sync-wedge-ISSUE.md into the upstream repo themselves, once the prototype fix has been tested (E001-fix in queue). Never post it ourselves.

## Rules for autonomous operation
- Shared box: before any A/B timing run, check `pgrep -fa shadow` and `uptime`. If selfishmining lanes are running, do only non-timing work (analysis, building, profiling). Never touch /home/selfishmining or their processes. Build with -j10 or less.
- The peer .22 belongs to the owner: RPC reads only (get_info, headers). No stop_daemon, set_log or bans on it.
- Never post, share or publish anything outside the LAN without the owner's approval.
- Keep >=20 GB disk free (snapshots are ~17 GB each); delete only our own working copies under ~/work/research-artifacts or ~/work/chains, never the baseline snapshot.
- Results count only if they pass the guardrails (same top hash as .22 at the end height, no verification weakened, wall time within ~10%, no shift to swap/disk).
- At the end of each check-in: update this file (Currently running, Queue, Last updated), append to JOURNAL.md, commit, then on the control box run `git -C ~/research-mirror pull -q origin master && git -C ~/research-mirror push -q github master`.
- The repo is PUBLIC at https://github.com/Fountain5405/monerod-memory-research (owner approved 2026-11-02). Never commit third-party (non-LAN) IPs, credentials, or large artifacts. Before each push, check: `git log -p -1 | grep -oE "([0-9]{1,3}\\.){3}[0-9]{1,3}"` should show only LAN/loopback/version strings.
- Delegate: mechanical runs and waits go to frugal:builder or frugal:mechanic with a complete spec; code location to frugal:scout; log or summary extraction to frugal:extractor. Keep design, interpretation and notes in the main context. Never pull raw transcripts or big logs into context (owner, 2026-11-02).
- Harness gotchas: write prose files locally and scp them (apostrophes break `ssh '...'` heredocs); find monerod PIDs with `pgrep -x monerod` plus a cmdline match (pgrep -f self-matches); get_info returns target_height=0 when synced; restricted RPC 28089 lacks ranges, so use .22:28081.
