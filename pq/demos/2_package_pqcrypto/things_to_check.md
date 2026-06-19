# 

Briefly started to audit the pqcrypto code, putting it through Claude code, reading the source code manually and even 

Double check these constants

```dart
          const KyberParams(k: 2, eta1: 3, eta2: 2, du: 10, dv: 4),
        );
      case KyberLevel.kem768:
        return KyberKem._(
          level,
          const KyberParams(k: 3, eta1: 2, eta2: 2, du: 10, dv: 4),
        );
      case KyberLevel.kem1024:
        return KyberKem._(
          level,
          const KyberParams(k: 4, eta1: 2, eta2: 2, du: 11, dv: 5),
```

Srie's Idea: >:) --> Double checking that both mlkem-native does the same thing as pqcrypto
--> Alice - pqcrypto , Bob - mlkem-native
--> Languages differ but algorithms stay the same

Here is the full security audit. Do not use this package in production.

-- reach out to maintainer to stable v1
-- first we try to lend help first

---
Security Audit: pqcrypto ML-KEM-768

Summary verdict: 2 critical bugs, 2 high severity issues, and incomplete tests. The library produces keys and ciphertexts incompatible with every other FIPS 203-compliant implementation.

---
CRITICAL #1 — Wrong Key Generation Input (kem.dart:83)

FIPS 203 Algorithm 13 requires G(d || k) where k = 0x03 (the security level byte). The code calls G(d) with only 32 bytes, omitting the domain separator. Every keypair generated is non-interoperable with OpenSSL, liboqs, or any other standard ML-KEM implementation.

// WRONG:
final rhoSigma = _G(d);
// CORRECT:
final rhoSigma = _G(Uint8List.fromList([...d, params.k]));

CRITICAL #2 — Compress Uses Clamp Instead of Modular Reduction (pack.dart:26)

FIPS 203 requires Compress_d(x) = ⌈(2^d / q) · x⌉ mod 2^d. The code saturates (clamps) instead of wrapping:

// WRONG — should be: return result & maxVal;
return result > maxVal ? maxVal : result;

For compress_4 (used for v in ML-KEM-768), this corrupts approximately 3.12% of coefficients — which means virtually every ciphertext (≈99.97%) contains at least one wrong coefficient. The library appears to work for self-generated roundtrips only because both sides use the same bug. Against any standard-compliant peer, decapsulation always returns the wrong key silently.

---
HIGH #3 — Barrett Reduction Returns Negative Values (poly.dart:20-26)

barrettReduce() does not guarantee output is in [0, q-1]. For ~0.54% of valid input pairs it returns negative values, which propagate through NTT butterfly operations and corrupt polynomial arithmetic.

Fix: Add if (res < 0) res += q; and if (res >= q) res -= q; after the existing computation.

HIGH #4 — Timing Side-Channel in Implicit Rejection (kem.dart:140-144)

The comparison between ct and re-encrypted cPrime uses a correct XOR accumulator (_constantTimeEq), but the result is used in a plain if/else branch. A JIT compiler will produce measurable timing differences between the two paths, leaking whether the ciphertext was valid — breaking IND-CCA2.

Fix: Compute both K' and K_bar unconditionally, then select with bitwise masking.

---
MEDIUM #5 — KAT Tests Never Verify Key Generation

The test suite skips KeyGen verification entirely (the if (seed.length == 48) branch does nothing because it lacks the required NIST AES-256-CTR DRBG). This is why Critical Bug #1 was never caught — all 3000 claimed passing tests only exercise the decapsulation path.

---
Things That Are Correct

- ML-KEM-768 parameters (k=3, η₁=2, η₂=2, du=10, dv=4) — correct
- Hash/XOF assignments (G=SHA3-512, H=SHA3-256, J=SHAKE-256, XOF=SHAKE-128) — correct
- Secret key structure (dk_PKE ‖ ek_PKE ‖ H(ek) ‖ z) — all four FIPS 203 components present
- NTT zeta table — spot-checked correct
- CBD sampling logic — correct
- CSPRNG — uses dart:math Random.secure() (OS entropy) — correct

---
Bottom Line

The two critical bugs mean this library cannot exchange keys with any other ML-KEM-768 implementation (OpenSSL, liboqs, Bouncy Castle, etc.), and approximately 99.97% of ciphertexts are silently malformed — though they still roundtrip correctly within the library itself. The high-severity timing issue further undermines IND-CCA2 security. These are not minor oversights; they are fundamental correctness failures that a test suite claiming "3000/3000 NIST KAT vectors passing" obscured because the test harness never verified key generation.

If you need ML-KEM-768 for production, your options are:
1. Wait for official Dart/Flutter support (in progress in Dart's package:crypto roadmap)
2. Use dart:ffi to bind to a vetted C library (liboqs, BoringSSL post-quantum branch)
3. Fix these five specific issues and rerun a complete KAT suite including KeyGen verification
