# at_auth

Platform-neutral core of **onboarding**, **authentication**, and **APKAM
enrollment** for the Atsign Protocol. Used by both
[`at_onboarding_cli`](../at_onboarding_cli) (CLI / server apps) and
[`at_client_flutter`](../at_client_flutter) (Flutter apps) — most
application developers will pick up one of those higher-level packages
rather than consuming `at_auth` directly.

## What `at_auth` does

| Capability                      | Entry point                                            |
| ------------------------------- | ------------------------------------------------------ |
| CRAM-based initial onboarding   | `AtAuth.onboard(AtOnboardingRequest, cramSecret)`      |
| PKAM authentication             | `AtAuth.authenticate(AtAuthRequest)`                   |
| APKAM enrollment (request side) | `AtEnrollment.submit(...)`                             |
| APKAM enrollment (approve side) | `AtEnrollment.approve(...)` / `AtEnrollment.deny(...)` |
| APKAM enrollment (self side)    | `AtEnrollment.update(...)` — an approved enrollment amending its own record |
| Free atSign registration        | `RegistrarService` (fetches CRAM key by email)         |

See [`example/onboard.dart`](example/onboard.dart),
[`example/authenticate.dart`](example/authenticate.dart), and
[`example/enrollment_request.dart`](example/enrollment_request.dart) for
end-to-end usage.

## The atSign lifecycle

The full journey from "I don't own an atSign yet" to "my app is talking
to the atServer" breaks into three phases. Understanding all three is
important because each produces credentials that need to be handled
correctly.

### Phase 1 — Provision an atSign (get a CRAM key)

An atSign is a namespaced identity (e.g. `@alice`) with a matching
personal server (the **atServer**). Before any cryptographic keys exist,
you need to claim the atSign itself.

- Free atSigns: [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans)
- Paid / custom atSigns: [my.atsign.com](https://my.atsign.com)

Registration produces a **CRAM key** — a high-entropy secret, delivered
to the registered email address, that proves first-time ownership.
Programmatic registration is available via `RegistrarService` (see
[`lib/src/registrar/`](lib/src/registrar)).

At this point the atSign exists on the root directory but its atServer
has no authenticated user and no encryption keys. The CRAM key is the
one-time bootstrap credential.

### Phase 2 — Onboard the atSign (generate the master AtKeys)

Onboarding happens **exactly once per atSign** and consists of:

1. Authenticating to the atServer with the CRAM key.
2. Generating the atSign's cryptographic keypairs (PKAM signing,
   encryption, self-encryption).
3. Publishing the public halves and registering the PKAM public key on
   the atServer.
4. Writing the private halves to a local `.atKeys` file (for CLI apps)
   or to the device **keychain** (for Flutter apps).

The result is a **master AtKeys** set. These keys:

- Are the **root of trust** for the atSign — losing them is
  approximately as bad as forgetting the password to a cryptocurrency
  wallet; there is no recovery path that doesn't involve reclaiming the
  atSign from scratch.
- **MUST be backed up by the end user.** Any app that uses `at_auth` to
  onboard an atSign should tell the user to back up the `.atKeys`
  file / keychain entry. `at_client_flutter` surfaces an "export keys"
  flow; CLI apps typically just write the file and leave it to the user.
- Are the only keys allowed to **approve or deny APKAM enrollment
  requests** — see Phase 3.

After Phase 2, the CRAM key is no longer usable (onboarding is
single-shot). Use [`example/onboard.dart`](example/onboard.dart) to walk
through it end-to-end.

#### Post-quantum onboarding (opt-in)

Set `AtOnboardingRequest.signingAlgoType` to `mldsa65` and step 2 mints an
**ML-DSA-65** PKAM keypair instead of an RSA one. Two consequences are worth
knowing before turning it on:

