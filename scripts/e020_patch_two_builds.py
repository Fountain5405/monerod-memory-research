#!/usr/bin/env python3
"""E020: v2 with two circuit builds. Run on hydrogen in ~/work/monero-oxide-e020 (branch e020-two-builds on b180679).
1. generalized-bulletproofs: `skip_verify_transcript` (additive) next to `peek_z`, plus a check in the fuzz test.
2. fcmps: peek z2 on a clone after the discard build, one Fold rebuild with both z's, a transcript check after c1."""
import pathlib, re

# ---- 1. generalized-bulletproofs
p = pathlib.Path("crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs")
s = p.read_text()
anchor = "struct YzChallenges<C: Ciphersuite> {"
assert s.count(anchor) == 1 and "skip_verify_transcript" not in s
skip = '''/// Advance a transcript past the proof of a statement with `n` generators and `c` vector
/// commitments, performing exactly the reads and challenges `verify` performs, without verifying
/// anything.
///
/// `verify`'s transcript operations depend solely on `n` and `c`, never on the constraints, so a
/// caller may skip past one proof to peek at the next proof's challenges (`peek_z`) before either
/// proof's constraints exist. The skipped proof MUST still be verified on the real transcript, and
/// the caller SHOULD check the real transcript then matches the skipped one.
pub fn skip_verify_transcript<C: Ciphersuite>(
  transcript: &mut VerifierTranscript<'_>,
  n: usize,
  c: usize,
) -> Result<(), AcVerifyError>
where
  C::F: FromUniformBytes<64>,
{
  let ni = (2 * c) + 2;
  let t_poly_len = (2 * (ni + 1)) + 1;

  // AI, AO, S, then y and z
  for _ in 0 .. 3 {
    transcript.read_point::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
  }
  let _y = transcript.challenge::<C>();
  let _z = transcript.challenge::<C>();

  // T, before and after `ni`, then x
  for _ in (ni / 2) .. ni {
    transcript.read_point::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
  }
  for _ in (ni + 1) .. t_poly_len {
    transcript.read_point::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
  }
  let _x = transcript.challenge::<C>();

  // tau_x, mu, t_caret
  for _ in 0 .. 3 {
    transcript.read_scalar::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
  }

  // The inner-product argument: its challenge, `log2(n)` rounds of L, R and a challenge, then a, b
  let _ip_x = transcript.challenge::<C>();
  let mut lr_len = 0;
  while (1 << lr_len) < n {
    lr_len += 1;
  }
  for _ in 0 .. lr_len {
    transcript.read_point::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
    transcript.read_point::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
    let _x = transcript.challenge::<C>();
  }
  for _ in 0 .. 2 {
    transcript.read_scalar::<C>().map_err(|_| AcVerifyError::IncompleteProof)?;
  }
  Ok(())
}

'''
s = s.replace(anchor, skip + anchor, 1)
p.write_text(s)
print("gbp: skip_verify_transcript added")

t = pathlib.Path("crypto/generalized-bulletproofs/tests/arithmetic_circuit_proof.rs")
s = t.read_text()
old_imp = "  arithmetic_circuit_proof::{\n    Variable, LinComb, ArithmeticCircuitStatement, ArithmeticCircuitWitness,\n  },"
assert s.count(old_imp) == 1
s = s.replace(old_imp, "  arithmetic_circuit_proof::{\n    Variable, LinComb, ArithmeticCircuitStatement, ArithmeticCircuitWitness,\n    skip_verify_transcript,\n  },")
old = """    let mut transcript = VerifierTranscript::new([0; 32], &proof);
    let verifier_commmitments = transcript.read_commitments(C.len(), V.len());
    assert_eq!(commitments, verifier_commmitments.unwrap());
    statement.verify(&mut OsRng, &mut verifier, &mut transcript).unwrap();
    assert!(generators.verify(verifier));
  }
}"""
assert s.count(old) == 1
new = """    let mut transcript = VerifierTranscript::new([0; 32], &proof);
    let verifier_commmitments = transcript.read_commitments(C.len(), V.len());
    assert_eq!(commitments, verifier_commmitments.unwrap());
    // `skip_verify_transcript` must leave a transcript exactly where `verify` leaves it
    let mut skipped = transcript.clone();
    skip_verify_transcript::<Ristretto>(&mut skipped, 16, C.len()).unwrap();
    statement.verify(&mut OsRng, &mut verifier, &mut transcript).unwrap();
    assert_eq!(skipped.clone().challenge_bytes(), transcript.clone().challenge_bytes());
    assert_eq!(skipped.complete(), transcript.complete());
    assert!(generators.verify(verifier));
  }
}"""
s = s.replace(old, new, 1)
t.write_text(s)
print("gbp: fuzz test checks the skip")

