# STATE: read this first on every check-in

Last updated: 2026-11-03 14:48

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
- E010 long resync DONE 04:58 (experiments/E010-long-resync): combo peak -73%, idle -75%, no growth; wall +3.6% overall; small-tx blocks +14.8% (F22).
- E011 DONE 07:08 (experiments/E011-small-tx-attribution): small-tx wall vs base: cap +7.3%, cap+trim +13.3%, E007 +2.7%, combo +14.7% (F23).
- E012 DONE 09:15 (experiments/E012-adaptive-cap-trim, F24): adapt small-tx +4.0% vs base (combo +15.2%); heavy window adapt 109 s / 1,639 MB vs combo 110 s / 1,861 MB; e007 2,338 MB.
- E013 DONE 11:29 (experiments/E013-validate-adapt, F25): adapt is the RECOMMENDED build. Heavy A/B -68.2% peak, -50% wall; negtest PASS; min_mem 1,866 MB; long resync -70.5% peak, -4.6% wall. SUMMARY rewritten around adapt; owner pinged.
- E015 DONE 11:45: DIFF PASS at both heights (F26). **E014 RUNNING** (scripts/run_e015_e014.sh; thread sweep base vs adapt at --max-concurrency 4/2/1, 3 rounds; 15/18 runs at 14:47, est. done ~15:35. Base peaks vary run to run (c4: 1,351 / 2,193 / 2,020 MB; c2: 1,348 / 1,077 / 1,246) while adapt is tight (c4 1,050-1,064; c2 884-941; c1 893-912); report medians with spread. All hashes match so far; log e015_e014.chain ends CHAIN_E015_E014_COMPLETE).
- **E018 ARMED** (scripts/run_e018.sh, started 12:47): waits for CHAIN_E015_E014_COMPLETE AND the go-marker ~/work/research-artifacts/e018.go (touch it once ~/work/monero-oxide-e017 is reset to the final box81 commits). Then: build monero-fcmp-e017 (-j10), heavy A/B base/adapt/e017 x3 -> e018_heavy/, small-tx x3 -> e018_small/, negdiff vs base -> e018_neg/, min_mem e017 -> e018_minmem/, long resync e017_bss5 -> e018_long/. Log e018.chain ends CHAIN_E018_COMPLETE. Inputs verified 13:35 (cargo metadata resolves the [patch] to monero-oxide-e017 at 4bf0c13 + b180679; build dir fresh). Timeline estimate from 14:47: build ~40 min from ~15:35, heavy A/B done ~17:30, small-tx A/B ~20:00, negdiff + min_mem + long resync to ~23:00. Owner asked (13:3x) to be pinged when E017 is measured: ping once heavy + small-tx + negdiff are in (~20:30), again only if min_mem / long resync change the picture.
  - E015 differential negtest (safety): negdiff.sh + negtest2.py + negdiff_compare.py at H=3,105,401 (heavy txs) and H=3,106,400 (small/mid txs). Up to 4 big, 3 mid and 3 small real txs; 32 spread single-bit flips per proof, proof swaps between equal-length txs, then the originals. Oracle = base; adapt must give an identical (status, flags) per case, with all tampered rejected and all originals accepted. Output in e015/h*/ (summary ends NEGDIFF_COMPLETE with DIFF PASS/FAIL).
  - E014 thread sweep (does it hold on small machines?): heavy window, base vs adapt at --max-concurrency 4/2/1, 3 rounds, TO 1800 -> e014/. Caveat: the adapt cap is inert at pools <= 12 here.
- Snapshots: stressnet_h3106400 (WORKING copy for E011/E012, deletable when done), stressnet_synced_h3123270 (pristine), stressnet_wedge_h3105401.

