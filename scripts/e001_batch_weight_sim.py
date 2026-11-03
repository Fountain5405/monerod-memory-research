#!/usr/bin/env python3
"""Worst-case weight of one NOTIFY_RESPONSE_GET_OBJECTS batch under Monero's block weight rules.

Companion to reports/E001-sync-wedge-ISSUE.md ("Does mainnet permit this pattern?").

Model (Blockchain::update_next_cumulative_weight_limit, HF v15+):
  F      = long-term effective median = max(full reward zone, long-term median); constant here,
           since the long-term median moves on a 100,000-block window.
  median = epee median of the last 100 block weights (average of the two middle values).
  limit  = 2 * min(max(F, median), surge * F)
The attacker fills every requested block to the limit; the limit is recomputed after each block.

Estimator (core::get_block_sync_size): W = max weight of the last 100 blocks;
  N = 100 if W * 100 < B; 1 if W >= B / 2; else B // W, where B is --batch-max-weight in bytes.

Caps (the proposed fixes in the issue), budget = 90 MB:
  patch:   cap = budget / L, L = the current limit
  step51:  cap = budget / L, then (cap + 51) / 2 if cap > 51       (quiet-tip step)
  window:  cap = budget / L', L' = max(L, 2 * W), then (cap + 50) / 2 if cap > 50

The search covers windows of k small blocks followed by 100-k blocks of weight A, and the
reverse order, keeping only windows that are reachable (each A block fit under the limit in force
when it was mined, starting from an all-small window). It is a search over these shapes, not a
proof over all windows.

Usage: e001_batch_weight_sim.py [--fast]
"""
import sys

SMALL = 1000
BUDGET = 90e6
RULES = (("today", 300_000, 50), ("v17", 625_000, 8))
BATCHES = (10e6, 30e6, 40e6, 50e6)


def median(v):
    s = sorted(v)
    return (s[49] + s[50]) / 2


def limit(window, F, surge):
    return 2 * min(max(F, median(window)), surge * F)


def estimator(window, B):
    W = max(window)
    if W * 100 < B:
        return 100
    if W >= B / 2:
        return 1
    return int(B // W)


def cap_patch(window, F, surge):
    return max(1, int(BUDGET // limit(window, F, surge)))


def cap_step51(window, F, surge):
    cap = cap_patch(window, F, surge)
    return (cap + 51) // 2 if cap > 51 else cap


def cap_window(window, F, surge):
    L = max(limit(window, F, surge), 2 * max(window))
    cap = max(1, int(BUDGET // L))
    return (cap + 50) // 2 if cap > 50 else cap


CAPS = (("none", None), ("patch", cap_patch), ("step51", cap_step51), ("window", cap_window))


def batch_weight(window, F, surge, N):
    w = list(window)
    total = 0
    for _ in range(N):
        L = limit(w, F, surge)
        total += L
        w = w[1:] + [L]
    return total


def reachable_small_first(k, A, F, surge):
    w = [SMALL] * 100
    for _ in range(100 - k):
        if A > limit(w, F, surge):
            return False
        w = w[1:] + [A]
    return True


def windows(F, surge, fast):
    stride = max(1, int(F // (100 if fast else 200)))
    for k in range(0, 101):
        for A in range(int(F * 0.2), int(2 * F) + 1, stride):
            if reachable_small_first(k, A, F, surge):
                yield [SMALL] * k + [A] * (100 - k), (k, A, "small-first")
            if A <= 2 * F:  # big-first windows are reachable whenever A fits under the floor limit
                yield [A] * (100 - k) + [SMALL] * k, (k, A, "big-first")


def worst(F, surge, B, cap_fn, fast):
    best = (0, None)
    for win, desc in windows(F, surge, fast):
        N = estimator(win, B)
        if cap_fn:
            N = min(N, cap_fn(win, F, surge))
        t = batch_weight(win, F, surge, N)
        if t > best[0]:
            best = (t, desc + (N,))
    return best


def main():
    fast = "--fast" in sys.argv
    print(f"{'rules':6s} {'batch':>6s} {'cap':>7s} {'worst MB':>9s}  window (k small, A, order, N)")
    for label, F, surge in RULES:
        for B in BATCHES:
            for cap_name, cap_fn in CAPS:
                t, desc = worst(F, surge, B, cap_fn, fast)
                print(f"{label:6s} {B/1e6:5.0f}M {cap_name:>7s} {t/1e6:9.1f}  {desc}")
    quiet = [SMALL] * 100
    for label, F, surge in RULES:
        print(f"quiet tip, {label}: step51 cap {min(100, cap_step51(quiet, F, surge))}, "
              f"window cap {min(100, cap_window(quiet, F, surge))}")


if __name__ == "__main__":
    main()