# ---- 2. fcmps
p = pathlib.Path("crypto/fcmps/src/lib.rs")
s = p.read_text()
old_imp = "  arithmetic_circuit_proof::{AcStatementError, AcProveError, AcVerifyError, peek_z},"
assert s.count(old_imp) == 1
s = s.replace(old_imp, "  arithmetic_circuit_proof::{\n    AcStatementError, AcProveError, AcVerifyError, peek_z, skip_verify_transcript,\n  },")

# the explanatory comment
m = re.search(r"    /\*\n      Each statement only uses its circuit's constraints folded.*?    \*/\n", s, re.S)
assert m
comment = """    /*
      Each statement only uses its circuit's constraints folded with the proof's `z` challenge,
      which is sampled after the challenges the circuits' construction samples. Rather than store
      the constraints until `z` is known (hundreds of MB for the largest proofs), the circuits are
      built twice from the same transcript state:

      1) discarding the constraints, which advances the transcript exactly as storing them would;
      2) folding each circuit's constraints with its `z`. The first proof's `z` is peeked from the
         transcript directly. The second proof's `z` is peeked after skipping past the first proof
         on a clone, which is possible as `verify`'s transcript operations depend solely on the
         statement's size, not its constraints.

      The construction is deterministic to its arguments and the transcript, so both builds yield
      the same constraints. The rebuild is checked to have performed the same multiplications,
      constraints, and transcript operations as the first build regardless, and the real
      transcript is checked to arrive where the skip did once the first proof is verified.
    */
"""
s = s[:m.start()] + comment + s[m.end():]

old_body = """    let z1 = peek_z::<C::C1>(&transcript)?;
    let (c1_circuit, _) = Self::rebuild_verifier_circuits(
      params,
      tree,
      layers,
      inputs,
      &proof_1_vcs,
      &proof_2_vcs,
      &transcript_before_circuits,
      &transcript_after_circuits,
      original,
      Some(z1),
      None,
    )?;
    let (c1_statement, _witness) = c1_circuit.statement(c1_generators, proof_1_vcs.clone())?;
    c1_statement.verify(rng, verifier_1, &mut transcript)?;

    let z2 = peek_z::<C::C2>(&transcript)?;
    let (_, c2_circuit) = Self::rebuild_verifier_circuits(
      params,
      tree,
      layers,
      inputs,
      &proof_1_vcs,
      &proof_2_vcs,
      &transcript_before_circuits,
      &transcript_after_circuits,
      original,
      None,
      Some(z2),
    )?;
    let (c2_statement, _witness) = c2_circuit.statement(c2_generators, proof_2_vcs)?;
    c2_statement.verify(rng, verifier_2, &mut transcript)?;

    Ok(())
"""
assert s.count(old_body) == 1
new_body = """    let z1 = peek_z::<C::C1>(&transcript)?;
    let mut transcript_after_c1 = transcript.clone();
    skip_verify_transcript::<C::C1>(&mut transcript_after_c1, c1_padded_pow_2, proof_1_vcs.C().len())?;
    let z2 = peek_z::<C::C2>(&transcript_after_c1)?;

    let (c1_circuit, c2_circuit) = Self::rebuild_verifier_circuits(
      params,
      tree,
      layers,
      inputs,
      &proof_1_vcs,
      &proof_2_vcs,
      &transcript_before_circuits,
      &transcript_after_circuits,
      original,
      Some(z1),
      Some(z2),
    )?;

    let (c1_statement, _witness) = c1_circuit.statement(c1_generators, proof_1_vcs)?;
    c1_statement.verify(rng, verifier_1, &mut transcript)?;
    // The second proof's `z` was peeked on a transcript skipped past the first proof. Verifying the
    // first proof must have brought the real transcript to the same state.
    if transcript.clone().challenge_bytes() != transcript_after_c1.challenge_bytes() {
      Err(FcmpError::InconsistentCircuitReplay)?;
    }

    let (c2_statement, _witness) = c2_circuit.statement(c2_generators, proof_2_vcs)?;
    c2_statement.verify(rng, verifier_2, &mut transcript)?;

    Ok(())
"""
s = s.replace(old_body, new_body, 1)
p.write_text(s)
print("fcmps: two builds")
