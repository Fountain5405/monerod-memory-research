#!/usr/bin/env python3
"""E004c: cap FCMP++ batch-verification parallelism at the physical core count (rctSigs.cpp).
Run from the monero tree root."""
p = "src/ringct/rctSigs.cpp"
s = open(p).read()

inc_anchor = '#include "common/threadpool.h"\n'
assert s.count(inc_anchor) == 1
s = s.replace(inc_anchor, inc_anchor + "#include <boost/thread/thread.hpp>\n", 1)

old = """      tools::threadpool &tpool = tools::threadpool::getInstanceForCompute();
      tools::threadpool::waiter waiter(tpool);
      const std::size_t n_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());
      const bool multithreaded = n_threads > 1;
"""
assert s.count(old) == 1, "batchVerifyFcmpPpProofs thread setup not found (or not unique)"
new = """      tools::threadpool &tpool = tools::threadpool::getInstanceForCompute();
      tools::threadpool::waiter waiter(tpool);
      // Each concurrently verifying batch holds a large transient working set (the per-proof
      // FCMP++ circuit, ~200 MB on stressnet), so peak memory scales with the number of batches.
      // Verification is compute-bound and gains nothing from SMT siblings, so use at most one batch
      // per physical core (falls back to the pool size if the core count is unknown).
      const std::size_t pool_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());
      const std::size_t physical_cores = boost::thread::physical_concurrency();
      const std::size_t n_threads = physical_cores > 0 ? std::min(pool_threads, physical_cores) : pool_threads;
      const bool multithreaded = n_threads > 1;
"""
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("patched", p)