## Queue (do the first item that is unblocked)
A. (DONE 02:56: the 50% verify hotspot is gone from the combo profile; recorded in E007.)
B. (DONE 03:30: E009 written up; owner informed.)
C. (DONE 05:02: E010 written up; owner pinged.)
D. reports/SUMMARY.md: E010 filled in 05:02 (bottom line now says speed is mixed). Fill in E011 when done.
E. DONE (E011 -> E012 -> E013; adapt recommended). NEXT after E015/E014: write experiments/E015 (negdiff summaries: DIFF PASS/FAIL, case counts, the oracle's rejection flag mix) and experiments/E014 (ab_stats per thread count; base vs adapt peak and wall at c4/c2/c1), update SUMMARY 'How real' and the guardrails, ping the owner. Then W002 (wallet) or an idle-trim refinement for adapt.
F. Fix the perf_classify.py regex and the stack_attrib.py owning-frame view (low priority).
F1. **E017 CRATE-LEVEL DONE 13:05 (all tests PASS on box81); NODE-LEVEL = E018 (armed, see above).** Worktree ~/work/monero-oxide-e017 at 4bf0c13 + b180679 (= box81 a0ff587 + cb3bafa). Sizes vs 31c26d9: code +513/-88 (refactor commit 92/33 is motion; GBP +25 additive lines, verify untouched), tests +228 plus a benchmark. Patches in patches/v2-E017-minimal/ (v1 kept in patches/v1-E007-full-streaming/ at the owner's request). After E018: write experiments/E018; v2 replaces v1 as the recommended series if heavy peak is within ~10% of adapt, small-tx wall is acceptable, negdiff PASS and hashes match; then update SUMMARY / FINDINGS / patches README (squash monerod 0004+0006 if v2 wins) and ping the owner. Original plan: owner request 12:0x: shrink the E007 patch).** Plan in experiments/E017-minimal-streaming/README.md: keep `ArithmeticCircuitStatement::verify` byte-identical; fcmps pre-folds each circuit into ONE constraint L = sum z^k c_k (so verify computes sum z^(k+1) c_k as before), using Discard + Fold circuit modes and a peeked z; three builds. Target ~150-200 non-test lines. New branch from 31c26d9 in ~/work/monero-oxide-e007 (not on top of E007). Acceptance: crate equivalence vs the UNCHANGED stock verify (8 shapes, honest + tampered), window peak within ~10% of adapt, wall within ~5%, hashes, negdiff identical to base. If it holds it replaces E007 in patches/ and E016 targets it.
F2. E016 (base-equivalence test for v1/E007): only needed if v1 stays the recommended series. In v2/E017 `verify_stored` is the stock verifier, so its equivalence test already closes the review's F1. Decide after E018.
G. Wallet track: W001 code map DONE (experiments/W001-wallet-tree-cache: the tree cache is bounded by reorg depth except registered outputs, which are tiny; peak candidates are refresh-time transients). NEXT: W002 measure refresh RSS/heaptrack of a fresh wallet over the dense stretch against OUR node, after E010. Also: stagenet/master comparison, monerosim scenarios.

## Second work box: box81 (added by the owner 2026-11-03 ~12:30)
- `ssh box81` (192.168.1.81), Ryzen 5 5600G 6c/12t Zen3, 14 GB, ~22 GB free SHARED disk. Rules in `~/README-FIRST.md` there: shared with `user`, `selfishmining`, `blocksize` (never touch their files/processes; no system-wide changes; stay in /home/optimizer); check idle (`uptime; who; ps`) and pin the governor before benchmarks; builds `nice -n 10`, at most `-j6`; NOT hardware-identical to hydrogen: never compare timings across boxes, never copy binaries (ARCH=native). Rust 1.97.1 via rustup (repo-pinned). Baseline monero 3fd0f88c2 built in ~/work/monero/build/baseline (step 1 verified 12:36: monerod --version OK, 233 unit tests PASS).
- Use: crate compiles/tests and crate-level micro-benchmarks, so hydrogen timing runs are undisturbed. No room for the 18 GB stressnet DB, so monerod-level measurements stay on hydrogen.
- On it: ~/work/monero-oxide-e017 (upstream 31c26d9 + E017, final commits a0ff587 + cb3bafa; ALL tests PASS 13:05: equivalence with the unchanged stock verify, tampered, error paths, the existing fcmps suite incl. test_malleated_proofs, GBP lib + integration with --features tests; ported to hydrogen, e018.go touched 13:00) and ~/work/monero-oxide-e007 (v1 + the counting-allocator benchmark as an uncommitted test append, scratch). Idle since 13:20, nothing queued: node-level A/B must run next to the hydrogen baselines and binaries never cross boxes.

## Watch (read-only)
- 192.168.1.116 (owner LAN node) was syncing at 2,097,439 at 20:10 on 2026-11-02. On each check-in, look up its height in .22 `get_connections` (scripts/peer_check.py). Does it pass 3,105,401 with multiple peers, or wedge there? Record in E001 notes.

## In flight (agents)
- None. (The Fable-tier E007 review finished 12:00: reports/E007-crypto-review.md, F28.)

## Needs owner (do not act on these alone)
- E001 upstream filing: READY (tested fix included, 2026-11-02 21:10). The owner will paste reports/E001-sync-wedge-ISSUE.md into the upstream repo themselves, once the prototype fix has been tested (E001-fix in queue). Never post it ourselves.
- E001: the owner's 72a62f5 shows the proposed cap is too loose for post-FCMP++ mainnet rules (the limit can double after 51 blocks) and proposes a window-aware cap (simulated, not built). On stressnet both caps give 4 blocks, so no research build is affected. Building and testing the window-aware cap is the owner's call; I have not acted on it.


## Rules for autonomous operation
- Shared box: before any A/B timing run, check `pgrep -fa shadow` and `uptime`. If selfishmining lanes are running, do only non-timing work (analysis, building, profiling). Never touch /home/selfishmining or their processes. Build with -j10 or less.
- The peer .22 belongs to the owner: RPC reads only (get_info, headers). No stop_daemon, set_log or bans on it.
- Never post, share or publish anything outside the LAN without the owner's approval.
- Keep >=20 GB disk free (snapshots are ~17 GB each); delete only our own working copies under ~/work/research-artifacts or ~/work/chains, never the baseline snapshot.
- Results count only if they pass the guardrails (same top hash as .22 at the end height, no verification weakened, wall time within ~10%, no shift to swap/disk).
- At the end of each check-in: update this file (Currently running, Queue, Last updated), append to JOURNAL.md, commit, then on the control box run `git -C ~/research-mirror pull -q origin master && git -C ~/research-mirror push -q github master`.
- The repo is PUBLIC at https://github.com/Fountain5405/monerod-memory-research (owner approved 2026-11-02). Never commit third-party (non-LAN) IPs, credentials, or large artifacts. Before each push, check: `git log -p -1 | grep -oE "([0-9]{1,3}\\.){3}[0-9]{1,3}"` should show only LAN/loopback/version strings.
- Delegate: mechanical runs and waits go to frugal:builder or frugal:mechanic with a complete spec; code location to frugal:scout; log or summary extraction to frugal:extractor. Keep design, interpretation and notes in the main context. Never pull raw transcripts or big logs into context (owner, 2026-11-02).
- The owner also commits to GitHub directly (first time: 72a62f5, 2026-11-03 11:13, E001 mainnet analysis). Mirror sync is therefore: `git -C ~/research-mirror pull -q origin master && git -C ~/research-mirror fetch -q github`. If github/master has commits we lack, merge them in the mirror (`merge --no-ff`, never rebase or force-push), push to github, then `git push origin master:refs/heads/owner-sync` and on hydrogen `git merge --ff-only owner-sync && git branch -d owner-sync`.
- Timestamps: take them from the box clock at the moment of writing; in record scripts use $(date +%H:%M), never a literal time guessed ahead (this went wrong twice on 2026-11-03).
- Harness gotchas: write prose files locally and scp them (apostrophes break `ssh '...'` heredocs); find monerod PIDs with `pgrep -x monerod` plus a cmdline match (pgrep -f self-matches); get_info returns target_height=0 when synced; restricted RPC 28089 lacks ranges, so use .22:28081.
