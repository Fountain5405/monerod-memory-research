# E003: does the FCMP++ verification peak scale with threads or with proofs?

**Question:** E002b put 4.33 GB of the 4.99 GB peak under `rct::batchVerifyFcmpPpProofs`, which bin-packs a block's FCMP++ proofs into one batch per thread and runs `fcmp_pp::verify(batch)` on each thread.
- Model A (accumulating batch verifier): memory ∝ proofs per block, roughly independent of the thread count.
- Model B (transient per-proof working set): memory ∝ concurrent verifier threads.

**Setup (2026-11-02 20:52, scripts/e003_sweep.sh):** baseline beta31 binary, `--block-sync-size 5` (E001 workaround), exclusive peer .22. Each run is rewound to 3,105,401 (pop_to.sh v2) and stops when the log height reaches 3,105,440: the same 40-block window for every run, including the ~10 MB stress blocks at 3,105,429+. Sampler at 2 s. Box quiet (no selfishmining lanes, no other runs). One run per setting.

**Results:**

| --max-concurrency | peak RssAnon | wall time for the window |
|---|---|---|
| 1 | 1,232 MB | 844 s |
| 4 | 2,033 MB | 279 s |
| 12 | 3,302 MB | **199 s** |
| default (24 = logical CPUs) | 5,400 MB | 220 s |

**Conclusion:**
- **Model B holds; model A is rejected.** The peak falls 4.4x from 24 threads to 1, while the set of proofs verified is identical; under A it would be roughly flat. Linear fit: ~1.0 GB base (RandomX, block data, accumulated batch terms, everything else) plus **~170-270 MB per concurrent FCMP++ verifier thread**.
- **Throughput does not benefit from SMT here.** 12 threads (= physical cores) beat 24 (199 s vs 220 s, n=1). The extra 12 threads add ~2.1 GB of peak for no speed.
- Implications:
  1. **E004a (config/default):** cap FCMP++ verification concurrency at the physical core count. Predicted here: about -39% peak with no slowdown. It needs a proper A/B (>=3 alternating runs); now running.
  2. **E004b (code):** shrink the per-verifier working set (2.3 GB of the 24-thread peak is under `divisor_challenge_eval`, mostly Vec growth). That helps every machine regardless of thread count. Rust sources are being located.

**Evidence:** evidence/E003_summary.txt, evidence/E003_*.mem.csv. Raw: ~/work/research-artifacts/E003/.
