#!/usr/bin/env python3
"""E004d (on top of E004c): cap glibc malloc arenas at the physical core count, too.
Run from the monero tree root (a copy of the e004c tree)."""
p = "src/ringct/rctSigs.cpp"
s = open(p).read()
old = """      tools::threadpool &tpool = tools::threadpool::getInstanceForCompute();
      const std::size_t n_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());

      // Use at least 2 arenas always to match glibc's default minimum"""
assert s.count(old) == 1, "limitMaxMemArenas anchor"
new = """      tools::threadpool &tpool = tools::threadpool::getInstanceForCompute();
      const std::size_t pool_threads = std::max<std::size_t>(1, tpool.get_max_concurrency());
      // glibc keeps freed memory inside each arena. The large transient FCMP++ verification working
      // sets move between pool threads over time, so with one arena per pool thread RSS grows to
      // (pool threads) x (per-thread high-water mark) even though batchVerifyFcmpPpProofs only runs
      // one batch per physical core at a time. Use one arena per physical core as well.
      const std::size_t physical_cores = boost::thread::physical_concurrency();
      const std::size_t n_threads = physical_cores > 0 ? std::min(pool_threads, physical_cores) : pool_threads;

      // Use at least 2 arenas always to match glibc's default minimum"""
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("patched limitMaxMemArenas")
