# Research: reducing monerod memory footprint

## Question
How much can monerod memory use be reduced *for real*, without weakening verification and without moving the cost elsewhere? The owner's target is 40%. Daemon first, wallet later.

## Metrics (in priority order)
1. Peak and steady-state **anonymous / private-dirty** memory (from /proc/PID/status and smaps_rollup), sampled every 10 s.
2. **Minimum cgroup memory.max** at which a fixed sync window (and eventually a full sync) completes with wall time within ~10% of the unconstrained run.
3. Reported but not optimized for: VmRSS and RssFile (the LMDB mmap, which is reclaimable page cache).

## Guardrails (every result must pass all of these)
- Same final chain state: the top block hash at the end height equals the reference peer's hash.
- No verification skipped or weakened (no embedded block hashes; same consensus checks).
- No cost shifted into swap, disk I/O or page cache. Wall time and disk I/O are recorded for every run.
- A/B runs happen on a quiet box (no selfishmining lanes, no other syncs), with at least 3 runs per arm, reporting median and spread.

## Reference baselines
- **Primary:** seraphis-migration/monero v0.19.0.0-beta.3.1 (d80596ad1, FCMP++), syncing stressnet from the LAN peer 192.168.1.22:28080 (testnet nettype).
- **Secondary:** upstream monero master 3fd0f88c2, syncing stagenet from public peers.

## Layout
- `JOURNAL.md`: chronological lab notebook (append-only, dated entries).
- `experiments/ENNN-<slug>/README.md`: one experiment each, with Hypothesis / Setup / Commands / Results / Conclusion / Evidence.
- `scripts/`: harness scripts. Runs use these copies, so the git history records what was run.
- `evidence/`: small raw evidence (CSVs, summaries, environment captures, diffs).
- `~/work/research-artifacts/`: large artifacts (heaptrack captures, logs, DB snapshots), indexed by sha256 in `evidence/ARTIFACTS.sha256`.
- `FINDINGS.md`: current ranked findings; becomes the final report.
- `patches/`: **the code**: the ordered `git format-patch` series for the recommended build (1 monero-oxide patch, 5 monerod patches) with reproduction instructions. Per-step diffs also sit under `evidence/`.
- `reports/`: owner-facing write-ups: SUMMARY.md (results), HOW-IT-WORKS.md and HOW-IT-WORKS-plain.md (the mechanism, technical and plain language), REVIEW-70pct.md (a critical re-check of the headline), PRIOR-ART.md (what upstream already did about verification memory, with links), E001-sync-wedge-ISSUE.md.
