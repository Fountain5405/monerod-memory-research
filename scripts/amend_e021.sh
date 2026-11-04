#!/bin/bash
set -e
R=~/work/research; T=~/work/monero-fcmp-idle
V1=$R/patches/v1-E007-full-streaming/monerod; V2=$R/patches/v2-E017-minimal/monerod
OLD=$(ls $V1/0006-E021-*.patch); before=$(git -C $T diff HEAD~1 HEAD | sha256sum)
git -C $T commit -q --amend -F - <<'EOF_MSG'
E021: trim FCMP++ verifier memory once verification goes idle

E012 trims after heavy batch-verify calls and at most every 10 s on light
calls, but only inside a verify call. After the last call of a sync burst
nothing trims, so whatever the last light calls freed stays resident in the
glibc arenas until the next verification.

Record the time of the last batch verification and of the last trim in two
atomics, and have core::on_idle (every 2 s) call rct::idleTrimFcmpPp(5000):
one malloc_trim(0) once no batch verification has run for 5 s and the last
one was not already followed by a trim. The verify path stores its timestamp
before deciding its own trim, so the idle trim never repeats one.

Measured (E021, 3 alternating A/B rounds vs the E012 build, hydrogen): each
trim releases 231-234 MB on the heavy window (about -17% of that run's anon)
and 37-43 MB on the small-tx window, while the E012 build moves 0-4 MB over
the same idle period. No measurable change in peak, wall or CPU; one trim per
run; all window hashes match. glibc only. Not measured at the chain tip, where
only the block path reaches this verifier, so it should fire at most once per
block; the INFO log line should be demoted before upstream use.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF_MSG
after=$(git -C $T diff HEAD~1 HEAD | sha256sum); [ "$before" = "$after" ] || { echo "CODE DIFF CHANGED"; exit 1; }
rm "$OLD" $V2/0007-E021-*.patch
git -C $T format-patch -1 --start-number 6 -o $V1/ > /dev/null
P=$(ls $V1/0006-E021-*.patch); cp "$P" "$V2/$(basename "$P" | sed 's/^0006-/0007-/')"
sed -i 's/^Subject: \[PATCH 6\/6\]/Subject: [PATCH]/' "$V2/$(basename "$P" | sed 's/^0006-/0007-/')" || true
git -C ~/work/monero-fcmp-e020 apply --check $V2/0007-E021-*.patch && echo V2_CHECK_OK
git -C $T log --oneline -1
cd $R; grep -c "0006-E021-trim-FCMP-verifier-memory-once-verification-go" patches/README.md; ls patches/v1-E007-full-streaming/monerod | grep E021
sed -i 's/0006-E021-trim-FCMP-verifier-memory-once-verification-go\.patch/'"$(basename "$P")"'/' patches/README.md
cp /tmp/amend_e021.sh scripts/amend_e021.sh
git add -A
git commit -q -F - <<'EOF_MSG2'
E021: correct the write-up after an audit against the evidence

94f570b had a wrong sampler table (kB/1000, wrong interval), headlined -19%
without saying the post-idle ranges overlap, attributed the remaining idle
memory with no measurement, and did not label the v2 and stock comparisons as
unmeasured or cross-experiment. The direct measure is the release across each
trim (scripts/e021_paired.py): 231-234 MB heavy, 37-43 MB small-tx, adapt 0-4.
Headline is now about -17%. Decision unchanged; validation gap stated. Patch
commit message corrected, code diff identical. Also adds the E022a scan scripts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF_MSG2
git log --oneline -1
git log -p -1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | sort | uniq -c
git status --short | wc -l
