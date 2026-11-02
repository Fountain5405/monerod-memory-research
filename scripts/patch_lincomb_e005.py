#!/usr/bin/env python3
"""Insert LinComb::shrink_to_fit INSIDE the `impl` block that defines `term` (E005).
Operates on the pristine file from git (`git show HEAD~1:...`) to undo any earlier misplaced insert."""
import os
import subprocess

ox = os.path.expanduser("~/work/monero-oxide-e005")
rel = "crypto/generalized-bulletproofs/src/lincomb.rs"
s = subprocess.run(["git", "-C", ox, "show", "HEAD~1:" + rel], capture_output=True, text=True, check=True).stdout
anchor = "impl<F: PrimeField> LinComb<F> {\n  /// Add a new instance of a term to this linear combination.\n"
assert s.count(anchor) == 1, "impl/term anchor not unique"
head = "impl<F: PrimeField> LinComb<F> {\n"
method = """  /// Release the excess capacity of the sparse term vectors (E005 memory experiment).
  pub fn shrink_to_fit(&mut self) {
    self.WL.shrink_to_fit();
    self.WR.shrink_to_fit();
    self.WO.shrink_to_fit();
    for weights in self.WCG.values_mut() {
      weights.shrink_to_fit();
    }
    self.WV.shrink_to_fit();
  }

"""
s = s.replace(anchor, head + method + anchor[len(head):], 1)
open(os.path.join(ox, rel), "w").write(s)
print("inserted shrink_to_fit inside impl block")
