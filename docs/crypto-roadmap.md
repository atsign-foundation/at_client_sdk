# Encryption / decryption roadmap

How the SDK moves from the legacy encryption schemes to post-quantum-safe,
group-based encryption with rotating keys — preserving every current
capability (encrypt/decrypt for other clients of the same atSign,
encrypt/decrypt for other atSigns), strengthened with two-lever key
rotation, and giving applications a bootstrap path to pq-mls groups.

Starting point: `trunk`, incorporating and extending three lines of work:

| Work                 | Contributes                                                         | Status                  |
|----------------------|---------------------------------------------------------------------|-------------------------|
| `jt-pq`              | Post-quantum primitives in at_chops (ML-KEM-768, X25519)            | Merged to trunk         |
| `xl-pluggable`       | Pluggable `CryptoProvider` model + wire routing (`AppMetadata`)     | Merged to working branch |
| `gkc-alice-to-alice` | Per-client identity, discovery, and same-atSign delivery + the above | Integration branch    |

### Delivery model

All of this is built and verified **locally first**, end-to-end across the
`at_client_sdk`, `at_server` and `sshnoports` repos, then staged as a
**sequence of independently-reviewable per-package PRs** in dependency order.
`gkc-alice-to-alice` is the at_client_sdk integration branch holding every
package change here; the per-package PR branches are reconstructed from it.
The dependency-ordered sequence: `at_commons` (the `appMetadata` wire field) →
`at_chops` (X-Wing / AES-GCM / key consolidation) → `at_client` (pluggable
crypto + secret sharing). `at_server` must round-trip `appMetadata` before the
at_client crypto path verifies end-to-end, so it lands ahead of or paired with
the at_client PR; `sshnoports` consumes the released SDK and comes last.

## The end state

The organizing idea is that the end state is a *group* abstraction in both
directions: "the clients of @alice" is a group, and "@alice's and @bob's
clients" is a group. Legacy treats self and shared encryption as unrelated
mechanisms; MLS unifies them. So everything becomes a group, with a
deliberately MLS-shaped interim implementation, and "bootstrap to pq-mls"
is an engine swap under a stable interface rather than a redesign.

```
enrollment approval ceremony (human/policy decision)
  └─ APKAM keypair                    (per enrollment — auth + signing root)
      └─ leaf identity                (per client — KeyPackage: KEM init keys + leaf signing key)
          └─ group membership          (per scope — commits)
              └─ epoch secrets         (per group — lever A)
                  └─ exported secrets  (per use — ephemeral)
```

Each tier anchors the one below; rotating a tier invalidates downward,
never upward.

**Two-lever rotation**, independently pullable:

- **Lever A (fast/cheap): data-key epochs.** Rotate the symmetric key a
  group encrypts under — mandatorily on every membership change, by policy
  on time/volume. Pre-MLS: distribute a new epoch key; in MLS: a commit.
- **Lever B (slow/identity): leaf-key rotation.** A client retires its KEM
  or signing keypair and publishes a fresh KeyPackage; peers encapsulate to
  the new key thereafter. In MLS: a leaf Update. Neither lever forces the
  other.

