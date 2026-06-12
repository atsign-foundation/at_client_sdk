# Encryption / decryption roadmap

Where the SDK's encryption and decryption are headed, in seven steps. Each
step is a separately reviewable PR (or small PR series); the dependency
graph is at the end.

| Step | Deliverable                                          | Status                       |
|------|------------------------------------------------------|------------------------------|
| 1    | Same-atSign secret sharing between clients           | Done — PR #1976              |
| 2    | Pluggable encrypt/decrypt (`CryptoProvider`)         | Branch `xl-pluggable`        |
| 3    | Rotating-key `CryptoProvider` built on steps 1+2     | Designed (below)             |
| 4    | Post-quantum primitives in at_chops                  | Branch `jt-pq` + follow-up   |
| 5    | Step 1 made post-quantum-safe                        | Designed (below)             |
| 6    | Step 3 made post-quantum-safe                        | Mostly falls out of 3+5      |
| 7    | pq-mls `CryptoProvider` (self AND shared encryption) | Research done; engine TBD    |

## 1. Same-atSign secret sharing — done (PR #1976)

Multiple clients of one atSign (same or different APKAM enrollments) share
secrets pairwise so that only the target *client* can read them. The pieces,
all in `packages/at_client/lib/src/secret_sharing/`:

- **Per-client identity**: random clientId + keypair; APKAM-signed
  `ClientKeyBundle` published as a hidden public key in the enrollment's
  reserved namespace (location exclusivity = identity anchor), plus
  namespace-scoped cleartext self-key copies whose *presence* proves the
  enrollment holds `rw` on that namespace (server-enforced).
- **Envelopes**: content key wrapped to the recipient's bundle key, payload
  encrypted, envelope APKAM-signed; stored as self keys whose names end with
  the application namespace, so the atServer's enrollment authorization
  scopes delivery with no server changes.
- **SecretStore** keyed `(namespace, name)`, newest-`createdAt`-wins on
  receive; approver-side `shareAllSecretsWithEnrollment` shares held secrets
  with a newly approved enrollment's clients, filtered by its approved
  namespaces.
- **Crypto agility**: bundles carry `{kid, use, alg, pub}` key lists;
  envelopes carry `{keyAlg, kid, encAlg}`. Algorithms are ids in
  `SecretSharingAlgos` (`rsa-2048` + `aes-256-ctr` today); readers skip
  unknown ids, senders pick the best mutually-supported one. This is what
  makes steps 5 and 6 small.

## 2. Pluggable encrypt/decrypt — `CryptoProvider` (branch `xl-pluggable`)

`CryptoProvider { id; initialize(CryptoContext); encrypt; decrypt }`,
registered per AtClient via `CryptoConfig` in `AtClientPreference`, routed by
`CryptoRuntime` on the put/get/notify/sync paths. The wire carries
`Metadata.appMetadata = AppMetadata{providerId, additional}` — `providerId`
routes decryption to the right provider; `additional` is provider-owned
opaque metadata. `LegacyCryptoProvider` (`'legacy'`) preserves today's
behavior; `CryptoStorage` gives providers secondary-backed key persistence.

