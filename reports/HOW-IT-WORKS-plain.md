# How the memory reduction works (plain language)

Technical version: reports/HOW-IT-WORKS.md.

## The problem
A Monero node checks every transaction's proof before accepting a block. With FCMP++, each transaction has one big proof covering all of its inputs, and checking a proof means re-deriving a very long list of equations, millions of lines for the largest transactions, and confirming they all balance.

The current software does this the obvious way: it writes the entire list down in memory first, then goes through it to do the sums. One large proof's list takes about 250 MB. A 24-thread machine checks 24 proofs at once, so it needs 24 copies: around 5.5 GB.

Two things made it worse:
- Once a thread finished, the memory it had used was not given back to the operating system. Each thread kept its own pile. An idle node still sat at almost 5 GB long after the work was done.
- The sums were done inefficiently: for each of many "columns" the code re-read the whole list from the top. On the largest proofs that re-reading was half of all the work the node did.

## The fix, in three parts

**1. Stop writing the list down.** The key insight is that the checker never needs the individual lines, only their running totals. And the list is produced by a fixed recipe, so it can be regenerated at any time. The new code therefore reads through the recipe twice. The first time it writes nothing down; it only needs to reach the point where a certain secret multiplier becomes known. The second time it keeps running totals as each line is produced and throws the line away. The totals are a few thousand numbers instead of millions of lines.

Think of checking a very long receipt. Old way: photocopy every page, spread them over the desk, then go through all the pages once per column of the receipt. New way: read the receipt once to learn the rule, read it again keeping a running total, never make a copy.

As a safety measure, the two reads must agree exactly: the same number of lines, the same number of steps, the same checksum. If they do not, the proof is rejected. This part also removed the inefficient re-reading, so large proofs now check about twice as fast.

**2. Fewer simultaneous checks for the big proofs.** The machine has 12 real cores that can each run two threads. For the heavy maths of a big proof, two threads on one core only slow each other down while doubling the memory. So for blocks with big proofs the node now runs 12 checks at a time instead of 24. For small proofs, where the second thread does help, it still uses all 24.

**3. Give the memory back.** After each block with big proofs, the node explicitly hands its freed memory back to the operating system instead of keeping it in reserve. That is what brings an idle node down from ~5 GB to about 1 GB.

## What it adds up to
On the heaviest blocks the node's memory peak went from about 5.6 GB to about 1.8 GB, a cut of roughly two thirds. Over an 18,000-block catch-up the peak fell by 70%, and the catch-up finished slightly faster than before. On blocks with small, ordinary transactions the saving is smaller, about 30%, because those proofs were never very large.

A second, independent measurement agrees: we limited the memory the node was allowed to use and found the smallest limit it could still sync under. Stock software needs 5.75 GB; the new build needs 1.87 GB.

## Is it safe?
Nothing about what gets checked has changed; only how the sums are organised. We tested this several ways:
- The new code and the old code end up with exactly the same final numbers before the last step of the check, bit for bit, in the test suite.
- The node ends every test run on the same block as the reference node.
- We fed 236 deliberately corrupted or mismatched transactions to both the old and the new software. They made identical decisions on every one, rejecting all the bad ones and accepting all the genuine ones.

What has not happened yet: a review by the cryptographers who designed FCMP++. About two thirds of the saving comes from the part-1 change to the cryptographic code, which was written and tested here, not audited. Until that review happens, this is a research result, not something to run with real funds. The other two parts are small, ordinary changes to the node and are low-risk on their own; a config setting alone (`--max-concurrency 12`) gets about 40% of the saving on the stock software.

## Caveats, briefly
- Measured on one machine (12 cores, 16 GB) and on the stress-test network, whose blocks are a worst case. The worst case is still what a node has to be sized for, because anyone can send maximum-size transactions.
- The "give memory back" part relies on the standard Linux memory allocator (glibc); other systems were not tested.
- FCMP++ itself is still in testing and not on mainnet.