- The APKAM is filed as **typed material** under the enrollment id, and the
  `.atKeys` flat `apkamPublicKey`/`apkamPrivateKey` fields are left **empty**.
  That is deliberate: `AtKeys.toAtChops()` reads only the flat fields, so a
  tool that has not been taught about PQ enrollments fails outright instead of
  signing an ML-DSA key with the RSA routine. `AtAuth.authenticate` resolves
  such an enrollment on its own, via `signingAlgorithmForEnrollment` and
  `toAtChopsForEnrollment`.
- `AtOnboardingRequest.mintLegacyMaterial` governs the RSA encryption keypair,
  the self-encryption key, and whether `public:publickey` is published. It is
  an **opt-out**: leave it null and all three are still produced, because
  whether this atSign will ever need to talk to a pre-quantum peer is decided
  by the apps that adopt it rather than at activation. Set it false and a
  pre-quantum peer cannot send to the atSign at all.

`AtOnboardingRequest.metadataBuilder` attaches metadata to the first
enrollment's record. It runs on the request that creates that record, whose
metadata is never rewritten — so it is the only opportunity there will be.

### Phase 3 — Authenticate apps via APKAM (per-app scoped AtKeys)

The master AtKeys are powerful — they can read anything on the atServer
and approve new devices. You don't want every app on every device
holding them. APKAM (App-level Pkam Key Authentication Mechanism)
solves this.

How APKAM works:

1. A new app / device submits an **enrollment request** specifying the
   namespaces it needs and the access level it needs on each
   (e.g. `{'todos': 'rw', 'profile': 'r'}`). Each request gets a
   short-lived **OTP** to bind the request to a human-approved session.
2. An already-authenticated session holding the master AtKeys (or any
   session whose keys include the `__manage` namespace) **approves or
   denies** the request.
3. On approval, the atServer issues a **new, scoped AtKeys set** — it
   can only read/write within the granted namespaces.
4. The enrolling app stores those scoped keys (disk or keychain) and
   uses them for normal PKAM authentication thereafter.

Why this matters:

- **Scope limits blast radius.** An "evil" or simply buggy app with
  scoped keys can only damage data in its own namespace. A todos app
  with `{'todos': 'rw'}` can never read your `charts.acme` data even if
  it's fully compromised.
- **Scoped keys are revocable.** The master-keys holder can revoke any
  previously-approved enrollment; the atServer rejects future
  authentications from those keys immediately.
- **Audit trail.** Every active enrollment is listed with its `appName`,
  `deviceName`, namespace permissions, and status (`pending`,
  `approved`, `denied`, `revoked`, `expired`).

See [`example/enrollment_request.dart`](example/enrollment_request.dart)
for the submitting side; the approve/deny side is demonstrated in
[`at_onboarding_cli/example/apkam_examples/enroll_app_listen.dart`](../at_onboarding_cli/example/apkam_examples/enroll_app_listen.dart).

## The `.atKeys` file format

`FileAtKeysIo` reads and writes `.atKeys` files
(default path `~/.atsign/keys/<atsign>_key.atKeys`). A file has up to
three layers, outermost first:

1. **Optional passphrase envelope** — when a `passPhrase` is configured,
   the whole document is AES-encrypted with a key derived from the
   passphrase (argon2id) and stored as
   `{"content": ..., "iv": ..., "hashingAlgoType": "argon2id"}`.
   Detected by the presence of `iv`.
2. **Self-encrypted legacy fields** — the document's four legacy RSA
   fields (`aesPkamPublicKey`, `aesPkamPrivateKey`,
   `aesEncryptPublicKey`, `aesEncryptPrivateKey`) are AES-256-encrypted
   with the document's own plaintext `selfEncryptionKey`, using a
   deterministic IV (so identical plaintext always produces identical
   ciphertext).
