# Security Audit: pqcrypto ML-KEM-768

**Original verdict (May 22): 2 critical bugs, 2 high severity issues, and incomplete tests. The library produced keys and ciphertexts incompatible with every other FIPS 203-compliant implementation.**

**Status (May 25): Four FIPS 203 conformance bugs have been fixed in a local fork at `~/GitHub/pqcrypto`. Demo 3 now passes all four cross-implementation tests against OpenSSL 3.6 — shared secrets match byte-for-byte in both directions.** The remaining high-severity issue (#4, timing side-channel in implicit rejection) and the medium-severity test-coverage gap (#5) are *not* fixed yet — they do not affect interop, only IND-CCA2 hardness and audit confidence.

The four applied fixes live as uncommitted edits and one upstream commit (`c076f55`) in the fork. See `~/GitHub/pqcrypto/CHANGES.md` for the canonical change description; the rest of this document is the per-bug audit record.

---

## CRITICAL #1 — Wrong Key Generation Input (`kem.dart:83`) — **FIXED**

FIPS 203 Algorithm 13 requires `G(d || k)` where `k` is the parameter-set rank byte (`0x02`/`0x03`/`0x04` for ML-KEM-512/768/1024). The code called `G(d)` with only 32 bytes, omitting the domain separator. Every keypair generated was non-interoperable with OpenSSL, liboqs, or any other standard ML-KEM implementation — and worse, all three parameter sets shared a keygen stream because there was no domain separation between them.

**Fix applied:**

```dart
- final rhoSigma = _G(d);
+ final rhoSigma = _G(Uint8List.fromList([...d, params.k]));   // FIPS 203 §5.1
```

---

## CRITICAL #2 — Compress Uses Clamp Instead of Modular Reduction (`pack.dart:26`) — **FIXED**

FIPS 203 Definition 4.7 requires `Compress_d(x) = ⌈(2^d / q) · x⌉ mod 2^d`. The code saturated (clamped) instead of wrapping:

```dart
- return result > maxVal ? maxVal : result;
+ return result & maxVal;                       // mod 2^d, not clamp
```

For `compress_4` (used for `v` in ML-KEM-768), the clamp corrupted approximately 3.12% of coefficients — meaning virtually every ciphertext (≈99.97%) contained at least one wrong coefficient. The library *appeared* to work for self-generated roundtrips only because both encapsulation and decapsulation used the same bug. Against any standard-compliant peer, decapsulation always returned the wrong key silently. The bitmask form is exactly `mod 2^d` for non-negative integers and wraps `2^d → 0` per spec.

---

## HIGH #3 — Barrett Reduction Returns Out-of-Range Values (`poly.dart:20–26`) — **FIXED**

`barrettReduce()` (using `v = ⌊2^26 / q⌋ = 20159`, shift = 26) did not guarantee output in `[0, q-1]`. For ~0.54% of valid input pairs it returned negative or `≥ q` values, which propagated through NTT butterfly operations and corrupted polynomial arithmetic.

**Fix applied** (committed as `c076f55` in the fork):

```dart
  int res = a - product * q;
+ if (res < 0) res += q;
+ if (res >= q) res -= q;
  return res;
```

The pre-correction error is bounded by ±q, so a single add or single subtract is sufficient — no loop, constant-time-friendly.

---

## CRITICAL — XOF Index Ordering in `_genMatrixPoly` (`indcpa.dart:195–198`) — **FIXED**

*This bug was not in the original May 22 audit; it was discovered during the demo 3 interop investigation on May 23 and is the final piece that made interop work.*

FIPS 203 Algorithm 13 specifies `A[i][j] = SampleNTT(XOF(ρ, j, i))` — column index byte first, row index byte second. The callers at `indcpa.dart:47` and `indcpa.dart:256` already passed arguments as `_genMatrixPoly(rho, j, i)` to build `A[i][j]`, so inside the function the formal parameter named `i` is the outer column (`j`) and formal `j` is the outer row (`i`). The XOF input was written `rho || formal_j || formal_i` = `rho || row || col` — exactly transposed from spec.

The result: every non-diagonal entry of matrix `A` was derived from a different XOF stream than any spec-compliant implementation. The library remained internally consistent (keygen and encapsulation both used the same wrong order) but was completely incompatible with OpenSSL/liboqs.

**Fix applied:**

```dart
- input[32] = j;   // formal j = outer row
- input[33] = i;   // formal i = outer col
+ input[32] = i;   // formal i = outer col (XOF input: col first per FIPS 203)
+ input[33] = j;   // formal j = outer row
```

A comment now documents the caller convention so this naming subtlety doesn't get re-broken.

---

## HIGH #4 — Timing Side-Channel in Implicit Rejection (`kem.dart:140–144`) — **NOT FIXED**

The comparison between `ct` and re-encrypted `cPrime` uses a correct XOR accumulator (`_constantTimeEq`), but the result is used in a plain `if/else` branch. A JIT compiler will produce measurable timing differences between the two paths, leaking whether the ciphertext was valid — breaking IND-CCA2.

**Recommended fix:** Compute both `K'` and `K_bar` unconditionally, then select with bitwise masking over both candidate keys.

*Does not affect interop. Affects IND-CCA2 hardness in adversarial timing environments only.*

---

## MEDIUM #5 — KAT Tests Never Verify Key Generation — **NOT FIXED**

The test suite skips `KeyGen` verification entirely (the `if (seed.length == 48)` branch does nothing because it lacks the required NIST AES-256-CTR DRBG). This is why Critical Bug #1 was never caught upstream — all 3000 claimed passing tests only exercise the decapsulation path.

A complete KAT harness covering KeyGen + Encaps would have caught bugs #1, #2, and the XOF ordering issue immediately.

---

## What Is Correct

- ML-KEM-768 parameters (`k=3, η₁=2, η₂=2, du=10, dv=4`) — correct
- Hash/XOF assignments (`G=SHA3-512, H=SHA3-256, J=SHAKE-256, XOF=SHAKE-128`) — correct
- Secret key structure (`dk_PKE ‖ ek_PKE ‖ H(ek) ‖ z`) — all four FIPS 203 components present
- NTT zeta table — spot-checked correct
- CBD sampling logic — correct
- CSPRNG — uses `dart:math Random.secure()` (OS entropy) — correct

---

## Empirical Confirmation (demo 3)

### Before fixes (May 22)

```
[PASS] OpenSSL encaps/decaps shared secrets match        (Test A — OpenSSL self-consistent)
[PASS] pqcrypto encaps/decaps shared secrets match       (Test B — pqcrypto self-consistent)
[FAIL] OpenSSL keygen + pqcrypto encaps → OpenSSL decaps (Test C — INTEROP FAILS)
[FAIL] pqcrypto keygen + OpenSSL encaps → pqcrypto decaps (Test D — INTEROP FAILS)
```

### After fixes (May 25)

```
[PASS] OpenSSL encaps/decaps shared secrets match
[PASS] pqcrypto encaps/decaps shared secrets match
[PASS] OpenSSL keygen + pqcrypto encaps + OpenSSL decaps: shared secrets match
[PASS] pqcrypto keygen + OpenSSL encaps + pqcrypto decaps: shared secrets match
```

All four tests pass. Shared secrets are byte-identical in both cross-implementation directions, confirming the fork now conforms to FIPS 203.

---

## Bottom Line

The two critical bugs and the XOF index ordering bug, taken together, meant the original library could not exchange keys with any other ML-KEM-768 implementation (OpenSSL, liboqs, Bouncy Castle, etc.), and approximately 99.97% of ciphertexts were silently malformed. All three are now fixed in the local fork at `~/GitHub/pqcrypto`, and demo 3 stably passes all four cross-implementation tests against OpenSSL 3.6.

The remaining timing side-channel (#4) and the test-coverage gap (#5) should be addressed before this fork is upstreamed or shipped in production, but neither affects interop with FIPS 203-compliant peers.

**If you need ML-KEM-768 for production today, your options are:**

1. Use this fork (with the four fixes applied) and add a constant-time implicit-rejection fix plus a complete KeyGen+Encaps KAT harness
2. Wait for official Dart/Flutter support (in progress in Dart's `package:crypto` roadmap)
3. Use `dart:ffi` to bind to a vetted C library (liboqs, BoringSSL post-quantum branch, or OpenSSL ≥ 3.2) — which is what this demo's OpenSSL side does
