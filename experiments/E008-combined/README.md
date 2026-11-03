# E008: combined build (E004c + E004e + E007 + E001 fix)

**Hypothesis:** the three memory changes compose:
- E004c bounds the number of concurrent FCMP++ working sets (12 instead of 24).
- E007 shrinks each working set (no stored circuit).
- E004e returns freed memory to the OS once per block.

The E001 fix is included for the final build. With `--block-sync-size 5` it is inactive, because it only caps the adaptive sync size.

**Tree:** ~/work/monero-fcmp-combo, branch combo-e001-e004ce-e007:
- d80596ad1 (beta31)
- 2e80c0685 (E004c batch cap)
- 3ffb58c77 (E004e malloc_trim)
- 90921e2b3 (E001 fix, cherry-pick of 7dacc3156)
- 1c15cefd6 (E007 cargo patch, cherry-pick of bfd179a6a)

Build: build/beta31-combo, sha256 f0f664f1….

**Prediction:** peak ≈ 12 × (E007 working set) + base ≈ 1.5-2 GB; post-idle ≈ 0.5-0.6 GB (like E004e); wall ≈ E007.

**Results (chain combo, 2026-11-03 01:18-01:44):** 3 alternating rounds, governor pinned, every end hash = .22.

| round | arm | peak RssAnon MB | post-idle RssAnon MB | wall s |
|---|---|---|---|---|
| 1 | base | 5,237 | 4,732 | 220 |
| 1 | combo | 1,520 | 673 | 117 |
| 2 | combo | 1,751 | 993 | 117 |
| 2 | base | 5,289 | 4,850 | 217 |
| 3 | base | 5,436 | 5,046 | 220 |
| 3 | combo | 1,803 | 1,181 | 107 |

Medians (evidence/E008/stats.md):
- **peak RssAnon 5,289 → 1,751 MB (-66.9%)**. The ranges don't overlap: 5,237-5,436 vs 1,520-1,803.
- Private_Dirty -66.7%
- peak RSS 6,370 → 2,712 MB (-57.4%)
- **post-idle 4,850 → 993 MB (-79.5%)**
- **wall 220 → 117 s (-46.8%)**
- Disk writes unchanged (467 vs 465 MB).
- Negative test (E007 notes): combo rejects 24/24 tampered FCMP++ txs at the FCMP++ check and accepts 3/3 originals.

**Prediction check:**
- Peak landed inside the predicted range.
- Post-idle came in above E004e's ~574 MB, at 673-1,181 MB, and varies more. A trim only runs at the end of each block's batch verify. Memory freed later in the block-add path stays in the arenas until the next block. Also, small allocations interleaved with longer-lived chunks fragment the arenas, so a trim cannot release every page. Not chased further: it is still -80% vs base.
- Wall time is about E007 (108-115 s). The 12-thread cap costs nothing measurable here.

**Verdict: CONFIRMED.** This is the best build so far: -67% peak anon/private-dirty and -80% post-sync idle memory on the FCMP++ worst-case window, while syncing 47% faster.

**Next:** min cgroup memory (min_mem.sh) for base vs combo; then a long resync with default settings (exercises the E001 fix) to the tip.
