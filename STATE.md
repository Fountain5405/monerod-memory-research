# STATE: read this first on every check-in

Last updated: 2026-11-03 01:00

## Goal (one line)
A real, verified reduction in monerod memory (owner's target: 40%), measured as peak and steady anon/private-dirty memory, plus the minimum cgroup memory.max for a fixed sync window, against the FCMP++ v0.19.0.0-beta.3.1 baseline on stressnet. See README.md for metrics and guardrails.

## Currently running
- Done so far:
  - E004a: -39.6% peak with the `--max-concurrency 12` config.
  - E004c: wall -9%.
  - E004d: -8%.
  - E005: rejected.
  - E006: profile.
  - **E004e: CONFIRMED -44.6% peak RssAnon (5,309 → 2,943 MB), -88% post-idle (4,794 → 574 MB), -5.5% wall, hashes OK.**
- **Chain e007** (scripts/chain_build_ab.sh v2): builds ~/work/monero-fcmp-e007 (streaming verifier only, on top of beta31) into build/beta31-e007, then runs a 3-round A/B vs base with the governor pinned. Log: ~/work/research-artifacts/e007.chain, ending CHAIN_E007_COMPLETE; build log e007.build.log.
- **Chain combo**: queued; waits for CHAIN_E007_COMPLETE. Tree ~/work/monero-fcmp-combo, branch combo-e001-e004ce-e007: E004c + E004e + E001 fix (90921e2b3) + E007 cargo patch (1c15cefd6). Then a 3-round A/B vs base. Log ~/work/research-artifacts/combo.chain.
- Snapshots: stressnet_synced_h3123270 (pristine), stressnet_wedge_h3105401.

## Queue (do the first item that is unblocked)
A. When chain e007 is done: write up E007 results (experiments/E007-streaming-verifier), run scripts/ab_stats.py, ping the owner.
B. When chain combo is done: write it up and ping the owner. Then run **min_mem.sh** (quiet box) for base (ref wall = its A/B median, ~219 s) and for the best build (E004e or combo; ref = its own median wall). Bounds lo 1500, hi 8000, tol 250. This is the cgroup "real memory" metric.
C. Longer resync with the best build: from the wedge snapshot (3,105,401) to the tip, default settings (exercises the E001 fix in combo), hash check, peak/post-idle.
D. Write reports/SUMMARY.md: the owner-facing report of results, negative results, side findings, and caveats (128-input worst case, glibc-only trim).
E. Fix the perf_classify.py regex and the stack_attrib.py owning-frame view (low priority).
F. Later: wallet (tree_cache), stagenet/master comparison, monerosim scenarios.

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
