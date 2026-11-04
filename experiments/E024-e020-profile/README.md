# E024: where e020's extra wall goes on the heavy window (flat CPU profile)

**Status: done. The extra cost is mostly more field multiplication, plus the verifier and fold loops themselves. Extra copying is a small part. The profile has no call graphs, so it does not say which caller does the extra multiplication.**

**Why:** E020 left v2 at +28% heavy wall over v1, more than the crate benchmark predicted (about +12%), and listed two candidates: the fold accumulator, and copying from the transcript clone.

**Setup:** hydrogen, 2026-11-04 09:32-09:41, `scripts/run_e024.sh`: `scripts/profile_window.sh` (perf -F 199, all threads, no call graphs), heavy window 3,105,401 -> 3,105,441, 2 rounds per arm in the order e020, final, final, e020. Arms: **e020** (sha a4d8448a) and **final** (sha d779a522). This e020 binary does not have v2's patches 0007 and 0008, so it uses threshold 16 and has no idle trim. On this window that changes behaviour on 2 blocks at most. This is a profile, not a timing result: wall under perf was 146 / 144 s against 110 / 109 s, and cycles are reported below only as shares.

## Result
Total cycles: final 3.67e12, e020 5.01e12, **+1.34e12 (+36.5%)**, in line with E020's +35% CPU. Absolute cycles per symbol, means of 2 rounds (`scripts/e024_diff.py`, evidence/E024/diff.csv):

| symbol | final, e12 | e020, e12 | difference, e12 | share of the difference |
|---|---|---|---|---|
| `crypto_bigint montgomery_reduction<4>` | 0.678 | 1.146 | +0.468 | 34.9% |
| `crypto_bigint Uint<4>::mul_wide<4>` | 0.451 | 0.734 | +0.283 | 21.2% |
| `ArithmeticCircuitStatement<Selene>::verify` | 0.000 | 0.197 | +0.197 | 14.7% |
| `ScalarVector<HelioseleneField> * HelioseleneField` | 0.001 | 0.152 | +0.151 | 11.3% |
| `FoldedConstraints::accumulate`, Selene + Helios | 0.000 | 0.105 | +0.105 | 7.8% |
| `ScalarVector + &ScalarVector` | 0.000 | 0.030 | +0.030 | 2.2% |
| `memmove` + `memset` | 0.185 | 0.236 | +0.051 | 3.8% |
| `LinComb::term` | 0.158 | 0.180 | +0.022 | 1.7% |
| `accumulate_vector`, `constrain_equal_to_zero`, `PendingVerification::apply` (v1's counterparts) | 0.127 | 0.018 | -0.109 | -8.1% |

The two rounds of each arm agree closely (top shares within 0.3 percentage points).

## Reading
- **Copying is not the main cause.** memmove and memset together are 3.8% of the difference, so E020's copying candidate explains little of it.
- **More than half the difference is field multiplication** (`montgomery_reduction` + `mul_wide`, 56%). A flat profile does not say who calls them. The symbols that appear only in e020 (`verify`, the `ScalarVector` multiply, `accumulate`, 34% together) are the likely callers, but that is an inference.
- **Symbol comparisons across two different code paths are rough:** e020 and v1 inline different things, which is why v1 shows 0.000 for `verify`. The table shows where self-time lands, not a clean function-by-function cost.
- **So the outcome E020 asked about leans towards "the remaining cost is in the fold and its verify path", not a removable overhead such as copying.** That is not proven. A call-graph profile (`perf record -g`) would attribute the 56%.

Whether to go further is the owner's call: it matters only if v2 is the series they want to present, since v1 stays recommended.

## Guardrails
- No shadow lanes (the chain checked `pgrep`; `r1_e020/summary.txt` lists one match, which is my own launch shell, whose command text contained the word). Governor pinned per run and restored.
- All 4 runs reached 3,105,441. Hashes were not checked, since this harness does not check them.
- Symbols below perf's 0.05% limit are not counted. Evidence: evidence/E024 (perf_symbols.txt per run, diff.csv); perf.data is not in the repo.
