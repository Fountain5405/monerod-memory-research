#!/usr/bin/env python3
"""E004e (on top of E004c): malloc_trim(0) after each FCMP++ batch verification (rctSigs.cpp).
Run from the monero tree root (a copy of the e004c tree)."""
p = "src/ringct/rctSigs.cpp"
s = open(p).read()
old = """      if (multithreaded)
        CHECK_AND_ASSERT_THROW_MES(waiter.wait(), "Failed to batch verify FCMP++ proofs");
"""
assert s.count(old) == 1, "wait anchor"
new = """      if (multithreaded)
        CHECK_AND_ASSERT_THROW_MES(waiter.wait(), "Failed to batch verify FCMP++ proofs");

      // Each batch just freed a large transient working set (the per-proof FCMP++ circuits, ~200 MB
      // per batch on stressnet). glibc keeps freed memory inside each thread's arena, so without a
      // trim RSS grows to (threads that ever ran a batch) x (per-thread high-water mark) and stays
      // there after sync. Return it to the OS once per batch-verify call (once per block).
#if defined(__GLIBC__)
      malloc_trim(0);
#endif
"""
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("patched: malloc_trim after FCMP++ batch verify")
