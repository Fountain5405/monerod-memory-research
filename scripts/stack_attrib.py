#!/usr/bin/env python3
"""Attribute peak memory from heaptrack folded stacks (peak cost type, demangled).
usage: stack_attrib.py <folded file> [min_MB]
Prints (1) inclusive peak per normalized frame and (2) peak by first 'interesting' caller above
allocator/container glue, so the owning algorithm is visible."""
import collections
import re
import sys

path = sys.argv[1]
min_mb = float(sys.argv[2]) if len(sys.argv) > 2 else 40.0

GLUE = re.compile(
    r"(^alloc::|^core::|^std::|^__|malloc|calloc|realloc|operator new|RawVec|raw_vec|finish_grow|"
    r"reserve|grow_one|do_reserve|SpecFromIter|SpecExtend|from_iter|::collect|::extend|::push|::clone|"
    r"::to_vec|::insert_entry|::insert|btree::|vec::Vec|Iterator|::map|::fold|::for_each|heaptrack|"
    r"__gnu_cxx|_M_|std::vector|::resize|::emplace|<unknown>|^\?\?$)"
)


def norm(f):
    f = f.strip()
    f = re.sub(r"::h[0-9a-f]{16}$", "", f)
    prev = None
    while prev != f:  # strip nested generic args
        prev = f
        f = re.sub(r"<[^<>]*>", "", f)
    f = re.sub(r"\[[^\]]*\]", "", f)
    f = re.sub(r"\(.*\)( const)?$", "", f)  # drop C++ parameter lists
    parts = [p for p in f.split("::") if p]
    return "::".join(parts[-3:]) if parts else f


incl = collections.Counter()
owner = collections.Counter()
total = 0
with open(path) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line or " " not in line:
            continue
        stack, cost = line.rsplit(" ", 1)
        try:
            cost = int(cost)
        except ValueError:
            continue
        total += cost
        frames = [norm(f) for f in stack.split(";")]
        for f in set(frames):
            incl[f] += cost
        own = next((f for f in reversed(frames) if not GLUE.search(f)), frames[-1] if frames else "?")
        owner[own] += cost

print("total peak cost: %.2f GB" % (total / 1e9))
print("\n== peak by owning (first non-glue) frame, >= %.0f MB" % min_mb)
for f, c in owner.most_common(40):
    if c / 1e6 < min_mb:
        break
    print("%8.0f MB  %5.1f%%  %s" % (c / 1e6, 100.0 * c / total, f[:150]))
print("\n== inclusive peak per frame (fcmp/bulletproof/verify/cryptonote related), >= %.0f MB" % min_mb)
keys = re.compile(r"(fcmp|bulletproof|circuit|verif|lincomb|LinComb|monero|cryptonote|ver_|tree|Selene|Helios|divisor|gadget)", re.I)
shown = 0
for f, c in incl.most_common():
    if c / 1e6 < min_mb:
        break
    if keys.search(f):
        print("%8.0f MB  %5.1f%%  %s" % (c / 1e6, 100.0 * c / total, f[:150]))
        shown += 1
        if shown >= 45:
            break
