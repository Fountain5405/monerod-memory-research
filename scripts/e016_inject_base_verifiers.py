#!/usr/bin/env python3
"""E016 step 1: inject verbatim copies of the base (31c26d9) verifiers into the e007 tree as
`ArithmeticCircuitStatement::verify_base` (generalized-bulletproofs, feature "tests") and
`Fcmp::verify_base` (fcmps, cfg(test)). Run on hydrogen in ~/work/monero-oxide-e007."""
import pathlib, re, sys

BASE_ACP = pathlib.Path("/tmp/e016/base_acp.rs").read_text().splitlines(keepends=True)
BASE_FCMPS = pathlib.Path("/tmp/e016/base_fcmps.rs").read_text().splitlines(keepends=True)

# ---- generalized-bulletproofs: base verify is lines 657..820 (1-indexed) inside the impl at 646..821
fn_lines = BASE_ACP[656:820]
assert fn_lines[0].lstrip().startswith("pub fn verify<R: RngCore + CryptoRng>("), fn_lines[0]
assert fn_lines[-1] == "  }\n", repr(fn_lines[-1])
body = "".join(fn_lines).replace("pub fn verify<R: RngCore + CryptoRng>(", "pub fn verify_base<R: RngCore + CryptoRng>(", 1)
acp_block = (
    "\n"
    "#[cfg(feature = \"tests\")]\n"
    "impl<C: Ciphersuite> ArithmeticCircuitStatement<'_, C>\n"
    "where\n"
    "  C::F: FromUniformBytes<64>,\n"
    "  C::G: ConditionallySelectable,\n"
    "{\n"
    "  /// E016: the verifier of monero-oxide 31c26d9 (`ArithmeticCircuitStatement::verify` before the\n"
    "  /// streaming change), copied verbatim and renamed. Test-only; the reference the streaming\n"
    "  /// verifier is checked against.\n"
    + body +
    "}\n"
)
p = pathlib.Path("crypto/generalized-bulletproofs/src/arithmetic_circuit_proof.rs")
s = p.read_text()
assert "fn verify_base" not in s
marker = "#[cfg(test)]\nmod tests;"
if marker in s:
    s = s.replace(marker, acp_block + "\n" + marker, 1)
else:
    s = s.rstrip("\n") + "\n" + acp_block
p.write_text(s)
print("acp: injected", len(fn_lines), "lines")

# ---- fcmps: base Fcmp::verify is lines 762..1003 inside impl ending at 1004
fn_lines = BASE_FCMPS[761:1003]
assert fn_lines[0].lstrip().startswith("pub fn verify<R: RngCore + CryptoRng>("), fn_lines[0]
assert fn_lines[-1] == "  }\n", repr(fn_lines[-1])
body = "".join(fn_lines).replace("pub fn verify<R: RngCore + CryptoRng>(", "pub(crate) fn verify_base<R: RngCore + CryptoRng>(", 1)
n_stmt = len(re.findall(r"_statement\.verify\(", body))
body = re.sub(r"_statement\.verify\(", "_statement.verify_base(", body)
fcmps_block = (
    "\n"
    "  /// E016: `Fcmp::verify` of monero-oxide 31c26d9 (before the streaming change), copied verbatim,\n"
    "  /// renamed, and calling the equally verbatim `ArithmeticCircuitStatement::verify_base`. Test-only;\n"
    "  /// the reference the streaming verifier is checked against.\n"
    "  #[cfg(test)]\n"
    "  #[allow(clippy::too_many_arguments)]\n"
    + body
)
p = pathlib.Path("crypto/fcmps/src/lib.rs")
s = p.read_text()
assert "fn verify_base" not in s
marker = "  /// Read an FCMP.\n"
assert s.count(marker) == 1
s = s.replace(marker, fcmps_block + "\n" + marker, 1)
p.write_text(s)
print("fcmps: injected", len(fn_lines), "lines;", n_stmt, "statement.verify calls redirected")