3. **The document** — one of two shapes:
   - **Legacy flat** (no `version` field): a flat JSON object of the
     fields above plus `selfEncryptionKey`, `apkamSymmetricKey`, and
     `enrollmentId`.
   - **Typed-keys** (`"version": 1`): adds `atsign` and two containers
     of typed key materials, while the legacy fields stay flat at the
     top level — a typed-keys file's legacy portion is byte-identical to
     a legacy-only file, so legacy readers can still use it.
     - `enrollments` — one entry per enrollment, carrying its
       `enrollmentId`, an optional `namespaces`/`appName`/`deviceName`
       snapshot of its enrollment record, and its own `keys` array.
     - `atsignKeys` — a `keys` array for material belonging to the
       atSign rather than to any enrollment: the PQ signing root, an
       nskey private.

     Both group materials by `keyId` with their `keyParts`. A key entry
     carries no `enrollmentId` — its container states the owner once — so
     **a keyId is unique within its container, not across the document**:
     two enrollments may each hold `auth:mldsa65:1`, and identity is
     `(enrollment, keyId)`.

     Structured keyIds are `<role>:<algorithm>:<generation>`
     (`auth:mldsa65:1`, `sign:rsa2048:1`, `root:mldsa65:1`), the
     generation counted per role and algorithm. An entry addressed by a
     kid — a key package's, whose id is a digest of the key itself —
     keeps that kid.

     ⚠️ A `"version": 1` document carrying a top-level `keys` array is an
     older shape and is **refused**, naming itself, rather than read as a
     legacy-only file. Nothing released ever wrote one.

In memory, `AtKeys` always holds plaintext; all three layers are applied
and peeled exclusively by `FileAtKeysIo`.

Persistence has three verbs:

- `write(atsign, atKeys)` — create-only initial persist (fresh onboard);
  throws if the file already exists.
- `update(atsign, mutate)` — **the one to reach for when adding key
  material.** It reads, applies your mutation and persists as a single
  operation, holding the keyfile lock across all three steps. The callback
  returns whether anything changed, so finding the material already there
  costs no write:

  ```dart
  await atKeysIo.update(atSign.toAtsign(), (keys) {
    if (keys.getKey(enrollmentId, keyId,
            CryptographicMaterialRole.privateDecapsulation) !=
        null) {
      return false; // already filed; nothing to write
    }
    keys.addKey(material);
    return true;
  });
  ```

  The lookup takes the enrollment because identity is `(enrollment, keyId)`.
  For material the **atSign** owns rather than any one enrollment — the
  signing root, an nskey private — the sibling is `getAtSignKey(keyId, type)`.
  `addKey` is deliberately not split: a material states its own owner through
  its `enrollmentId`, and a null one routes it to the atSign's container.

- `flush(atsign, atKeys)` — persist the current in-memory state. If the
  file exists, `flush` first validates that nothing it holds would be lost
  (key material is never removed — a key's `status` may only move forward,
  `active` → `retired` → `dead`), then rewrites it; flushing a legacy
  file upgrades it in place to a typed-keys document. If the file does
  not exist, `flush` creates it.

**Do not hand-roll `read` → mutate → `flush`.** Those three steps
interleave: two callers running concurrently both read the same state, and
the second's `flush` presents a candidate missing the first's addition.
`flush` is right to refuse it — nothing may be lost — so what you get is a
thrown assurance exception and one addition silently gone. Preventing that
is what `update` is for, and the lock it takes serialises coroutines inside
one process as well as separate processes. For the same reason `update`
must never be nested, and `flush` must not be called from inside one: the
lock is not reentrant.

All three verbs write atomically (write-to-temp + rename), so a crash
mid-write can never truncate the keyfile, and a rewrite over an existing
file first preserves the previous state as `<file>.bak` alongside it.

## Where to go next

| If you're building…            | Use                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| A CLI or server app            | [`at_onboarding_cli`](../at_onboarding_cli) + [`at_cli_commons`](../at_cli_commons)   |
| A Flutter app                  | [`at_client_flutter`](../at_client_flutter) — includes pre-built onboarding widgets   |
| Anything that reads/writes data after auth | [`at_client`](../at_client)                                               |

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
