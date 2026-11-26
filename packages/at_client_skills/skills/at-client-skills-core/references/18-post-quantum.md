# Post-Quantum Posture

How far into post-quantum cryptography a client runs is its **posture**, set
by `AtClientPreference(posture: ...)` and fixed when the preference is built.

**A new app names `PqPosture.pqActive`** and sets `namespace`. The SDK's
default is `legacy` (and may change in a later release), so a preference that
names no posture builds an app that encrypts the old way — and nothing fails
to tell you. A brand-new app has no older clients to wait for, so it goes
straight to `pqActive`; the two-step move below is only for an app already
deployed on legacy.

---

## The postures

| Posture                          | Writes                                  | Reads post-quantum data | Needs                                                                       |
| -------------------------------- | --------------------------------------- | ----------------------- | --------------------------------------------------------------------------- |
| `PqPosture.legacy` (the default) | legacy encryption                       | no                      | nothing new                                                                 |
| `PqPosture.pqReady`              | legacy, so every peer can read it       | yes                     | an atServer that verifies ML-DSA-65 signatures                              |
| `PqPosture.pqActive`             | post-quantum; a legacy write is refused | yes                     | every client of its namespaces on `pqReady` or later first; `namespace` set |

The at_client README's "Post-quantum cryptography" section has the full
ladder and what each stage switches on.

## Moving an existing app

An app built on at_client 3.x, whose data is legacy-encrypted, moves in two
steps: rebuild it with `PqPosture.pqReady` and roll that out to every client,
then rebuild it with `PqPosture.pqActive` and roll that out.

## The floor

A client never runs below its floor. A keyfile holding a namespace key's
private sets `pqReady`; an ML-DSA-65 data signing key sets `pqActive`.
Configured lower, the client logs a warning and is raised on authentication,
data signing, and reading and writing post-quantum. It seeds no namespace keys
and mints no signing root that its configured posture would not, and
`disallowLegacyEncryption` stays as configured.

## The keyfile changes after first use

Under `pqReady` or `pqActive`, start-up files each namespace key's private in
the atsign's keys: it rewrites a `.atKeys` file in place, or updates the
keychain entry. Later writes there record rotations and retired keys. So the
keys are state the client keeps, not a fixed credential.

- **Never put an earlier copy back.** A copy made before the client first
  started in a namespace lacks that namespace key's private, while the
  atServer still advertises its public half. Writes in that namespace then
  throw `NskeyPrivateNotHeldException`, unless another of the atsign's devices
  holds the private and conveys it. That includes a keyfile restored from
  source control, a test fixture copied over the file before each run, and a
  backup saved when the atsign was activated.
- **Back up after first use.** A copy taken after the app has started once in
  each namespace it writes holds those privates. A test copies its fixture to
  a fresh path for each run, against a fresh atServer, and never back.
- **Files beside it.** Each write keeps the previous file as `<file>.bak`,
  replaced by the next write. Upgrading a keyfile from the older flat format
  keeps the original once as `<file>.pre-v1`, the only copy older builds can
  read.

## Running at `pqActive`

- **Namespaces.** A client whose enrollment is granted `*` holds a namespace
  key only for `preference.namespace`; with none set it has nothing to write
  with. A collection's namespace therefore ends with `.` and
  `preference.namespace` (`'todos.my_app'` under `my_app`), or a namespace its
  enrollment is granted. In any other namespace the client's start-up
  publishes no key, and the first write throws
  `NamespaceKeyUnavailableException`.
- **Right after open.** A write made before start-up has published the
  namespace key waits up to 30 seconds for it, then throws
  `NamespaceKeyUnavailableException` naming that key. One made while start-up
  is yet to ask, or is asking, the atsign's other enrollments for the key's
  private waits up to 30 seconds in all for the answer, then throws
  `NskeyPrivateNotHeldException`.
- **Offline.** A device's first write in a namespace needs the atServer, which
  seeds or conveys that namespace's key, and a share needs it whenever the
  client holds no current copy of the recipient's key. Once a device has
  written in a namespace, it goes on writing there offline, across restarts.
- **Shares.** A share is sealed to each recipient's namespace key. A recipient
  that has published none makes `create`, `upsert`, `update` or
  `updateSharedWith` throw `CollectionOpException`, whose failure is a
  `NamespaceKeyUnavailableException` naming them;
  `CryptoRuntime(atClient).isReadyFor(recipient, namespace)` asks first. A
  share is sealed to the most specific key the recipient advertises for the
  key's whole name; `PutRequestOptions.sealToNamespace` requires one
  namespace, and `CryptoRuntime(atClient).canSealTo(recipient, namespace)`
  asks whether the recipient advertises a key there; it never throws, and
  answers false, with a warning, when it cannot tell.

## Mixed fleets

A program whose peers are a mixed fleet, some advertising a namespace key and
some not, builds `PqPosture.pqActive.copyWith(disallowLegacyEncryption:
false)` and sets `allowLegacyCryptoFallback`: each send requires the peer's
namespace with `sealToNamespace`, and a peer advertising nothing there gets
legacy encryption. A `pqReady` client with `allowLegacyCryptoFallback` can
instead ask `canSealTo` before each send and send with `sealToNamespace` where
it answers true: with no `cryptoProviderId`, `sealToNamespace` selects the
namespace-key provider wherever the client's config registers it, as
`pqReady` and above do.

## Approving enrollments

An approver runs post-quantum too: see
[15-client-lifecycle.md](15-client-lifecycle.md) (section 8).
