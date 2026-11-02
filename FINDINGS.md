# Findings (living summary)

Status: harness under construction; no optimization results yet.

| # | Finding / candidate | Evidence | Est. saving | Status |
|---|---|---|---|---|
| F1 | The FCMP++ branch already caps glibc arenas (`rct::limitMaxMemArenas()`, called from cryptonote_core.cpp:444; M_ARENA_MAX = max(2, nthreads)). Upstream master does not. | code read, JOURNAL 2026-11-02 | already in the primary baseline | noted |
| F2 | Stagenet (master build): heap 217 MB -> 698 MB between heights 105k and 128k while sync slowed ~10x | E000 trace | TBD | to attribute (heaptrack) |
| F3 | RandomX keeps 2 light-mode caches (main + secondary seed), 256 MB each | rx-slow-hash.c:258-275, 430, 508, 535 | up to 256 MB if the second is avoidable | to measure |
