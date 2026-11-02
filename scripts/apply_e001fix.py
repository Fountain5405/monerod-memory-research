#!/usr/bin/env python3
"""Apply the E001 sync-size cap to src/cryptonote_core/cryptonote_core.cpp (run from the repo root)."""
import sys

p = "src/cryptonote_core/cryptonote_core.cpp"
s = open(p).read()

inc_anchor = '#include "cryptonote_core.h"\n'
inc_new = inc_anchor + '#include "net/levin_base.h"\n'
assert s.count(inc_anchor) == 1, "include anchor not unique"
s = s.replace(inc_anchor, inc_new, 1)

anchor = '''        MINFO("projected blocksize is " << projected_blocksize << " bytes, sync " << res << " blocks in next batch");
      }
    }
'''
assert s.count(anchor) == 1, "body anchor not unique"
new = '''        MINFO("projected blocksize is " << projected_blocksize << " bytes, sync " << res << " blocks in next batch");
      }

      // The estimate above only looks backward, at blocks we already have. After a run of
      // near-empty blocks it asks for BLOCKS_MAX_WINDOW blocks even if the next blocks are
      // large, and the peer's NOTIFY_RESPONSE_GET_OBJECTS can then exceed the levin packet
      // limit: the connection is dropped and the same request is retried forever.
      // Bound the request by the consensus block weight limit instead: a block's serialized
      // size does not exceed its weight, so N blocks at the limit fit in N * limit bytes
      // (plus small per-block/per-tx overhead, covered by the 10% margin).
      const uint64_t weight_limit = m_blockchain_storage.get_current_cumulative_block_weight_limit();
      if (weight_limit > 0)
      {
        const uint64_t budget = LEVIN_DEFAULT_MAX_PACKET_SIZE / 10 * 9;
        const size_t cap = std::max<uint64_t>(1, budget / weight_limit);
        if (res > cap)
        {
          MINFO("capping block sync size from " << res << " to " << cap << " blocks (block weight limit " << weight_limit << " bytes)");
          res = cap;
        }
      }
    }
'''
s = s.replace(anchor, new, 1)
open(p, "w").write(s)
print("patched", p)
