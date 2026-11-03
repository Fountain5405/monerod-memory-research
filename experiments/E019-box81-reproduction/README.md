# E019: independent reproduction on a second machine (box81, Ryzen 5 5600G 6c/12t, 14 GB)

**Why:** every node-level number so far came from one box (hydrogen, Ryzen 9 3900X 12c/24t, 16 GB) and reports/REVIEW-70pct.md asked for a second machine before the headline is believed. The owner freed disk on box81 on 2026-11-03 for exactly this. E019 repeats the E018 A/B (base vs adapt vs e017) on the heavy and the small-tx windows there, with the three binaries built natively on box81 (ARCH=native, so **box81 numbers are compared only with box81 numbers**; nothing here is a timing comparison with hydrogen).

**Setup:** box81, 2026-11-03 15:44-17:56, scripts/run_e019.sh (chain log evidence/E019/e019.chain, builds evidence/E019/e019.builds). Trees relayed from hydrogen: base = v0.19.0.0-beta.3.1 d80596ad1 (`monero-fcmp/build/beta31`, sha bac70623), adapt = `monero-fcmp-adapt` 4a51d434d (E012 cap + trim + E007 v1 verifier, sha fba28e56), e017 = `monero-fcmp-e017` 92f7ac279 (adapt + E017 v2 folded verifier, sha 4ff51c27). The 18.9 GB unpruned wedge snapshot at 3,105,401 was streamed from hydrogen through the control box (box81 cannot reach hydrogen). Default thread count on box81 is 12 (hardware threads), so the stock node verifies with 12 threads and adapt's cap on heavy proofs is 6 (physical cores). Idle check before the chain: load 0.38, four sessions of another user, all idle; governor pinned to `performance` for the whole chain and restored to `powersave` after. box81 keeps a 4 GB swap file, so `VmSwap` of our monerod was sampled every 2 s and reported per run.

- **(a) heavy window** 3,105,401 -> 3,105,441 (40 blocks, 64 x 128-input FCMP++ txs per block), `--block-sync-size 5`, DB restored from the snapshot before every run, 3 rounds, order alternated per round: 9 runs.
- **(b) prep sync** base to 3,106,400 (959 blocks, 374 s, peak 3,366 MB, post-idle 2,548 MB): one run, sets up (c).
- **(c) small-tx window** 3,106,400 -> 3,107,400 (1,000 blocks of ordinary 1-2 input txs), in-place rewind with pop_to.sh before every run, 3 rounds alternated: 9 runs.

