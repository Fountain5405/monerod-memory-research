#!/usr/bin/env python3
"""E012: make the E004c batch cap and the E004e malloc_trim adaptive to proof size (on top of the combo tree).
- Cap at physical cores only for heavy calls (largest proof >= 16 inputs); light calls use the whole pool.
- Trim after every heavy call; otherwise at most once every 10 s.
Run from the tree root (~/work/monero-fcmp-adapt). All anchors asserted before writing."""
p = "src/ringct/rctSigs.cpp"
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, old[:80]
    s = s.replace(old, new, 1)

rep("#include <boost/thread/thread.hpp>\n", "#include <boost/thread/thread.hpp>\n#include <chrono>\n")

rep("""      const std::size_t pool_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());
      const std::size_t physical_cores = boost::thread::physical_concurrency();
      const std::size_t n_threads = physical_cores > 0 ? std::min(pool_threads, physical_cores) : pool_threads;
""", """      // E012: apply the cap only to heavy calls. A proof's verifier working set grows with its input count.
      // With many-input proofs, SMT siblings slow verification down (E004c: -9% wall with the cap) and
      // multiply peak memory. With few-input proofs SMT helps (E011: the cap costs +7% wall on 2-input txs),
      // so light calls use the whole pool. The inputs are sorted by input count, descending, above.
      static constexpr std::size_t HEAVY_PROOF_MIN_INPUTS = 16;
      const bool heavy_call = fcmp_pp::n_inputs_in_fcmp_pp(fcmp_pp_verify_inputs.front()) >= HEAVY_PROOF_MIN_INPUTS;
      const std::size_t pool_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());
      const std::size_t physical_cores = boost::thread::physical_concurrency();
      const std::size_t n_threads = (heavy_call && physical_cores > 0) ? std::min(pool_threads, physical_cores) : pool_threads;
""")

rep("""#if defined(__GLIBC__)
      malloc_trim(0);
#endif
""", """#if defined(__GLIBC__)
      // E012: trim after every heavy call, which just freed large working sets. Otherwise trim at most
      // once every 10 s (E011: a trim after every light block costs +6% wall on 2-input txs).
      {
        static std::atomic<std::int64_t> last_trim_ms{0};
        const std::int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch()).count();
        if (heavy_call || now_ms - last_trim_ms.load(std::memory_order_relaxed) >= 10000)
        {
          last_trim_ms.store(now_ms, std::memory_order_relaxed);
          malloc_trim(0);
        }
      }
#endif
""")
open(p, "w").write(s)
print("patched", p)
