# app_2 — Hybrid PQC Key Exchange: X25519 + ML-KEM-768

Demonstrates a hybrid post-quantum key exchange using:

- **X25519** — classical Diffie-Hellman (via the `cryptography` Dart package)
- **ML-KEM-768** — NIST-standardized post-quantum KEM (via Dart FFI → liboqs)
- **HKDF-SHA256** — combines both shared secrets into a single 32-byte hybrid key
- **AES-256-GCM** — encrypts a message with the hybrid key
- **SHA-256** — produces a session fingerprint

The design follows the hybrid KEM pattern: even if one primitive is broken (classical or post-quantum), the combined key remains secure as long as the other holds.

---

## Prerequisites

### 1. Dart SDK ≥ 3.11

```
dart --version
```

### 2. liboqs (Open Quantum Safe)

On macOS via Homebrew:

```sh
brew install liboqs
```

This installs the static archive at `/opt/homebrew/lib/liboqs.a` and headers at `/opt/homebrew/include/oqs/`.

liboqs depends on OpenSSL, which Homebrew installs as a dependency automatically.

---

## Build the shared library

Dart FFI requires a dynamic library (`.dylib` / `.so`). Because Homebrew only ships `liboqs.a`, you must build the dylib yourself once:

```sh
# from the app_2/ directory
clang -shared -o liboqs.dylib \
  -Wl,-force_load,/opt/homebrew/lib/liboqs.a \
  -L/opt/homebrew/lib \
  -lcrypto
```

This produces `app_2/liboqs.dylib`. The app loads it at runtime from the directory adjacent to `bin/`.

> **Linux equivalent:**
> ```sh
> gcc -shared -o liboqs.so \
>   -Wl,--whole-archive /usr/local/lib/liboqs.a -Wl,--no-whole-archive \
>   -lcrypto
> ```

---

## Install Dart dependencies

```sh
dart pub get
```

---

## Run

```sh
dart run bin/app_2.dart
```

Expected output:

```
=== Hybrid PQC Key Exchange: X25519 + ML-KEM-768 ===

--- Step 1: X25519 ---
Alice X25519 shared: 0b12122d786a17aa...  (32 bytes)
Bob   X25519 shared: 0b12122d786a17aa...  (32 bytes)
X25519 match: true

--- Step 2: ML-KEM-768 (via FFI → liboqs) ---
Bob  ML-KEM-768 pk: 568a4c2671784...  (1184 bytes)
Ciphertext:          681e45b3a245...  (1088 bytes)
Alice ML-KEM-768 ss: b9198ce557a3...  (32 bytes)
Bob   ML-KEM-768 ss: b9198ce557a3...  (32 bytes)
ML-KEM-768 match:    true

--- Step 3: HKDF-SHA256 (combine X25519 + ML-KEM-768 secrets) ---
Hybrid key (Alice): 9f310ae95ec2f4aa...
Hybrid key (Bob):   9f310ae95ec2f4aa...
Hybrid key match:   true

--- Step 4: AES-256-GCM ---
Plaintext:  Hello, post-quantum world! ...
Ciphertext: 2d7a35205f1a773e...  (76 bytes)
MAC:        0ef42298c2dea72f...
Decrypted:  Hello, post-quantum world! ...
Decrypt OK: true

--- Step 5: SHA-256 session fingerprint ---
Session fingerprint: 75cc3302574d20be...

=== All steps completed successfully ===
```

---

## Cryptographic primitives

### X25519 — how it works

X25519 is an elliptic-curve Diffie-Hellman (ECDH) key exchange over Curve25519. Both parties generate a keypair and exchange public keys. Each side can independently compute the same shared secret using their own private key and the other party's public key — without ever sending the secret over the wire.

```
Alice                                        Bob
─────                                        ───
Generate keypair:                            Generate keypair:
  alice_sk (random scalar)                     bob_sk (random scalar)
  alice_pk = alice_sk × G                      bob_pk = bob_sk × G
                                               (G = curve base point)

              ──── alice_pk ────►
              ◄─── bob_pk   ────

shared = alice_sk × bob_pk       shared = bob_sk × alice_pk
       = alice_sk × bob_sk × G           = bob_sk × alice_sk × G
                                                    ↑ same point
```

Security relies on the **elliptic curve discrete logarithm problem (ECDLP)**: given `alice_pk` and `G`, finding `alice_sk` is computationally infeasible — on classical computers.

#### X25519 weakness: quantum computers

Shor's algorithm running on a sufficiently large quantum computer can solve ECDLP in polynomial time, recovering the private key from the public key. A quantum-capable adversary who recorded your ciphertext today can decrypt it once they have the hardware ("harvest now, decrypt later").

```
Classical attacker sees:  alice_pk, bob_pk, ciphertext
                          ✗ cannot reverse ECDLP
                          ✗ cannot read the message

Quantum attacker sees:    alice_pk, bob_pk, ciphertext
                          ✓ Shor's algorithm recovers alice_sk or bob_sk
                          ✓ computes shared secret
                          ✓ decrypts the message
```

---

### ML-KEM-768 — how it works

ML-KEM-768 (formerly Kyber-768) is a **Key Encapsulation Mechanism** standardized by NIST (FIPS 203). Unlike ECDH where both sides contribute randomness, a KEM is asymmetric: one side *encapsulates* a secret to the other's public key; only the holder of the secret key can *decapsulate* it.

Security is based on the **Module Learning With Errors (MLWE)** problem: recovering a secret from a noisy linear system over a polynomial ring, which is believed to be hard for both classical and quantum computers.