**All 18 end-hash checks against .22 pass. VmSwap of our monerod was 0 kB in every sample of every run** (the 51 MB of system swap in use belongs to other users' idle processes and did not change).

## Results (median of 3, min-max in brackets; MB are RssAnon from the 2 s sampler)

### Heavy window (128-input proofs)

| metric | base | adapt (v1) | e017 (v2) | adapt vs base | e017 vs base |
|---|---|---|---|---|---|
| peak anon MB | 3,379 (3,063-3,557) | 1,302 (1,296-1,357) | 1,207 (1,183-1,270) | **-61.5%** | **-64.3%** |
| peak Private_Dirty MB | 3,385 (3,086-3,557) | 1,324 (1,322-1,379) | 1,223 (1,209-1,293) | -60.9% | -63.9% |
| peak RSS MB (incl. LMDB pages) | 4,698 (4,375-4,870) | 2,529 (2,490-2,586) | 2,441 (2,393-2,501) | -46.2% | -48.0% |
| post-idle anon MB | 3,095 (2,814-3,326) | 902 (861-937) | 851 (812-897) | **-70.9%** | **-72.5%** |
| wall s | 238 (236-239) | 136 (136-137) | 213 (210-213) | -42.9% | -10.5% |
| CPU s | 2,407 (2,403-2,417) | 660 (659-661) | 1,075 (1,067-1,075) | -72.6% | -55.3% |
| read / write MB | 9 / 466 | 9 / 466 | 9 / 466 | same | same |

Peak-anon ranges do not overlap between base and either patched arm.

### Small-tx window (1,000 blocks of 1-2 input txs)

| metric | base | adapt (v1) | e017 (v2) | adapt vs base | e017 vs base |
|---|---|---|---|---|---|
| peak anon MB | 1,091 (964-1,252) | 729 (727-738) | 721 (721-731) | **-33.2%** | **-33.9%** |
| peak Private_Dirty MB | 1,277 (1,113-1,356) | 919 (883-929) | 900 (859-910) | -28.0% | -29.5% |
| peak RSS MB | 3,747 (3,648-4,234) | 3,472 (3,209-3,508) | 3,713 (3,177-3,777) | -7.3% | -0.9% |
| post-idle anon MB | 853 (839-1,132) | 695 (684-696) | 710 (701-713) | -18.5% | -16.8% |
| wall s | 149 (148-149) | 157 (156-159) | 174 (172-176) | +5.4% | +16.8% |
| CPU s | 969 (969-977) | 1,063 (1,061-1,075) | 1,218 (1,212-1,236) | +9.7% | +25.7% |
| read / write MB | 0 / 1,128 | 0 / 1,129 | 0 / 1,139 | same | +1% |

Raw rows: results.csv (column `window` = heavy or small); per-run logs, samplers and the ab_window check logs in evidence/E019/.

## What it says

1. **The headline reproduces on different hardware.** On a 6-core Zen 3 box with half the threads, adapt removes 61.5% of the stock peak on the heavy window (hydrogen, same windows, same day, E018: -70.6%) and 71% of the post-idle footprint (hydrogen -74%), while being 43% faster with 73% less CPU. The owner's 40% target is met on the heavy window with margin on both machines.
2. **The stock peak is smaller here because there are fewer threads, as E003/E014 predicted.** base peaks at 3.4 GB with 12 verification threads on box81, against 5.4 GB with 24 on hydrogen and 2.0 GB with 4 (E014). The patched arms do not depend on the thread count in the same way (adapt 1.30 GB here vs 1.59 GB on hydrogen, with the cap at 6 vs 12), which is why the percentage shrinks as the box gets smaller while the absolute saving stays large (2.1 GB here, 3.8 GB on hydrogen).
3. **Small-tx blocks: the same -33% peak at both sites, with the same speed cost.** adapt is -33.2% peak here and -32.6% on hydrogen; its wall cost is +5.4% here and +6.0% there; e017's is +16.8% here and +12.1% there. The post-idle saving on small blocks is smaller on box81 (-18.5%) than on hydrogen (-30%), and base's post-idle spread is wide (839-1,132 MB) because the stock node's idle footprint depends on what the last batch left in the arenas.
4. **v2 (e017) matches v1's memory and costs CPU, here as on hydrogen.** e017's heavy peak is 7% below adapt's and its idle 6% below, but its heavy wall is 213 s against adapt's 136 s (+57%, CPU +63%), and on small-tx blocks it is +11% wall over adapt. The E017 plan predicted "wall within ~5% of adapt"; that prediction is wrong on both machines. The v1-vs-v2 decision is made in experiments/E018 with both sites' data.
5. **No swap, no disk shift, no reordering.** VmSwap 0 kB in all 18 runs although the box has a swap file; identical read/write bytes per arm; every end hash equals .22.

## Guardrails
- End hash equal to .22 in all 18 runs (heavy at 3,105,441 + the 5 blocks the peer serves past the target; small at 3,107,400-3,107,410, same behaviour as on hydrogen); no run timed out; no rewind failed.
- Verification unchanged in adapt (E015 differential negtest DIFF PASS, same source 4a51d434d) and in e017 (E018 (c) negdiff DIFF PASS at both heights on hydrogen, same source 92f7ac279).
- No shift to disk or swap: identical read/write bytes per arm; VmSwap 0 in every sample.
- Quiet box: idle check passed before the chain, governor `performance` for all 19 runs, no other user's load during the chain (load 1.1 at the end, all ours).
- Not a cross-machine timing comparison: box81 binaries are ARCH=native builds on Zen 3; only percentages are set side by side with hydrogen's, never seconds.
