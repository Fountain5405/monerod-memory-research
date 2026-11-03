#!/usr/bin/env python3
"""E016 step 2: tests comparing the streaming verifier with the verbatim base verifier.
Refactors the tampering-region computation of the existing tampered-proof test into a helper
(pure motion) and appends the base-equivalence tests. Run on hydrogen in ~/work/monero-oxide-e007."""
import pathlib

p = pathlib.Path("crypto/fcmps/src/tests.rs")
s = p.read_text()

# ---- 1. move the region computation out of test_streaming_verify_rejects_tampered_proofs
start_marker = "    // Find the commitments' quantities\n"
end_marker = "    regions.push((\"root blind PoK\", offset + 32, pok_scalar));\n"
assert s.count(start_marker) == 1 and s.count(end_marker) == 1
i, j = s.index(start_marker), s.index(end_marker) + len(end_marker)
region_code = s[i:j]
# the enum is defined inside the old block; hoist it
enum_src = """    #[derive(Clone, Copy, Debug)]
    enum Element {
      C1Point,
      C1Scalar,
      C2Point,
      C2Scalar,
    }

"""
assert enum_src in region_code
region_code = region_code.replace(enum_src, "")
# the old block ends by sanity-checking against `buf.len()`; the helper takes the length
assert "assert_eq!(offset + 64, buf.len());" in region_code
region_code = region_code.replace("assert_eq!(offset + 64, buf.len());", "assert_eq!(offset + 64, proof_len);")
# de-indent by 2 (from test body to fn body)
region_code = "".join((l[2:] if l.startswith("  ") else l) for l in region_code.splitlines(keepends=True))
helper = (
    "/// An element of a serialized FCMP, for tampering tests.\n"
    "#[derive(Clone, Copy, Debug)]\n"
    "enum Element {\n  C1Point,\n  C1Scalar,\n  C2Point,\n  C2Scalar,\n}\n\n"
    "/// The offsets of a variety of elements within a serialized proof of `proof_len` bytes, with a\n"
    "/// name for the region and the kind of element found there.\n"
    "fn tampering_regions(\n"
    "  proof_len: usize,\n"
    "  root: TreeRoot<Selene, Helios>,\n"
    "  layers: usize,\n"
    "  paths: usize,\n"
    ") -> Vec<(&'static str, usize, Element)> {\n"
    + region_code +
    "  regions\n}\n\n"
)
s = s[:i] + "    let regions = tampering_regions(buf.len(), root, layers, paths);\n" + s[j:]
test_marker = "#[test]\nfn test_streaming_verify_rejects_tampered_proofs() {"
assert s.count(test_marker) == 1
s = s.replace(test_marker, helper + test_marker, 1)

