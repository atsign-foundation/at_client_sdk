# Phase 6 (steps 4–5) — consumer-package crypto migration audit

**Goal (reframed):** route every `at_` package's **encryption, signing, and
KDF** through **at_chops** alone. *Out of scope:* non-security hashing used as
a naming/identifier primitive in a foundational leaf package that sits **below**
at_chops in the dependency graph (i.e. `at_utils` — see below). The goal is to
harden the one crypto/security boundary, not to ban every `sha256` call
everywhere regardless of purpose.

This doc audits the non-at_client consumers. Companion:
`at_client/PHASE6_AT_CHOPS_MIGRATION_AUDIT.md` (at_client, done).

## Dependency-graph reality (corrects the plan's "additive, no new arrows")

`at_chops`'s own deps include **`at_utils`** and `at_commons`. So:

| Package | at_chops dep? | Routes through at_chops? |
|---------|---------------|------------------------------|
| `at_utils` | **NO — at_chops depends on `at_utils`** | **Out of scope** (below at_chops; non-security naming hash). |
| `at_lookup` | yes (`^3.0.0`) | yes |
| `at_auth` | yes (`^3.0.0`) | yes |
| `at_onboarding_cli` | yes (`^3.0.0`) | yes |
| `at_login_flutter` | **NO** | **Out of scope** (being removed by a separate effort). |

**`at_utils` is a foundational dependency *of* at_chops, not a consumer.** It
cannot route through at_chops without a dependency cycle — but more
importantly, its one `sha256` use is not a security operation, so it's out of
scope for this phase (see below), not a reluctant carve-out.

## Per-site inventory

### at_utils — OUT OF SCOPE by design (keeps `crypto`)
- `src/atsign_util.dart:89` — `AtUtils.getShaForAtSign(atSign)` =
  `sha256.convert(utf8.encode(atsign)).toString()`.
- **Not encryption/signing — a naming hash.** It derives a filesystem/Hive-box-
  safe identifier from an atSign (atSigns contain `@`, `.`, emoji). Used to name
  Hive boxes + files: at_client's sync-queue box, and at_server's keystore /
  commit-log / access-log / notification-log boxes + a `.hash` file.
- **Frozen on-disk identifier.** Its output names persisted boxes/files; changing
  it would orphan all existing storage on upgrade. It must stay sha256 and
  byte-stable forever — i.e. we should *not* be churning it regardless.
- **Cannot route through at_chops** anyway (at_chops → at_utils cycle); at_utils
  is a leaf depending only on logging/yaml/crypto/at_commons/collection/chalkdart.
- **Decision:** keep `package:crypto` here; it falls outside the reframed goal
  (security crypto only). The import gate whitelists at_utils.

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

### at_login_flutter — OUT OF SCOPE (being removed)
- `utils/at_login_utils.dart:4` — `package:basic_utils` (pointycastle wrapper).
- `services/at_login_service.dart:12` — `crypton`.
- **Not migrated:** a separate effort is removing this package entirely, so
  migrating its crypto would be wasted work. Excluded from the goal and
  whitelisted in the gate until it is deleted.

## Recommended implementation order

1. **at_lookup** — DONE. byte-identical, dependency-first. crypton+crypto gone.
2. **at_auth** — DONE. 2 RSA sites; functional/enrollment verify before PR.
3. **at_onboarding_cli** — DONE. crypto+encrypt+crypton gone (incl. the
   keypair-type change, option B). Pre-existing 5.0.0 test break also fixed.
4. **at_login_flutter** — out of scope (being removed by a separate effort).
5. **at_utils** — out of scope by design (above); keeps `crypto`.

With at_lookup/at_auth/at_onboarding_cli done and at_login_flutter + at_utils
out of scope, the consumer migration is **complete** — only the gate remains.

Each is its own per-package commit. Auth/enrollment packages (1–3) are
wire-sensitive → run the functional/end-to-end auth suite before their PRs.

## Enforcement (Phase 6 step 6) — IMPLEMENTED

`tools/check_crypto_imports.sh` fails on any `package:` import of
`crypton | crypto/crypto.dart | encrypt/encrypt.dart | pointycastle |
basic_utils | cryptography` in a **consumer** `lib/`. Wired into CI as the
`crypto_import_gate` job in `.github/workflows/at_client_sdk.yaml` (pure
bash + grep; no Dart toolchain needed). **Whitelist:**
- `at_chops` — the wrapper; it owns the primitive libraries.
- `at_utils` — out of scope (foundational leaf below at_chops; non-security
  naming hash, frozen on-disk identifier).
- `at_login_flutter` — out of scope (being removed by a separate effort).
- at_client's v4-quarantined files (`encryption_util.dart`,
  `aes_converter.dart`) — until the deprecated stream/file methods are removed.

The gate scope is *security crypto in consumers*, matching the reframed goal —
it is not a blanket ban on `sha256` everywhere. To change the boundary, edit
the whitelist in the script with a justification.
