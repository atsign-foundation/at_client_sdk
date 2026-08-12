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
| Free atSign registration        | `RegistrarService` (fetches CRAM key by email)         |

See [`example/onboard.dart`](example/onboard.dart),
[`example/authenticate.dart`](example/authenticate.dart), and
[`example/enrollment_request.dart`](example/enrollment_request.dart) for
end-to-end usage.

## Two barrels: `at_auth.dart` and `at_auth_web.dart`

| Barrel              | Contains                                                                                     |
| ------------------- | -------------------------------------------------------------------------------------------- |
| `at_auth.dart`      | **Import this.** The whole package: everything below **plus** `FileAtKeysIo` and `secureSocketProbe`, both wired up as defaults |
| `at_auth_web.dart`  | The platform-neutral subset, naming no `dart:io` type — `AtAuth`, `AtEnrollment`, `AtKeys`, the `AtKeysIo` interfaces, `InMemoryAtKeysIo`, serialization, the session models, `RegistrarService` |

Ordinary use needs nothing extra — `at_auth.dart` behaves as it always has:

```dart
import 'package:at_auth/at_auth.dart';

final atAuth = AtAuth.create();
final request = AtOnboardingRequest('@alice')
  ..atKeysIo = FileAtKeysIo(filePath: (_) => '/path/to/@alice_key.atKeys');
```

**Building for the web** (dart2wasm or dart2js)? Import `at_auth_web.dart`
instead. It is a *narrowing*, not a different API: code written against it runs
unchanged on native. Two things it cannot give you, because a browser has neither
a filesystem nor a raw socket:

| Omitted             | Consequence on web                                                                 |
| ------------------- | ----------------------------------------------------------------------------------- |
| `FileAtKeysIo`      | `onboard()` has no default key store, so set `AtOnboardingRequest.atKeysIo` yourself — `InMemoryAtKeysIo` is exported from both barrels |
| `secureSocketProbe` | `validateAtServer` still polls the atDirectory but does not wait for the atServer to start listening; it logs a warning saying so |

Both have platform-conditional defaults inside `AtAuthImpl`
(`src/io/defaults_io.dart` / `defaults_stub.dart`, selected with
`if (dart.library.io)`), so native callers get them without asking.

Two caveats worth knowing. The split is held by **barrel discipline, not by the
compiler**: `dart compile wasm` accepts `dart:io` and defers the failure to a
runtime `UnsupportedError`, so importing `at_auth.dart` in a browser build
compiles clean and then throws the first time a file or socket is touched. And
this does not yet make at_auth *run* on the web — `at_lookup`'s socket transport
still needs porting. See
[`docs/projects/wasm/plan.md`](../../docs/projects/wasm/plan.md).

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
[`lib/src/registrar/`](lib/src/registrar)). It talks to the registrar over
`package:http` and validates the registrar's TLS certificate; pass your own
`httpClient` if you need to reach a registrar with an untrusted certificate.

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

`FileAtKeysIo` (from `at_auth.dart`) reads and writes `.atKeys` files
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
   - **Typed-keys** (`"version": 1`): adds `atSign` and a `keys` array
     of typed key materials (grouped by `keyId` with their `keyParts`),
     while the legacy fields stay flat at the top level — a typed-keys
     file's legacy portion is byte-identical to a legacy-only file, so
     legacy readers can still use it.

In memory, `AtKeys` always holds plaintext; all three layers are applied
and peeled exclusively by `FileAtKeysIo`.

Persistence has two verbs:

- `write(atsign, atKeys)` — create-only initial persist (fresh onboard);
  throws if the file already exists.
- `flush(atsign, atKeys)` — persist the current in-memory state (e.g.
  after `AtKeys.addKey` or `AtKeys.retireKey`). If the file exists,
  `flush` first validates that nothing it holds would be lost (key
  material is never removed — a key's `status` may only move forward,
  `active` → `retired` → `dead`), then rewrites it; flushing a legacy
  file upgrades it in place to a typed-keys document. If the file does
  not exist, `flush` creates it.

Both verbs write atomically (write-to-temp + rename), so a crash mid-write
can never truncate the keyfile, and a `flush` over an existing file first
preserves the previous state as `<file>.bak` alongside it.

## Where to go next

| If you're building…            | Use                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| A CLI or server app            | [`at_onboarding_cli`](../at_onboarding_cli) + [`at_cli_commons`](../at_cli_commons)   |
| A Flutter app                  | [`at_client_flutter`](../at_client_flutter) — includes pre-built onboarding widgets   |
| Anything that reads/writes data after auth | [`at_client`](../at_client)                                               |

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
