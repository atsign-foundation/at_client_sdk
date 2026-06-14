# Phase 6 (steps 4–5) — consumer-package crypto migration audit

Goal: route every `at_` package's crypto/hashing through **at_chops** alone.
This doc audits the non-at_client consumers. Companion:
`at_client/PHASE6_AT_CHOPS_MIGRATION_AUDIT.md` (at_client, done).

## Dependency-graph reality (corrects the plan's "additive, no new arrows")

`at_chops`'s own deps include **`at_utils`** and `at_commons`. So:

| Package | at_chops dep? | Can route through at_chops? |
|---------|---------------|------------------------------|
| `at_utils` | **NO — at_chops depends on `at_utils`** | **BLOCKED** (circular). Permanent exception. |
| `at_lookup` | yes (`^3.0.0`) | yes |
| `at_auth` | yes (`^3.0.0`) | yes |
| `at_onboarding_cli` | yes (`^3.0.0`) | yes |
| `at_login_flutter` | **NO** | yes, but needs a **new** `at_chops` dep (UI pkg, no cycle) |

**`at_utils` is a foundational dependency *of* at_chops, not a consumer.** Its
one crypto site cannot route through at_chops without a dependency cycle, so
the goal "ALL at_ packages depend only on at_chops" has a structural exception
here. at_utils legitimately keeps `package:crypto`.

## Per-site inventory

### at_utils — BLOCKED (architectural exception)
- `src/atsign_util.dart:89` — `AtUtils.getShaForAtSign` = `sha256.convert(utf8.encode(atsign)).toString()`.
  Cannot use at_chops (cycle). **Keep `crypto`**; document the exception; the
  Phase 6 gate must whitelist at_utils.

### at_lookup — SAFE, byte-identical-by-construction (4 sites)
All four wrap calls at_chops already re-exposes via `PkamSigningAlgo` /
`SHA512HashingAlgo` (which themselves call the identical crypton/crypto APIs):

- `at_lookup_impl.dart:178` — `RSAPublicKey.fromString(pub).verifySHA256Signature(data, sig)`
  → `PkamSigningAlgo(null, HashingAlgoType.sha256).verify(data, sig, publicKey: pub)`.
- `at_lookup_impl.dart:454` — legacy `authenticate()`: `RSAPrivateKey.fromString(pk).createSHA256Signature(data)`
  → `PkamSigningAlgo(AtPkamKeyPair.create('', pk), HashingAlgoType.sha256).sign(data)`.
- `at_lookup_impl.dart:544` — cram: `sha512.convert(bytes)` (→ `.toString()` hex via `$digest`)
  → `SHA512HashingAlgo().hash(bytes)`.
- `monitor_client.dart:76` — same RSA-SHA256 sign as the legacy `authenticate()`
  → `PkamSigningAlgo(...).sign(...)`.

The modern `pkamAuthenticate()` already uses `_atChops!.sign(...)`. **Auth-path
→ functional/auth verification recommended before the at_lookup PR** even
though the bytes are provably identical.

### at_auth — RSA enrollment (1 file, 2 sites)
- `enroll/at_enrollment_impl.dart:100` — `RSAPublicKey.fromString(defaultEncryptionPublicKey).encrypt(apkamSymmetricKey.key)`
  → `RsaEncryptionAlgo()..atPublicKey=AtPublicKey.fromString(pub)`; `base64Encode(algo.encrypt(utf8(key)))`
  (same framing proven in at_client's encryptKey). **DIVERGED** — round-trip,
  not byte-equality (RSA PKCS1v15 non-deterministic).
- `:142` — `RSAPrivateKey.fromString(atLookUp.atChops!...privateKey).decrypt(encrypted)`
  → `RsaEncryptionAlgo()..atPrivateKey=...`; or, since `atChops` is in hand,
  `atLookUp.atChops!.decryptString(encrypted, EncryptionKeyType.rsa2048)`.
  Enrollment-path → functional gate.

### at_onboarding_cli — mixed (3 sites, the tangled one)
- `helpers/enrollment_checkpoint.dart:40` — `sha256.convert(...)` → `SHA256HashingAlgo().hash(...)`. **MATCHED.**
- `onboard/at_onboarding_service_impl.dart:751` — `generateRsaKeypair() => RSAKeypair.fromRandom()`.
  **CAUTION:** `AtChopsUtil.generateRSAKeyPair()` *returns crypton's
  `RSAKeypair`* — routing through it does **not** drop the crypton import (the
  return type re-pulls it). Need `generateAtEncryptionKeyPair()` /
  `generateAtPkamKeyPair()` (at_chops types) and adapt the call sites, or
  accept crypton stays for the keypair type. **DIVERGED — needs call-site work.**
- `:757` — `generateAESKey() => AES(Key.fromSecureRandom(32)).key.base64`
  → `AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key`. **MATCHED.**
- Also uses `at_client`'s `EncryptionUtil.encryptValue/decryptValue` (the
  quarantined-until-v4 AES) at :626–650 — those are at_client API calls, not a
  direct `encrypt` import issue here; the `encrypt` import here is only for
  `AES`/`Key`/`IV`. Removing crypton+encrypt from this file requires the
  keypair-type fix above plus routing the AES key/IV gen.

### at_login_flutter — Flutter, step 5 (needs new dep)
- `utils/at_login_utils.dart:4` — `package:basic_utils` (pointycastle wrapper).
- `services/at_login_service.dart:12` — `crypton`.
- Needs a **new `at_chops` dependency**. Read both files before migrating;
  lowest priority.

## Recommended implementation order

1. **at_lookup** — safest (byte-identical), dependency-first (dep of
   at_client/at_auth). Removes `crypton`+`crypto` from at_lookup/lib.
2. **at_auth** — 2 RSA sites; round-trip-gated; functional/enrollment verify.
3. **at_onboarding_cli** — sha256 (easy) + the keypair-type caution + AES gen.
4. **at_login_flutter** — add at_chops dep; basic_utils + crypton. Lowest prio.
5. **at_utils** — leave as-is (documented exception); whitelist in the gate.

Each is its own per-package commit. Auth/enrollment packages (1–3) are
wire-sensitive → run the functional/end-to-end auth suite before their PRs.

## Enforcement (Phase 6 step 6)

The import gate runs after the above. **Whitelist:** `at_utils` (structural
exception) and the at_client v4-quarantined files
(`encryption_util.dart`, `aes_converter.dart`).
