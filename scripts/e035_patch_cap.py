#!/usr/bin/env python3
"""E035: replace the E001 sync cap with the owner's window-aware cap (reports/E001-sync-wedge-ISSUE.md, 72a62f5). Run from a tree root that has patch 0003. Anchors asserted."""
import pathlib
def rep(path, old, new):
    p = pathlib.Path(path); s = p.read_text()
    assert s.count(old) == 1, (path, old[:70], s.count(old))
    p.write_text(s.replace(old, new, 1))

rep("src/cryptonote_core/cryptonote_core.cpp",
"""  size_t core::get_block_sync_size(uint64_t height, const uint64_t max_average_of_blocksize_in_queue) const
""",
"""  size_t get_block_sync_size_cap(uint64_t budget, uint64_t weight_limit, uint64_t window_max_weight)
  {
    // The limit can only rise once the short-term median does, and until 50 more blocks have
    // arrived the median is at most W, the largest block in the window. So budget for
    // L = max(current limit, 2 * W) for the next 50 blocks and 2 * L after that.
    const uint64_t budget_limit = std::max<uint64_t>(weight_limit, 2 * window_max_weight);
    size_t cap = std::max<uint64_t>(1, budget / budget_limit);
    const size_t step = CRYPTONOTE_REWARD_BLOCKS_WINDOW / 2;
    if (cap > step)
      cap = (cap + step) / 2;
    return cap;
  }
  //-----------------------------------------------------------------------------------------------
  size_t core::get_block_sync_size(uint64_t height, const uint64_t max_average_of_blocksize_in_queue) const
""")
rep("src/cryptonote_core/cryptonote_core.cpp",
"""      // Bound the request by the consensus block weight limit instead: a block's serialized
      // size does not exceed its weight, so N blocks at the limit fit in N * limit bytes
      // (plus small per-block/per-tx overhead, covered by the 10% margin).
""",
"""      // Bound the request by what the consensus rules allow the next blocks to weigh: a block's
      // serialized size does not exceed its weight, so the batch fits in its total weight
      // (plus small per-block/per-tx overhead, covered by the 10% margin).
""")
rep("src/cryptonote_core/cryptonote_core.cpp",
"""        const size_t cap = std::max<uint64_t>(1, budget / weight_limit);
        if (res > cap)
        {
          MINFO("capping block sync size from " << res << " to " << cap << " blocks (block weight limit " << weight_limit << " bytes)");
""",
"""        const size_t cap = get_block_sync_size_cap(budget, weight_limit, max_weight);
        if (res > cap)
        {
          MINFO("capping block sync size from " << res << " to " << cap << " blocks (block weight limit " << weight_limit << " bytes, largest recent block " << max_weight << " bytes)");
""")
rep("src/cryptonote_core/cryptonote_core.h",
"""namespace cryptonote
{
""",
"""namespace cryptonote
{
   /**
    * @brief the most blocks to request in one batch, so that the blocks cannot weigh more than budget
    *
    * @param budget the batch's budget in bytes of block weight
    * @param weight_limit the current block weight limit, must be > 0
    * @param window_max_weight the largest block weight among the last CRYPTONOTE_REWARD_BLOCKS_WINDOW blocks
    *
    * @return the cap, at least 1
    */
   size_t get_block_sync_size_cap(uint64_t budget, uint64_t weight_limit, uint64_t window_max_weight);

""")
rep("tests/unit_tests/CMakeLists.txt",
"""  long_term_block_weight.cpp
""",
"""  long_term_block_weight.cpp
  block_sync_size_cap.cpp
""")
print("E035 patched")
