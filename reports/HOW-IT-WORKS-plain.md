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

**1b. The same idea with a much smaller change to the checker.** The first version of part 1 rewrote the checker itself so that it keeps running totals as the recipe is replayed. That touches about 1,000 lines, nearly 600 of them inside the one piece of code that cryptographers have audited, which is the hardest kind of change to get accepted.

A second version (E017, "v2") gets the same memory saving without touching the checker at all. It uses one more fact about the checker: at its final step it never looks at the lines one by one. It multiplies line 1 by a secret number, line 2 by that number squared, line 3 by its cube, and so on, and adds everything up. It also never checks how many lines it was given. So instead of a list of a million lines, it can be handed **one line that is already that weighted sum**, and it will do exactly the same arithmetic on it, because multiplying one pre-summed line by the secret number gives the same total.

The new code therefore reads the recipe once to learn the secret number, then reads it again while adding each line, times the right power of the number, into a single running line, and hands that one line to the original, unchanged checker. The proof has two halves, so this second read happens once per half: three reads of the recipe in all, against two in the first version. The whole change is about 500 lines, of which only 25 are in the audited checker, and those 25 only add the ability to copy its state and to look ahead at the secret number; nothing in it is modified or removed. A reviewer has four things to confirm: one line of algebra, a 40-line adding routine, that the repeated reads see the same recipe, and that the checker's sanity checks are as good on one combined line as on a million. And because the original checker still exists unchanged, the tests compare the new path against it directly.

The price is the extra read. On the biggest proofs the second version is about 1.5 times slower than the first, though still faster than the stock software; on ordinary blocks it is 12-17% slower than stock, where the first version is 5-6% slower. Memory is the same or slightly better. The report recommends the first version on the measurements, and keeps the second as the option for anyone who values a small change to audited code over speed.

**2. Fewer simultaneous checks for the big proofs.** The machine has 12 real cores that can each run two threads. For the heavy maths of a big proof, two threads on one core only slow each other down while doubling the memory. So for blocks with big proofs the node now runs 12 checks at a time instead of 24. For small proofs, where the second thread does help, it still uses all 24.

**3. Give the memory back.** After each block with big proofs, the node explicitly hands its freed memory back to the operating system instead of keeping it in reserve. That is what brings an idle node down from ~5 GB to about 1 GB.

## What it adds up to
On the heaviest blocks the node's memory peak went from about 5.6 GB to about 1.8 GB, a cut of roughly two thirds. Over an 18,000-block catch-up the peak fell by 70%, and the catch-up finished slightly faster than before. On blocks with small, ordinary transactions the saving is smaller, about 30%, because those proofs were never very large.

A second, independent measurement agrees: we limited the memory the node was allowed to use and found the smallest limit it could still sync under. Stock software needs 5.75 GB; the new build needs 1.87 GB.

## Piece by piece
The two-thirds saving is the three parts together, not the new checker alone. On the heaviest blocks, on the 24-thread machine:

| build | memory peak | time for the heavy blocks |
|---|---|---|
| stock software | 5.3-5.6 GB | reference |
| stock software told to use 12 threads (a setting, no code change) | 3.3 GB (-40%) | 11% faster |
| parts 2 and 3 only (fewer checks at once, give memory back) | 2.9 GB (-45%) | 5% faster |
| part 1 only (stop writing the list down) | 2.3 GB (-59%) | 2x faster |
| all three parts (the recommended build) | 1.6-1.8 GB (-68%) | 2x faster |

The parts overlap, which is why they do not simply add up: each one attacks the same product, how many proofs are checked at once times how much memory each check needs. Part 2 halves the first number, part 1 shrinks the second by about fifty times, and part 3 stops finished threads from hoarding. The idle-node saving, from about 5 GB to about 1 GB, comes almost entirely from part 3.

## Does it cost speed?
For the recommended build, no. The same change that stops writing the list down also removes the inefficient re-reading, so the new checker is both smaller and faster on big proofs: twice as fast on the heaviest blocks, and about 5% faster over an 18,000-block catch-up. The only cost is on blocks of ordinary small transactions, where the node is 5-6% slower than stock, mostly from handing memory back and from reading the recipe twice. That is a real cost but a small one, and the catch-up as a whole still finishes sooner.

The smaller second version of part 1 (1b above) does cost speed, but it trades speed for a smaller change, not for memory. It saves exactly as much memory, is still faster than stock on the heaviest blocks but about 1.5 times slower than the first version there, and is 12-17% slower than stock on ordinary blocks. So the choice between the two versions is speed against the size of the change to audited code; the memory saving is the same either way.

## Is it safe?
Nothing about what gets checked has changed; only how the sums are organised. We tested this several ways:
- The new code and the old code end up with exactly the same final numbers before the last step of the check, bit for bit, in the test suite. "The old code" here is a verbatim copy of the checker as it was before the change, kept for the tests, and the comparison covers honest proofs, deliberately tampered ones and randomly corrupted ones, which are rejected in the same way by both.
- The node ends every test run on the same block as the reference node.
- We fed 236 deliberately corrupted or mismatched transactions to both the old and the new software. They made identical decisions on every one, rejecting all the bad ones and accepting all the genuine ones.

What has not happened yet: a review by the cryptographers who designed FCMP++. About two thirds of the saving comes from the part-1 change to the cryptographic code, which was written and tested here, not audited. Until that review happens, this is a research result, not something to run with real funds. The other two parts are small, ordinary changes to the node and are low-risk on their own; a config setting alone (`--max-concurrency 12`) gets about 40% of the saving on the stock software.

## Caveats, briefly
- Measured on two machines (12 cores / 16 GB and 6 cores / 14 GB; the second reproduced the result) and on the stress-test network, whose blocks are a worst case. The worst case is still what a node has to be sized for, because anyone can send maximum-size transactions.
- The "give memory back" part relies on the standard Linux memory allocator (glibc); other systems were not tested.
- FCMP++ itself is still in testing and not on mainnet.
