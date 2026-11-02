# STATE: read this first on every check-in

Last updated: 2026-11-02 21:05 (check-in #1)

## Goal (one line)
A real, verified reduction in monerod memory (owner's target: 40%), measured as peak and steady anon/private-dirty memory, plus the minimum cgroup memory.max for a fixed sync window, against the FCMP++ v0.19.0.0-beta.3.1 baseline on stressnet. See README.md for metrics and guardrails.

## Currently running
- **E001-fix test v3** (scripts/e001fix_test.sh -> repro_e001.sh v3, patched binary, 90 s bug + 90 s control, each followed by a rewind), started 20:48. Marker: E001FIX_COMPLETE at the end of ~/work/research-artifacts/E001/fixtest.done. Attempt 1 already showed the fix working (+1,074 blocks past the wedge, 0 oversize errors).
- **E003 concurrency sweep**, chained to start when the fix test completes: scripts/e003_sweep.sh 3105440 900 0 4 1 12 (baseline binary, window 3,105,401→3,105,440). Marker: E003_COMPLETE at the end of ~/work/research-artifacts/E003/summary.txt.
- Snapshots: stressnet_synced_h3123270 (pristine), stressnet_wedge_h3105401. Rewind the working DB with scripts/pop_to.sh (v2).

## Queue (do the first item that is unblocked)
1. (DONE 20:20: E002a, 316 MB, RandomX 89%, no jump without tx verification.) Analyze E002b: `heaptrack_print -f <file>.zst` (peak consumers, allocated/leaked); compare heaptrack's peak heap with RssAnon from mem.csv (tests H3, allocator retention). Write the Results section in experiments/E002-attribute-heap/README.md.
1b. (RUNNING) **E001-fix**: patched tree ~/work/monero-fcmp-e001fix (branch e001-sync-size-cap, commit 7dacc3156; diff in evidence/E001/e001-fix.diff). Build daemon-only into build/beta31-e001fix (-j10, only when no heaptrack run is active, because of RAM). Then rewind ~/work/chains/stressnet to 3,105,401 (pop_to.sh) and run repro_e001.sh with the PATCHED binary. Pass = the default-settings run advances past 3,105,401 with 0 oversize errors, and the end-height hash matches .22. Also record blocks/min vs the --block-sync-size 5 control. Write the results into reports/E001-sync-wedge-ISSUE.md (add a "Tested fix" section with the diff), then tell the owner it is ready to paste.
1c. **E003 analysis** when done: model A (peak flat across C, so bound proofs per verify batch, i.e. sub-batch to K proofs) vs model B (peak ∝ C, so a shared circuit or a cap on concurrent verifications). Then design the first memory fix (E004), on a branch in a copy of the source like monero-fcmp-e001fix, and A/B it (>=3 alternating runs, same window, peak RssAnon + wall time + end hash).
2. (DONE: E002b) If E002a did not reproduce the multi-GB jump: run **E002b**. Copy the synced snapshot to a working dir, pop back to < 3,102,800 (RPC `pop_blocks` on our own node), save that as snapshot `stressnet_preHF17_h<H>`, then replay the window under heaptrack (`--block-sync-size 5` because of E001).
3. Build the A/B harness `scripts/run_window.sh`: restore a snapshot, sync to a fixed end height from .22, check our block hash at the end height against .22 (get_block_header_by_height), and record peak/steady anon, wall time, and disk I/O (/proc/PID/io). Add `scripts/min_mem.sh`: a binary search over a systemd-run scope MemoryMax for the smallest limit that completes within 1.1x the unconstrained wall time.
4. Baseline the window: 3 runs of beta31 (median and spread). This is the number the 40% is measured against.
5. Iterate on the top consumer from E002: one change per experiment (ENNN dir), on a branch in ~/work/monero-fcmp (worktree per experiment), building to build/<exp>. Then A/B with >=3 alternating runs, guardrails, record, commit.
6. Draft the E001 sync-wedge write-up for the FCMP++ devs. **Do not post it**; the owner decides.
7. Later: wallet (tree_cache), stagenet/master comparison, monerosim scenarios.

## Watch (read-only)
- 192.168.1.116 (owner LAN node) was syncing at 2,097,439 at 20:10 on 2026-11-02. On each check-in, look up its height in .22 `get_connections` (scripts/peer_check.py). Does it pass 3,105,401 with multiple peers, or wedge there? Record in E001 notes.

## Needs owner (do not act on these alone)
- E001 upstream filing: the owner will paste reports/E001-sync-wedge-ISSUE.md into the upstream repo themselves, once the prototype fix has been tested (E001-fix in queue). Never post it ourselves.

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
