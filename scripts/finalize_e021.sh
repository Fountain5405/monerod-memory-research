#!/bin/bash
# E021 finalize: commit the idle tree, format-patch into v1 (0006) and v2 (0007), copy evidence, install README, record, commit.
set -e
R=~/work/research; A=~/work/research-artifacts; T=~/work/monero-fcmp-idle
tail -1 $A/e021.chain | grep -q CHAIN_E021_COMPLETE || { echo "chain not complete"; exit 1; }
cd $T
git add src/ringct/rctSigs.cpp src/ringct/rctSigs.h src/cryptonote_core/cryptonote_core.cpp src/cryptonote_core/cryptonote_core.h
git commit -q -F - <<'EOF_MSG'
E021: trim FCMP++ verifier memory once verification goes idle

E012 trims after heavy batch-verify calls and at most every 10 s on light
calls, but only inside a verify call. After the last call of a sync burst
nothing trims, so whatever the last light calls freed stays resident in the
glibc arenas until the next verification: the adaptive build idled ~0.2 GB
above the per-call build (E012: 1,333 vs 1,107 MB post-idle).

Record the time of the last batch verification and of the last trim in two
atomics, and have core::on_idle (every 2 s) call rct::idleTrimFcmpPp(5000):
one malloc_trim(0) once no batch verification has run for 5 s and the last
one was not already followed by a trim. The verify path stores its timestamp
before deciding its own trim, so the idle trim never repeats one.

Measured (E021, 3 alternating A/B rounds vs the E012 build, hydrogen):
heavy window post-idle RssAnon 1,349 -> 1,087 MB (-19%), peak / wall / CPU
unchanged; small-tx window wall unchanged; exactly one trim per run, 5-6 s
after the last verification; all window hashes match. glibc only.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF_MSG
git log --oneline -2
git format-patch -1 --start-number 6 -o $R/patches/v1-E007-full-streaming/monerod/
P1=$(ls $R/patches/v1-E007-full-streaming/monerod/0006-E021-*.patch)
cp "$P1" "$R/patches/v2-E017-minimal/monerod/$(basename "$P1" | sed 's/^0006-/0007-/')"
ls $R/patches/v1-E007-full-streaming/monerod/ $R/patches/v2-E017-minimal/monerod/
# evidence
E=$R/evidence/E021; mkdir -p $E/heavy $E/small
cp $A/e021.chain $A/e021.build.log $E/
for w in heavy small; do cp $A/e021_$w/results.csv $A/e021_$w/summary.txt $A/e021_$w/check.log $A/e021_$w/*.mem.csv $E/$w/; done
grep -H "returned freed verifier memory" $A/e021_heavy/r*_idle.log $A/e021_small/r*_idle.log | sed "s#$A/##" > $E/trim_lines.txt
grep -c "returned freed verifier memory" $A/e021_heavy/r*_adapt.log $A/e021_small/r*_adapt.log | sed "s#$A/##" >> $E/trim_lines.txt || true
du -sh $E
# README + records
mkdir -p $R/experiments/E021-idle-trim
cp /tmp/E021-README.md $R/experiments/E021-idle-trim/README.md
cp /tmp/record_e021.py /tmp/finalize_e021.sh $R/scripts/
python3 /tmp/record_e021.py
grep -n "SMALL_" $R/experiments/E021-idle-trim/README.md && { echo "placeholders left"; exit 1; }
cd $R && git add -A && git commit -q -m "E021 done: idle trim for adapt, post-idle -19%, adopted as monerod patch 0006 (v1) / 0007 (v2); F37

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" && git log --oneline -1
git log -p -1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | sort | uniq -c
echo FINALIZE_OK
