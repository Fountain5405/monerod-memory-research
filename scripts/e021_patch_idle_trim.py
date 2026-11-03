#!/usr/bin/env python3
"""E021: idle trim for adapt. After the last FCMP++ batch verification, nothing in adapt (E012) releases the
freed verifier working sets if no further verification happens (light calls trim at most every 10 s, and only
when a call occurs), so the node idles 0.1-0.4 GB above the per-block-trim combo. This adds one malloc_trim(0)
from core::on_idle once no batch verification has run for 5 s and the last verification was not followed by a
trim. Run from the tree root (~/work/monero-fcmp-idle, copy of monero-fcmp-adapt 4a51d434d). Anchors asserted."""
import pathlib

def rep(path, old, new):
    p = pathlib.Path(path); s = p.read_text()
    assert s.count(old) == 1, (path, old[:70], s.count(old))
    p.write_text(s.replace(old, new, 1))

# ---- rctSigs.cpp: shared timestamps, record the verification, idle trim function
rep("src/ringct/rctSigs.cpp",
"""    bool batchVerifyFcmpPpProofs(std::vector<fcmp_pp::FcmpPpVerifyInput> &&fcmp_pp_verify_inputs) {
""",
"""    // E021: when the last FCMP++ batch verification ran, and when the last trim ran (steady_clock ms).
    // Written by batchVerifyFcmpPpProofs, read by idleTrimFcmpPp from the core idle loop.
    static std::atomic<std::int64_t> s_fcmp_last_verify_ms{0};
    static std::atomic<std::int64_t> s_fcmp_last_trim_ms{0};

    static inline std::int64_t steadyNowMs()
    {
      return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    bool idleTrimFcmpPp(std::int64_t idle_ms)
    {
#if defined(__GLIBC__)
      const std::int64_t last_verify = s_fcmp_last_verify_ms.load(std::memory_order_relaxed);
      if (last_verify == 0 || s_fcmp_last_trim_ms.load(std::memory_order_relaxed) >= last_verify)
        return false; // nothing verified since the last trim
      const std::int64_t now_ms = steadyNowMs();
      if (now_ms - last_verify < idle_ms)
        return false; // still verifying
      s_fcmp_last_trim_ms.store(now_ms, std::memory_order_relaxed);
      malloc_trim(0);
      MGINFO("FCMP++ verification idle for " << (now_ms - last_verify) / 1000 << " s: returned freed verifier memory to the OS");
      return true;
#else
      (void)idle_ms;
      return false;
#endif
    }

    bool batchVerifyFcmpPpProofs(std::vector<fcmp_pp::FcmpPpVerifyInput> &&fcmp_pp_verify_inputs) {
""")

rep("src/ringct/rctSigs.cpp",
"""      {
        static std::atomic<std::int64_t> last_trim_ms{0};
        const std::int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch()).count();
        if (heavy_call || now_ms - last_trim_ms.load(std::memory_order_relaxed) >= 10000)
        {
          last_trim_ms.store(now_ms, std::memory_order_relaxed);
          malloc_trim(0);
        }
      }
""",
"""      // E021: record the verification first, so a trim here counts as "after the last verification"
      // and the idle trim does not repeat it.
      {
        const std::int64_t now_ms = steadyNowMs();
        s_fcmp_last_verify_ms.store(now_ms, std::memory_order_relaxed);
        if (heavy_call || now_ms - s_fcmp_last_trim_ms.load(std::memory_order_relaxed) >= 10000)
        {
          s_fcmp_last_trim_ms.store(now_ms, std::memory_order_relaxed);
          malloc_trim(0);
        }
      }
""")

# ---- rctSigs.h: declaration
rep("src/ringct/rctSigs.h",
"""    bool verRctNonSemanticsSimple(const rctSig & rv);
""",
"""    bool verRctNonSemanticsSimple(const rctSig & rv);
    // E021: return freed FCMP++ verifier memory to the OS once no batch verification has run for idle_ms.
    // Returns true if a trim was performed. No-op on non-glibc builds.
    bool idleTrimFcmpPp(std::int64_t idle_ms);
""")

# ---- cryptonote_core.h: a 2 s periodic task
rep("src/cryptonote_core/cryptonote_core.h",
"""     epee::math_helper::once_a_time_seconds<60*60*24*7, false> m_diff_recalc_interval; //!< interval for recalculating difficulties
""",
"""     epee::math_helper::once_a_time_seconds<60*60*24*7, false> m_diff_recalc_interval; //!< interval for recalculating difficulties
     epee::math_helper::once_a_time_seconds<2, false> m_fcmp_idle_trim_interval; //!< E021: interval for the FCMP++ idle trim check
""")

# ---- cryptonote_core.cpp: call it from on_idle
s = pathlib.Path("src/cryptonote_core/cryptonote_core.cpp").read_text()
if '#include "ringct/rctSigs.h"' not in s:
    rep("src/cryptonote_core/cryptonote_core.cpp",
        '#include "cryptonote_core.h"\n',
        '#include "cryptonote_core.h"\n#include "ringct/rctSigs.h"\n')
rep("src/cryptonote_core/cryptonote_core.cpp",
"""    m_diff_recalc_interval.do_call(boost::bind(&core::recalculate_difficulties, this));
    m_miner.on_idle();
""",
"""    m_diff_recalc_interval.do_call(boost::bind(&core::recalculate_difficulties, this));
    m_fcmp_idle_trim_interval.do_call([]{ rct::idleTrimFcmpPp(5000); return true; }); // E021
    m_miner.on_idle();
""")
print("E021 patched: rctSigs.cpp/.h, cryptonote_core.cpp/.h")
