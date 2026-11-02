#!/usr/bin/env python3
"""Classify `perf report --stdio --no-children --sort symbol` self time into coarse categories.
usage: perf_classify.py <perf_symbols.txt>
Categories are regex-based and approximate. Run with -I."""
import collections
import re
import sys

CATS = [
    ("alloc/free/memcpy", r"(malloc|free|realloc|calloc|_int_malloc|_int_free|cfree|memcpy|memmove|memset|__memcpy|__memmove|__memset|mremap|madvise|munmap|mmap|brk|page_fault|clear_page|do_anonymous|alloc_pages|__rust_alloc|__rust_dealloc|__rdl_|RawVec|raw_vec|finish_grow|grow_one)"),
    ("circuit building (LinComb / BTreeMap / gadgets)", r"(LinComb|lincomb|btree|BTree|insert_entry|VacantEntry|circuit_abstraction|Circuit|divisor_challenge_eval|discrete_log|ec_gadgets|gadget|tape|Tape|first_layer|additional_layer|member_of_list|incomplete_add|on_curve|tuple_member)"),
    ("verify statement (weights / yz / IPA)", r"(accumulate_vector|yz_challenges|ArithmeticCircuitStatement|arithmetic_circuit_proof|inner_product|IpStatement|ScalarVector|PointVector|powers)"),
    ("multiexp / batch verifier", r"(multiexp|Multiexp|straus|pippenger|BatchVerifier|batch_verifier|verify_vartime)"),
    ("field / point arithmetic", r"(helioselene|HelioseleneField|Helios|Selene|dalek_ff_group|FieldElement|curve25519|crypto_bigint|montgomery|mul_wide|square|invert|sqrt|point::|Point|EdwardsPoint|fe_|ge_|sc_|ProjectivePoint|ff::|subtle::)"),
    ("divisors (ec-divisors, interpolation)", r"(ec_divisors|Interpolator|interpolat|Poly)"),
    ("RandomX / hashing", r"(randomx|RandomX|blake2|keccak|cn_slow_hash|cn_fast_hash|hash_extra)"),
    ("LMDB", r"(mdb_|lmdb|LMDB)"),
    ("zeroize", r"(zeroize|Zeroize)"),
    ("kernel / other", r".*"),
]

rows = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"\s*([0-9.]+)%\s+\[(.)\]\s+(.*)$", line)
    if m:
        rows.append((float(m.group(1)), m.group(2), m.group(3).strip()))

total = sum(r[0] for r in rows)
cat = collections.Counter()
examples = collections.defaultdict(list)
for pct, kind, sym in rows:
    name = sym if kind != "k" else "[kernel] " + sym
    for c, rx in CATS:
        if re.search(rx, name):
            cat[c] += pct
            if len(examples[c]) < 4:
                examples[c].append((pct, sym[:90]))
            break

print("perf self-time by category (sum of symbols >= 0.05%%; total listed = %.1f%%)" % total)
for c, _ in CATS:
    if cat[c] > 0:
        print("%6.1f%%  %s" % (cat[c], c))
        for pct, sym in examples[c]:
            print("           %5.2f%%  %s" % (pct, sym))
print("\ntop 25 symbols:")
for pct, kind, sym in sorted(rows, reverse=True)[:25]:
    print("%6.2f%% [%s] %s" % (pct, kind, sym[:110]))
