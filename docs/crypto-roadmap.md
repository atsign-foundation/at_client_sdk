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
| `gkc-pqmls-spike`    | Per-client identity, discovery, and same-atSign delivery + the above | Integration branch    |

### Delivery model

All of this is built and verified **locally first**, end-to-end across the
`at_client_sdk`, `at_server` and `sshnoports` repos, then staged as a
**sequence of independently-reviewable per-package PRs** in dependency order.
`gkc-pqmls-spike` is the at_client_sdk integration branch holding every
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

## Milestones and capabilities

The path to the end state, framed by capability. Each milestone is usable on
its own; later ones build on earlier. (Phase numbers cross-reference the
[Phases](#phases) section.)

| Milestone | Capability added | Why it matters |
|-----------|------------------|----------------|
| **M0 · Pluggable crypto seam** (Phase 0) | Per-value `CryptoProvider` routing via `AppMetadata`; legacy + new schemes coexist | The migration machinery — old data stays readable forever, new schemes drop in as providers, no flag-day. Everything rides this seam. |
| **M1 · PQ primitives** (Phase 1) | X-Wing hybrid KEM, AES-256-GCM, HKDF in at_chops; PQ enrollment-conveyance pubkey | Post-quantum/hybrid building blocks; closes the last harvest-now-decrypt-later hole (enrollment); the crypto-agile base. |
| **M2 · Per-client identity / KeyPackages** (Phase 2) | Each client = a leaf (clientId + X-Wing leaf keys + signing) as an APKAM-signed KeyPackage; AtKeys device-local split | The MLS identity layer; per-device granularity + revocability; the one-leaf-per-instance correctness precondition. |
| **M3 · SecureGroup v1 + `group` provider** (Phase 3) | `seal/open/rotate/export` + a v1 epoch engine; self data encrypted as group messages; two-lever rotation; retires `selfEncryptionKey` | First real (intra-atSign) group encryption with rotating keys + revocation; the stable interface MLS later swaps under. |
| **M4 · Cross-atSign groups** (Phase 4) | Pair/multi-atSign groups; explicit membership + consent; `group` serves shared keys; retires static `shared_key.*` | First cross-atSign group encryption; per-client granularity/revocability for shared data; the precursor to NoPorts sessions. |
| **M5 · Group Delivery Service** (atServer groups) | Ciphertext-only DS atSign + group object/verbs (`seq`, log, ack, fetch); wake-then-pull; ordering + catch-up + retention | Makes group-addressed delivery scale on the pairwise substrate; solves fan-out + ordering + retention; operable as infrastructure. This is what makes *large* groups work. |
| **M6 · pq-mls engine** (Phase 5) | Swap the v1 engine for MLS (TreeKEM, RFC 9420 FS/PCS, PQ ciphersuites) behind the same interface + DS | O(log n) commits, standardized + audited group security — the actual end state. |
| **NoPorts adoption** (finish line) | Session keys via `SecureGroup.export`; daemon-feature-gated tiers 0–2 | The production payoff: PQ-safe NoPorts, derived (not transmitted) session keys, fleet management. |

Status: M0, M1 (X-Wing/GCM/HKDF), M2 (KeyPackage framing), M3 (self) and the
cross-cutting "at_chops is the sole security-crypto dependency" (Phase 6) are
done or in flight; **M4, M5, M6 are the substantive build ahead.**

## How it works — NoPorts (summary)

A NoPorts session is a *small* group — @client↔@daemon (plus @srvd for relay)
— so the member-atSign count is 1–2 and there is **no Delivery Service**:
delivery stays pairwise, as today. Backwards compatibility rides the daemon
ping's `supportedFeatures`; three feature-gated tiers:

- **Tier 0 — transport PQ-safe:** daemons advertise `groupCrypto`; the client
  routes per-destination through the `group` provider (PQ-safe) or falls back
  to `legacy`. The still-RSA-wrapped session key now travels *inside* a
  group-encrypted payload, so a recorded exchange can't be peeled open later —
  harvest-now-decrypt-later closed, no protocol change.
- **Tier 1 — derive, don't transmit:** gated on `pqSessionKeys`; both sides
  form the @client↔@daemon pair group and `export()` the session keys
  independently — no key material in flight; deletes the per-session RSA
  keypair.
- **Tier 2 — fleet self-group:** many sshnpd on one device atSign + a policy
  client are a self group; config secrets are shared once and read by all
  daemons; revoke → leaf removed + rotate → a stolen daemon reads nothing
  after.

Full walk-through: [Appendix A](#appendix-a--noports-end-to-end-detailed).

## How it works — a large group (summary)

A large group runs against a dedicated, **ciphertext-only Delivery Service
atSign** (e.g. `@my_org_groups`) operated as infrastructure. Members are
leaves (per-client); one or more admins drive membership. The DS atServer
holds the group object (roster + monotonic `seq` + TTL'd ciphertext log) and
does the work the pairwise model can't:

- **sequencing** — the atomic per-group `seq` is the MLS commit order;
- **fan-out** — wake-then-pull, **O(member-atSigns), not O(member-clients)**;
- **catch-up / retention** — `fetch:since` is the single delivery primitive;
  app messages may expire (tombstoned), commits are retained until
  applied-by-all or a straggler rejoins.

The DS never decrypts and cannot forge membership (members validate commits
cryptographically; reorder/withhold is detectable via the transcript hash).
The crypto is MLS (v2) — TreeKEM gives O(log n) commits and real FS/PCS —
behind the same `SecureGroup` interface.

Full walk-through: [Appendix B](#appendix-b--a-large-group-end-to-end-detailed).

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

`jt-pq` merged to trunk; `xl-pluggable` merged into `gkc-pqmls-spike`; the
secret-sharing substrate is in place. The get-path invariants above hold
post-merge (at_client 711 / at_chops 99 / at_commons 486 tests green).

### Phase 1 — complete the PQ primitives (at_chops)

- **X-Wing hybrid KEM** (draft-connolly-cfrg-xwing-kem-10): X25519 +
  ML-KEM-768 with the SHA3-256 combiner; 32-byte seed secret keys expanded
  via SHAKE-256 (pointycastle, already a dependency). **Done on
  `gkc-pqmls-spike`** (`XWingPureDartAlgo`), verified byte-exact against
  the draft's Appendix C vectors including derandomized encapsulation.
  ~150 lines composing existing pieces. **Preferred long-term home:
  upstream in `pqcrypto`** (which already provides ML-KEM and experimental
  ML-DSA) — offer the implementation as a contribution; the
  `AtKemAlgorithm` seam makes the swap invisible to callers. ML-DSA
  (needed around phase 5 for PQ signatures) is likewise pqcrypto's domain;
  register interest, adopt when it stabilizes against FIPS 204 vectors.
- **AES-256-GCM AEAD** — **done on `gkc-pqmls-spike`**
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

- **Frame bundles as KeyPackages.** **Done on `gkc-pqmls-spike`**, and
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
    **This is an MLS correctness precondition, not just key hygiene.** MLS
    gives each member one ratchet-tree leaf with exclusive, linearly-evolving
    send/commit state, so two instances sharing one clientId + leaf keys
    cannot both act as that leaf: concurrent sends collide on the per-leaf
    generation counter (receivers drop the duplicate as a replay, or lose the
    key to forward secrecy) and concurrent commits race on the epoch. v1's
    stateless `seal()` (epoch key + random IV, no per-sender ratchet) masks
    this — same-clientId clones "work" on v1 and break on the MLS swap. The
    rule: **one clientId per running instance, leaf keys never copied → one
    leaf per instance.** Two machines that should share an identity join as
    two leaves of the same group, not one shared leaf.
  Dynamic state (epoch tables, ratchet state) stays out — it churns per
  commit and lives in `CryptoStorage`/provider storage encrypted under the
  storage master key. The existing `loadClientKeys`/`saveClientKeys` and
  `SecretStorePersistence` hooks get default SDK implementations over the
  existing keychain/biometric/file plumbing, so apps supply nothing.

  **Rejected alternative — per-clientId secrets on the atServer.** Storing
  the leaf private keys + storage master key server-side (instead of
  device-local) was considered and rejected. To be usable they must be
  wrapped under a *locally-held* key, and the only local material here is the
  *portable* enrollment credential — so the leaf becomes reconstructable by
  any enrollment-holder. That (1) makes **cloning the default** rather than a
  rare misuse (every device sharing the enrollment pulls the same leaf →
  concurrent clones → the MLS send/commit breakage above), forcing the
  single-owner lock/lease just to make the *normal* case safe; (2) opens a
  **harvest-now-decrypt-later hole on the PQ leaf KEM key** — wrapping it
  under today's RSA-2048 enrollment key leaves a recorded ciphertext a future
  quantum adversary can open; (3) **couples the data and key blast radii**
  through the most-copied credential (server breach alone reveals nothing
  today; this makes the enrollment key the single secret that unlocks
  server-resident data); and (4) if dynamic state's unwrapping root is also
  centralized, **breaks forward secrecy / PCS** (deletion is no longer final)
  and the **linear send-ratchet** (server newest-wins ≠ a monotonic counter),
  and adds an online dependency that breaks local-first seal/open. Note the
  design *already* keeps dynamic state server-side — but wrapped under the
  *device-local* storage master key, which is exactly why it's safe; moving
  that root to the server is the qualitative regression. The convenience it
  buys (recoverable/stable leaf) is already provided more cheaply by
  fork-to-new-leaf + cheap lever-B rotation; server-mediated single-ownership
  needs only a lease *token*, not the secrets. If a leaf-recovery feature is
  ever wanted, the only defensible shape is narrow and opt-in: back up the
  **static leaf keypair only** (never dynamic state), **PQ-wrapped** (not
  RSA-2048), as a **recovery operation gated by the single-owner
  acquisition** — eyes open that it still leaves a server-resident PQ-key
  ciphertext and complicates lever-B (superseded leaf keys linger
  server-side until actively deleted).
- **Client identity resolution (multi-program UX).** Requiring every CLI
  invocation to pass `--client-id` is a usability fail; the SDK should
  *determine* the leaf. Each device-local keyset is
  `{clientId (random), label (local selection metadata), leafKeys, lockfile}`,
  stored per-atSign. Default `label` = program-set, falling back to the
  executable basename. Resolution at startup:
  - explicit `--client-id` → claim it (lock; error if already live);
  - else scan keysets, filter to **claimable** (not locked by a live owner):
    a claimable label-match → **resume** it (the common case); a label-match
    that is **locked** (another instance of me) → **fork** to an *ephemeral*
    leaf (not persisted, so no keyset proliferation); no label-match → **mint**
    a persistent keyset for the label; keysets exist but none is mine and no
    label to go on → an **actionable error** listing the leaves and how to
    pick.
  The owner lockfile (the single-owner advisory lock) doubles as the
  resolver's liveness check — it both prevents clones and drives
  resume-vs-fork. *Prefer resume* (fork/mint leaves are brand-new and must
  join groups first — see Phase 4). Intentional multi-instance (a daemon
  fleet of stable members) uses **distinct labels / keyset dirs** (persistent
  leaves), not forks. Per-workspace identity, if wanted, comes from a
  discoverable `.atsign-client` file (cwd/ancestor, like `.git`/`.env`), not
  raw cwd. Ships as the default `loadClientKeys`/`saveClientKeys`
  implementation, so apps supply nothing; zero-argument for the normal
  multi-program case, never clones, asks for an id only when genuinely
  ambiguous.
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

### Admission UX — a new leaf never blocks on a manual step

A freshly-minted or forked leaf must publish its KeyPackage and be admitted
before it can do group work. For *shared cross-atSign collaboration* groups
that admission is an explicit admin Add + consent — real friction, and
appropriate there. **NoPorts escapes it**, because its "groups" are only ever
two shapes, both with automatic / policy-driven admission:

- **Fleet = a self group (derived membership).** A new sshnpd leaf is a member
  the moment its enrollment is authorized for the namespace — existing members
  add its validly-credentialed KeyPackage (the late-appearing-clients flow),
  no human "add to group" action. Admission is **bound to the enrollment
  approval NoPorts already requires**, and a reinstalled daemon (new
  device → new leaf, since leaf keys never copy) **auto-rejoins** under its
  still-authorized enrollment.
- **Session = a pair group, admitted by the daemon's accept policy.** The
  "admin admitting" is just the daemon's existing connect-accept decision
  (its allow-list). The session *request* and the *join* are the **same
  event**: a fresh client leaf publishes its KeyPackage and requests, and the
  accept forms the pair group on the spot — so a new leaf is never stuck
  before "doing group work"; its first request *is* the join.

So "admitted by an admin" reduces to authorizations NoPorts already performs
(enrollment approval; the daemon allow-list) — no new manual step. **Three
design requirements keep it that way:** (1) enrollment approval auto-admits
the leaf to the self-groups for the namespaces it grants (one approval, not
two steps); (2) self-group membership stays *derived* (authorized
enrollment → auto-member), so installs/reinstalls auto-(re)join; (3) session
admission stays the daemon's accept policy, evaluated at request time. If
"add a leaf to a group" ever became a separate manual action, the friction
returns — so admission must be a *consequence* of decisions NoPorts already
makes.

**Role-aware concurrency** (from the client-identity resolver): a short-lived
client may **fork to an ephemeral leaf** under accidental concurrency — fine,
each `sshnp` run forms its own session. A long-running **daemon** should
instead **refuse-to-start (or use a distinct persistent label)** — an
ephemeral daemon leaf has no stable self-group membership.

## Known shape risks & corrective actions (assessment 2026-06-17)

A review of the secret-sharing + group work against the MLS end state,
taken after the all-in-MLS decision. The early classical interim
(RSA-2048 key transport + AES-256-CTR) is gone — the substrate is
PQ-native (X-Wing + AES-256-GCM), so the "legacy-plus" secret-sharing
mechanisms that predated this decision have already been superseded.

The load-bearing decisions hold and carry forward to MLS as an engine
swap: the provider seam, PQ-native KeyPackages, the `SecureGroup`
`seal/open/rotate/export` interface, `(atSign, namespace)` scoping that
mirrors server authorization, and lazy `AppMetadata`-routed migration.
What carries forward is the **interface + identity (KeyPackage) + delivery
layers**; what does **not** is the v1 `PairwiseGroup` epoch engine and its
leaderless convergence model (`kid`-is-truth, concurrent epochs coexist) —
TreeKEM replaces it wholesale. So do not over-invest in hardening v1
concurrency; invest in the interface/identity/ordering decisions that
survive the swap.

Risks, ordered by how much cheaper they are to fix now than later:

1. **Membership is implicit — a Phase-3-only shape.** The implemented
   `SecureGroup` is `groupId / currentEpoch / seal / open / rotate /
   export`; it dropped the `members` / `add` / `remove` that the Phase 3
   sketch above lists. v1 self-groups *derive* membership (`rotate()`
   re-runs `discoverClients(namespace)`), which works only because one
   server is the authority on authorization. Cross-atSign groups (Phase 4)
   and MLS are explicit-roster, so the interface must grow membership ops
   there — and adding methods to a published abstract is a breaking change.
   **Action: lift `members` / `add` / `remove` into the durable
   `SecureGroup` interface now, with v1 implementing them by derivation, so
   the app surface is stable across Phases 3→4→5.** (Cheap now.)

2. **The delivery channel is a KeyPackage directory + best-effort secret
   channel, not an ordered MLS Delivery Service.** Epoch keys and envelopes
   converge newest-`createdAt`-wins, with no ordering guarantee; the v1
   model embraces forks. MLS requires agreement on commit *order*.
   **Action: before Phase 5, decide where commit ordering comes from —
   atServer sequencing, a designated per-group committer, or per-epoch
   compare-and-set — and record it in the Phase 5 plan.** The v1 "forks are
   fine" assumption must not leak into MLS expectations.

3. **Phase 3 → Phase 4 is the real discontinuity.** The code is solidly
   Phase 3 (`GroupCryptoProvider.encrypt` hard-rejects shared keys).
   Cross-atSign pair groups — what NoPorts actually needs — require
   cross-atSign KeyPackage fetch+verify, a consent hook, explicit
   membership, and group state not derivable from one server. That is
   mostly greenfield; the substrate covers identity + transport only.
   **Action: scope Phase 4 as the major build it is — treat
   membership/consent/group-state as new, not as an extension of the
   self-group path.**

4. **`GroupCryptoProvider` corrupts binary values.** It does
   `utf8.encode(plaintext.toString())` / `utf8.decode(...)`; the legacy
   path honours `isBinary` but the group provider does not.
   **Action: make the `group` provider seal/open bytes (binary-safe)
   before any binary value relies on it.**

5. **Naming collision.** The v1 self engine is `PairwiseGroup` ("pairwise"
   = the X-Wing encapsulation method), but Phase 4's cross-atSign groups
   are also called "pair groups" above. **Action: rename the v1 engine
   (e.g. `SelfGroup`) to free "pair group" for the cross-atSign meaning.**

### Connection model & the MLS leaf

at_client uses several physical connections to the atServer (monitor /
request-response / sync) that collectively act as one logical client. This
is **not** the cloning hazard: the MLS leaf binds to the logical client
that exclusively owns the mutable crypto state — the `AtClientImpl` instance
(it owns `atChops`, `cryptoRegistry`, and the group provider via
`CryptoRuntime`) — **not** to a connection. MLS rides above transport, so N
connections under one instance = one leaf, by construction. The default
makes this safe out of the box: `clientId` is per-process and ephemeral
(`Uuid().v4()`, lives until the process ends), so each instance is a fresh
leaf regardless of socket count. If anything, the model is a *positive* — it
hands MLS a single logical-client object to anchor leaf identity and group
state on; multiplexing connections (fewer or more) is orthogonal.

The model is safe *because* one instance owns the state, which turns into
three obligations:

- **Serialize crypto-state mutation within the instance** (engine, Phase 5).
  Connections drive concurrent async work — the monitor can deliver a Commit
  (epoch change) while a request connection is mid-`seal()`. MLS generation
  /ratchet/epoch transitions are not reentrancy-safe; a mutex/sequencer must
  guard seal/open/apply-commit. Intra-instance lock, cheap — not distributed.
- **Apply inbound handshake before sealing under the new epoch** (engine,
  Phase 5). Commits/Welcomes arrive on the notification connection; data on
  get/notify; sync on its own — all converge on one epoch/ratchet that must
  advance in order. Handshake and data are one state machine, not independent
  streams.
- **One live owner per persisted `clientId`** (identity, Phase 2). The sharp
  edge is `loadClientKeys`, not connections: handing the same stored
  clientId + leaf seed to two *concurrent* instances (two apps, app + daemon,
  overlapping restart, HA pair) is the clone bug regardless of socket count.
  Rule: a persisted leaf identity has exactly one live owner at a time —
  mint-fresh by default (today's behavior) or persist-with-an-exclusive-
  runtime-lock.

What it is **not**: never "one connection per leaf"; connection count never
forks or merges a leaf. The only thing that forks a leaf is more than one
runtime owner of the same crypto state — a process/instance/identity-
persistence decision, never a socket decision.

## atServer group Delivery Service (target design)

Group-addressed delivery on the pairwise substrate — taken straight to the
end state, not via incremental half-measures. A group's Delivery Service
(DS) is operated as a dedicated, **ciphertext-only** service atSign (e.g.
`@my_org_groups`), run as critical infrastructure, whose atServer gains a
first-class **group** object. The DS never holds group secrets — it stores
plaintext routing metadata + an opaque ciphertext log it can order but not
read — so E2E and the MLS leaf model are untouched. It can order, route,
and (mis)deliver, all detectable via the MLS transcript hash; it cannot
read content or forge membership (members reject any commit not signed by
an authorised owner leaf).

### One design, two placements (host = member, or dedicated)

This is **one** design; "small self-hosted group" and "large dedicated-DS
group" are the same group object + verbs + wake-then-pull below, differing
only in *where the DS role is hosted and whether that host also
participates*:

- **Dedicated (large groups):** the DS-hosting atSign (e.g.
  `@my_org_groups`) is *neither* an admin nor a member — a pure service.
- **Self-hosted (small groups):** the DS role runs on an atSign (e.g.
  `@alice`) that *also* is an admin and *also* contributes member leaves.
  Same verbs, same log, same sequencing — just co-located with a
  participant. A sole-admin group never produces a `seq` conflict, but the
  sequencer is present either way. (Tiny groups — a NoPorts @a↔@b session —
  *may* skip the group object and peer-fan-out, but they don't have to.)

The DS **atServer holds only ciphertext in both placements** — invariant.
The DS role never needs plaintext: sequencing is an arrival-order counter,
fan-out targets the plaintext roster, retention keys off `expiresAt`/`msgId`,
read-auth off roster membership. The member *clients* hold the group keys
and decrypt on-device — that is the member role, not the DS role, and not
the atServer.

So the only substantive consequence of the placement is **whether the DS
operator can read group content**: self-hosted, the operator (Alice) can,
because its atSign contributes member leaves; dedicated, it cannot, because
`@my_org_groups` has none. That follows entirely from membership, not from
the DS role. (Plus the orthogonal operational point: a dedicated DS can run
as HA infrastructure; a member-hosted DS rides that member's availability.)

### The group object (server-side, on the DS atSign)

A named object in the DS atSign's reserved namespace (`__group.<groupId>`):
- `ownerAcl` — atSigns permitted to administer/sequence. Coarse anti-spam
  gate only; the real membership authority stays the cryptographic in-group
  owner policy that member clients validate.
- `members` — the plaintext **delivery roster** (fan-out + read-auth set). A
  soft projection of the encrypted ratchet tree; transient divergence from
  it is benign.
- `seq` — monotonic per-group counter; the commit-ordering authority.
- `log` — a TTL'd append-only **ciphertext** log keyed by `seq`, doubling as
  the delivery payload store **and** the catch-up store.

### Verbs

- `group:create:{group, ownerAcl}` — provision the object.
- `group:add:{group, atSign}` / `group:remove:{group, atSign}` — mutate the
  roster (owner-ACL gated; carried as a delta alongside the membership
  commit).
- `group:members:<group>` — read the roster.
- `group:append:{group, value:"<b64 ciphertext>", msgId, ttl}` — **write
  path.** The atServer atomically assigns the next `seq`, appends ciphertext
  to the log, dedupes on `msgId` (idempotent resubmit), and fans out a
  **minimal wake** to each member atSign carrying only `{group, seq}` —
  never the payload. Returns the assigned `seq` (a concurrent admin that
  lost the race rebases and resubmits). One small fixed-size request from
  the DS client regardless of group size.
- `group:fetch:{group, since:<seq>}` — **read path, and the single delivery
  primitive.** Returns log entries with `seq > since` (ciphertext).
  Steady-state delivery, catch-up, missed-wake, and late-join are all the
  same call — pull the delta from your last `seq`. Authorised by **group
  membership** (the atServer checks the caller is in `members`) — the new
  capability beyond pairwise `sharedWith`: a log readable by a *set* of
  atSigns. The server returns ciphertext it cannot read.

### Delivery model — wake, then pull

Notifications are minimal wake-ups, not payload carriers:
1. `group:append` → server logs ciphertext + fans out `{group, seq}` wakes,
   one per **member atSign** (that atSign's atServer/clients pull) — so
   delivery is O(member-atSigns), never O(member-clients).
2. The member pulls via `group:fetch:since:<lastSeq>` into its **own** local
   store; its many clients then see it through ordinary local sync. One
   fetch drains multiple pending seqs, and wakes may be coalesced ("group
   advanced to seq M"), so a burst costs one wake + one pull per member.
3. Catch-up / late-join / missed-wake are not special paths — they are the
   same `group:fetch:since`. Once pulled, group messages behave like
   ordinary local-first data.

### Properties / invariants

- **No new trust.** Ciphertext + plaintext rosters only; orders and routes,
  never decrypts, cannot forge membership.
- **Sequencing IS the commit-ordering answer.** `group:append`'s atomic
  `seq` is the MLS DS total order — this **resolves** the standalone
  "decide commit-ordering" question (decision: atServer per-group
  sequencing).
- **Idempotent + best-effort + retry.** `msgId` dedupe; wakes ride the
  existing notification queue + retry; the authoritative state is the log,
  so a lost wake is harmless (the next fetch closes the gap).
- **Bounded fan-out.** Per message: one `group:append` from the sender, then
  O(member-atSigns) wakes + pulls — never O(member-clients).
- **Reuses existing machinery.** Wakes are ordinary notifications; the log
  is ordinary TTL'd keystore entries; genuinely new are only the group
  object, the membership-gated read, and the atomic `seq`.

### expiresAt / availableAt and catch-up

TTL punches gaps in the `seq` log, and a gap is ambiguous (expired-and-
skippable vs missing-and-fatal). The resolution splits on message **kind**,
so the log carries plaintext per-entry metadata — `kind` (commit|app),
absolute `expiresAt`, absolute `availableAt`, `msgId` — which the DS reads
but never the content.

**Two retention classes:**
- *Application messages* — sender-set `expiresAt`/`availableAt`; **may
  expire/disappear**. MLS app messages are independent (per-epoch secret-tree
  ratchet), so a lost one is benign. A gap here is fine.
- *Commits / handshake* — **never short-TTL'd**; retained until applied-by-all
  (or a deadline). A member that misses a commit cannot advance past that
  epoch — fatal-but-detectable (the transcript hash catches it; the member is
  stuck, not corrupted), so commits must not vanish under a current member.

**Catch-up** (`group:fetch:since`):
- App messages: returns survivors; misses are the intended ephemeral
  semantics. Expired entries leave a **tombstone** `{seq, expired:true}` with
  *longer retention than the payload*, so a puller distinguishes expired from
  a hole.
- Commits: replay survivors in `seq` order; if a needed commit has aged out,
  the member is a **straggler and rejoins at the current epoch** (fresh
  Welcome / external commit), never a full-history replay.

**Bounded commit retention:** members send `group:ack:{group, seq}` (a seq,
not content); the DS truncates the log below `min(member high-water marks)` —
everyone has those — or below a **max-retention deadline**. A member past the
deadline (e.g. its atServer down for weeks) becomes a straggler → rejoin.
This also pressures admins to remove dead members (good for PCS).

**"Expires before ever delivered" (recipient atServer down):**
- App message → the recipient misses it permanently; correct (disappearing-
  message semantics), marked by a tombstone.
- Commit → forbidden for current members (no short TTL + applied-by-all
  retention); a recipient down past the deadline falls off → re-added. Never
  silent corruption.

**`expiresAt` must be absolute, sender-set UTC** — not a per-hop duration. A
per-hop TTL gains a fresh lifetime at each hop (DS log, then each recipient's
local store) and outlives its intended window.

**`availableAt` is application-message-only and enforced recipient-locally.**
A commit can't defer a state transition without stalling the epoch chain. For
app messages the DS delivers in `seq` order **immediately** (ciphertext is
opaque to it); the recipient pulls and **embargoes locally** via the existing
`nextAvailableAt`/`peekNewlyAvailable` machinery. So `group:fetch:since` must
**return** future-`availableAt` entries (with metadata), never withhold them
— else a member offline at maturity never gets them. (The DS may defer the
*wake*, never the log entry.) Keeps `seq` monotonic and leaks no timing.

**`availableAt` vs forward secrecy (the subtle bound):** an app message is
sealed under the epoch-N secret, but FS deletes old epoch keys — so a
long-deferred message can mature *after* its decryption key is gone.
Deferred availability is therefore **bounded by epoch-key retention**; longer
embargoes need the sender to re-key under a deliberately-retained
`export()`-derived secret. "Schedule for next month" and forward secrecy are
in tension; the bound must be explicit.

These are policy + metadata over the atServer's existing expiry/availability
timers; the only genuinely new server behavior is the commit-retention
policy, tombstones, and ack-truncation.

(A simpler inline-payload, client-supplied-recipient-list `notify:list` is a
possible transitional form, but the target is the group object + wake/pull
+ membership-gated log above.)

## Appendix A — NoPorts, end to end (detailed)

Actors: **@client** (sshnp), **@daemon** (sshnpd; a device may run many),
**@srvd** (relay; a third atSign). Each client is a leaf with a published
KeyPackage. Tier/rollout detail lives in
[Upgrading NoPorts](#upgrading-noports-with-daemon-ping-feature-discovery);
this is one session's trace.

1. **Discovery.** sshnp pings @daemon (existing flow); the ping response
   carries `supportedFeatures`, read null-tolerantly (a missing map = old
   daemon). The client learns `groupCrypto` and `pqSessionKeys`.
2. **Session request (Tier 0 — transport).** The client picks a provider per
   the ping — `provider = features['groupCrypto'] ? 'group' : 'legacy'`, set
   via `PutRequestOptions.cryptoProviderId`. With `group`, the request
   notification is a PQ-safe group message of the @client↔@daemon pair group;
   with `legacy`, byte-identical to today. Because the (still RSA-wrapped)
   session key rides *inside* this payload, a recorded exchange can no longer
   be peeled open later — the harvest-now hole is closed even before Tier 1.
3. **Session keys (Tier 1 — derive, don't transmit).** If `pqSessionKeys`,
   both sides resolve the same pair group and derive
   `aesC2D = pair.export('c2d:'+sessionId)` and
   `aesD2C = pair.export('d2c:'+sessionId)`. Same `(label, epoch)` → identical
   bytes on both sides; the response carries only `sessionId`, no key material
   in flight, and the per-session RSA keypair generation is deleted. Without
   `pqSessionKeys`, fall back to today's ephemeral-RSA exchange (already
   protected by Tier 0).
4. **srvd relay.** The relay-auth key involves a third atSign; a per-session
   3-party group is overkill, so it stays transmitted, protected by Tier 0.
5. **Delivery.** The group is 2 atSigns (or a self group within one atSign for
   Tier 2). The member-atSign count is tiny, so there is **no DS host** —
   pairwise notify + the recipient atServer's sync to its own clients.
   (Appendix B's Delivery Service is only for large groups.)
6. **Fleet management (Tier 2 — self group).** Many sshnpd on one device atSign
   plus a policy/management client are a self `SecureGroup`. Management writes
   a config secret once; every daemon reads it, joined automatically at
   enrollment. A stolen device → `enroll:revoke` → the daemon's leaf is
   removed and the group rotates → everything shared after that instant is
   unreadable by it.
7. **Rollout.** (1) ship dual-stack daemons that advertise the features — safe,
   nothing changes on the wire; (2) ship clients that prefer the features when
   advertised; (3) once the deployed-daemon floor includes `groupCrypto`, flip
   the client default; (4) `pqSessionKeys` retires `genBundle`/ephemeral-keypair
   code when the floor allows.

Net: every request/response/heartbeat becomes PQ-safe (Tier 0), session keys
stop travelling at all (Tier 1), and fleet secrets get rotating-key
distribution with instant revocation (Tier 2) — with old peers always
negotiating cleanly via feature discovery.

## Appendix B — a large group, end to end (detailed)

Actors: a dedicated DS atSign **`@my_org_groups`** running the
[group Delivery Service](#atserver-group-delivery-service-target-design);
admins **@alice**, **@bob**; members across many atSigns, each a leaf with a
published KeyPackage.

1. **Provision the DS.** `@my_org_groups` is operated as infrastructure (HA,
   monitored, backed up). It is ciphertext-only — never a group member, never
   holds group keys.
2. **Create.** `@alice` → `group:create{groupId, ownerAcl:[@alice,@bob]}`. The
   DS provisions the group object: roster, `seq=0`, empty TTL'd log.
3. **Add a member (@frank).** An admin: fetches + verifies @frank's published
   KeyPackage; commits an Add locally (advances the epoch), producing a Commit
   + a Welcome; sends the **Welcome pairwise** to @frank (1:1); then
   `group:append{kind:commit, value:<commit ct>, msgId}` + `group:add @frank`
   to the DS. The DS assigns `seq=N`, logs it, adds @frank to the roster, and
   fans out `{group, N}` **wakes** to every member atSign. Members
   `group:fetch:since` the commit, apply it, advance to epoch N; @frank pulls
   current state and joins.
4. **Application message (any member → group).** The sender seals once under
   the epoch key, then one `group:append{kind:app, value:<ct>, expiresAt,...}`
   to the DS. The DS assigns the next `seq`, logs (with the app TTL), fans out
   wakes. Each member atServer pulls the delta into local storage; that
   atSign's many clients then read it via ordinary sync — including the
   sender's *own* other clients (the DS fans out to the sender's atSign too).
   Cost: one append + O(member-atSigns) wakes/pulls — never O(member-clients).
5. **Concurrent admins.** @alice and @bob both commit at epoch N. Both
   `group:append`; the DS's atomic `seq` orders them — one lands at N, the
   other gets a conflict, rebases to N+1, resubmits. No fork.
6. **Catch-up.** A member offline for a while returns and
   `group:fetch:since:<lastSeq>`. Commits replay in `seq` order; expired app
   messages appear as tombstones (skippable). If a commit it still needs has
   aged out (offline past the retention deadline), it is a straggler → an
   admin **re-adds it at the current epoch** (fresh Welcome), not a
   full-history replay.
7. **Remove / revoke (@grace).** An admin commits a Remove + rotates the epoch
   (`excludeEnrollmentIds`), then `group:append{kind:commit}` +
   `group:remove @grace`. The DS sequences, fans out, drops @grace from the
   roster. Everything from the new epoch on is unreadable by @grace.
8. **Retention & GC.** Members periodically `group:ack{seq}`; the DS truncates
   the log below the min high-water mark (everyone has those) or a deadline.
   App messages expire per their `expiresAt`; commits are retained until
   applied-by-all or the deadline (then straggler-rejoin).
9. **Trust boundary.** The DS only ever sees ciphertext + the plaintext atSign
   roster: it orders, routes, and retains, but never decrypts and cannot forge
   membership — members reject any commit not signed by an authorised owner
   leaf, and reorder/withhold is detectable via the MLS transcript hash.
10. **Engine (v2).** The crypto is MLS: TreeKEM makes each commit O(log n)
    instead of O(n), with RFC 9420 forward secrecy and post-compromise
    security — all behind the same `SecureGroup` interface and the same DS.

Net: members send/admin once to the DS; the DS sequences and fans out
ciphertext it can't read; catch-up, retention, ordering, and revocation are
handled at the group object — and the per-message cost scales with the number
of member *atSigns*, not member *clients*.