**What becomes obsolete**: `selfEncryptionKey` (one symmetric key for all
self data, held identically by every client, never rotated, re-conveyed to
every new enrollment forever) and the static per-pair `shared_key.bob@alice`
keys. Both are replaced by groups and retire on the four-phase path in
[Retiring selfEncryptionKey](#retiring-selfencryptionkey-and-shared_key).

### Key inventory and rotation

| Key                        | Scope          | Role in the end state                                                       | Rotation                                                                              |
|----------------------------|----------------|------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| APKAM keypair              | per enrollment | atServer auth + trust root for everything the client publishes (`_apsk`)      | Rare; rotation ≈ revoke + re-enroll. Revocation must pull lever A in every group touched |
| Default encryption keypair | per atSign     | Shrinks to enrollment-approval conveyance + legacy interop                    | Rare; blast radius shrinks as legacy data migrates. Gains a PQ sibling (phase 1)         |
| apkamSymmetricKey          | per enrollment | Approval conveyance                                                           | n/a — lives and dies with the enrollment                                                 |
| Leaf KEM init keys         | per client     | The KeyPackage; what others encapsulate to                                    | Lever B, frequent and cheap — scheduled with bundle TTL, after use as join material      |
| Leaf signing key           | per client     | Signs KeyPackages/envelopes (v1: = APKAM key; MLS: per-leaf, APKAM-certified) | Lever B, months / on compromise                                                          |
| Device storage master key  | per device     | Encrypts local dynamic state (epoch table, ratchet state)                     | Local decision, on compromise; re-encrypt local store only                               |
| Group epoch secret         | per group      | Data encryption                                                               | Lever A: every membership change (mandatory) + schedule/volume (policy)                  |
| selfEncryptionKey          | per atSign     | Legacy self data only                                                         | **Retired** — see below                                                                  |
| shared_key.\<atSign\>      | per pair       | Legacy shared data only                                                       | **Retired** — same path                                                                  |

## Foundations (what exists today)

**`xl-pluggable` — the provider seam.** `CryptoProvider { id;
initialize(CryptoContext); encrypt; decrypt }`, registered per AtClient via
`CryptoConfig`, routed by `CryptoRuntime` on the put/get/notify/sync paths.
The wire carries `Metadata.appMetadata = AppMetadata{providerId,
additional}`; `LegacyCryptoProvider` preserves today's behavior;
`CryptoStorage` gives providers secondary-backed persistence;
`PutRequestOptions.cryptoProviderId` overrides per operation. This seam is
the migration machinery itself: legacy and new schemes coexist per-value,
old data stays readable forever, re-encryption can be lazy.

**`jt-pq` — PQ primitives.** ML-KEM-768 and X25519 (pure-Dart and
OpenSSL-FFI), the `AtKemAlgorithm` interface, in at_chops.

**Secret sharing — identity + same-atSign delivery.** Per-client identity
(clientId + X-Wing keypair) published as an APKAM-signed `ClientKeyPackage`:
canonical hidden public key in the enrollment's reserved namespace (location
exclusivity = identity anchor) plus namespace-scoped copies whose *presence*
proves the enrollment holds `rw` on that namespace (server-enforced, verified
empirically). Store-and-forward encrypted envelopes scoped by application
namespace; `SecretStore` with newest-wins merge; enrollment-approval sharing;
shared per-AtClient instance (`AtClientSecretSharing.forClient`); race-free
`waitForSecret`; crypto-agile formats (`{kid, use, alg}` key lists,
`{keyAlg, kid, encAlg}` envelopes) so algorithms upgrade by id with no schema
change. PQ-native: `x-wing` key transport + `aes-256-gcm` payloads. API
`@experimental` (durable surface will be `SecureGroup`).

**Get-path invariants** (the secret-sharing and pluggable-crypto work both
touch the get path; both are satisfied on the integration branch):

- `get` respects the `isEncrypted` tri-state: explicit `false` skips
  decryption and returns the raw value; absent (legacy data) takes the
  try-decrypt fallback; `true` decrypts via the routed provider.
- `PutRequestOptions.shouldEncrypt = false` is a true no-crypto path on both
  write and read — secret-sharing envelopes and key-package copies are stored
  that way.

## Phases

### Phase 0 — land the foundations — **done on the integration branch**

`jt-pq` merged to trunk; `xl-pluggable` merged into `gkc-alice-to-alice`; the
secret-sharing substrate is in place. The get-path invariants above hold
post-merge (at_client 711 / at_chops 99 / at_commons 486 tests green).

### Phase 1 — complete the PQ primitives (at_chops)

- **X-Wing hybrid KEM** (draft-connolly-cfrg-xwing-kem-10): X25519 +
  ML-KEM-768 with the SHA3-256 combiner; 32-byte seed secret keys expanded
  via SHAKE-256 (pointycastle, already a dependency). **Done on
  `gkc-alice-to-alice`** (`XWingPureDartAlgo`), verified byte-exact against
  the draft's Appendix C vectors including derandomized encapsulation.
  ~150 lines composing existing pieces. **Preferred long-term home:
  upstream in `pqcrypto`** (which already provides ML-KEM and experimental
  ML-DSA) — offer the implementation as a contribution; the
  `AtKemAlgorithm` seam makes the swap invisible to callers. ML-DSA
  (needed around phase 5 for PQ signatures) is likewise pqcrypto's domain;
  register interest, adopt when it stabilizes against FIPS 204 vectors.
