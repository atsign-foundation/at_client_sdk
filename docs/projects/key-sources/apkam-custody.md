# APKAM custody: hardware-held credentials and a server-held atKeys document

A companion to [`design.md`](design.md). That design protects the atKeys
document at rest with a key source. This one moves the APKAM credential itself
into the device's secure hardware (Secure Enclave, TPM, Android Keystore or a
passkey), and keeps the rest of the enrollment's keys on the atServer as a
version 2 envelope that only that hardware can open. The hardware plugs into
`design.md`'s store as one more `AtKeysKeySource`.

## Status

Draft, 2026-10-01. Nothing here is built. The hardware capabilities in
[section 2](#2-what-the-hardware-offers) are taken from vendor documentation
and haven't been probed; [section 10](#10-open-questions) lists what would
settle them. The at_server claims were read from trunk. Updated 2026-11-02 to match
trunk's key-source rework (`e4de03a60` every client is given its keys,
`4c07f9aff` the mint guard); where this design and trunk differ, trunk wins.

## Table of contents

- [1. The problem](#1-the-problem)
- [2. What the hardware offers](#2-what-the-hardware-offers)
- [3. Why a signature can't be the secret](#3-why-a-signature-cant-be-the-secret)
- [4. Custody tiers and the ranking rule](#4-custody-tiers-and-the-ranking-rule)
- [5. The seam: SecurityPlatform](#5-the-seam-securityplatform)
- [6. SecurityPlatformKeySource](#6-securityplatformkeysource)
- [7. The server-held document](#7-the-server-held-document)
- [8. Opening a session](#8-opening-a-session)
- [9. The browser as the only device](#9-the-browser-as-the-only-device)
- [10. Open questions](#10-open-questions)
- [11. Changes by package](#11-changes-by-package)

## 1. The problem

Today an APKAM private key is bytes. It is minted in Dart, written into the
atKeys document, and signs `from:` challenges from memory. Protecting the
document at rest (`design.md`) stops a copied disk from yielding it, but any
process that opens the document gets a key it can take elsewhere.

Two stages fix that:

1. **The hardware mints the APKAM key.** Only its public half is enrolled, and
   PKAM signs challenges inside the hardware, so the key can't leave the
   device.
2. **The rest of the enrollment's keys** (encryption key pair, self encryption
   key, `apkamSymmetricKey`, any software signing keys) are kept on the
   atServer in an envelope that only this device's hardware can open. Nothing
   secret sits on the device at rest.

Recovery depends on the tier, and only the passkey tier recovers by syncing. A
Secure Enclave key can't sync (a keychain item backed by the Secure Enclave
can't be synchronisable), so for hw-kem a lost device means its server-held
document can't be opened. Recovery is enrolling a new device and having an
existing one approve it. A synced passkey does re-derive the same keys on
another device, reading the enrollment id from the bootstrap record
([section 9](#9-the-browser-as-the-only-device)). There is no
manual export to another device in any tier.

## 2. What the hardware offers

| Platform                | Signs in hardware            | Key encapsulation in hardware | Deterministic secret in hardware              |
| ----------------------- | ---------------------------- | ----------------------------- | --------------------------------------------- |
| Apple Secure Enclave, OS 26+ | ML-DSA-65, P-256 ECDSA  | ML-KEM-768 and ML-KEM-1024    | P-256 ECDH against a fixed point              |
| Apple Secure Enclave, earlier | P-256 ECDSA                 | none                          | P-256 ECDH against a fixed point              |
| Windows TPM (NCrypt PCP) | P-256, RSA-2048              | none                          | ECDH_ZGen; HMAC may not be exposed through PCP |
| Linux TPM (tpm2-tss)    | P-256, RSA-2048              | none                          | `TPM2_HMAC` with a keyedHash key              |
| Android StrongBox or TEE | P-256; Ed25519 on TEE with KeyMint 2+ | none                | HMAC-SHA256 key                               |
| Browser                 | none (WebCrypto keys are software) | none                    | the WebAuthn PRF extension                    |

None of them offers Ed25519 across the board: `TPM_ALG_EDDSA` is in TPM spec
1.83 and later but not in shipping chips, and the Secure Enclave has none. AES
is no better: the Secure Enclave holds no AES key, and TPMs often disable
`EncryptDecrypt`. Android is the exception, with AES-GCM in hardware.

## 3. Why a signature can't be the secret

The first idea was to sign a fixed message, such as `atSign|enrollmentId|pkam`,
with the hardware key and use the signature as an encryption key. It fails
twice. ECDSA from the Secure Enclave and TPM, and hedged ML-DSA, are
randomised, so the same message gives a different signature each time. And the
PKAM key signs whatever challenge the atServer sends; the `from:` validator in
`at_lookup_impl.dart` constrains the shape, but a key whose signatures are
secrets would hand them to a malicious server.

The deterministic primitives are a hardware PRF (HMAC, ECDH against a fixed
point, WebAuthn PRF) and hardware key decapsulation. The PKAM key is never
used for either.

## 4. Custody tiers and the ranking rule

There are three tiers, and each feeds machinery the post-quantum work already
built:

- **hw-kem.** The Secure Enclave holds an ML-KEM-1024 key. Its public half is
  advertised with the existing `ml-kem-1024-rfc9180-v1` suite, and
  `privateDecapsulation` is a reference, never bytes.
- **hw-prf-seed.** `seed = HKDF-SHA256(PRF(input), salt, info)`, where the PRF
  input is a fixed constant and the salt is a random 32 bytes per enrollment.
  The seed goes to the existing
  `keyPairFromSeed` (X-Wing, or ML-DSA-65 once that has a seed keygen), so no
  new suite is needed. The seed exists only in memory for the session.
- **software.** Today's behaviour, and the default.

The salt can't be the enrollment id, because the public keys go into
`enroll:request` before the id exists. Natively it sits in the same keychain
item as the hardware key reference. In the browser it is the passkey's
`userHandle`, which a discoverable `get()` returns; WebAuthn fixes the PRF
input in the `get()` request and the `userHandle` arrives only in the
response, so a `userHandle` PRF input would cost a second `get()` and a
second prompt. The input is a constant and the `userHandle` is the HKDF
salt, so one ceremony still covers it
([`prf-server-keys-blob.md`](prf-server-keys-blob.md#derivation)).

Tiers rank differently by role, because the threats differ:

| Role                        | Order                                  | Why                                                                                                 |
| --------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Key encapsulation (the document) | hw-kem, hw-prf-seed (HMAC-based PRFs; ECDH-based PRFs rank below hw-kem and are classical), software | the envelope sits on the atServer for years, so "harvest now, decrypt later" dominates: post-quantum first |
| Authentication (PKAM)       | hardware signing, hw-prf-seed, software | a forgery can't be harvested for later, and the key can be rotated: non-exportable first         |

Within a tier the strongest algorithm wins, using
`SigningAlgoType.strongestFirst` for signing and the posture's key-establishment
order for encapsulation. The tier is chosen once, at enrollment, and recorded
with the enrollment. The fallbacks in [section 6](#6-securityplatformkeysource)
and [section 9](#9-the-browser-as-the-only-device) apply only to that choice,
and a weaker tier taken there is recorded as what it is. After enrollment
nothing runs below the recorded tier: if it is unavailable the operation is
refused, not retried with a lower one. (The trusted-devices decision record
that would hold this rule doesn't exist yet; writing it is the `docs` row of
[section 11](#11-changes-by-package).)
A `PqPosture` setting of `custody: required` refuses the software tier.

## 5. The seam: SecurityPlatform

Every current signing path takes a private key as a string and runs
synchronously, so hardware can't plug in anywhere. `SecurityPlatform` is that
missing boundary. It holds handles, not bytes:

```dart
abstract interface class SecurityPlatform {
  /// 'apple-se', 'android-keystore', 'win-tpm', 'tpm2', 'webauthn', 'software'.
  String get id;

  Future<CustodyCapabilities> capabilities();

  Future<CustodyKey> mint(CryptographicMaterialRole role,
      CryptographicMaterialAlgorithm algorithm, {required String keyId});

  /// Raises the one biometric or PIN prompt for the session.
  Future<CustodySession> openSession({required String reason});
}

abstract interface class CustodySession {
  Future<Uint8List> sign(CustodyKey key, Uint8List message);
  Future<Uint8List> decapsulate(CustodyKey key, Uint8List enc);
  Future<Uint8List> prf(CustodyKey key, Uint8List input);
  Future<void> close();
}
```

It is a new, non-sealed interface in at_auth. `AtKeysIo` is sealed, but
`WrittenAtKeysIo` is an open abstract subclass that platform packages already
extend (at_client_flutter's `KeychainAtKeysIo`), so storage can be plugged in
without it. The seam is separate because holding keys by handle is a different
job from storing a document. It holds no keys and isn't a registry.
`CustodyKey` is an opaque `{platformId, ref, publicKey, role, algorithm}`, so a
future remote custodian (an identity provider's key, say) fits without an
interface change. The platform is injected through the same doors as storage:
`Atsign.activate/enroll/open(…, security:)`, defaulting to
`SoftwareSecurityPlatform`.

Role names, key ids (`auth:<algo>:<n>`), algorithm names and the per-enrollment
namespace are the ones the post-quantum work already uses.

## 6. SecurityPlatformKeySource

A platform becomes a key source for `design.md`'s store through a wrapper:

```dart
final class SecurityPlatformKeySource implements AtKeysKeySource {
  SecurityPlatformKeySource(this.platform, this.key, {required this.session});

  final SecurityPlatform platform;

  /// An encapsulation or PRF key; never the PKAM key.
  final CustodyKey key;

  /// The session's shared prompt.
  final Future<CustodySession> Function() session;

  @override
  String get id => 'custody:${platform.id}';

  @override
  Future<WrappedKey> wrap(Uint8List dataKey, {required String atSign});

  @override
  Future<Uint8List> unwrap(WrappedKey wrapped, {required String atSign});
}
```

- **hw-kem** wraps by sealing the data key to the Secure Enclave's ML-KEM-1024
  public key, which needs no prompt, and unwraps through
  `session.decapsulate`.
- **PRF-backed sources** (WebAuthn PRF, TPM HMAC, Keystore HMAC, Secure Enclave
  ECDH) wrap with AES-256-GCM under `HKDF(prf, salt, "atkeys-kek|<atSign>")`,
  the atSign-bound label [`prf-server-keys-blob.md`](prf-server-keys-blob.md#derivation)
  and `design.md` section 8 use. The atSign in the label is what keeps two
  atSigns on one device from sharing a recordId or a kek. For the HMAC-based
  PRFs the key is symmetric, so it is already post-quantum. Secure Enclave ECDH
  against a fixed
  point is not: its output is only as secret as a P-256 private key, so anyone
  holding the public half (which stays in the keychain, which narrows the
  exposure) and a quantum computer can recompute the KEK. For a document that
  sits on the atServer for years, ECDH-PRF ranks below hw-kem and counts as
  classical.
- The constructor rejects a key whose role is `privateAuthentication`, which
  keeps the rule from [section 3](#3-why-a-signature-cant-be-the-secret) out of
  the caller's hands.

So the store never learns about custody. A Secure Enclave, DPAPI and a cloud
KMS are all entries in the envelope's `keys` list, and a daemon could carry a
`custody:tpm2` entry beside a `systemd-credential` one. Software custody isn't
wrapped; the store keeps its platform default.

The two TPM uses are separate. `systemd-creds` protects a daemon's document at
rest, as `design.md` section 7 describes. A `tpm2` security platform holds the
APKAM key itself. A daemon can use either or both.

On macOS the Secure Enclave keys live in the keychain, so they inherit the
signing rule measured in `design.md` section 3: a team-signed binary with
`keychain-access-groups` reads them, and an unsigned CLI build gets software
custody, which is recorded.

## 7. The server-held document

The atKeys document for a custody enrollment is a version 2 envelope, kept at
`atkeys.<enrollmentId>.a.__e@<atSign>` as a private record. Three things make
that namespace the right home:

- The atServer confines `<enrollmentId>.a.__e` keys to that enrollment, so
  another enrollment on the same atSign can't read the record.
- Revoking or deleting the enrollment moves its per-enrollment data to `.r.__e`
  or `.d.__e`, so the record goes with it.
- It needs no server change.

Expiry is a third case. Since at_server#2858 (shipped in p3.18.1, fixing
[at_server#2831](https://github.com/atsign-foundation/at_server/issues/2831)),
the first `llookup` of an expired enrollment's data moves it to `.d.__e`
(`EnrollmentManager.moveExpiredEnrollmentData`), so it is never served from
`.a.__e`; the expiry sweep is the backstop for data nobody looks up.

The approver's secret-sharing envelope can't serve instead. `__ssenv`
envelopes are deleted once consumed (`pairwise_secret_sharing.dart`), including
one a device addressed to itself.

The document is written on activate, when an enrollment completes, and on
every key rotation. The device's keychain keeps only public halves, hardware
key references, the salt, the key-package id and the enrollment id, which the
PKAM verb and the record name both need. In the browser there is no keychain
that survives eviction, so the enrollment id travels in the gate (a) record
([section 9](#9-the-browser-as-the-only-device)); everything else the browser
keeps in IndexedDB is a rebuildable cache.

## 8. Opening a session

One prompt covers the whole session, including reconnects:

```mermaid
sequenceDiagram
  participant App
  participant C as SecurityPlatform
  participant K as Keychain
  participant S as atServer
  App->>K: read references, salt, public halves
  App->>C: openSession(reason): one biometric prompt
  C-->>App: CustodySession
  App->>S: from:@alice
  S-->>App: challenge
  App->>C: session.sign(auth key, challenge)
  App->>S: pkam:signingAlgo:<algo>:enrollmentId:<id>:<signature>
  App->>S: llookup:atkeys.<enrollmentId>.a.__e@alice
  App->>C: SecurityPlatformKeySource.unwrap (decapsulate or prf)
  App-->>App: document opened; a server-backed WrittenAtKeysIo is handed to the client
  Note over App,C: a reconnect signs through the same session, with no prompt
```

| Platform              | How the session holds one prompt                                          |
| --------------------- | ------------------------------------------------------------------------- |
| Apple                 | one `LAContext`, passed as `kSecUseAuthenticationContext`                 |
| Android               | `setUserAuthenticationParameters` with a timeout                          |
| TPM and Windows Hello | the prompt gates the PRF or encapsulation key; the PKAM key has no prompt |
| Browser               | one PRF `get()`; the derived keys are held for the session                |

Trunk requires every client to be given an `AtKeysIo` at construction, and
that store MUST be a durable `WrittenAtKeysIo`: the guards check the type
only, and durability is the MUST in `WrittenAtKeysIo`'s dartdoc
(`at_keys_io.dart`; see `design.md` section 4). So the order above is: the handshake authenticates
through an `InMemoryAtKeysIo()` it writes the handshake keys into, as at_auth's
handshake does, then the document is fetched, then a server-backed `WrittenAtKeysIo` is built
over it and handed to the client. That store writes `flush` and `update` back
to `atkeys.<enrollmentId>.a.__e`; it is not a session-memory copy, because a
client running on a store that forgets would mint a signing root whose private
is lost. Trunk's guard is the store's type: a client on any other `AtKeysIo`
mints no root, signing keys or key package and skips the enrollment snapshot.

The server-backed store needs a conditional update on the atServer before it
ships. Devices that share a synced passkey share one enrollment and one record
([section 9](#9-the-browser-as-the-only-device)), so two of them can write it at
once, and with a plain `update` the later write drops what the earlier one
filed. A dropped root or nskey private can't be replaced. at_server trunk has
no compare-and-swap today.

Each platform reports whether it achieved per-operation, per-session or no
prompting, so policy can see what it got.

The atServer side is already on trunk. It verifies a PKAM signature with the
algorithm the enrollment record holds, `ecc_secp256r1` and `mldsa65` included
(`apkam_signature_verifier.dart`), and honours the client's `apsk`. What the
client lacks is ES256 in JOSE, and ecc in `mintApkamKeyPair`,
`signPkamChallenge` and the possession proof, which today take only RSA-2048
and ML-DSA-65.

## 9. The browser as the only device

`design.md` section 8 needs a gate for fetching the document before the
browser holds a PKAM key, and offers two: a hidden `public:_` record named from
the PRF, or an enrollment whose credential is the passkey. There is a third:

> Derive the APKAM key from the passkey. The PRF output, run through
> `HKDF(prf, salt, "at_auth/custody/auth-seed/v1|<atSign>")` (with `<atSign>`
> in canonical form, as `toAtsign()` returns it, e.g. `@colinconstable`), seeds
> an ML-DSA-65 key pair, which is enrolled as an ordinary APKAM key. The browser
> does a normal PKAM, then reads the private `atkeys.<enrollmentId>.a.__e` record.

- **No server change.** Trunk already verifies ML-DSA-65 PKAM, and no atServer
  implementation has to verify WebAuthn assertions.
- **The gate (a) record stays, as the bootstrap.** Gate (c) needs the
  enrollment id, and nothing can derive it: the atServer assigns it at
  `enroll:request`, after the passkey and its `userHandle` already exist. After
  eviction, or on a second synced device, no device state holds it —
  IndexedDB is cleared, and a new device never had it — yet the PKAM verb
  (`pkam:...:enrollmentId:<id>:...`), the record name
  (`atkeys.<enrollmentId>.a.__e`) and the envelope's AAD all need it. So the
  browser keeps the `public:_<recordId>` bootstrap record from gate (a) and stores the
  enrollment id in it in the clear (the document envelope is stored exclusively in
  `atkeys.<enrollmentId>.a.__e`; see [`prf-server-keys-blob.md`](prf-server-keys-blob.md#derivation)); the
  restore reads the id from it, re-derives the PKAM key, performs an ordinary PKAM, and
  then reads and unwraps the private `atkeys.<enrollmentId>.a.__e` document. The record's name is still the secret;
  the id in the clear reaches only whoever already knows the name.
- **Revocation** is enrollment revocation, as with any device, and it must
  also delete the gate (a) bootstrap record; until an atServer does that, the
  unauthenticated-read threat gate (a) leaves open stays open
  ([`prf-server-keys-blob.md`](prf-server-keys-blob.md#open)).
- **One enrollment across synced devices.** A synced passkey derives the same
  APKAM key on every device it reaches, so they all authenticate as one
  enrollment, the atServer can't tell them apart, and revoking it signs them
  all out.
- **Eviction loses nothing.** IndexedDB becomes a cache: after it is cleared,
  the passkey re-derives the recordId and the PKAM key, the bootstrap record
  supplies the enrollment id, and the atServer supplies the document.
- **The cost:** the PKAM key sits in page memory for the session, the same
  exposure `design.md` section 9 already accepts for the data key.

A separate label, `HKDF(prf, salt, "atkeys-kek|<atSign>")`, derives the key
that wraps the document, so the PKAM key and the document key stay
independent and bound to the atSign. Where PRF is
unavailable, the fallbacks are largeBlob, then a non-extractable WebCrypto key
(recorded as software custody), then refusal under `custody: required`.

Passkey sync makes the provider part of the trust base, as `design.md` notes,
and that is accepted here as the recovery route.

## 10. Open questions

The wire format of ecc PKAM is settled from trunk and isn't open: at_chops'
`EccSigningAlgo.sign` signs the SHA-256 of the challenge and returns the code
units of `toCompactHex()` (r‖s as hex), `pkam:` carries that base64-encoded,
the public key is hex, and at_server's `ApkamSignatureVerifier` goes through
the same code. Secure Enclave and TPM output (DER, or CryptoKit's raw r‖s) must
be converted to compact hex. A pin test still guards it
([section 11](#11-changes-by-package)).

| Question | How to settle it |
| --- | --- |
| Does the Secure Enclave's ML-DSA-65 signature verify with the pure-Dart verifier (context string, pure or pre-hash)? | A macOS 26 probe that signs and verifies in Dart |
| Do Secure Enclave ML-KEM-1024 public-key bytes give the same key-package id as ours? | The same probe |
| Does NCrypt PCP expose HMAC on Windows TPMs, or only ECDH_ZGen? | A Windows probe |
| Is the custody tier worth recording in the enrollment record, so policy can require hardware later? | A decision for at_server; not blocking |
| How is a device secret rotated, and does revocation force it? | Design: new secret, new record name, old record deleted |
| Is the PRF output stable across UV states on every authenticator? | Pin UV to `required` and probe hmac-secret with and without UV |

## 11. Changes by package

| Package | Change |
| --- | --- |
| at_chops | ML-DSA-65 `keyPairFromSeed` (pure Dart and FFI); `pqOpen` with an external decapsulator; conversion of ECDSA DER and raw r‖s output (Secure Enclave, TPM) to the compact hex `EccSigningAlgo` emits; one HKDF helper for the custody labels |
| at_auth | `SecurityPlatform`, `CustodySession`, `CustodyKey`, `SoftwareSecurityPlatform`, `SecurityPlatformKeySource`; a tier selector; a `custody` field in keyfile material; the four raw-key signing paths routed through custody; the `_pkam` injected-signer path stops assuming RSA-2048 |
| at_client | no keyless path: custody keys reach the client only through the `AtKeysIo` it is given, which must be a `WrittenAtKeysIo`; ES256 in `envelope_signature.dart`; key packages advertise the custody encapsulation key; a server-backed store at `atkeys.<enrollmentId>.a.__e`; `open`, `activate` and `enroll` go through the session; `PqPosture.custody` |
| at_client_cli | `--security tpm2\|software`, with a tpm2-tss FFI platform in its own package |
| at_client_flutter | A federated `at_security_platform` plugin for Darwin (CryptoKit), Android (Keystore) and Windows (NCrypt); `KeychainAtKeysIo` keeps only references and public halves |
| at_client_web | `WebAuthnSecurityPlatform`, as in [section 9](#9-the-browser-as-the-only-device) |
| at_commons, at_lookup | none; the PKAM grammar already carries `ecc_secp256r1` and `mldsa65` |
| at_server | a conditional update (compare-and-swap) on a record, a prerequisite for the server-backed store ([section 8](#8-opening-a-session)); a pin test that ecc PKAM signatures are compact hex |
| docs | a trusted-devices decision record that separates APKAM custody from the device-assertion credential, which must never be a PKAM key, and holds the tier rule: chosen once at enrollment, recorded, never run below |

The order that keeps each step shippable: at_chops primitives, then the at_auth
seam with only the software platform (no behaviour change), then the server
store and session in at_client, then Apple (the first hw-kem), the browser,
Android, Windows and the TPM CLI.
