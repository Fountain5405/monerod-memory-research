#!/usr/bin/env python3
"""E029: verify proofs with few inputs on the stored-circuit path, not the streaming one. Run from the root of the monero-oxide-e029 tree. Anchors asserted.
The dispatch is compiled out under cfg(test), so the crate's existing tests keep exercising streaming and comparing it with verify_stored and verify_base. The dispatch itself is exercised at the node, by negdiff and the window hashes."""
import pathlib
p = pathlib.Path("crypto/fcmps/src/lib.rs"); s = p.read_text()
a = """  ) -> Result<(), FcmpError> {
    let (layout, mut transcript, proof_1_vcs, proof_2_vcs) =
      self.verify_prelude(rng, verifier_1, verifier_2, params, tree, layers, inputs)?;

    let c1_generators = params
"""
b = """  ) -> Result<(), FcmpError> {
    // E029: streaming builds every circuit twice to avoid storing it. For proofs with few inputs the
    // stored circuit is small, so keep it and skip the second build.
    #[cfg(not(test))]
    {
      const STREAM_MIN_INPUTS: usize = 8;
      if inputs.len() < STREAM_MIN_INPUTS {
        return self.verify_stored(rng, verifier_1, verifier_2, params, tree, layers, inputs);
      }
    }

    let (layout, mut transcript, proof_1_vcs, proof_2_vcs) =
      self.verify_prelude(rng, verifier_1, verifier_2, params, tree, layers, inputs)?;

    let c1_generators = params
"""
assert s.count(a) == 1; s = s.replace(a, b)
a = "  #[cfg(test)]\n  #[allow(clippy::too_many_arguments)]\n  pub(crate) fn verify_stored<"
b = "  #[allow(clippy::too_many_arguments)]\n  pub(crate) fn verify_stored<"
assert s.count(a) == 1; s = s.replace(a, b)
p.write_text(s)
print("E029 patched")