**Merge checklist** (coordination with PR #1976, both touch the get path):

- Preserve the `isEncrypted` tri-state semantics (PR #1976 commit
  `a6f3a013d`) when `get_response_transformer.dart` is rewritten to route
  through `CryptoRuntime`: explicit `false` on the wire skips decryption
  entirely; absent (legacy data) takes the try-decrypt fallback, which moves
  inside `LegacyCryptoProvider`.
- `PutRequestOptions.shouldEncrypt = false` must remain a no-crypto path:
  secret-sharing envelopes and bundle copies are stored that way (their
  values are already end-to-end encrypted or deliberately cleartext).

## 3. Rotating-key `CryptoProvider`

Provider `id: 'rotating'`: encrypts app data under per-scope **epoch keys**,
distributing the epoch keys to the atSign's other clients via step 1.
Self-encryption only at first (the substrate is same-atSign); cross-atSign
keys keep routing to `'legacy'`.

- **Scope = (atSign, namespace)** — the substrate's authorization unit, so
  the atServer's enrollment namespace checks bound who can ever receive a
  scope's keys. `RotationPolicy{maxEpochAge?, rotateOnRevocation, manual}`;
  time-based rotation enforced lazily at encrypt time. No scheduler, no
  leader.
- **Wire metadata**: `AppMetadata(providerId: 'rotating', additional:
  {scope, epoch, kid, enc, iv})`. **`kid` is the truth, `epoch` an ordering
  hint**: two clients may concurrently rotate and both mint "epoch N+1";
  both keys survive under distinct `kid`s and every ciphertext stays
  resolvable. No coordination protocol needed.
- **Epoch keys are Secrets** in the scope's namespace: immutable
  `__rk.<epoch>.<kid>` entries plus one mutable pointer `__rk.current`,
  which converges via the store's newest-`createdAt`-wins rule.
- **Rotation** (any client): mint key → `putSecret` both entries →
  `discoverClients(namespace: scope)` → `shareSecretWith` each bundle.
- **Missing-key recovery is pull**: send a `kind:'request'` envelope
  (`{wants: 'secrets', namePrefix: '__rk.'}`) to namespace clients; holders
  respond via `shareSecretWith`; the decrypt path awaits `waitForSecret`
  and, on timeout, throws a typed key-unavailable error.
- **Revocation**: app revokes enrollment E, then
  `rotate(scope, excludeEnrollmentIds: {E})` for each scope E could access.
  Revoked bundles stay published until TTL, so the exclusion filter is
  mandatory. Rotation protects future writes; old epochs the revoked client
  already holds are not retroactively protected.

Substrate additions this step needs (deliberately not in PR #1976):
`kind:'request'`/`'response'` envelope flow with an answer policy;
`onNewClientDiscovered` roster watch; `excludeEnrollmentIds` filters on
discovery/sharing; `SecretStore.listSecrets(namePrefix:)`; and on the
step-2 side a `CryptoPolicy.onDecryptFailed` hook.

## 4. Post-quantum primitives

Merge `jt-pq` (ML-KEM-768 and X25519, pure-Dart + OpenSSL-FFI variants, the
`AtKemAlgorithm` interface, in at_chops). Then one at_chops PR adds:

- **X-Wing hybrid KEM** (draft-connolly-cfrg-xwing-kem): X25519 + ML-KEM-768
  with the SHA3-256 combiner; 32-byte seed secret keys expanded via
  SHAKE-256. SHA3/SHAKE come from pointycastle (already a dependency).
  Tests against the draft's vectors.
- **AES-256-GCM AEAD** (via the `cryptography` package, already a
  dependency).

## 5. Secret sharing made post-quantum-safe

The step-1 agility pays off: append `x-wing-<draft>` to
`SecretSharingAlgos.keyAlgos` and `aes-256-gcm` to `encAlgos`;
`registerClient` adds an X-Wing `BundleKey` beside the `rsa-2048` one
(bundles already carry key lists, so rotation overlaps); the envelope's
`encryptedKey` field carries the KEM encapsulation ciphertext. No schema,
key-shape, or server change. Envelope signing stays RSA-APKAM — signatures
are not harvest-now-decrypt-later exposed; a PQ signature suite (ML-DSA) can
slot into the envelope's `signingAlgo` field later if wanted.

## 6. Rotating provider made post-quantum-safe

Nearly free once 3 and 5 exist: epoch-key *distribution* becomes PQ-safe
automatically (it rides step 5), and symmetric encryption is already
PQ-resistant — the provider just moves `additional.enc` to `aes-256-gcm`.
Same provider id; the per-value metadata carries the algorithm change.

## 7. pq-mls `CryptoProvider`

MLS (RFC 9420) with a post-quantum ciphersuite (X-Wing KEM per
draft-mahy-mls-xwing / draft-ietf-mls-pq-ciphersuites), used for both
self-encryption (group = the atSign's clients) and shared encryption
(groups spanning atSigns). Gains over step 6: TreeKEM forward secrecy and
post-compromise security, standardized group semantics.

- **Engine decision required**: the pub.dev `openmls` wrapper already ships
  an experimental X-Wing ciphersuite but is a third-party Rust binary
  dependency (supply-chain and pure-Dart-host caveats); alternatives are an
  Atsign-owned `mls-rs` binding or a pure-Dart implementation (multi-month).
  If a native engine is chosen, ship the provider as a separate package so
  `at_client` stays pure Dart.
- **Within-atSign**: step 1 is the delivery service — bundles act as the
  KeyPackage directory, envelopes carry Welcome/Commit messages, and
  membership follows the enrollment lifecycle (first enrollment creates the
  group; approvers add; revocation removes + rekeys).
- **Cross-atSign**: needs a cross-atSign delivery service (notifications /
  shared keys) and per-atSign KeyPackage discovery — new work, not covered
  by step 1.

## Dependencies

```
1 (done) ──────────┬────────────► 3 ──► 6
2 (xl-pluggable) ──┘                    ▲
                                        │
4 (jt-pq + X-Wing/GCM) ──► 5 ───────────┘

7 ◄── 2 (provider model) + 1 (within-atSign DS) + engine decision
```

Step 2 is independent of step 1 except for the get-path merge checklist
above. Steps 4 and 5 can proceed in parallel with 3.