- **AES-256-GCM AEAD** — **done on `gkc-alice-to-alice`**
  (`AesGcm256EncryptionAlgo`, NIST-vector verified). **HKDF** (via
  `cryptography`) — adapter only, when its first consumer (the rotating
  provider's `export()`) arrives in phase 3.
- **PQ public key for enrollment conveyance.** The enrollment flow is the
  last harvest-now-decrypt-later hole: `encryptedAPKAMSymmetricKey` is
  RSA-wrapped to `public:publickey@alice`, and everything the approval
  conveys hangs off it. Fix without server changes: publish an X-Wing
  public key alongside (`public:publickey.pq@alice` or a key-list format);
  new enrollees prefer it for wrapping; approvers accept either.

### Phase 2 — identity layer: KeyPackages and per-client AtKeys

- **Frame bundles as KeyPackages.** **Done on `gkc-alice-to-alice`**, and
  more strongly than originally planned: since `jt-pq` merged before PR
  #1976 shipped, the classical interim was deleted outright — the identity
  layer is **PQ-native from day one** (`ClientKeyPackage` carries a single
  `x-wing` key; envelopes carry the KEM encapsulation ciphertext and seal
  payloads with `aes-256-gcm` under the encapsulated secret; nothing
  rsa-2048 ever shipped). The Dart types use the KeyPackage naming so the
  phase-5 MLS join is mechanical; the API surface is marked
  `@experimental` pending the `SecureGroup` reshaping in phase 3.
- **Evolve AtKeys for per-client persistence.** Today's `.atKeys` file is
  per-credential and routinely copied across devices; leaf keys must not be
  (copying would clone the client identity). Split:
  - *Shareable credential section* (today's content): PKAM/APKAM keypair,
    encryption keypair, apkamSymmetricKey. Copyable as today.
  - *Device-local client section* (new; marked section or sibling file):
    clientId, leaf KEM private keys, leaf signing key, storage master key.
    Never copied; importing a credential file without one mints a fresh
    client identity.
  Dynamic state (epoch tables, ratchet state) stays out — it churns per
  commit and lives in `CryptoStorage`/provider storage encrypted under the
  storage master key. The existing `loadClientKeys`/`saveClientKeys` and
  `SecretStorePersistence` hooks get default SDK implementations over the
  existing keychain/biometric/file plumbing, so apps supply nothing.
- **Cross-atSign KeyPackage publication**: each atSign exposes its clients'
  KeyPackages as public keys so other atSigns can fetch and verify them
  (signature chain to the publishing enrollment's `_apsk` / the atSign's
  public key, with pubkey-hash pinning as today).

### Phase 3 — SecureGroup v1 + the `group` provider (self encryption)

One interface, two implementations over time:

```dart
abstract class SecureGroup {
  String get groupId;            // deterministic, e.g. self:<atSign>:<ns>
  Set<LeafIdentity> get members;
  int get epoch;
  Future<Sealed> seal(plaintext);          // -> {epoch, kid, iv, ct}
  Future<dynamic> open(Sealed sealed);
  Future<void> add(KeyPackage member);
  Future<void> remove(LeafIdentity member);
  Future<void> rotate();                   // lever A
  Future<Uint8List> export(String label);  // app secrets bound to the epoch
}
```

- **v1 `PairwiseGroup`**: the committer generates the new epoch key and
  encapsulates it pairwise (X-Wing) to every member's KeyPackage, delivered
  over the secret-sharing channel as `__`-reserved system secrets
  (`__rk.<epoch>.<kid>` immutable entries + a `__rk.current` pointer that
  converges by newest-wins). **`kid` is the truth, `epoch` an ordering
  hint** — concurrent rotations both survive and every ciphertext stays
  resolvable; no coordination protocol. O(n) per commit; forward secrecy on
  rotation; PCS via full rotation. Its state — member KeyPackages, epoch
  keys, delivery channel — is exactly MLS bootstrap material.
- **`group` CryptoProvider**: encrypts self data as group messages.
  `AppMetadata(providerId: 'group', additional: {groupId, epoch, kid, enc,
  iv})`. Scope = **(atSign, namespace)** — the group key topology must
  mirror the server's enrollment authorization topology, or the crypto
  layer is more permissive than the transport layer (one atSign-wide group
  would hand a `chess`-only enrollment the keys to `banking` data). Default
  one self group per application namespace; `scopeSelector` hook for
  coarser/finer.
- **Membership lifecycle** (derivable rule: members = registered clients
  whose enrollment is authorized for the namespace):
  - *Creation*: lazy, leaderless — first authorized writer creates;
    deterministic groupId makes concurrent creation converge.
  - *Enrollment approval*: the approver adds the new client's leaf to the
    self group of every namespace it granted.
  - *Late-appearing clients* (second client on an enrollment; restarted
    ephemeral identity): any member that sees a validly-credentialed
    KeyPackage for the scope adds it; the requester side uses the pull flow
    below.
  - *Revocation*: remove leaf + rotate (`excludeEnrollmentIds` so the
    revoked enrollment's still-published bundles are skipped). Protects
    future writes; old epochs the revoked client held are not retroactive.
- **Substrate additions** (deferred from the secret-sharing work by design):
  `kind:'request'`/`'response'` envelope flow with an answer policy (pull
  recovery: "send me `__rk.current`", then specific epochs on decrypt
  miss); `onNewClientDiscovered` roster watch; `excludeEnrollmentIds`
  filters; `SecretStore.listSecrets(namePrefix:)`; and on the provider side
  `CryptoPolicy.onDecryptFailed` so apps choose throw/skip/retry-after-sync.
- **selfEncryptionKey retirement phases 1–2** begin here (below).

### Phase 4 — cross-atSign groups (shared encryption)

- **Pair groups** per atSign pair (or app-defined member sets): members are
  *both sides' clients*, which fixes a quiet legacy weakness — today
  `shared_key.bob@alice` is one static key decryptable by every bob client
  forever; per-client leaves give cross-atSign data the same per-device
  granularity and revocability as self data.
- **Add flow for another atSign's client**: fetch + verify their published
  KeyPackages → consent hook on the invitee's side (apps may auto-accept
  for namespaces they manage) → Add + Commit by any current member →
  Welcome delivered by ordinary cross-atSign notification (a Welcome is
  already encrypted to the KeyPackage init key; transport needs integrity
  only) → invitee joins at the current epoch. Commits fan out to every
  member atSign; the invitee's own enrollments gate which of *its* clients
  can see the traffic — symmetric with self groups.
- The `group` provider now serves both self and shared keys: one code path
  for both directions, for the first time.
- Static `shared_key.*` retirement follows the same four-phase path as
  selfEncryptionKey.

### Phase 5 — pq-mls engine (SecureGroup v2)

- **Engine decision**: pub.dev `openmls` wrapper (ships an experimental
  X-Wing ciphersuite; third-party Rust binary — supply-chain and
  pure-Dart-host caveats) vs an Atsign-owned `mls-rs` binding vs pure Dart
  (multi-month). If native, ship as a separate package so `at_client`
  stays pure Dart.
- **Bootstrap**: create the MLS group from the *same member set* (their
  KeyPackages are already published in MLS-compatible shape), flip
  `groupId`/`providerId` on new writes, lazily re-encrypt old values on
  touch. Welcome/Commit ride the same delivery channels (phase 3 within an
  atSign, phase 4 across atSigns). Apps see an engine swap under the same
  `SecureGroup` interface; the consent/membership hooks are unchanged.
- Gains over v1: TreeKEM (O(log n) commits), real forward secrecy and
  post-compromise security per RFC 9420, standardized group semantics, and
  PQ ciphersuites tracking the IETF drafts (draft-mahy-mls-xwing /
  draft-ietf-mls-pq-ciphersuites).
- selfEncryptionKey retirement phases 3–4 complete here.

## Retiring selfEncryptionKey (and shared_key.*)

"Obsolete" means three different things at different times; four phases:

1. **Stops being used for new writes** — the default provider flips to
   `'group'`. Old values keep routing to `LegacyCryptoProvider` via
   `AppMetadata`; zero breakage.
2. **Stops protecting old data** — lazy re-encryption on touch plus an
   optional background sweep; migration progress is observable per atSign.
3. **Stops being conveyed** — the real kill. `enroll:approve` today always
   ships `encryptedDefaultSelfEncryptionKey` and the enrollee's
   `waitForApproval` expects it; once an atSign's data is migrated,
   approval omits it and new enrollments never receive the key. Small,
   compatible at_auth change (tolerate absence, both sides); must be
   sequenced after phase 2 of the retirement.
4. **Stops existing** — onboarding no longer generates it for new atSigns;
   dropped from the AtKeys model. Gated on ecosystem floor versions (old
   SDKs and sibling apps reading the same atSign), so last and unhurried.

End state: the only symmetric key that ever sat still is gone; every
long-lived secret is either per-enrollment (rare rotation, anchored in an
approval ceremony) or per-client (routine lever-B rotation); everything
that actually encrypts data is epochal and rotates as a matter of course.

## Dependencies

```
0 (merge 1976 + xl-pluggable + jt-pq)
└─► 1 (X-Wing, GCM, HKDF, PQ enrollment pubkey)
    └─► 2 (KeyPackages PQ-native, AtKeys split, cross-atSign publication)
        └─► 3 (SecureGroup v1 + group provider, self)  ─► retire sEK 1–2
            └─► 4 (cross-atSign pair groups, shared)   ─► retire shared_key
                └─► 5 (pq-mls engine, bootstrap)       ─► retire sEK 3–4
```

## Upgrading NoPorts (with daemon-ping feature discovery)

NoPorts is the canonical consumer: it already has the many-clients-per-
atSign problem (multiple sshnpd daemons per device atSign), already signs
envelopes (its `validation_utils` is the ancestor of the SDK's
`EnvelopeSigning`), and its main harvest-now-decrypt-later exposure is the
session-key exchange (sshnpd RSA-2048-wraps AES session keys to sshnp's
per-session ephemeral keypair).

Backwards compatibility rides NoPorts' existing **feature discovery**: the
daemon's ping response carries `supportedFeatures: {name: bool}`
(`sshnpd_impl.dart`), clients read it null-tolerantly (a missing map means
an old daemon), and features gate behavior per session — exactly how
`twinKeys` rolled out. Two new `DaemonFeature`s:

| Feature         | Daemon advertises that it...                                                  |
|-----------------|-------------------------------------------------------------------------------|
| `groupCrypto`   | can decrypt notifications encrypted by the SDK's `group` provider             |
| `pqSessionKeys` | supports deriving session keys from a pair-group `export()` (none in flight)  |

The crucial subtlety: a client must NOT flip its default provider for
traffic to a daemon that can't decrypt it. `PutRequestOptions.
cryptoProviderId` (per-operation override, from `xl-pluggable`) is the
gate: choose the provider per destination based on the ping response.

**Tier 0 — transport becomes PQ-safe (no protocol change).** Daemons
upgrade first (the new SDK decrypts both legacy- and group-encrypted
values automatically via `AppMetadata` routing) and advertise
`groupCrypto`. Clients then send per-destination:

```dart
final features = await pingDaemon(device);            // existing flow
final provider = features['groupCrypto'] == true ? 'group' : 'legacy';
await notify(req, ..., putRequestOptions: PutRequestOptions()
  ..cryptoProviderId = provider);
```

Old daemon → legacy path, byte-identical to today. New daemon → every
request/response/heartbeat is group-encrypted and PQ-safe. Note the
compounding effect: the RSA-wrapped session keys travel *inside* these
payloads, so tier 0 alone closes the harvest-now hole — a recorded
exchange can no longer be peeled open later to recover the inner RSA
ciphertext.

**Tier 1 — derive session keys, never transmit them.** Gated on
`pqSessionKeys`:

```dart
// sshnpd, replacing genBundle():
final pair = await atClient.groups
    .withAtSigns([requestingAtsign], namespace: '$device.sshnp');
final aesKeyC2D = await pair.export('c2d:$sessionId');
final aesKeyD2C = await pair.export('d2c:$sessionId');
// response carries only sessionId — no key material in flight

// sshnp: the same two export() calls; both sides derive independently
```

When the daemon doesn't advertise `pqSessionKeys`, the client falls back
to today's ephemeral-RSA exchange (which tier 0 already protects in
flight). Side benefit: deletes the per-session RSA-2048 keypair
generation — a measurable startup win on small devices. The srvd
relay-auth key involves a third atSign; a per-session 3-party group is
overkill, so it stays transmitted, protected by tier 0.

**Tier 2 — fleet management via the self group.** Many daemons on one
device atSign plus the policy service is the self-group use case:

```dart
// management client, once:
await atClient.groups.self('policy_v2.sshnp')
    .putSecret('webhook-token', token);

// every sshnpd, joined automatically at enrollment:
final token = await atClient.groups.self('policy_v2.sshnp')
    .getSecret('webhook-token');

// stolen device: enroll:revoke → leaf removed + group rotates;
// everything shared after that moment is unreadable by it
```

**Rollout order**: (1) ship daemons that are dual-stack readers and
advertise the features — safe immediately, changes nothing on the wire;
(2) ship clients that prefer the new features when advertised; (3) once
the deployed-daemon floor includes `groupCrypto`, flip the client default
and keep the legacy fallback for stragglers; (4) the `pqSessionKeys` path
retires `genBundle`/ephemeral-keypair code when the floor allows.
Consolidation bonus at any point: NoPorts can replace `validation_utils`
signing with the SDK's `EnvelopeSigning` (its descendant), moving
verification onto the per-enrollment `_apsk` trust chain — strictly better
for multi-daemon deployments.