# ---- 2. the base-equivalence tests
s = s.rstrip("\n") + "\n" + r'''
// ---- E016: equivalence with the verifier of monero-oxide 31c26d9 ----
//
// `Fcmp::verify_base` and `ArithmeticCircuitStatement::verify_base` are verbatim copies of the
// verifiers before the streaming change. These tests check the streaming verifier against them,
// not against the refactored stored path (`Fcmp::verify_stored`), which shares code with it.

/// `additional` as a multiset, so the comparison doesn't depend on the order terms were pushed in.
fn additional_multiset<C: Ciphersuite>(
  verifier: &generalized_bulletproofs::BatchVerifier<C>,
) -> Vec<(Vec<u8>, Vec<u8>)> {
  let mut res = verifier
    .additional
    .iter()
    .map(|(scalar, point)| (scalar.to_repr().as_ref().to_vec(), point.to_bytes().as_ref().to_vec()))
    .collect::<Vec<_>>();
  res.sort();
  res
}

/// Assert two batch verifiers are equal, with `additional` compared as a multiset.
fn assert_verifiers_eq_multiset<C: Ciphersuite>(
  a: &generalized_bulletproofs::BatchVerifier<C>,
  b: &generalized_bulletproofs::BatchVerifier<C>,
) {
  assert_eq!(a.g, b.g);
  assert_eq!(a.h, b.h);
  assert_eq!(a.g_bold, b.g_bold);
  assert_eq!(a.h_bold, b.h_bold);
  assert_eq!(a.h_sum, b.h_sum);
  assert_eq!(a.additional.len(), b.additional.len());
  assert_eq!(additional_multiset(a), additional_multiset(b));
}

/// Verify a proof with the streaming verifier (`Fcmp::verify`) and the base verifier
/// (`Fcmp::verify_base`), using the same randomness.
fn verify_streaming_and_base(
  proof: &Fcmp<MoneroCurves>,
  params: &FcmpParams<MoneroCurves>,
  root: TreeRoot<Selene, Helios>,
  layers: usize,
  inputs: &[Input<<Selene as Ciphersuite>::F>],
) -> (VerificationResult, VerificationResult) {
  let rng = DeterministicRng::new();

  let mut streaming_1 = generalized_bulletproofs::Generators::batch_verifier();
  let mut streaming_2 = generalized_bulletproofs::Generators::batch_verifier();
  let streaming = proof.verify(
    &mut rng.clone(),
    &mut streaming_1,
    &mut streaming_2,
    params,
    root,
    layers,
    inputs,
  );

  let mut base_1 = generalized_bulletproofs::Generators::batch_verifier();
  let mut base_2 = generalized_bulletproofs::Generators::batch_verifier();
  let base =
    proof.verify_base(&mut rng.clone(), &mut base_1, &mut base_2, params, root, layers, inputs);

  ((streaming, streaming_1, streaming_2), (base, base_1, base_2))
}

#[test]
fn test_streaming_verify_matches_base() {
  let (G, T, U, V, params) = random_params(4);

  // Both C1 and C2 roots, with and without branches on either curve
  for (paths, layers) in [(1, 1), (1, 2), (1, 3), (1, 5), (2, 1), (2, 4), (3, 2), (3, 3)] {
    println!("Comparing the streaming and base verifiers for {paths} inputs and {layers} layers");
    let (proof, root, inputs) = random_proof(&params, (G, T, U, V), paths, layers);

    let ((streaming, streaming_1, streaming_2), (base, base_1, base_2)) =
      verify_streaming_and_base(&proof, &params, root, layers, &inputs);
    streaming.unwrap();
    base.unwrap();
    assert_verifiers_eq_multiset(&streaming_1, &base_1);
    assert_verifiers_eq_multiset(&streaming_2, &base_2);
    assert!(batch_verifies(&params, &streaming_1, &streaming_2));
    assert!(batch_verifies(&params, &base_1, &base_2));
  }
}

#[test]
fn test_streaming_verify_matches_base_on_tampered_proofs() {
  let (G, T, U, V, params) = random_params(2);

  // A C1 root (with branches on both curves) and a C2 root
  for (paths, layers) in [(2, 3), (1, 2)] {
    let (proof, root, inputs) = random_proof(&params, (G, T, U, V), paths, layers);
    let mut buf = vec![];
    proof.write(&mut buf).unwrap();

    for (name, offset, element) in tampering_regions(buf.len(), root, layers, paths) {
      // Replace the element with another valid element, and flip a bit within it
      let replacement = match element {
        Element::C1Point => <Selene as Ciphersuite>::G::random(&mut OsRng).to_bytes(),
        Element::C1Scalar => <Selene as Ciphersuite>::F::random(&mut OsRng).to_repr(),
        Element::C2Point => <Helios as Ciphersuite>::G::random(&mut OsRng).to_bytes(),
        Element::C2Scalar => <Helios as Ciphersuite>::F::random(&mut OsRng).to_repr(),
      };
      let mut replaced = buf.clone();
      replaced[offset .. (offset + 32)].copy_from_slice(&replacement);
      let mut flipped = buf.clone();
      flipped[offset + 1] ^= 1;

      for tampered in [replaced, flipped] {
        assert_ne!(tampered, buf);
        let tampered = Fcmp::<MoneroCurves>::read(&mut tampered.as_slice(), paths, layers).unwrap();
        let ((streaming, streaming_1, streaming_2), (base, base_1, base_2)) =
          verify_streaming_and_base(&tampered, &params, root, layers, &inputs);
        // The same proofs are well-formed, with the same error otherwise
        assert_eq!(streaming.is_ok(), base.is_ok(), "{name} {element:?}");
        assert_eq!(format!("{streaming:?}"), format!("{base:?}"), "{name} {element:?}");
        if streaming.is_ok() {
          assert_verifiers_eq_multiset(&streaming_1, &base_1);
          assert_verifiers_eq_multiset(&streaming_2, &base_2);
          assert!(!batch_verifies(&params, &streaming_1, &streaming_2), "{name} {element:?}");
          assert!(!batch_verifies(&params, &base_1, &base_2), "{name} {element:?}");
        }
      }
    }
  }
}

#[test]
fn test_streaming_verify_matches_base_under_random_mutation() {
  let (G, T, U, V, params) = random_params(2);

  // Random single-byte mutations anywhere in the serialized proof, including the root blind PoK
  for (paths, layers) in [(2, 3), (1, 2)] {
    let (proof, root, inputs) = random_proof(&params, (G, T, U, V), paths, layers);
    let mut buf = vec![];
    proof.write(&mut buf).unwrap();

    let mut well_formed = 0;
    for i in 0 .. 128 {
      let mut mutated = buf.clone();
      let offset = usize::try_from(OsRng.next_u64() % u64::try_from(buf.len()).unwrap()).unwrap();
      let mut mask = 0;
      while mask == 0 {
        mask = u8::try_from(OsRng.next_u64() & 0xff).unwrap();
      }
      mutated[offset] ^= mask;
      assert_ne!(mutated, buf);

      let mutated = Fcmp::<MoneroCurves>::read(&mut mutated.as_slice(), paths, layers).unwrap();
      let ((streaming, streaming_1, streaming_2), (base, base_1, base_2)) =
        verify_streaming_and_base(&mutated, &params, root, layers, &inputs);
      assert_eq!(streaming.is_ok(), base.is_ok(), "mutation {i} at byte {offset}");
      assert_eq!(format!("{streaming:?}"), format!("{base:?}"), "mutation {i} at byte {offset}");
      if streaming.is_ok() {
        well_formed += 1;
        assert_verifiers_eq_multiset(&streaming_1, &base_1);
        assert_verifiers_eq_multiset(&streaming_2, &base_2);
        assert!(!batch_verifies(&params, &streaming_1, &streaming_2), "mutation {i} at byte {offset}");
        assert!(!batch_verifies(&params, &base_1, &base_2), "mutation {i} at byte {offset}");
      }
    }
    println!("{paths} inputs, {layers} layers: 128 mutations, {well_formed} still well-formed");
  }
}
'''
p.write_text(s)
print("tests written")