```
Bob                                          Alice
───                                          ─────
Generate keypair:
  (bob_pk, bob_sk) = KeyGen()

          ──────── bob_pk (1184 B) ─────────►

                                             (ct, ss) = Encaps(bob_pk)
                                             # ct  = ciphertext (1088 B)
                                             # ss  = shared secret (32 B)
                                             #       known only to Alice (so far)

          ◄──────── ct (1088 B) ────────────

ss = Decaps(ct, bob_sk)
# Bob recovers the same ss
# ss is now known to both sides
```

The ciphertext `ct` is essentially an encryption of `ss` under `bob_pk`, with built-in noise that makes the MLWE problem hard to invert.

#### ML-KEM-768 weakness: implementation maturity

ML-KEM is young (standardized 2024). The concern is not mathematical but practical:

- **Side-channel attacks** — timing or power analysis on flawed implementations can leak the secret key. Classical cryptography has decades of hardened implementations; ML-KEM does not yet.
- **Unknown unknowns** — a novel cryptanalytic technique could weaken the underlying lattice problem. No such attack is known, but the algorithm hasn't been stress-tested for as long as elliptic curves have.
- **Not broken by classical computers** — but if a subtle flaw is found in the MLWE construction, a classical attacker could exploit it.

```
Classical attacker sees:  bob_pk, ct
                          ✗ MLWE is hard classically
                          ✗ cannot recover ss

Quantum attacker sees:    bob_pk, ct
                          ✗ no known quantum speedup for MLWE
                          ✗ cannot recover ss

Implementation flaw:      timing side-channel in decaps()
                          ✓ may leak bob_sk
                          ✓ attacker recovers ss
```

---

### Why combining them makes it PQ-safe

Neither primitive alone is sufficient:

| Threat | X25519 alone | ML-KEM-768 alone | X25519 + ML-KEM-768 |
|--------|-------------|-----------------|---------------------|
| Classical cryptanalysis | Secure | Secure | Secure |
| Quantum computer (Shor's) | **Broken** | Secure | **Secure** |
| Lattice cryptanalysis / ML-KEM flaw | Secure | **Broken** | **Secure** |
| Side-channel on ML-KEM | Secure | **Broken** | **Secure** |

The hybrid works because the two shared secrets are combined through HKDF:

```
ikm = mlkem_ss || x25519_ss   ← ML-KEM first, per X25519MLKEM768 spec
key = HKDF-SHA256(ikm, info="hybrid-x25519-mlkem768")
```

HKDF's security property is: the output `key` is indistinguishable from random **as long as at least one input is secret**. An attacker must break *both* X25519 and ML-KEM-768 simultaneously to recover `key`. Breaking one leaves the other's contribution as an unresolvable unknown.

```
Quantum attacker:
  ✓ breaks X25519  →  learns x25519_ss
  ✗ cannot break ML-KEM-768
  ✗ ikm = [unknown 32 bytes] || x25519_ss
  ✗ cannot derive key  →  message stays secret

Classical attacker with ML-KEM flaw:
  ✓ breaks ML-KEM-768  →  learns mlkem_ss
  ✗ cannot break X25519 classically
  ✗ ikm = mlkem_ss || [unknown 32 bytes]
  ✗ cannot derive key  →  message stays secret
```

This is the standard **hybrid KEM** construction recommended by NIST and used in TLS 1.3 post-quantum drafts (e.g. `X25519MLKEM768` in Chrome/Cloudflare deployments).

---

## How the exchange works

```
Alice                                    Bob
─────                                    ───
Generate X25519 keypair                  Generate X25519 keypair
                                         Generate ML-KEM-768 keypair
                    ← Bob's X25519 pub
                    ← Bob's ML-KEM-768 pub

x25519_ss = DH(alice_sk, bob_x25519_pk)
(ct, mlkem_ss) = ML-KEM-768.Encaps(bob_mlkem_pk)
                    → ciphertext (ct) →

                                         x25519_ss = DH(bob_sk, alice_x25519_pk)
                                         mlkem_ss  = ML-KEM-768.Decaps(ct, bob_mlkem_sk)

ikm  = mlkem_ss || x25519_ss            ikm  = mlkem_ss || x25519_ss
key  = HKDF-SHA256(ikm, info=...)       key  = HKDF-SHA256(ikm, info=...)
(ML-KEM first, per X25519MLKEM768 spec)

         ── both sides now hold the same 32-byte hybrid key ──

Encrypt with AES-256-GCM(key)           Decrypt with AES-256-GCM(key)
```

### ML-KEM-768 sizes

| Parameter    | Size     |
|--------------|----------|
| Public key   | 1184 B   |
| Secret key   | 2400 B   |
| Ciphertext   | 1088 B   |
| Shared secret| 32 B     |

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [`cryptography`](https://pub.dev/packages/cryptography) | X25519, HKDF-SHA256, AES-256-GCM, SHA-256 |
| [`ffi`](https://pub.dev/packages/ffi) | `calloc` allocator for native memory |
| [`path`](https://pub.dev/packages/path) | Resolve dylib path relative to the script |
| [liboqs](https://github.com/open-quantum-safe/liboqs) | Native ML-KEM-768 implementation |

---

## Project layout

```
app_2/
├── bin/
│   └── app_2.dart      # entry point — runs the full demo
├── lib/
│   └── app_2.dart      # (generated stub, unused)
├── liboqs.dylib         # built manually (see above) — not committed
├── pubspec.yaml
└── README.md
```
