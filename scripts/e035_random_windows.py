#!/usr/bin/env python3
"""E035: random reachable windows through the owner's simulation model, which E035 part a checked against the real limit code.
The simulation searches two-weight window shapes. This tries windows it does not cover: each block is random, up to the limit in force, in bursts.
Usage: e035_random_windows.py <path to e001_batch_weight_sim.py> <windows per rule set> [seed]"""
import importlib.util, random, sys
spec = importlib.util.spec_from_file_location("sim", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
n = int(sys.argv[2]); random.seed(int(sys.argv[3]) if len(sys.argv) > 3 else 35)

def random_window(F, surge):
    w = [m.SMALL] * 100
    # start from a random prehistory length so the window can also hold blocks over the floor
    for _ in range(random.randint(100, 300)):
        if random.random() < 0.15:
            mode = random.choice(("small", "frac", "limit", "F"))
        else:
            mode = getattr(random_window, "mode", "small")
        random_window.mode = mode
        L = m.limit(w, F, surge)
        b = {"small": m.SMALL, "frac": int(L * random.random()), "limit": L, "F": min(L, F)}[mode]
        w = w[1:] + [max(m.SMALL, b)]
    return w

print(f"{'rules':6s} {'batch':>6s} {'cap':>7s} {'worst MB':>9s}  N   W   L at start")
for label, F, surge in m.RULES:
    worst = {(B, c): (0, None) for B in m.BATCHES for c, _ in m.CAPS}
    for _ in range(n):
        win = random_window(F, surge)
        W = max(win); L0 = m.limit(win, F, surge)
        w = list(win); totals = [0]
        for _i in range(100):
            L = m.limit(w, F, surge); totals.append(totals[-1] + L); w = w[1:] + [L]
        for B in m.BATCHES:
            E = m.estimator(win, B)
            for c, fn in m.CAPS:
                N = min(E, fn(win, F, surge)) if fn else E
                if totals[N] > worst[(B, c)][0]:
                    worst[(B, c)] = (totals[N], (N, W, L0))
    for B in m.BATCHES:
        for c, _f in m.CAPS:
            t, d = worst[(B, c)]
            print(f"{label:6s} {B/1e6:5.0f}M {c:>7s} {t/1e6:9.1f}  {d}")
