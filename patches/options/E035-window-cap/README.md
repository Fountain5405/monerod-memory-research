# E035: window-aware E001 sync cap

Replaces patch 0003's cap with the owner's window-aware cap (`reports/E001-sync-wedge-ISSUE.md`, 72a62f5): budget for `max(limit, 2 * largest recent block)` over the next 50 blocks and twice that after them. Applies on top of the v1 monerod series (`final`, tree fcbc96d3); applied, the tree hash is `ced7116caa99fb6321fb48788b83f81370dc44fa`.

Code change: +17/-4 in `cryptonote_core.cpp`, +11 in `cryptonote_core.h`. Also adds `tests/unit_tests/block_sync_size_cap.cpp` (+217), which drives `Blockchain`'s real weight-limit code. Measurements: `experiments/E035-*/`, when done.
