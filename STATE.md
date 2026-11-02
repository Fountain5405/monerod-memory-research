# STATE: read this first on every check-in

Last updated: 2026-11-02 20:00 (session start of autonomous mode)

## Goal (one line)
A real, verified reduction in monerod memory (owner's target: 40%), measured as peak and steady anon/private-dirty memory, plus the minimum cgroup memory.max for a fixed sync window, against the FCMP++ v0.19.0.0-beta.3.1 baseline on stressnet. See README.md for metrics and guardrails.

## Currently running
- **E002a**: heaptrack of the synced beta31 node after restart, 600 s from 19:52 UTC. Artifacts: ~/work/research-artifacts/E002a-restart-synced/ (run.txt ends with "DONE" when finished).
  Check: `tail -3 ~/work/research-artifacts/E002a-restart-synced/run.txt; tail -2 .../mem.csv`

## Queue (do the first item that is unblocked)
1. Analyze E002a: `heaptrack_print -f <file>.zst` (peak consumers, allocated/leaked); compare heaptrack's peak heap with RssAnon from mem.csv (tests H3, allocator retention). Write the Results section in experiments/E002-attribute-heap/README.md.
2. If E002a did not reproduce the multi-GB jump: run **E002b**. Copy the synced snapshot to a working dir, pop back to < 3,102,800 (RPC `pop_blocks` on our own node), save that as snapshot `stressnet_preHF17_h<H>`, then replay the window under heaptrack (`--block-sync-size 5` because of E001).
3. Build the A/B harness `scripts/run_window.sh`: restore a snapshot, sync to a fixed end height from .22, check our block hash at the end height against .22 (get_block_header_by_height), and record peak/steady anon, wall time, and disk I/O (/proc/PID/io). Add `scripts/min_mem.sh`: a binary search over a systemd-run scope MemoryMax for the smallest limit that completes within 1.1x the unconstrained wall time.
4. Baseline the window: 3 runs of beta31 (median and spread). This is the number the 40% is measured against.
5. Iterate on the top consumer from E002: one change per experiment (ENNN dir), on a branch in ~/work/monero-fcmp (worktree per experiment), building to build/<exp>. Then A/B with >=3 alternating runs, guardrails, record, commit.
6. Draft the E001 sync-wedge write-up for the FCMP++ devs. **Do not post it**; the owner decides.
7. Later: wallet (tree_cache), stagenet/master comparison, monerosim scenarios.

## Watch (read-only)
- 192.168.1.116 (owner LAN node) was syncing at 2,097,439 at 20:10 on 2026-11-02. On each check-in, look up its height in .22 `get_connections` (scripts/peer_check.py). Does it pass 3,105,401 with multiple peers, or wedge there? Record in E001 notes.

## Needs owner (do not act on these alone)
- Whether and where to report E001 (sync wedge) upstream.

## Rules for autonomous operation
- Shared box: before any A/B timing run, check `pgrep -fa shadow` and `uptime`. If selfishmining lanes are running, do only non-timing work (analysis, building, profiling). Never touch /home/selfishmining or their processes. Build with -j10 or less.
- The peer .22 belongs to the owner: RPC reads only (get_info, headers). No stop_daemon, set_log or bans on it.
- Never post, share or publish anything outside the LAN without the owner's approval.
- Keep >=20 GB disk free (snapshots are ~17 GB each); delete only our own working copies under ~/work/research-artifacts or ~/work/chains, never the baseline snapshot.
- Results count only if they pass the guardrails (same top hash as .22 at the end height, no verification weakened, wall time within ~10%, no shift to swap/disk).
- At the end of each check-in: update this file (Currently running, Queue, Last updated), append to JOURNAL.md, commit, and `git -C ~/research-mirror pull` on the control box.
- Delegate: mechanical runs and waits go to frugal:builder or frugal:mechanic with a complete spec; code location to frugal:scout; log or summary extraction to frugal:extractor. Keep design, interpretation and notes in the main context. Never pull raw transcripts or big logs into context (owner, 2026-11-02).
- Harness gotchas: write prose files locally and scp them (apostrophes break `ssh '...'` heredocs); find monerod PIDs with `pgrep -x monerod` plus a cmdline match (pgrep -f self-matches); get_info returns target_height=0 when synced; restricted RPC 28089 lacks ranges, so use .22:28081.
