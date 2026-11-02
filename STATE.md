# STATE: read this first on every check-in

Last updated: 2026-11-02 23:10

## Goal (one line)
A real, verified reduction in monerod memory (owner's target: 40%), measured as peak and steady anon/private-dirty memory, plus the minimum cgroup memory.max for a fixed sync window, against the FCMP++ v0.19.0.0-beta.3.1 baseline on stressnet. See README.md for metrics and guardrails.

## Currently running
- E004a DONE: -39.6% peak anon (median 5,614 → 3,393 MB), -10.9% wall time, all hashes match.
- E004c DONE (wall -9%, RSS -1.3%: arena retention). E006 DONE (construction ~5% of CPU).
- **E004d chain RUNNING** (scripts/chain_build_ab.sh e004d ...): build, then A/B base vs e004d, 3 rounds. Marker: CHAIN_E004D_COMPLETE at the end of ~/work/research-artifacts/e004d.chain; data in ~/work/research-artifacts/e004d/results.csv.
- E005 DONE (no effect; rejected).
- Snapshots: stressnet_synced_h3123270 (pristine), stressnet_wedge_h3105401.

## Queue (do the first item that is unblocked)
1. (DONE 20:20: E002a, 316 MB, RandomX 89%, no jump without tx verification.) Analyze E002b: `heaptrack_print -f <file>.zst` (peak consumers, allocated/leaked); compare heaptrack's peak heap with RssAnon from mem.csv (tests H3, allocator retention). Write the Results section in experiments/E002-attribute-heap/README.md.
1b. (DONE 21:10, PASSED; issue text ready) **E001-fix**: patched tree ~/work/monero-fcmp-e001fix (branch e001-sync-size-cap, commit 7dacc3156; diff in evidence/E001/e001-fix.diff). Build daemon-only into build/beta31-e001fix (-j10, only when no heaptrack run is active, because of RAM). Then rewind ~/work/chains/stressnet to 3,105,401 (pop_to.sh) and run repro_e001.sh with the PATCHED binary. Pass = the default-settings run advances past 3,105,401 with 0 oversize errors, and the end-height hash matches .22. Also record blocks/min vs the --block-sync-size 5 control. Write the results into reports/E001-sync-wedge-ISSUE.md (add a "Tested fix" section with the diff), then tell the owner it is ready to paste.
1c. (DONE 21:15: model B, per-thread working set ~170-270 MB) **E003 analysis**: model A (peak flat across C, so bound proofs per verify batch, i.e. sub-batch to K proofs) vs model B (peak ∝ C, so a shared circuit or a cap on concurrent verifications). Then design the first memory fix (E004), on a branch in a copy of the source like monero-fcmp-e001fix, and A/B it (>=3 alternating runs, same window, peak RssAnon + wall time + end hash).
1d. (DONE 21:45, CONFIRMED -39.6%) **E004a analysis:** if c12 cuts peak >=30% with wall time within ~10% across 3 rounds, prototype a TARGETED change: FCMP++ batch verify uses min(threadpool size, physical cores, or a configurable cap) instead of the global --max-concurrency, and A/B that build against baseline.
1f. min_mem.sh is READY (cgroup v2 scope self-test OK: runs as optimizer, MemoryMax honored, swap off). Run it on a quiet box: base (ref wall 220 s) and the best candidate (ref = its own A/B median wall). Suggested bounds: lo 1500, hi 8000, tol 250 MB. After E004d: a COMBINED build (E001 fix + E004c + E005 if it helps), then a final A/B vs baseline (>=3 rounds) and a min-cgroup-memory test (scripts/min_mem.sh). Also test a full-chain resync from the wedge snapshot to the tip with the combined build, checking hash and peak.
1g. (DONE 22:45) **E006 CPU profile** (after E004c; quiet box): `perf record` (flat, -F 199) on the baseline node over the window. Classify self time into circuit construction (LinComb ops/term/add/sub/mul, divisor_challenge_eval, BTreeMap, malloc/free/memcpy) vs curve math/multiexp/IPA. This prices E007.
1h. (FEASIBLE WITH CHANGES; 2-build plan; implementation delegated to an agent at 23:05, no cargo builds until e004d is done; see experiments/E007-streaming-verifier/README.md) **E007 streaming verifier (design + prototype):** Circuit modes {Store, Discard, Accumulate(z)}. Fcmp::verify keeps a clone T0 of the transcript at the start of the build. Pass 1 discards both circuits on the real transcript. Split ArithmeticCircuitStatement::verify into (a) read AI/AO/S and derive y,z, then (b) verify with pre-accumulated weights (l/r/o/cg/V weights plus the constant). Pass 2 replays the build on a clone of T0, accumulating c1 with z1; pass 3 does the same for c2. Gadget code is unchanged. Expected: per-verifier memory ~200 MB -> a few MB, at +2x the circuit-building CPU share. Needs careful equivalence testing (same accept/reject on valid AND tampered proofs).
1e. (DONE: E005 rejected) **E004b:** read the Rust verifier code (scout results); find what makes ~200 MB per verifier (divisor_challenge_eval, LinComb Vec growth); prototype a reduction (exact capacity, reuse buffers across proofs, a compact representation, dropping per-proof state earlier); build; A/B.
2. (DONE: E002b) If E002a did not reproduce the multi-GB jump: run **E002b**. Copy the synced snapshot to a working dir, pop back to < 3,102,800 (RPC `pop_blocks` on our own node), save that as snapshot `stressnet_preHF17_h<H>`, then replay the window under heaptrack (`--block-sync-size 5` because of E001).
3. Build the A/B harness `scripts/run_window.sh`: restore a snapshot, sync to a fixed end height from .22, check our block hash at the end height against .22 (get_block_header_by_height), and record peak/steady anon, wall time, and disk I/O (/proc/PID/io). Add `scripts/min_mem.sh`: a binary search over a systemd-run scope MemoryMax for the smallest limit that completes within 1.1x the unconstrained wall time.
4. Baseline the window: 3 runs of beta31 (median and spread). This is the number the 40% is measured against.
5. Iterate on the top consumer from E002: one change per experiment (ENNN dir), on a branch in ~/work/monero-fcmp (worktree per experiment), building to build/<exp>. Then A/B with >=3 alternating runs, guardrails, record, commit.
6. Draft the E001 sync-wedge write-up for the FCMP++ devs. **Do not post it**; the owner decides.
7. Later: wallet (tree_cache), stagenet/master comparison, monerosim scenarios.

## Watch (read-only)
- 192.168.1.116 (owner LAN node) was syncing at 2,097,439 at 20:10 on 2026-11-02. On each check-in, look up its height in .22 `get_connections` (scripts/peer_check.py). Does it pass 3,105,401 with multiple peers, or wedge there? Record in E001 notes.

## In flight (agents)
- E007 implementation agent: monero-oxide-e007 + monero-fcmp-e007, with tests. When it reports: REVIEW THE DIFF YOURSELF (soundness guards, z binding, determinism checks, bounds checks), then build and A/B.

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
