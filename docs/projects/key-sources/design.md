# Key sources: protecting atKeys at rest on every platform

A design for separating where an atSign's keys are kept from what unlocks
them, so that a headless daemon, a desktop CLI, a Flutter app and a browser can
each protect the same atKeys document with whatever their platform offers: a
TPM, a systemd credential, a cloud KMS, the OS keychain, DPAPI, or a passkey.

## Status

Draft, 2026-09-29. Nothing here is built, and none of it is ruled. The
measurements in [section 3](#3-measurements) were taken on 2026-09-28 and
2026-09-29 with the probes in [`probes/`](probes/), and each one names the
probe that reproduces it. Claims not yet measured are marked as such, and
[section 10](#10-open-questions-and-probes-still-to-run) lists what would
settle them.

## Table of contents

- [1. The problem](#1-the-problem)
- [2. What exists today](#2-what-exists-today)
- [3. Measurements](#3-measurements)
- [4. The split: a store and a key source](#4-the-split-a-store-and-a-key-source)
- [5. Envelope version 2](#5-envelope-version-2)
- [6. Key sources by platform](#6-key-sources-by-platform)
- [7. Headless daemons, end to end](#7-headless-daemons-end-to-end)
- [8. The browser](#8-the-browser)
- [9. What this does not protect](#9-what-this-does-not-protect)
- [10. Open questions and probes still to run](#10-open-questions-and-probes-still-to-run)

## 1. The problem

An atKeys document holds an enrollment's private keys, and whoever reads it
can act as that enrollment. Protecting it means encrypting it, and encrypting
it moves the problem to whatever holds the decryption key. A person can hold
that in their head as a passphrase, but a daemon that has to start unattended
can't, so at some layer the machine itself holds the first secret. The
industry calls this the *secret zero* problem, and the accepted practice is to
put that first secret somewhere hard to extract rather than to pretend it can
be avoided.

A passphrase stored next to the file it protects adds nothing, since whoever
can read one can read the other.

## 2. What exists today

The stores implement `WrittenAtKeysIo` in
`packages/at_auth/lib/src/keys/io/at_keys_io.dart`, whose contract is a
create-only `write`, a `flush` that must never lose material already stored,
and an `update` that reads, mutates and writes as one operation.

| Store              | Where                                                       | How it meets the contract                                                                                                                                                                               |
| ------------------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FileAtKeysIo`     | at_auth, `lib/src/keys/io/file_io.dart`                     | an inter-process lock file around `flush` and `update`, write-to-temp then rename, a rolling `.bak`, a one-off `.pre-v1` copy, and an optional passphrase envelope                                      |
| `KeychainAtKeysIo` | at_client_flutter, `lib/src/keychain/keychain_io_impl.dart` | built on the `biometric_storage` Flutter plugin; one entry per app package holding every atSign, split into 2,560-byte segments on Windows; no lock, and `update` is the interface's non-atomic default |
| `InMemoryAtKeysIo` | at_auth                                                     | process-local, for tests                                                                                                                                                                                |

Four facts shape the design.

The passphrase envelope in
`packages/at_auth/lib/src/keys/serialization/passphrase_envelope.dart` is
unauthenticated. Version 1 derives an AES-256 key with Argon2id over a random
salt and encrypts with AES-256-CTR, and its own dartdoc says a wrong passphrase
"yields arbitrary bytes, and the JSON parse is what rejects them". Tampering
isn't detected either.

The keychain store can't be used by a pure-Dart CLI, because
`biometric_storage` is a Flutter plugin.

The retrofit lock assumes that only a file can be shared.
`fileRetrofitSerializer` in
`packages/at_auth/lib/src/enroll/file_retrofit_serializer.dart` locks only a
`FileAtKeysIo`, and runs any other store unserialised because it "is
process-local by construction". An OS keychain or an atServer-held blob is
shared between processes, so any new shared store has to bring its own lock and
have the serialiser use it.

A legacy enrollment holds atSign-wide decryption keys. The approver encrypts
the atSign's default encryption private key and self-encryption key for the new
enrollment (`enrollment_approver.dart`, around line 55), and the enrollee's
handshake fetches and files them (`enrollment_handshake.dart`, lines 99 to
134). So one compromised enrollment can decrypt data for the whole atSign, not
only its own namespaces. The post-quantum per-namespace keys are the structural
answer to that, and they are outside this design's scope.

## 3. Measurements

### macOS login keychain

Taken on macOS 26.5.2, arm64, with Dart 3.13.3. The probe is a Dart FFI program
that calls Security.framework with user interaction disabled, so that a read
which would raise an access dialog returns an error instead. Reproduce with
[`probes/macos_keychain/run.sh`](probes/macos_keychain/run.sh).

| Arm                                                                                      | Result                                                     |
| ---------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Read before the item exists (negative control)                                           | `-25300`, item not found                                   |
| An AOT binary stores 16,384 bytes and reads its own item                                 | `0`, content identical                                     |
| A different binary reads that item                                                       | `-25293`                                                   |
| The same program, rebuilt at the same path, reads it                                     | `-25293`                                                   |
| An item created with `security add-generic-password -A` (any app), read by both binaries | `-25293`                                                   |
| `security -i` given the 16,384-byte value on stdin                                       | stores 4,032 of 32,768 hex characters and reports no error |
| `/usr/bin/security` writes the value as an argument and reads it back                    | identical                                                  |
| Our binary reads the item `/usr/bin/security` created                                    | `-25293`                                                   |

`dart compile exe` produces ad-hoc signed binaries with no team identity, so
macOS treats every build as a new program. Direct Security.framework access
therefore doesn't survive an upgrade, and doesn't cross from one CLI to
another. The refusal of the any-app item shows the per-app access list isn't
the only gate. The likeliest second gate is the keychain's partition list,
which records the signer that created an item, and the login keychain here
does carry `partition_id` records, but I haven't confirmed that mechanism for
these items. Routing every read and write through `/usr/bin/security` does
work across binaries, at the cost of putting the value on the command line or
feeding it through stdin in lines of under about 4 KB.

### Linux Secret Service

Taken in a `debian:bookworm-slim` container with `libsecret-tools` and
`gnome-keyring`. Reproduce with
[`probes/linux_secret_service.sh`](probes/linux_secret_service.sh).

| Arm                                                                   | Result                                                                 |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Store with no session bus, the daemon case                            | refused: "Cannot autolaunch D-Bus without X11 $DISPLAY"                |
| A private session bus and a keyring unlocked with a supplied password | stores, but `secret-tool` keeps 8,192 of 32,768 characters and exits 0 |
| A fresh session with the keyring unlocked again                       | the item is still there                                                |

A headless daemon would have to supply the keyring's password at every start,
which moves the secret rather than protecting it.

### systemd credentials sealed to a TPM

Taken in a `debian:trixie` container with systemd 257 and `swtpm`, a software
TPM. Reproduce with
[`probes/systemd_creds_swtpm.sh`](probes/systemd_creds_swtpm.sh).

| Arm                                              | Result                                                               |
| ------------------------------------------------ | -------------------------------------------------------------------- |
| Seal 16,384 bytes to TPM A, unseal on TPM A      | identical; the sealed blob is 22,652 bytes                           |
| Unseal the same blob on TPM B (negative control) | refused, "Failed to unseal secret using TPM2", nothing written       |
| Seal and unseal with the host key only           | identical; relies on `/var/lib/systemd/credential.secret`, mode 0400 |

The software TPM has no boot measurements, and systemd warned that the PCR
policy was "effectively unenforced". Binding to a machine is shown here, but
binding to its boot state is not.

### What a systemd service receives

Taken on an Ubuntu VM, first on 22.04 with systemd 249 (plain
`LoadCredential=`, reproduce with
[`probes/systemd_load_credential.sh`](probes/systemd_load_credential.sh)),
then on the same VM upgraded to 24.04.5 with systemd 255
(`LoadCredentialEncrypted=` with the host key, reproduce with
[`probes/systemd_load_credential_encrypted.sh`](probes/systemd_load_credential_encrypted.sh)).
Both scripts are fed to the host with `ssh <host> 'bash -s' < script`, need
passwordless `sudo`, and remove what they create.

| Property                                | systemd 249, `LoadCredential=`            | systemd 255, `LoadCredentialEncrypted=`                                                             |
| --------------------------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Content at service start                | 16,384 bytes, identical                   | 16,384 bytes, identical                                                                             |
| Filesystem                              | ramfs                                     | tmpfs                                                                                               |
| Permissions                             | directory 0500, file 0400                 | directory 0500, file 0400                                                                           |
| Mount options                           | `ro,nosuid,nodev,noexec`                  | `ro,nosuid,nodev,noexec,nosymfollow`                                                                |
| Append, replace or create beside it     | refused, "Read-only file system", as root | refused, "Read-only file system", as root                                                           |
| After the service stops                 | removed                                   | removed                                                                                             |
| One byte of the blob flipped            | not applicable                            | the service doesn't start: "Failed to set up credentials: Protocol error", status `243/CREDENTIALS` |
| `--with-key=tpm2` on a host with no TPM | not applicable                            | refused, "Failed to create TPM2 context"                                                            |

A systemd credential is a read-only, per-service copy that disappears at stop.
That suits a key, but it can't carry the atKeys document itself, because the
client writes to its keys while running: `flush` and `update` file namespace
keys, signing keys and retrofit results.

A container running systemd under Docker Desktop on macOS couldn't deliver any
credential to a service, not even an inline `SetCredential=` value, and
systemd logged "failed to open credentials directory". That result is about
the container, not about systemd, and it's why the service rows come from a
VM.

## 4. The split: a store and a key source

The store keeps the whole document, with its locking and backups, as the
stores do today. A key source wraps and unwraps a 32-byte data key and never
sees the document. The store encrypts the document with a fresh data key and
asks the key source to wrap that data key; on read it asks for the data key
back.

```dart
/// Wraps and unwraps a document's data key; never sees the document.
abstract interface class AtKeysKeySource {
  /// Recorded in the envelope, so a reader knows which source to ask.
  String get id;

  Future<WrappedKey> wrap(Uint8List dataKey, {required String atSign});

  Future<Uint8List> unwrap(WrappedKey wrapped, {required String atSign});
}
```

The interface is wrap and unwrap rather than "return the key", so a source
whose key can't be exported still fits: a TPM, a cloud KMS, or a
non-extractable WebCrypto key. `FileAtKeysIo(passPhrase: …)` keeps working as
shorthand for a passphrase source, since apps outside this repository call it.

## 5. Envelope version 2

```json
{"v": 2, "alg": "AES-256-GCM", "iv": "<base64, 12 bytes>",
 "content": "<base64 ciphertext and tag>",
 "keys": [{"source": "systemd-credential", "ref": "atkeys-kek",
           "wrapped": "<base64>"}]}
```

The content is encrypted with AES-256-GCM, with the atSign, the enrollment id
and the version bound in as associated data, so a tampered, truncated or
swapped document fails to decrypt rather than failing to parse.

`keys` is a list, so one data key can be wrapped by more than one source: a
machine's TPM and a recovery passphrase, say, or two devices sharing a
document. Changing or adding a source rewraps 32 bytes and leaves the content
alone.

Readers accept all three shapes: the legacy unsalted form, version 1 and
version 2. Writers produce version 2 only when a key source is configured. With
none, the file stays plaintext, as it does today, which is the right baseline
for a daemon that has nowhere better to keep a key (see
[section 7](#7-headless-daemons-end-to-end)).

## 6. Key sources by platform

| Platform                | Key source                                                                                                                                                                 | Measured?                                                                                                      |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Linux daemon            | a 32-byte key sealed with `systemd-creds` (TPM where there is one, the host key where not), delivered by `LoadCredentialEncrypted=` and read from `$CREDENTIALS_DIRECTORY` | yes, see [section 3](#3-measurements)                                                                          |
| Container or Kubernetes | a key in an environment variable or a mounted secret; read-only injection suits a key, and not the writable document                                                       | no                                                                                                             |
| Cloud VM                | a cloud KMS (AWS, GCP or Azure) wraps and unwraps, and the instance's cloud identity is the first secret                                                                   | no; a daemon would then need the KMS reachable to start                                                        |
| macOS desktop           | a 32-byte key in the login keychain, written and read through `/usr/bin/security`                                                                                          | yes: works across binaries, and a 64-character value is far below the line limit that truncated the 16 KB test |
| Windows                 | DPAPI (`CryptProtectData`), scoped to the user or the machine                                                                                                              | no                                                                                                             |
| Browser                 | a passkey's PRF output, or a non-extractable WebCrypto key; see [section 8](#8-the-browser)                                                                                | no                                                                                                             |

The keychain row holds a key rather than the whole document, which avoids the
size limits, the Windows segmenting and both truncations measured in
[section 3](#3-measurements). The document stays a file, so the lock file,
backups, `at_activate decrypt` and copying keys between machines keep working.

## 7. Headless daemons, end to end

The baseline needs nothing new: a dedicated service user, a 0600 keyfile with
no passphrase stored beside it, and one enrollment per daemon with the
narrowest namespaces it needs. That's how `sshd` protects its host keys, and it
stops other users on the machine. It doesn't stop someone holding a copy of the
disk or a backup.

The protected form adds a key source. A command such as
`at_activate keys protect --with systemd-credential` would generate a key, seal
it with `systemd-creds encrypt --with-key=tpm2` (or the host key where there's
no TPM), rewrite the keyfile as version 2, and print the
`LoadCredentialEncrypted=` line for the unit. At start the daemon reads the key
from `$CREDENTIALS_DIRECTORY` and unwraps the data key, and every `flush` and
`update` re-encrypts. The existing lock file still serialises writers, and
`fileRetrofitSerializer` still recognises the store as a file.

A copy of the disk or a backup then yields nothing, because the key is sealed
to that machine's TPM. With the host key only, it yields nothing to someone who
lacks `/var/lib/systemd/credential.secret`, and systemd warns when that file
isn't on encrypted storage.

For daemons, re-enrolling beats a recovery wrap. A lost TPM or host key then
means approving a new enrollment, rather than keeping a second secret
somewhere.

## 8. The browser

A web page can't reach the OS keychain or the TPM directly. Its only route is
WebAuthn, and WebAuthn signs but doesn't decrypt, so a private key held in the
authenticator can't unwrap anything for the page. What it can do is the PRF
extension: the authenticator holds a secret per passkey and, after a
fingerprint or PIN, returns an HMAC of a salt the page supplies. The same salt
gives the same 32 bytes every time. The secret never leaves the authenticator,
and only the derived value reaches the page, during unlock.

The plan builds on that. The browser's atKeys document is kept on the atServer
as a version 2 envelope, and the passkey's PRF output, run through HKDF, is its
key source. Clearing the browser then loses nothing, and any device holding the
passkey can recover it. The key is symmetric, which also matters here: a blob
held long-term on a server under an RSA or elliptic-curve wrap is what "harvest
now, decrypt later" targets, and an HMAC-derived key is already post-quantum.

Passkeys synced through iCloud Keychain or Google Password Manager give the
same key on every synced device. That's convenient, but it makes the passkey
provider part of the trust base, and it blurs one enrollment per device unless
each device has its own passkey and its own document.

The browser has to fetch the document before it holds a PKAM key, so the fetch
needs a gate of its own. There are two, and they can be combined.

The first is a record whose name is derived from the passkey, for example
`public:_<HKDF(prf, "atkeys-record-id")>`, domain-separated from the
`HKDF(prf, "atkeys-kek")` that encrypts it. On at_server trunk (`47a6a978`,
`scan_verb_handler.dart`), a scan hides every `public:_` key from other atSigns
and from the owner, and `showhidden:true` re-admits only `public:__` and `_`
keys. So the record can't be listed, and it can only be fetched by someone who
already knows its 256-bit name. That hides the record's existence, size and
update times, and denies an attacker the ciphertext. It's a secret that
travels, though: the name appears in every `lookup:` and in logs that record
keys, and changing it means moving the record. It's safe only because the
encryption key is high-entropy. The same scheme with a passphrase-derived key
would invite offline guessing.

The second is a trusted device, and the shape suggested here is an enrollment
whose credential is the passkey. The atServer verifies a WebAuthn assertion
where it would otherwise verify a PKAM signature, and that enrollment's
permissions allow reading the one record. This reuses enrollment, approval,
permissions and revocation, so revoking the device stops the fetch, and the
record can be private rather than public. A metadata attribute restricting who
may fetch a public record would have to be honoured on every path that serves
public data, including plookup and the caches other atServers keep, on every
atServer implementation. The cost of the enrollment route is that every
atServer implementation has to verify WebAuthn assertions: `clientDataJSON`,
`authenticatorData`, the origin and relying-party id, and ES256 signatures. The
per-connection challenge from `from:` already covers replay.

Updating the document needs the same atomicity `update` has for a file. I
haven't checked whether the atServer offers anything like a compare-and-swap,
and without one two browsers updating at once could lose a write.

This fits the WASM plan's key-material gates X-K1 to X-K4 in
[`../wasm/acceptance.md`](../wasm/acceptance.md#9a1-confidentiality--key-material-new-the-existing-key-gates-measure-only-time),
which were written for a non-extractable WebCrypto key in IndexedDB. That key
remains a reasonable local cache or a fallback where PRF isn't available, but
code on the page can use it while the page is open, and IndexedDB can be
evicted unless the site holds persistent storage.

## 9. What this does not protect

A running daemon holds its unwrapped keys in memory, so root on that host, or
anything that can read the process, has them. In a browser, script running on
the page's origin can use the key while the page is open. And none of it
narrows what one enrollment can decrypt: as
[section 2](#2-what-exists-today) shows, a legacy enrollment carries the
atSign-wide encryption keys.

## 10. Open questions and probes still to run

| Question                                                                                                               | How to settle it                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Is the partition list what refuses the macOS reads?                                                                    | Inspect a probe item's partition list without a dialog, or sign the probe with a stable Developer ID and repeat the arms |
| Does a stable Developer ID signature let direct Security.framework access survive rebuilds?                            | The macOS arms with a signed binary                                                                                      |
| Does DPAPI behave as expected for a service account?                                                                   | A Windows probe, which hasn't been run                                                                                   |
| Does a real TPM bind the seal to the boot state?                                                                       | `systemd-creds` on hardware with a TPM, with a PCR policy                                                                |
| Does Chrome support the PRF extension with Google Password Manager passkeys, and give the same output across sessions? | A localhost page in Chrome that creates a passkey with PRF and derives twice                                             |
| Does a non-extractable WebCrypto key survive reload, restart and storage pressure in Chrome and Safari?                | The WASM plan's X-K2 to X-K4                                                                                             |
| Does a `public:_` record's name reach the owner's other clients through sync, or the commit log?                       | Read the atServer and at_client sync paths                                                                               |
| Can the atServer update a record conditionally?                                                                        | Read the update verbs on every atServer implementation                                                                   |
