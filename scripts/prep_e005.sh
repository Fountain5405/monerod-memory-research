#!/bin/bash
# Prepare E005: shrink LinComb term vectors to fit when a constraint is stored (no build).
set -eu
SRC=~/.cargo/git/checkouts/monero-oxide-3366610e7b6e517d/31c26d9
OX=~/work/monero-oxide-e005
TREE=~/work/monero-fcmp-e005
GIT="git -c user.name=optimizer -c user.email=optimizer@hydrogen"

# 1) local, git-tracked copy of the pinned monero-oxide checkout
rm -rf $OX; cp -a $SRC $OX; rm -f $OX/.cargo-ok
cd $OX
if [ -d .git ]; then echo "existing checkout repo at: $(git log --oneline -1)"; git status --short | head -3; else git init -q && $GIT add -A >/dev/null && $GIT commit -q -m "monero-oxide @ 31c26d96 (cargo checkout copy)"; fi
$GIT checkout -q -B e005-lincomb-shrink
python3 - <<'EOF'
import os
ox = os.path.expanduser("~/work/monero-oxide-e005")
p = ox + "/crypto/generalized-bulletproofs/src/lincomb.rs"
s = open(p).read()
anchor = "impl<F: PrimeField> LinComb<F> {\n  /// Add a new instance of a term to this linear combination.\n"
if anchor not in s:
    # fall back: insert before `pub fn term`
    anchor = "  pub fn term(mut self, scalar: F, constrainable: Variable) -> Self {"
    assert s.count(anchor) == 1, "term anchor"
    new = """  /// Release the excess capacity of the sparse term vectors (E005 memory experiment).
  pub fn shrink_to_fit(&mut self) {
    self.WL.shrink_to_fit();
    self.WR.shrink_to_fit();
    self.WO.shrink_to_fit();
    for weights in self.WCG.values_mut() {
      weights.shrink_to_fit();
    }
    self.WV.shrink_to_fit();
  }

""" + anchor
    s = s.replace(anchor, new, 1)
open(p, "w").write(s)
p = ox + "/crypto/fcmps/circuit-abstraction/src/lib.rs"
s = open(p).read()
old = "  pub fn constrain_equal_to_zero(&mut self, lincomb: LinComb<C::F>) {\n    self.constraints.push(lincomb);\n  }"
assert s.count(old) == 1, "constrain anchor"
new = "  pub fn constrain_equal_to_zero(&mut self, mut lincomb: LinComb<C::F>) {\n    // E005: stored constraints live until verification; drop the Vec growth slack.\n    lincomb.shrink_to_fit();\n    self.constraints.push(lincomb);\n  }"
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("patched lincomb.rs and circuit-abstraction")
EOF
$GIT commit -q -am "E005: LinComb::shrink_to_fit; shrink constraints when stored" && git log --oneline -2

# 2) separate monero-fcmp copy using the patched crates
rsync -a --delete --exclude /build ~/work/monero-fcmp/ $TREE/
cd $TREE && git checkout -q -B e005-lincomb-shrink
cat >> src/fcmp_pp/fcmp_pp_rust/Cargo.toml <<EOF2

[patch."https://github.com/monero-oxide/monero-oxide"]
generalized-bulletproofs = { path = "$OX/crypto/generalized-bulletproofs" }
generalized-bulletproofs-circuit-abstraction = { path = "$OX/crypto/fcmps/circuit-abstraction" }
EOF2
source ~/.cargo/env
cd src/fcmp_pp/fcmp_pp_rust && cargo metadata --format-version 1 > /dev/null 2> /tmp/e005_meta.err || { cat /tmp/e005_meta.err; exit 1; }
cd $TREE && git diff --stat && git diff src/fcmp_pp/fcmp_pp_rust/Cargo.lock | grep -E "^[-+]" | grep -v -E "^(---|\+\+\+)" | head -20
$GIT commit -q -am "E005: build fcmp_pp_rust against local monero-oxide-e005 (LinComb shrink)" && git log --oneline -1
cd $OX && git diff HEAD~1 > ~/work/research/evidence/E005_monero-oxide.diff
echo PREP_E005_OK
