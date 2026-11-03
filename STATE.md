# STATE: read this first on every check-in

Last updated: 2026-11-03 12:30

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
- E015 DONE 11:45: DIFF PASS at both heights (F26). **E014 RUNNING** (scripts/run_e015_e014.sh; log e015_e014.chain, ends CHAIN_E015_E014_COMPLETE). The owner asked (11:2x) for 'the next thing that needs doing to show this works and is safe'.
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
F1. **E017 CODE STAGED, compile/test pending E014.** Worktree ~/work/monero-oxide-e017, branch e017-folded-verify: 7e32894 (refactor: build_verifier_circuits, no behaviour change) + d9a5329 (the fold). Sizes vs 31c26d9: non-test +513/-54 (of which 92/33 pure motion; GBP only +25 additive lines: VerifierTranscript Clone + peek_z; verify untouched), tests +228. NOT compiled yet (no cargo on hydrogen during E014 timing). Next: `cargo test -p generalized-bulletproofs-circuit-abstraction`, `-p generalized-bulletproofs --release`, `-p full-chain-membership-proofs --release -- --skip prove_benchmark --skip verify_benchmark` (test_malleated_proofs ~45 min, run last); fix compile errors; then monerod tree monero-fcmp-e017 (copy of adapt with the cargo [patch] paths sed-ed to monero-oxide-e017), build -j10, then measure: heavy A/B base/adapt/e017 (3 rounds), small-tx window, negdiff vs base, min_mem, long resync. Patch files: /tmp/e017/ on hydrogen and the control-box scratchpad e017/. Original plan: pdated: 2026-11-03 12:10

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
- E015 DONE 11:45: DIFF PASS at both heights (F26). **E014 RUNNING** (scripts/run_e015_e014.sh; log e015_e014.chain, ends CHAIN_E015_E014_COMPLETE). The owner asked (11:2x) for 'the next thing that needs doing to show this works and is safe'.
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
F1. **E017 minimal streaming verifier (after E014; owner request 12:0x: shrink the E007 patch).** Plan in experiments/E017-minimal-streaming/README.md: keep `ArithmeticCircuitStatement::verify` byte-identical; fcmps pre-folds each circuit into ONE constraint L = sum z^k c_k (so verify computes sum z^(k+1) c_k as before), using Discard + Fold circuit modes and a peeked z; three builds. Target ~150-200 non-test lines. New branch from 31c26d9 in ~/work/monero-oxide-e007 (not on top of E007). Acceptance: crate equivalence vs the UNCHANGED stock verify (8 shapes, honest + tampered), window peak within ~10% of adapt, wall within ~5%, hashes, negdiff identical to base. If it holds it replaces E007 in patches/ and E016 targets it.
F2. **E016 (after E014; needs cargo on hydrogen, so not during timing runs): close the crypto review's F1.** In ~/work/monero-oxide-e007 add, under #[cfg(test)], a VERBATIM copy of base `Fcmp::verify` (git show 31c26d9:crypto/fcmps/src/lib.rs) and base `ArithmeticCircuitStatement::verify` (31c26d9:crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs:657-820; `legacy_verify` in acp/tests.rs is already that copy, make it reachable), extracted by line range, not retyped; a test over the 8 shapes with honest and tampered proofs comparing streaming vs base verifier state with `additional` as a multiset; and the FCMP-level differential fuzz from section 5.2 of the review. Verbatim-ness check: diff the copied bodies against the git-show extracts. Run with `cargo test -p fcmps --release -- --skip prove_benchmark` (-j10). Record in experiments/E016. Delegate the typing to a builder with this spec; review the diff in the main context.
G. Wallet track: W001 code map DONE (experiments/W001-wallet-tree-cache: the tree cache is bounded by reorg depth except registered outputs, which are tiny; peak candidates are refresh-time transients). NEXT: W002 measure refresh RSS/heaptrack of a fresh wallet over the dense stretch against OUR node, after E010. Also: stagenet/master comparison, monerosim scenarios.

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
 owner request 12:0x: shrink the E007 patch).** Plan in experiments/E017-minimal-streaming/README.md: keep `ArithmeticCircuitStatement::verify` byte-identical; fcmps pre-folds each circuit into ONE constraint L = sum z^k c_k (so verify computes sum z^(k+1) c_k as before), using Discard + Fold circuit modes and a peeked z; three builds. Target ~150-200 non-test lines. New branch from 31c26d9 in ~/work/monero-oxide-e007 (not on top of E007). Acceptance: crate equivalence vs the UNCHANGED stock verify (8 shapes, honest + tampered), window peak within ~10% of adapt, wall within ~5%, hashes, negdiff identical to base. If it holds it replaces E007 in patches/ and E016 targets it.
F2. **E016 (after E014; needs cargo on hydrogen, so not during timing runs): close the crypto review's F1.** In ~/work/monero-oxide-e007 add, under #[cfg(test)], a VERBATIM copy of base `Fcmp::verify` (git show 31c26d9:crypto/fcmps/src/lib.rs) and base `ArithmeticCircuitStatement::verify` (31c26d9:crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs:657-820; `legacy_verify` in acp/tests.rs is already that copy, make it reachable), extracted by line range, not retyped; a test over the 8 shapes with honest and tampered proofs comparing streaming vs base verifier state with `additional` as a multiset; and the FCMP-level differential fuzz from section 5.2 of the review. Verbatim-ness check: diff the copied bodies against the git-show extracts. Run with `cargo test -p fcmps --release -- --skip prove_benchmark` (-j10). Record in experiments/E016. Delegate the typing to a builder with this spec; review the diff in the main context.
G. Wallet track: W001 code map DONE (experiments/W001-wallet-tree-cache: the tree cache is bounded by reorg depth except registered outputs, which are tiny; peak candidates are refresh-time transients). NEXT: W002 measure refresh RSS/heaptrack of a fresh wallet over the dense stretch against OUR node, after E010. Also: stagenet/master comparison, monerosim scenarios.

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
