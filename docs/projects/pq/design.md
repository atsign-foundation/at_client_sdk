# Post-quantum encryption for the Atsign Protocol — design

**Status:** the design as it stands on trunk, stated in the present tense. What is still to
change is in [Planned changes](#planned-changes). at_client 4.0.0, the first release that
carries this design, was published on 2026-11-04.

## Overview

### The problem

Before this work, everything the SDK encrypted rested on RSA-2048 key transport and AES: an
Atsign's own data under its `selfEncryptionKey`, data shared with another Atsign under a
`shared_key.*` wrapped to the recipient's RSA key, and the symmetric key an approver conveys to
a new enrollment. Ciphertext recorded today under RSA can be opened once a cryptographically
relevant quantum computer exists, so confidentiality is the urgent half. Client authentication
(PKAM) and data signatures were RSA-2048 too. A signature is not at risk from being recorded,
only from live forgery once such a computer exists.

This design replaces both with post-quantum or hybrid primitives. It keeps every existing
capability: encrypting for the Atsign's other clients and for other Atsigns. And it lets each
app move on its own schedule.

### D1 and D2

**D1, post-quantum messaging, is built** and ships in at_client 4.0.0:

- Every encryption path goes through a `CryptoProvider` chosen per value by
  `appMetadata.providerId`
  ([section 4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)).
- Key transport uses a post-quantum KEM. The default is X-Wing (ML-KEM-768 + X25519), which
  keeps a hedge against ML-KEM falling to classical cryptanalysis. The alternative is pure
  ML-KEM-1024, chosen through `keyEstablishmentAlgorithms` on the posture or on
  `AtClientPreference`; its specification chain contains no draft, and it is the parameter set
  CNSA 2.0 mandates
  ([ruling 50](detail/decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)).
  Neither restricts who an Atsign can reach: a sender seals to whatever the recipient
  advertises, and every client that reads post-quantum data registers both
  ([ruling 50.2](detail/decisions.md#502-the-sender-follows-the-recipient-so-configuring-a-kem-restricts-nobody)).
- Data is encrypted with AES-256-GCM.
- The symmetric key an approver conveys to a new enrollment can be encapsulated to the
  enrollment's key package instead of being RSA-wrapped (`EnrollmentKeyExchangeMode.pq`).
- The client authentication signing key and the client data signing key move to ML-DSA-65.
  The atServer verifies a PKAM signature under the algorithm stored on the enrollment record,
  never the one the client declares
  ([ruling 20.5](detail/decisions.md#205-scope-boundaries-and-versioning), item 8).
- How much of this a client runs is its `PqPosture` ([section 1.8](#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d)).
  In 4.0.x the default is `PqPosture.legacy`, which runs none of it unless the client's
  keyfile already holds post-quantum material, which raises the client to that floor.

**D2, the `at/pqmls` group provider, is planned.** It adds MLS (RFC 9420) on post-quantum
ciphersuites as another provider behind the same seam. D1 already gives coarse forward secrecy,
by rotating and deleting content keys, and post-compromise security, by rotating namespace keys.
D2 adds per-message forward secrecy, membership changes that cost O(log n), and groups whose
membership is not tied to namespace authorisation
([ruling 2](detail/decisions.md#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted)).
See [Planned changes](#planned-changes).

**Out of scope:** the TLS session to the atServer and atDirectory, and the atDirectory itself
([rulings of 2026-07-02](detail/decisions.md#rulings--2026-07-02)). Once payloads are
end-to-end post-quantum, what TLS still protects is verb-level metadata, such as key names and
timing, which the atServer sees by design. The atDirectory holds no ciphertext.

### The nskey data path, in concept

D1's data path has two providers, beside the built-in legacy one:

- `at/nskey/*` conveys a symmetric content key (CK). It seals the CK once to a namespace key
  (nskey) and writes the result as a record of its own.
- `at/symmetric/AES/GCM` encrypts application data under a key derived from the CK, and cites
  the CK by `ckKid`.

An nskey is a KEM keypair that content keys are encapsulated to. It never encrypts application
data. Each (Atsign, namespace) has one current nskey generation, which holds one key for each
key-establishment algorithm the Atsign's clients mint. It is the recipient key in both
directions: the owner seals its own content keys to it, and other Atsigns seal the content keys
they share with the owner to it. So self data and a share use one mechanism, and differ only in which
Atsign owns the content-key record.

- The private half lives in each of the owner's enrollments that may use the namespace. It is
  conveyed to each enrollment over the secret-sharing substrate
  ([section 2](#2-subsystem-b--the-secret-sharing-substrate)).
- The public half is published the moment it is minted, at `public:__nskey.<ns>@<atSign>`, so a
  sender never waits for a recipient to publish. The double underscore keeps it out of every
  scan an outsider can make, while an exact `plookup` still serves it. The record is mutable:
  rotation overwrites it under a short-lived lock, and every conveyance names the key it was
  sealed to by `nskeyKid`.

The developer API does not change: `put`, `get` and AtCollection, with identity still the
enrollment.

Compared with the legacy path:

| Legacy | The nskey data path |
|---|---|
| RSA-2048 key transport | X-Wing by default, ML-KEM-1024 by configuration |
| one self-encryption key covers every namespace | one key per namespace, matching how enrollments are authorised |
| the `selfEncryptionKey` never changes | namespace keys rotate, yearly by default and whenever a revocation touches the namespace |
| no way to cut one enrollment off from future data | a rotation conveys the new key to every enrollment except the revoked one |
| no forward secrecy | coarse forward secrecy by rotating and deleting content keys; per-message forward secrecy is D2 |

### Migration

Existing apps run legacy. Each app upgrades on its own schedule and stays compatible with peers,
and with the Atsign's other apps, that have not.

**The invariant.** A value is only written in a scheme every client that must read it supports.
Each value carries `appMetadata.providerId`, and a client that configures the post-quantum
providers (`PqPosture.pqReady` and above) keeps every older provider too. So upgrading only adds
what a client can read: the risk is writing too new, never reading too old.

**Two releases per app, and the app decides**
([ruling 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
The capability release (`pqReady`) reads everything, upgrades the app's enrollment and publishes
its namespace keys, and goes on writing legacy. The active release (`pqActive`, or a
`CryptoConfig` the app names) writes the nskey data path. The one discipline asked of the app's
developer is that the capability build reaches every install before the active one ships. The
SDK never picks a scheme per destination. A write toward an Atsign that has published no key for
the namespace is refused by name, or takes the legacy fallback the app opted into
([section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)).

**Defaults.** at_client 4.0.x defaults to `PqPosture.legacy`, and an app names `pqReady` or
`pqActive` to move earlier. The legacy provider stays for reading. Legacy key material goes on
being minted and conveyed until the ecosystem is post-quantum, not merely the Atsign
([ruling 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
The default flips still to come are in [Planned changes](#planned-changes).

### Usability and crypto-agility

`AtCollection` and `at_client` exist so that application authors, human or AI, can build on
the Atsign Platform with few footguns. This design is held to the same bar: in the common case
the user sees no new task, and the app author writes no new code. A change that adds a flag a
user must pass, a file a user must manage, an operator step, or a break between peers is not
done.

What that means today:

- **No admission step.** An enrollment is conveyed the namespace keys of every namespace its
  grant covers when it is approved, and every key minted after that
  ([ruling 147](detail/decisions.md#147-an-nskey-reaches-every-enrollment-with-access-to-its-namespace-when-it-is-minted-and-when-that-enrollment-is-approved-2026-10-04)).
- **Apps supply no key storage.** Namespace privates and conveyed secrets are filed in the
  enrollment's keyfile through `AtKeysIo`.
- **Old data stays readable, and there is no flag day.** Routing is per value, and legacy data
  is re-encrypted only when the app rewrites it.
- **A clash between processes is refused, not merged.** A second process that opens a store
  already open in another is refused (`AtStorageInUseException`), and keyfile updates run under
  an inter-process lock (`AtKeysFileLock`).

**Crypto-agility.** A scheme changes by id, with no schema change: each value routes by its
provider id. Every published key list (key packages, nskey advertisements, `_apsk` and the
signing root) is a list of `{kid, use, alg, pub, status?}` entries, and a secret envelope names
its `{suite, kid}`. Adding an algorithm is an add by the advertiser, and readers skip entries
they do not understand
([ruling 119](detail/decisions.md#119-crypto-agility-each-advertisement-adds-and-the-signer-chooses-2026-08-27)).
An encryption migration costs two releases, first minting and reading the new algorithm and then
sealing to it; a signing migration costs three
([ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28)).

## Document map

| Doc | What lives there |
|---|---|
| **design.md** (this doc) | Why the work exists, and the design as built: key shapes, providers, flows, invariants and defaults, by subsystem. Ends with the changes still planned. |
| [`seal-spec.md`](seal-spec.md) | The byte-level companion: the Atsign seal envelope around RFC 9180, which suite each version byte names, the framing and the error model, paired with the vectors under `packages/at_chops/test/vectors/`. |
| [`acceptance.md`](acceptance.md) | The Given/When/Then use-case catalogue with concrete at-keys, and the test harness. |
| [`decisions.md`](decisions.md) and [`detail/decisions.md`](detail/decisions.md) | The decision log: one index row per ruling, and each ruling's reasoning and rejected alternatives under a heading with the same number. |
| [`implementation-plan.md`](implementation-plan.md) | Open work only, in one prioritised list ([`## TODO`](implementation-plan.md#todo), P0–P3) and a [`## PARKED`](implementation-plan.md#parked) list. What is done is in `git log`. |

When a mechanism's reason matters, this doc states the mechanism and links the ruling. When a
mechanism has a testable case, this doc links the use case rather than restating it.

## Table of contents

- [0. Scope & conventions](#0-scope--conventions)
- [1. Subsystem A — D1 nskey data path](#1-subsystem-a--d1-nskey-data-path)
- [2. Subsystem B — the secret-sharing substrate](#2-subsystem-b--the-secret-sharing-substrate)
- [3. Subsystem C — at_chops PQ primitives](#3-subsystem-c--at_chops-pq-primitives)
- [4. Subsystem D — structural design (CryptoProvider seam, AtKeys/AtKeysIo & key stores, WASM barrel)](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)
- [5. Subsystem E — worked walkthrough (at_talk)](#5-subsystem-e--worked-walkthrough-at_talk)
- [6. Implementation notes & file-level pointers (consolidated)](#6-implementation-notes--file-level-pointers-consolidated)
- [7. Trust model](#7-trust-model)
- [8. Subsystem F — inter-server PQ authentication (IS-1)](#8-subsystem-f--inter-server-pq-authentication-is-1)
- [9. Subsystem G — signature agility (the auth/signing key split)](#9-subsystem-g--signature-agility-the-authsigning-key-split)
- [10. Record lifetimes and caching](#10-record-lifetimes-and-caching)
- [Planned changes](#planned-changes)

---

## 0. Scope & conventions

This document states what the code on trunk does. Each section describes one subsystem; a
mechanism carries its reason in a sentence and links the ruling that settled it.

### Conventions

- **`aS = pq`**: unless a passage says otherwise, the atServer is one that supports this
  design's verbs (`enroll:listns`, `enroll:link`, ML-DSA PKAM). The notation follows
  [`acceptance.md`](acceptance.md).
- **Key names are written in full**, with the `@<owner>` suffix:
  `public:__nskey.app_1.my_apps@alice`, not a bare `nskey`. The record names in this document
  are fixed wire vocabulary; `nskey_records.dart` holds them, and
  `test/wire_literal_pins_test.dart` pins each one.
- The namespace key-shape legend and the `(owner, namespace)` identity discipline follow the
  use-case catalogue in [`acceptance.md`](acceptance.md).
- Worked examples here trace mechanics. The testable form of each is in
  [`acceptance.md`](acceptance.md).

### Subsystem map

- [Section 1](#1-subsystem-a--d1-nskey-data-path): the nskey data path. Layers, providers,
  key shapes, the content-key model, cold start, rotation, and the rollout flags.
- [Section 2](#2-subsystem-b--the-secret-sharing-substrate): the secret-sharing
  substrate. `kpid` addressing, `__ssenv` envelopes, push and pull, `enroll:listns`, the
  enrollment record, and the self-retrofit.
- [Section 3](#3-subsystem-c--at_chops-pq-primitives): the at_chops primitives. X-Wing,
  ML-KEM-1024, `pqSeal`/`pqOpen`, ML-DSA.
- [Section 4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel):
  the `CryptoProvider` seam, `AtKeys`/`AtKeysIo` and the key stores, the WASM barrel split.
- [Section 5](#5-subsystem-e--worked-walkthrough-at_talk): worked
  walkthroughs, NoPorts and at_talk.
- [Section 6](#6-implementation-notes--file-level-pointers-consolidated): implementation
  notes.
- [Section 7](#7-trust-model): the trust model.
- [Section 8](#8-subsystem-f--inter-server-pq-authentication-is-1): inter-server
  post-quantum authentication.
- [Section 9](#9-subsystem-g--signature-agility-the-authsigning-key-split): signature
  agility, the split between authentication and data signing keys.
- [Planned changes](#planned-changes).

Section 1 relies on section 2 for Layer 1 transport and on section 3 for the seal. Section 4's
seam underpins both section 1's providers and section 2's substrate.

---

## 1. Subsystem A — D1 nskey data path

Application data is encrypted under a symmetric content key (CK). The CK is sealed once to the
recipient's namespace key (nskey) and written as a conveyance record of its own, and the nskey
private reaches each authorised enrollment over the secret-sharing substrate. Each (Atsign,
namespace) has one current nskey generation: the owner seals its own content keys to it, and
other Atsigns seal the content keys they share with the owner to it. Self data and sharing use the
same flow; only whose nskey the CK is sealed to differs. D1 is a single tier, and forward
secrecy is a rotation policy of this one path rather than a separate provider
([ruling 2](detail/decisions.md#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted)).

### 1.1 The three layers

The seam routes each stored value to a provider by its `appMetadata.providerId`:

```
LAYER 3  application data  ── AES-256-GCM, key derived per value from a CK ─▶  at/symmetric/AES/GCM
LAYER 2  content key (CK)  ── pqSeal to an nskey (X-Wing or ML-KEM-1024) ───▶  at/nskey/XWING, at/nskey/MLKEM1024
                                                                                (a <ckKid>.__ck record)
LAYER 1  nskey private     ── pqSeal to an enrollment's key package ────────▶  the secret-sharing substrate
                                                                                (transport, beneath the seam)
```

- **Layer 3 (data)** is symmetric only. A value carries its ciphertext and cites its CK by
  `ckKid`; no sealed key rides inside a value.
- **Layer 2 (CK conveyance)** is the `at/nskey/*` provider. The CK is sealed to an nskey and
  written once, as `<ckKid>.__ck.<ckNs>@<owner>`, and every value under that CK cites the
  `ckKid`. Keeping the CK out of the values is what lets deleting one record make every value
  under it unreadable
  ([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).
- **Layer 1 (the nskey private)** puts the private into each authorised enrollment's keyfile.
  It is transport, not a value-level provider: the private travels as a substrate secret sealed
  to the enrollment's key package
  ([section 2](#2-subsystem-b--the-secret-sharing-substrate)). Once a client holds the
  private, it opens any CK conveyed to that generation.

Layer 1 runs when a key is minted, added to or rotated, and when an enrollment is approved.
Layer 2 runs once per CK, and Layer 3 on every write.

### 1.2 The three providers (legacy, at/nskey, at/symmetric/AES/GCM)

| `providerId` | Tags a value that is… | Mechanism | Recipient |
|---|---|---|---|
| `legacy` | legacy data, with its key wrapped inline | RSA-2048 and AES | the recipient's RSA keypair. The default for a value with no `appMetadata` |
| `at/nskey/XWING`, `at/nskey/MLKEM1024` | a CK conveyance record | `pqSeal` of the CK to the nskey key of that KEM ([section 3](#3-subsystem-c--at_chops-pq-primitives)) | the nskey owner: the writer's own Atsign for self data, the recipient for a share |
| `at/symmetric/AES/GCM` | application data | AES-256-GCM under a key derived per value from a CK | none; the CK is cited by `ckKid` and resolved as [section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering) describes |

- **A provider id names the role, and an algorithm only where the value cannot**
  ([ruling 139](detail/decisions.md#139-a-provider-id-names-the-role-and-the-algorithm-only-where-the-value-cannot-2026-09-09)):
  `at/<role>[/<algorithm>]`. The conveyance ids name the KEM because a record routes back to
  the provider instance for that KEM; the AEAD comes from the `pqSeal` envelope's version byte
  ([`seal-spec.md`](seal-spec.md)). `ckKid` and `nskeyKid` stay in `appMetadata`. `at/nskey`
  is the family prefix, so "an `at/nskey` record" means either conveyance id. The ids are
  `nskeyCryptoProviderId`, `mlKemNskeyCryptoProviderId` and
  `symmetricAesGcmCryptoProviderId` in `nskey_records.dart`.
- **Reads route by the id each value carries.** A client registers every scheme it reads, so
  retired schemes keep opening. A client that configures the post-quantum providers registers
  both conveyance providers whatever its own Atsign mints (`CryptoConfig.nskey` and
  `CryptoConfig.readsNskeyWritesLegacy`). A new algorithm gets a new id beside today's, and
  values keep their tag.
- **Which scheme is written is the app's release decision.** The SDK never picks one per
  destination
  ([ruling 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
- **Layer 1 uses the same seal but is not an `at/nskey` record.** The private rides the
  substrate as transport.
- **The schemes coexist in a namespace.** `legacy`, `at/nskey/*` and `at/symmetric/AES/GCM`
  values sit side by side and route per value. Legacy data is read in place and re-encrypted
  only if rewritten.
- **A client at `PqPosture.legacy` registers none of the post-quantum providers**, and a value
  tagged with one is refused with `CryptoProviderNotRegistered`
  ([`acceptance.md` section 13](acceptance.md#13-cross-cutting-acceptance-applies-to-all-flows)).
- **Cold start has no provider.** The only Atsign-level key, the signing root, cannot receive
  an encapsulation, so a namespace with no nskey fails the write
  ([section 1.4](#14-the-nskey-and-the-signing-root)).

The seam itself, `CryptoRuntime` and `CryptoConfig` routing by `appMetadata.providerId`, is in
[section 4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel).

### 1.3 Keys & key shapes

Owner `@alice`, namespace `app_1.my_apps`.

| Object | Shape | Published? | Private held by | Role |
|---|---|---|---|---|
| **nskey advertisement** | `public:__nskey.app_1.my_apps@alice`: mutable, a signed envelope ([section 1.3.1](#131-the-advertisements-signed-envelope)) over `{v, createdAt, keys:[{kid, use, alg, pub, status?}], suites}` | from mint. Hidden from scans, revealed only by an authenticated `showhidden` scan; served on an exact `plookup` to any Atsign | each of Alice's enrollments authorised for the namespace | Alice seals Alice's own CKs to it, and other Atsigns seal shared CKs to it |
| **nskey mint lock** | `_nskeylock.app_1.my_apps@alice`: self key, immutable create, ttl `mintLockTtl` (2 minutes) plus a per-member budget | no | n/a | serialises mint, add and rotate between Alice's enrollments |
| **signing-root mint lock** | `_rootlock@alice`: self key, no namespace, immutable create, ttl `signingRootMintLockTtl` (15 seconds) | no | n/a | serialises minting the signing root between Alice's fully privileged enrollments |
| **CK conveyance** | `<ckKid>.__ck.app_1.my_apps@alice` (self data) | no | n/a | the `at/nskey/*` value: the CK sealed to the nskey key `nskeyKid` names |
| **CK sibling copy** | `<ckKid>.__ck.<ckNs>@alice`, naming its recipient in `appMetadata` | no | n/a | Alice's own sealed copy of a CK Alice shared ([section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)) |
| **current-CK pointer** | `__ckcur.<destination>.<ckNs>.<enrollmentId>.a.__e@alice` | no | n/a | ids only: which CK this enrollment writes under for a destination ([section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)) |
| **verified-advertisement record** | `local:__nskeyverified.<ns>.<enrollmentId>.a.__e@alice` | no, and never synced | n/a | the client's signed record that it verified its own advertisement ([section 1.5.1](#151-the-local-record-of-a-verified-advertisement)) |
| **data value** | `<key>.app_1.my_apps@alice` | no | n/a | `at/symmetric/AES/GCM`: AES-GCM under a key derived per value from a CK; cites `ckKid` |
| **substrate envelope** | `<msgId>.<inReplyTo>.<kpid>.__ssenv.app_1.my_apps@alice` (self key) | no | n/a | Layer 1: a secret, such as an nskey private, sealed to key package `kpid` ([section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify)) |
| **enrollment key package** | in the enrollment record ([section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify)) | through `enroll:listns` | the enrollment | the recipient of Layer 1 |

Across Atsigns the shapes mirror this, with `@bob` owning what Bob writes for Alice: the data
value `@alice:<key>.app_1.my_apps@bob` and the conveyance `@alice:<ckKid>.__ck.<ckNs>@bob`,
both resting on Alice's nskey as fetched from Alice's advertisement. The conveyance carries
`ttr -1` and `ccd: true`, so Alice's atServer caches it from the notification and drops the
copy when Bob deletes the original
([ruling 142.1](detail/decisions.md#1421-a-shared-conveyance-is-cached-at-its-recipient)).
That ownership is why forward secrecy across Atsigns is bilateral
([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).

**Two Atsigns, never one.** Every operation resolves both the **record owner** and the
**nskey owner**. The record owner is `sharedBy`, which the HPKE `info` binds as
`at/nskey:<sharedBy>:<ns>`, so self and inbound conveyances stay domain-separated under one
key. The nskey owner is `sharedWith ?? sharedBy`: whose nskey seals or opens the record, and
the CK cache's scope. On an inbound record the two differ, so a reader never looks the key ring
up by `sharedBy`
([ruling 15](detail/decisions.md#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02)).

**The nskey private.** A generation holds one KEM private for each algorithm it carries. Each
decapsulates content keys only, the owner's own and those sealed to it by others, and never
decrypts application data. A private is filed in the enrollment's keyfile as its seed, under
the id `nskey.<namespace>.<nskeyKid>`, because an ML-KEM decapsulation key cannot be turned
back into its public half.

**Keying.** Privates are held by `(owner, namespace, nskeyKid)`, since rotation leaves earlier
generations in use for retained history, with a current generation per `(owner, namespace)`
for sealing. The CK cache is keyed `(owner, ckNs, ckKid)` and never by `ckKid` alone, since
kids are unique only within a namespace (`ContentKeyCache`). In both, `owner` is the nskey
owner. A value whose namespace key this client holds no private for is undecryptable, and is
yielded as an error (`NskeyPrivateUnavailableException`), never skipped.

**One key package per enrollment.** Each enrollment has one APKAM keypair and one key package
([decision #F](detail/decisions.md#6-resolved--open-execution-decisions-af)), and holds the
namespace's nskey privates as conveyed to it over the substrate.

**Minting.** A generation is minted fresh, with one key for each algorithm in the minting
client's `keyEstablishmentAlgorithms`, duplicates dropped
(`PublishedNskeyKeyRing.wantedKeyAlgorithms`). Every key comes from a fresh random seed and is
never derived from a shared one
([ruling 10](detail/decisions.md#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30)).
The advertisement is published at mint; there is no owner-only stage and no promotion step
([ruling 13](detail/decisions.md#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)).
A client whose configuration names an algorithm the current generation does not offer adds a
key for it to the current generation in place, under the same lock, keeping the generation's
`createdAt` (`PublishedNskeyKeyRing.add`). An add is not a rotation: a rotation mints only new
material
([ruling 119, item 2](detail/decisions.md#2-the-nskey--a-rotation-mints-fresh-and-a-client-adds-what-it-needs)).

**`alg` and `suites` on the advertisement.** Each entry's `alg` names the KEM it is a key for.
A sender cannot tell an X-Wing key from an ML-KEM one by looking, and encapsulating under the
wrong KEM produces a conveyance the owner can never open.

- **What a reader keeps.** An entry missing any of `kid`, `use`, `alg` or `pub` is skipped
  (`PackageKey.fromJson`), and so is one naming an algorithm this build cannot encapsulate to.
  An advertisement with nothing left to seal to, or whose every usable key is retired, is
  refused (`ApkamSignedAdvertisedKeys.verify`). The same check refuses a usable entry whose key
  has the wrong length for its algorithm, or whose `kid` is not the SHA-256 prefix of the key.
- **What a sender picks.** It takes the first algorithm in its own `sealsToKeyAlgorithms`,
  strongest first, that the advertisement offers as active (`NskeyAdvertisement.usableFor`).
  Nothing in common is a refusal, never a walk to a broader namespace (`NskeyResolver`).
- **`suites`** names the sealing constructions the owner can open. It is derived from the
  generation's own keys, never from what the minting build supports. The sender intersects it
  with what its provider produces and derives the `pqSeal` version from the match:
  `x-wing-rfc9180-v1` for an X-Wing key, `ml-kem-1024-rfc9180-v1` for an ML-KEM-1024 key. No
  overlap is a refusal. An advertisement carrying no `suites` list is refused at the parse,
  unlike a key package, because senders act on an advertisement at once
  ([ruling 50.3](detail/decisions.md#503-the-kem-is-configured-the-construction-is-negotiated)).

#### 1.3.1 The advertisement's signed envelope

The advertisement payload is wrapped in a signed envelope of type `at-nskey-ring+jws`
(`EnvelopeType.nskeyRing`), signed with the minting enrollment's client data signing key.

- **Who verifies, and against what.** Before encapsulating anything to an advertisement, a
  reader verifies its envelope against the `_apsk` the signing enrollment published under the
  owning Atsign (`ApkamSignedAdvertisedKeys`, through
  `AtClientEnvelopeSigner.verifyEnvelopeSignature` expecting `EnvelopeType.nskeyRing`). The
  check is the same for the owner's own clients and for other Atsigns.
- **What is refused.** An advertisement whose envelope carries no signature, or whose
  signature does not verify.
- **Ordering.** A minting client publishes its own `_apsk` before the advertisement, so a peer
  always has the key to check against.
- **What it is for.** This signature, not immutability of the record, is what stops one
  advertisement being substituted for another.

The envelope's shape and protected header are in [section 9.4](#94-the-signed-envelope). What the
signature establishes, and what rests on the atServers, is in
[section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify) and
[section 7](#7-trust-model).

### 1.4 the nskey and the signing root

> The Atsign-level key is `public:pq_signing_root@<atSign>`. It signs and verifies only. It is
> not a KEM target, and nothing encapsulates to it, so there is no universal cold-start
> recipient: post-quantum sharing needs the recipient to have used or authorised the namespace
> ([ruling 18](detail/decisions.md#18-pq_signing_root-is-the-user-owned-signing-root-2026-08-03)).

**The nskey's public half is published at mint.** Minting writes
`public:__nskey.app_1.my_apps@alice` there and then, before any data and before any share. A
recipient that has used the namespace has a key there.

**Why the double underscore.** A published key reveals that its namespace exists, and
namespaces are app names, so the set of them profiles an Atsign. A `public:__` key is revealed
only by `showhidden`, and an unauthenticated scan ignores `showhidden`. So the only scan an
outsider can issue never returns it, while `plookup` still serves it on an exact name to any
Atsign. A single underscore would hide the key from every scan, but the atServer writes a
`public:_` key outside its commit log, so sync could never push it. For the same reason the
advertisement is written straight to the atServer rather than through the local-first put path:
it is useful only once a peer can fetch it
([ruling 13](detail/decisions.md#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)).

**The advertisement is mutable, and writes take a lock.** The record holds the current
generation and is overwritten on rotation. Stopping two of the owner's enrollments minting or
rotating at once is the job of a short-ttl immutable lock key, `_nskeylock.<ns>@<atSign>`: a
self key, since nobody else can write the owner's records
([ruling 105](detail/decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16)). A mint runs:

1. **Read the roster.** The client reads the namespace's enrollments from `enroll:listns`,
   and the time of the namespace's last revocation. A client whose own roster entry carries no
   verified key package could be conveyed nothing, so it mints nothing
   (`PrePublishConveyance.prepare`).
2. **Take the lock.** Its ttl is sized from the roster: `mintLockTtl`, plus
   `lockBudgetPerMember` (2 seconds) for each listed enrollment, key and conveyance, and never
   more than the atServer's 15-minute mutex limit (`PrePublishConveyance.lockTtlFor`). The
   loser backs off and re-reads.
3. **Re-read the advertisement from the atServer.** A cold-start mint that finds one published
   adopts it rather than overwriting a generation peers may already hold.
4. **File, convey, then publish.** The client files each private in its keyfile, publishes its
   own `_apsk`, and conveys the privates to every enrollment on the roster
   (`pushSecretToNamespaceMembers`). Only then does it write the advertisement, so publishing
   is the commit point
   ([UC-A3.7](acceptance.md#47-uc-a37--a-namespace-keys-private-reaches-every-listed-enrollment-before-anyone-can-seal-to-it)).
   If a revocation has touched the namespace since step 1, it publishes nothing and retires
   what it filed.
5. **Abandon on expiry.** A winner whose lock has expired by the time it would publish
   abandons instead.

Conveyance is best effort per member. A member the push misses is named in a warning, and it
gets the private by fetching and then asking, at its next start or its first read that misses
it ([UC-A3.6](acceptance.md#46-uc-a36--a-client-that-needs-a-private-it-does-not-hold-fetches-it-else-asks-else-fails)).
A rotation does not adopt: it mints whatever it finds published
(`PublishedNskeyKeyRing.rotate`). An add re-reads inside the lock and does nothing if the
generation changed in between.

Every re-read goes to the atServer, never to local storage or a cache. A sibling enrollment's
publication is not in local storage until sync catches up, and reading that absence as a cold
start is what would publish a second key over the first.

**The ttl is the only release, so it is also a cooldown.** Nothing deletes the lock. A rotation
of a namespace minted or rotated within the ttl is refused rather than queued
([ruling 105.6](detail/decisions.md#1056-built-the-cooldown-binds-rotation-too)). Because
`NskeyRotation.revokeEnrollmentAndRotate` revokes first and rotates after, a rotation the
cooldown refuses leaves the revoked enrollment cut off from the atServer while still holding
the live generation, until the caller retries after the ttl. Release at
expiry needs at_server c3.16.2 or later, and the client does not check the version
([ruling 143.7](detail/decisions.md#1437-minting-needs-at_server-c3162-or-later)).

The signing root follows the same pattern behind `_rootlock@<atSign>`
([ruling 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)).

**The private half** is conveyed to each enrollment as a substrate `Secret` named
`__nskey.<nskeyKid>` in the namespace, never through the RSA-protected self-encryption-key
chain. A client gets the public half by `plookup` and the private from the substrate.

**The signing root.** `public:pq_signing_root@alice` is the Atsign-level, user-owned root of
trust.

- **What it is.** An ML-DSA-65 key (`PqSigningRoot.rootKeyAlgo`) with no namespace, in a
  mutable record. It signs and verifies, and anchors the chain of links that vouch for
  enrollment signing keys
  ([ruling 56.1](detail/decisions.md#561-the-signing-chain-is-root-anchored-chain-links-are-provisional)).
  Links are written through `enroll:link`
  ([ruling 157](detail/decisions.md#157-a-link-vouches-for-one-key-and-the-atserver-writes-it-2026-10-16)).
- **Its value.** `{v, keys:[{kid, use, alg, pub, status?}]}`, the `_apsk` vocabulary, so its
  algorithm can change without a second record and a retired root stays advertised for what it
  signed
  ([ruling 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)).
  No client operation rotates the root.
- **Who holds it.** Only a fully privileged enrollment mints it: one with `rw` on both `*`
  and `__manage` (`isFullyPrivileged`). The private is filed in that enrollment's keyfile and
  reaches the Atsign's other fully privileged enrollments over the substrate, as a
  per-enrollment secret that is never forwarded to a namespace-scoped enrollment
  (`PqSigningRoot.secretName`). The `_rootlock` stops two of them minting two roots.
- **Not a recipient.** Nothing is encapsulated to it, so it is not a cold-start recipient.
- **Naming.** It carries no namespace suffix: `pq_signing_root`, not `publickey.pq`, which
  would put it in a namespace called `pq`.

Its lifecycle is in
[section 2.5](#25-the-authenticated-self-retrofit-flow-fresh-auto-approved-enrollment).

**Cold start fails.** When a sender finds no nskey for a destination (see
[section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding) for how levels are searched),
there is no post-quantum key to substitute. Under publication at mint, a missing nskey means the
recipient has never used or authorised the namespace.

- **The refusal.** `NamespaceKeyUnavailableException`, carrying the Atsign and the namespace
  so an app can say which recipient has not enabled what.
- **Asking first.** `CryptoRuntime.isReadyFor(atSign, namespace)` asks the same question of the
  default scheme before a user composes anything. `CryptoRuntime.canSealTo(atSign, namespace)`
  answers true only when the recipient advertises a verified key at exactly that namespace; it
  never throws, answering false with a warning when it cannot tell
  ([ruling 161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02)).
- **The one escape is opt-in.** `AtClientPreference.allowLegacyCryptoFallback` is off by
  default, because a silent downgrade to RSA is what this design exists to stop. It applies
  per write, so it is forward-only. Once the recipient publishes, shares are post-quantum again:
  from the first share after the 30-second window in which a share remembers finding nothing
  (`NskeyResolver.shareMissMemory`), or at once for a program that asks `canSealTo`.
  `disallowLegacyEncryption` overrides it
  ([section 1.8](#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d)).

### 1.5 The CK model, cache, ckKid & appMetadata encoding

**`appMetadata` carries `ns`, and a data value carries `ckNs` too**
([ruling 19](detail/decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)).
The namespace cannot come from the at-key name: `AtKey.fromString` splits at the last dot, so
`someid.d.c.b.a@alice` parses back as key `someid.d.c.b` in namespace `a`. Every record
therefore states its own. That discloses nothing new, since the namespace is already plaintext
in the key name.

- **On an `at/nskey/*` conveyance:**
  `{providerId, recipientKind, ckKid, nskeyKid, ns}`, plus `cutBy` and `cutAt` when an
  enrollment wrote it, and `destination` and `ckNs` on a sibling copy.
  - `recipientKind` has one member, `"nskey"`. It is on the wire so that a future class of
    recipient key could be told apart on records already written. The signing root is not, and
    never will be, one of them.
  - `nskeyKid` names the key the CK was sealed to, so a reader holding several generations
    indexes straight to the right private.
  - `ns` is the level the CK was sealed at, which the HPKE `info` binds.
  - `cutBy` and `cutAt` name the enrollment that cut the CK and when. Only that enrollment
    collects the key, and its grace counts from `cutAt`
    ([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).

  The `<ckKid>` in the record's name equals `appMetadata.ckKid`. The value is the `pqSeal`
  envelope around the CK, with no separate `iv` or `kemCt`.
- **On an `at/symmetric/AES/GCM` data value:** `{providerId, ckKid, salt, iv, ns, ckNs}`.
  - `salt` is 32 bytes of fresh randomness per value, base64-encoded. The value is encrypted
    under `HKDF-SHA256-Expand(prk = CK, info = "at/symmetric/AES/GCM/value-key/v2" ‖ salt,
    L = 32)` rather than under the CK itself, so no `(key, nonce)` pair can repeat however
    many values share a CK. The CK is already a uniform 256-bit key, so it keys the expand step
    directly (RFC 5869 section 3.3). A value carrying no `salt` is read under the CK itself
    (`SymmetricAesGcmProvider.valueKeyOf`).
  - `iv` is the 12-byte GCM nonce, per value, base64-encoded. No sealed key is present.
  - The AAD is `at/symmetric/AES/GCM:<sharedBy>:<sharedWith>:<key>.<namespace>`, binding the
    value's whole name, so two values under different sub-collections cannot have their
    ciphertexts swapped.
  - `ns` is the level the write's walk started at, and `ckNs` the namespace the CK and its
    conveyance live at. They differ whenever resolution walked up, and neither is derivable
    from the other.

**`ckKid`** is the first 16 hex characters of the SHA-256 of the CK, so identical keys
deduplicate (`ContentKey`). It is unique within `(owner, ckNs)` and keys the CK cache with
them. Since the id is public, a CK is always minted from a secure random source.

**Namespace resolution.** A write to the client's own Atsign and a share search for their key
differently.

- **A write to the client's own Atsign** starts at `NskeyResolver.startLevelOf`: the longer of
  the value's own namespace and the most specific namespace the client holds a namespace private
  for that the value's whole name ends with, after a dot. A key read from its string form names
  only its last label as its namespace, and the held namespaces recover the rest
  ([ruling 159](detail/decisions.md#159-a-write-starts-its-walk-at-the-namespace-its-key-names-in-full-2026-11-01)).
  - **The walk.** From there it walks most-specific-first (`d.c.b.a`, `c.b.a`, `b.a`, `a`)
    and seals to the first published nskey it finds. The namespace it lands on is `ckNs`, and
    an empty walk is a cold start.
  - **What it remembers.** A level found empty is remembered for `missMemory` (15 minutes),
    but a remembered miss never decides a refusal: when nothing resolves, the skipped levels
    are probed for real. A hit is never remembered, since it would let a later walk skip a
    deeper level and miss a key minted there.
  - **Waiting for start-up.** A write that finds no key while the client's start-up has yet to
    seed a namespace covering it waits for that seeding, at most 30 seconds
    (`StartUpSeeding.wait`)
    ([ruling 160](detail/decisions.md#160-a-write-made-before-start-up-has-seeded-waits-for-it-2026-11-01)).
- **A share** walks its recipient's levels (`NskeyResolver.shareLevelsOf`): every namespace
  the key's full name ends with after a dot, most specific first, folded, leaving out `*` and
  any level with a label starting `__`
  ([ruling 161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02)).
  - **One batch.** The levels are asked about in one `batch:` of lookups, and the share is
    sealed at the most specific level the recipient advertises a key at. What the writer holds
    does not enter into it, and a share does not wait for start-up.
  - **What it remembers.** A level found missing decides without a lookup for
    `shareMissMemory` (30 seconds).
  - **Requiring a namespace.** `PutRequestOptions.sealToNamespace`, and `sealToNamespace` on
    the notify paths, require exactly one namespace and do not walk.
- **In both,** only a not-found makes a level empty. A level whose advertisement cannot be
  fetched stops the walk there, and the write uses that level's cached advertisement within its
  grace, or fails. It never seals to a broader key that the deeper one was minted to exclude
  ([ruling 143.5](detail/decisions.md#1435-only-a-not-found-lets-the-resolver-walk-up)).

The walk mirrors the atServer's own suffix authorisation, so the crypto gate never widens past
the transport gate. It is also what makes AtCollection workable: sub-collection namespaces
embed a per-item id, and an exact-match rule would need a keypair and a conveyance per item
([ruling 19](detail/decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)).

**CK cache.** Keyed by `(owner, ckNs, ckKid)`, where `owner` is the nskey owner, so a CK is
scoped to the recipient it was cut for, not to the sender
([ruling 14](detail/decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)). The
`at/nskey/*` provider fills it when it opens a conveyance, and the data provider reads it for
each value. Only the client that cut a CK makes it current: an opened conveyance is cached but
never promoted, because sync is unordered and an older record would otherwise roll new writes
back onto a superseded key.

**The current CK is per enrollment.** Each writing enrollment keeps its own current CK per
destination. A pointer on the atServer, in the enrollment's own reserved namespace
(`__ckcur.<destination>.<ckNs>.<enrollmentId>.a.__e@<atSign>`), names it. The pointer holds
only ids (`ckKid`, `nskeyKid`, `ownNskeyKid`) and is written unencrypted (`CurrentCkPointer`).
After a restart the enrollment resumes the CK by opening its sibling copy
([section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)), so an ephemeral
local store does not force a fresh CK
([ruling 142.2](detail/decisions.md#1422-each-enrollment-keeps-its-own-key-and-its-siblings-can-open-it)).

**Conveyances are kept from application code.** No notification subscriber is handed a
conveyance notification, and `getKeys` lists conveyances only with `showHiddenKeys`
([ruling 142.5](detail/decisions.md#1425-conveyances-are-kept-from-application-code)).

**Key discovery, and how a sender learns of a rotation.** A sender gets a recipient's
`public:__nskey.<ns>@<recipient>` by `plookup` and verifies it
([section 1.3.1](#131-the-advertisements-signed-envelope)). No failed decapsulation is ever
reported back: the sender never decapsulates, and the recipient fails on its own device. So the
sender keeps a time-bounded cache of the advertisement, and `CkManager.ensureCurrent` compares
the advertised kid with the one its current CK was conveyed under. A mismatch cuts a fresh CK.

- **Why a cache.** It keeps the network off the write path, since `ensureCurrent` runs on every
  write and fetching each time would break offline writes.
- **How long it holds.** An advertisement is trusted for `advertisementTtl` (15 minutes). After
  that, a re-fetch that fails for any reason but a not-found keeps serving it for up to
  `advertisementStaleGrace` (15 minutes more), while a not-found ends sealing to that key at
  once
  ([ruling 143](detail/decisions.md#143-namespace-key-advertisements-no-ttr-a-not-found-is-final-and-a-clients-own-advertisement-refreshes-2026-09-30)).
  The worst-case delay before a sender notices a rotation is the ttl plus the grace
  (`PublishedNskeyKeyRing.advertisementTtl`).
- **Never a cached copy at the reader's atServer.** The advertisement carries no `ttr`, and the
  client always reads it from the owner's atServer rather than from a copy its own atServer
  holds
  ([ruling 145](detail/decisions.md#145-a-readers-atserver-caches-no-public-record-without-a-ttr-2026-09-30)).
- **The owner's own advertisement** is read local-first, which sync keeps current, through the
  same cache, and is re-read early whenever sync lands a change to it. Bytes already verified
  are not verified again, so the owner's writes need no network while nothing has changed. The
  privates Alice's clients hold come from the substrate
  ([section 2](#2-subsystem-b--the-secret-sharing-substrate)).

#### 1.5.1 The local record of a verified advertisement

The in-memory cache does not survive a restart, so each client keeps a record of the
advertisement bytes it verified (`VerifiedAdvertisementRecord`):

- **Where.** `local:__nskeyverified.<namespace>.<enrollmentId>.a.__e@<atSign>`, a `local:`
  key that never syncs.
- **What it is.** A signed envelope of type `at-verified-advertisement+jws`
  (`EnvelopeType.verifiedAdvertisement`), signed with the client's client data signing key, so
  nothing that can only write local storage can produce one. It names the bytes verified and
  the namespace keys filed for the namespace when it was written, retired ones included.
- **When it is used.** A start that cannot reach the atServer accepts its own advertisement
  from local storage only when this record vouches for exactly those bytes and for the keys the
  client holds now. When the atServer answers, the atServer decides.

What this leaves open is a copy of local storage restored from before a rotation whose key
never reached the client: it is accepted until sync pulls the current advertisement, as an
online start already accepts it until then. A client restarted without its atServer trusts the
last advertisement it verified online, however long ago; the next start that reaches its
atServer checks it again.

### 1.6 The uniform data flow + cold-start + resolution/ordering

One write and read pattern serves self data (Alice to Alice) and sharing (Bob to Alice); only
whose nskey is the target differs.

**Write.** The CK manager (`CkManager`) runs before the put pipeline starts, and the data
provider never touches asymmetric crypto:

1. **`ensureCurrent`.** `CkManager.ensureCurrent(context, valueKey)` resolves the destination's
   nskey ([section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)) and cuts a fresh CK
   when there is no current one, when the destination's advertised kid has moved, when the
   sender's own kid has moved for a share
   ([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)),
   or when `ckRotationPolicy` says so. A CK is per recipient, so writing to Bob and writing
   Alice's own data use different keys
   ([ruling 14](detail/decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)).
   Cuts queue behind one another within a client, so racing writes share one fresh CK; an
   explicit `rotateContentKey` always cuts.
2. **Convey the CK once** (`at/nskey/*`), sealed to the destination's nskey and written as
   `<ckKid>.__ck.<ckNs>@<owner>` stamping `nskeyKid`. The conveyance travels the same route as
   the write that cites it; a notification's is written remote-first. For a share, the same CK
   is conveyed a second time, as the **sibling copy**:
   - **What it is.** `<ckKid>.__ck.<ckNs>@<sender>`, sealed to the sender's own key at the
     sender's own level (the most specific namespace the sender holds a key for that covers the
     value) and naming the recipient in its `appMetadata`. It lets the sender's other
     enrollments, and the sender after a restart, open what it shared.
   - **Nothing is minted for it.** A sender with no key covering the value, one whose start-up
     has not yet published that key, or one whose level is broader than the recipient's, shares
     without the copy and logs a warning. The first share after it holds a key cuts a fresh CK
     with its copy
     ([ruling 161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02),
     item 7).
3. **Write the data** (`at/symmetric/AES/GCM`): AES-256-GCM under a key derived from the CK and
   a fresh salt, stamping `ckKid`, `salt`, `iv`, `ns` and `ckNs`.

A share therefore writes one ciphertext and up to two conveyances. An application that wants a
separate self copy of the value, as AtCollection does, still writes one.

**Read.** A conveyance is opened when a value that cites it is read:

1. The data provider looks the CK up in the cache by `(nskey owner, ckNs, ckKid)`.
2. **On a miss** it reads the conveyance (`SymmetricAesGcmProvider._resolveFromConveyance`).
   For a value shared with this client that means its own atServer's cached copy first, then
   the original; for a value this Atsign shared, its sibling copy. Each is read from local
   storage first, then from the atServer. Reading the conveyance runs `at/nskey/*`, which opens
   the CK with this client's own private for the `nskeyKid` the record names, never the record
   owner's, and caches it.
3. **A conveyance found nowhere** raises `ContentKeyUnavailableException`, which a caller can
   retry once sync has caught up. A CK deleted for forward secrecy stays unavailable, by design.
   A conveyance that is there but will not open raises `AtDecryptionException`.
4. **A missing private.** When the client does not hold the private the record names, the key
   ring fetches the conveyance records addressed to its enrollment and asks the Atsign's other
   enrollments (`PublishedNskeyKeyRing.privateHalf`). The read meanwhile throws
   `NskeyPrivateUnavailableException`. A notification that meets it is parked until the
   private is filed, and dropped with a warning after `parkTtl`
   ([ruling 106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17)).

**Cold start.** When the walk finds no nskey for the destination, the write fails. There is
nothing to seal to, because the signing root cannot receive an encapsulation
([section 1.4](#14-the-nskey-and-the-signing-root)). `CkManager.ensureCurrent` raises
`NamespaceKeyUnavailableException`, naming the Atsign and the namespace, in the pre-pass,
before anything is in flight, which leaves the caller free to reroute. The recipient's first use
of the namespace mints and publishes its nskey, and the sender's next resolution finds it. A
seal-and-hold outbox was considered and not built
([ruling 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).

**Binary values.** A value marked `isBinary` is sealed and opened as its bytes, decoded from
and re-encoded to `Base2e15`, rather than round-tripped through UTF-8.

### 1.7 Forward secrecy & rotation levers (CK rotation vs nskey-keypair rotation)

Two levers, with very different costs. The testable rotation and revocation cases are in
[`acceptance.md`](acceptance.md).

**(B5a) CK rotation: the cheap lever for coarse forward secrecy, O(1).** A fresh CK gets a new
`<ckKid>.__ck` conveyance sealed to the namespace's nskey, and new data uses it. Deleting the
superseded conveyance stops anyone opening that CK again, since the CK was never embedded in a
value. Each client drops its cached copy when it observes the deletion through sync
(`ContentKeyEviction`). The lever rides ordinary sync, not the substrate, and conveying the new
CK is one record that every client opens with the shared nskey private.

- **Retention.** A superseded conveyance is kept while any record cites its CK, so an enrollment
  that joins later can read history. Once nothing cites it and its grace is over, the
  enrollment that cut it (`cutBy`) deletes it, after sync has caught up
  (`collectUnusedOnceCaughtUp`). The grace is `supersededCkGrace`, 8 days by default
  (`defaultSupersededCkGrace`), the longest an atServer keeps a notification. It counts from
  the cut of the successor, or of the key itself when nothing replaced it, as `cutAt` records,
  so a recipient can still open a notification sent under it
  ([ruling 142.3](detail/decisions.md#1423-a-superseded-key-goes-once-no-record-cites-it-and-its-grace-is-over)).
- **The bound.** A client that already opened a CK holds it until it observes the deletion, so
  this forward secrecy is bounded by when each client next syncs. Deletion discipline is what
  the property rests on.

**(B5b) nskey rotation: the expensive lever for post-compromise security and revocation,
O(n) in the enrollments.** `NskeyRotation.rotateNamespaceKey` runs the mint of
[section 1.4](#14-the-nskey-and-the-signing-root) as a rotation:

1. Take `_nskeylock.<ns>@<atSign>`.
2. Mint a new generation.
3. Convey its privates over the substrate to every enrollment `enroll:listns` lists, except any
   in `excludeEnrollmentIds`.
4. Overwrite `public:__nskey.<ns>@<atSign>` with the new advertisement.
5. Leave the lock to expire.

It needs `rw` on the namespace, which the atServer already requires for the advertisement
write.

- **Earlier generations are kept, not discarded.** A client keeps every nskey private it has
  held, keyed by `nskeyKid`, so retained conveyances sealed to an earlier generation still open.
- **A newly approved enrollment** is conveyed every generation its approver holds in the
  namespaces its grant covers
  ([ruling 147](detail/decisions.md#147-an-nskey-reaches-every-enrollment-with-access-to-its-namespace-when-it-is-minted-and-when-that-enrollment-is-approved-2026-10-04)).
  A client that meets a conveyance for a generation it lacks fetches and asks for it on demand
  ([section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)).

**Senders must notice.** Rotation is the revocation lever, so a peer still sealing to the
superseded generation hands the revoked enrollment a key it can open. Nothing tells a sender, so
it re-resolves the advertisement at every `ensureCurrent`, from its cache while that is fresh,
and cuts a fresh CK when the kid has changed
([section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)).

**So must the sender's own side**
([ruling 154](detail/decisions.md#154-a-shared-content-key-follows-the-senders-own-namespace-key-too-2026-10-09),
[UC-A5.7](acceptance.md#67-uc-a57--a-content-key-follows-both-namespace-keys-it-rests-on)).
A shared CK is conveyed twice, to the recipient and as the sibling copy sealed to the sender's
own nskey. A revocation on the sender's Atsign rotates its own namespace keys just as one on the
recipient's rotates the recipient's.

- **What it compares.** `ensureCurrent` compares the own generation the sibling copy was sealed
  to (`ownNskeyKid`) with the newest own generation this enrollment both sees advertised and
  holds the private for. It cuts a fresh CK when they differ, unconditionally, before the
  rotation policy is asked.
- **A generation whose private has not arrived.** While a new own generation is advertised and
  its private has not arrived, the current CK is kept, and the check's `privateHalf` call pulls
  the missing private from the Atsign's other enrollments.
- **A CK cut in that window for another reason** (a first write, the destination rotating, the
  policy) seals its sibling copy to the own generation this enrollment already holds, its
  public half re-derived from the held seed (`heldPublic`). Where the client holds none, the
  share goes without a copy rather than failing.
- **The pointer** records both generations. A restart resumes only a pointer that names an own
  generation the sender holds, and a pointer written without an `ownNskeyKid` field names none.

Rotation buys namespace-granular post-compromise security, and it is the lever that cuts one
enrollment off. It does not give per-message forward secrecy or re-encrypt history, since the
old private is retained. Coarse forward secrecy comes from B5a.

**When each lever fires by default.**

- **On revocation.** At each start a client rotates any namespace a revocation has touched
  since the advertisement was last written (`NskeySeeding.rotateIfRevoked`), without asking any
  policy. It compares the namespace's last revocation, read from the enrollment directory, with
  the advertisement record's `updatedAt`; both are atServer timestamps
  ([ruling 130](detail/decisions.md#130-a-revocation-is-discoverable-per-namespace-and-rotates-unconditionally-2026-08-31)).
  A CK follows either namespace key it rests on, with no policy asked either.
- **By policy.** Both levers otherwise ask an application policy, and both defaults are a year
  ([ruling 155](detail/decisions.md#155-content-keys-and-namespace-keys-rotate-yearly-by-default-2026-10-09)).
  `rotateCkAfterOneYear` applies because a CK, with per-value keys, is a key-derivation key with
  no usage limit. `rotateNskeyAfterOneYear` is measured from the advertisement's own
  `createdAt`, on this device's clock, and is what heals a compromise nobody detected. The
  namespace-key policy is asked before a CK is conveyed to one of this Atsign's own namespace
  keys, and once per authorised namespace at every start. A year is NIST SP 800-57 Part 1's
  suggested cryptoperiod for a key-derivation key, and inside its 1-to-2-year range for a
  public key-transport key.

**(B6) Revocation.** `NskeyRotation.revokeEnrollmentAndRotate` revokes the enrollment with
`enroll:revoke`, then rotates every namespace it was granted, and every namespace this client
holds a key for below those grants, excluding it. A revoked enrollment, left out of a rotation,
cannot read data sealed after it. The order is the enforcement
([ruling 47](detail/decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)):

- **Why revoke first.** `excludeEnrollmentIds` stops only the rotating client pushing to the
  excluded enrollment. Another holder honours only what the atServer tells it, so a
  still-approved enrollment could pull the successor from whichever holder answers. Revoking
  first removes it from `enroll:listns`, which lists approved enrollments only, so every roster
  and every holder refuses it at once, including holders that never heard of the rotation.
- **Two privileges.** Rotating needs `rw` on the namespace; revoking needs `rw` on `__manage`.

**Forward secrecy across Atsigns is bilateral.** For self data the owner cuts the CK and owns
the conveyance, so Alice can make Alice's data forward-secret alone. For inbound data the sender
(`@bob`) cuts the CK on Bob's own cadence, and the authoritative conveyance is a record Bob owns on
Bob's atServer; Alice holds only a cached replica opened with Alice's own nskey private. Alice can
purge Alice's copy but cannot delete Bob's, so closing inbound forward secrecy depends on Bob, or on
Alice rotating Alice's namespace key (B5b). That is normal for any forward-secrecy system.

Per-message forward secrecy, O(log n) groups and groups decoupled from namespace authorisation
are D2 ([Planned changes](#planned-changes)).

### 1.8 Migration, rollout & the `disallowLegacyEncryption` flag (D1-C / D1-D)

The nskey data path coexists with legacy and is adopted per app, by the app's own two releases,
with no flag day, no negotiation and no readiness machinery
([ruling 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
**The unit of migration is the app, and an app is an enrollment**: its own keyfile, its own
APKAM keypair, its own namespaces. Apps migrate independently and never have to agree.

**The posture.** A client's rollout settings are one value, `AtClientPreference.posture`
([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)).
`PqPosture` carries these axes:

- `authenticationKeyAlgorithm`
- `dataSigningKeyAlgorithms`
- `seedNamespaceKeys`
- `keyExchangeMode`
- `writesPqByDefault`
- `configuresPqProviders`
- `disallowLegacyEncryption`
- `mintLegacyMaterial`
- `sealsToKeyAlgorithms`
- `keyEstablishmentAlgorithms`

Its constructor refuses combinations that contradict themselves.

| | `legacy` (the 4.0.x default) | `pqReady` | `pqActive` |
|---|---|---|---|
| authentication key | `rsa2048` | `mldsa65` | `mldsa65` |
| data signing keys | none (signs with the authentication key) | `{rsa2048}` | `{mldsa65}` |
| configures the post-quantum providers (reads) | no | yes | yes |
| writes post-quantum by default | no | no | yes |
| seeds namespace keys | no | yes | yes |
| enrollment key exchange | `legacy` | `pq` | `pq` |
| `disallowLegacyEncryption` | `false` | `false` | `true` |
| mints legacy key material | yes | yes | yes |

A posture is a floor. A client is raised to the floor its own keyfile's post-quantum material
sets (`PqPosture.raisedTo`). An enrollment holding a weaker authentication key than its posture
asks for is retrofitted into a new enrollment at its next start
([section 2.5](#25-the-authenticated-self-retrofit-flow-fresh-auto-approved-enrollment)).

**The two releases.**

1. **Capability: `PqPosture.pqReady`.** A rebuild with this posture reads anything ever
   written, legacy or nskey; upgrades its enrollment; mints and publishes its namespace keys, or
   pulls their privates
   ([ruling 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05));
   and keeps writing legacy. Upgrading only ever adds what a client can read. This build must
   reach every install before the next one ships. That ordering is the one thing the model asks
   of an app developer, and it replaces every piece of removed machinery.
2. **Active use: `PqPosture.pqActive`, or an app-named `CryptoConfig`.** The app now writes the
   nskey data path. The SDK never decides to write post-quantum on its own; the app's build
   tells it to.

`appMetadata.providerId` on each stored value, and on each notification, tells the recipient
which provider opens it. Reads are universal across the schemes a client's posture configures,
whoever wrote the value. A `PqPosture.legacy` client configures none of the post-quantum ones
and is refused by name
([`acceptance.md` section 13](acceptance.md#13-cross-cutting-acceptance-applies-to-all-flows)).
The only gate on the write path is **cold start**
([section 1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)): a destination with
no published nskey for the namespace is refused by name, with `allowLegacyCryptoFallback` as
the explicit escape.

**Mixed cases**
([ruling 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
to [ruling 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)):

- **Sibling apps** (`app1.my_apps` legacy, `app2.my_apps` active) coexist freely. The atServer's
  suffix authorisation means neither reads the other, and nskey resolution walking up only ever
  lands on ancestors whose holders could already read through the atServer.
- **A vendor app authorised at the parent** (`my_apps`) is a genuine reader of both children.
  If it is still legacy while a child goes active, it loses access to the child's new records,
  so the parent app's capability build goes first.
- **Mixed installs of one app** on the recipient side are the app developer's release
  discipline, not something the SDK detects.
- **Two apps sharing exactly one namespace** is that developer's problem, well upstream of
  encryption.

**Legacy key material is retained until the ecosystem is post-quantum, not the Atsign**
([ruling 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).

- **Onboarding** still mints the RSA encryption keypair, the `selfEncryptionKey` and the
  `apkamSymmetricKey` (`mintLegacyMaterial` is true in every named posture,
  `mintOnboardingKeys`), and a new Atsign publishes its RSA `public:publickey`.
- **`enroll:approve`** still conveys the encryption private key and the self-encryption key to
  each new enrollment.
- **A posture move** replaces the enrollment with a new one rather than changing its keys. The
  atServer revokes the predecessor as superseded once the successor first authenticates, except
  a fully privileged predecessor, which keeps its life
  ([ruling 134](detail/decisions.md#134-a-posture-move-replaces-the-enrollment-so-the-authentication-key-is-never-retained-2026-09-08)).

**D1-D: the `disallowLegacyEncryption` flag.** A field on `AtClientPreference` that states
"never write with the legacy provider":

- **Set by the posture alone**, with no constructor argument and no setter, and final once the
  preference is built.
- **What it means.** New data is never encrypted with the legacy provider. A write takes a
  post-quantum path or is refused with `LegacyEncryptionRefusedException`, never written legacy
  in silence.
- **What it governs.** Only legacy encryption. Legacy reads stay available, the
  `shouldEncrypt=false` path is unaffected, and a `local:` record is exempt, since it is never
  transmitted
  ([ruling 107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)).
- **How it is announced.** Every client states at creation whether it may write legacy, at
  `info` level. When `allowLegacyCryptoFallback` is set beside it, the client logs at `shout`
  that the fallback has no effect.
- **It wins over the fallback.** The cold-start fallback is a legacy write, so it trips the
  refusal. One setting says "reach this recipient however you can", the other "never write with
  the legacy provider", and the second wins (`CryptoRuntime.mayFallBackToLegacy`).

The legacy provider itself stays, because it is needed for reads for good.

---

## 2. Subsystem B — the secret-sharing substrate

The substrate is the post-quantum transport that moves secrets between the
enrollments of one Atsign. It carries the nskey privates (Layer 1 of
[section 1.1](#11-the-three-layers)), the signing root's private, and an
enrolling device's `apkamSymmetricKey`. **Pull (`requestSecret`) and push
(`pushSecretToNamespaceMembers`) are two faces of one substrate.** The facts they
share (the envelope, the discovery verb, the two gates, the idempotent merge and
the transport) are stated once below, and the pull and push subsections refer to
them.

**The recipient is an enrollment's key package**, addressed by `kpid`: the kid of
the package's active encapsulation key, X-Wing or ML-KEM-1024 (`KeyPackage.kpid`).
Cardinality is **1:1:1**: one enrollment has one APKAM keypair and one key package
(decision #F, [`decisions.md`](decisions.md)). A secret sealed to a key package
opens in every client process that shares that enrollment's keyfile, so nothing is
sealed per process. The per-enrollment private material (the client
authentication signing key, the client data signing keys and the key package's
decapsulation keys) is minted locally and never sent. What is shared is scoped to
the Atsign, to a namespace, or to one enrollment.

The code is in `packages/at_client/lib/src/secret_sharing/`
(`pairwise_secret_sharing.dart`, `secret_envelope.dart`, `envelope_addressing.dart`,
`key_package.dart`, `secret_store.dart`, `enrollment_directory.dart`), with the
envelope signer in `lib/src/signing/envelope_signature.dart` and
`lib/src/mixins/envelope_signing.dart`. Applications reach it through
`package:at_client/at_client_mixins.dart`.

### 2.1 kpid addressing, __ssenv envelope, sign/verify

#### 2.1.1 The envelope address and body

**Address.** `<msgId>.<inReplyTo>.<kpid>.__ssenv.<ns>@<owner>`. It is a self key,
put with `shouldEncrypt=false` because the value is already ciphertext.

- `msgId` is the sender's random uuid.
- `inReplyTo` is the id of the request an answer answers, or `0`
  (`EnvelopeAddressing.unsolicited`) for a request or a push. The copy in the key
  name is a routing hint. A decision to suppress an answer reads the request id
  from the sealed payload instead.
- `kpid` is the recipient's.

`EnvelopeAddressing` owns every builder, matcher and parser of this address, and
`test/wire_literal_pins_test.dart` pins it. An unconsumed envelope expires after
`PairwiseSecretSharing.envelopeTtl` (7 days). A recipient deletes an envelope once
it has consumed it.

**Body.** A signed envelope ([section 2.1.2](#212-the-signed-envelope)) whose
payload is a `SecretEnvelope`, version 2:

```json
{"v": 2,
 "from": {"kpid": "<sender kpid>", "enrollmentId": "<sender enrollment>"},
 "to": "<recipient kpid>",
 "ns": "<namespace>",
 "suite": "x-wing-rfc9180-v1",
 "kid": "<the recipient key sealed to>",
 "sealed": "<base64 pqSeal envelope>"}
```

`sealed` holds `pqSeal` bytes ([section 3](#3-subsystem-c--at_chops-pq-primitives))
at the version the suite maps to: `x-wing-rfc9180-v1` is `0x02` and
`ml-kem-1024-rfc9180-v1` is `0x03` (`SecretSharingAlgos.sealVersionFor`; byte
layout in [seal-spec.md](seal-spec.md)). The seal's `info` has five components:
the label `at_client/secret_sharing/v2`, `<fromEnrollmentId>`, `<fromKpid>`,
`<toKpid>` and `<ns>`. Each is written as its UTF-8 length in two big-endian
bytes followed by those bytes (`PairwiseSecretSharing.sealInfoFor`), so no two
sets of fields give the same info. The same envelope carries a pull request
(payload `kind: 'request'`) and a secret (payload `kind: 'secret'`).

#### 2.1.2 The signed envelope

The envelope around a `SecretEnvelope` is the protocol's one signed-envelope
shape: RFC 7515 general JSON serialization (`SignedEnvelope`, `signEnvelope` and
`verifyEnvelope` in `lib/src/signing/envelope_signature.dart`). It is specified in
full in [section 9.4](#94-the-signed-envelope).

```json
{"payload": "<base64url(JSON)>",
 "signatures": [{"protected": "<base64url(header)>", "signature": "<base64url>"}]}
```

Each protected header carries:

- `alg`: `ML-DSA-65` or `RS256`;
- `typ`: what the envelope was signed for, here `at-secret-envelope+jws`;
- `kid`: the client data signing key's kid;
- `enid`: the signing enrollment, absent when the signer has no enrollment id
  to stamp;
- `v`: `1`.

There is one entry per client data signing key the sender holds. Every entry covers the
same payload and names the same `enid` and `typ`. The sender signs with its
enrollment's client data signing keys, which are the keys its `_apsk` advertises.
An enrollment that holds none signs with its client authentication signing key
([section 9.1](#91-the-two-roles)).

A verifier fetches the `_apsk` of the enrollment the header names, at
`public:_apsk.<enrollmentId>.a.__e@<atSign>` (`apskUri`). It takes the strongest
algorithm the envelope and the `_apsk` share, finds the advertised key the
header's `kid` names, and verifies that one entry. A failure is final; it never
falls back to a weaker signature. It refuses an envelope whose `typ` is not the
one it expects, whose `v` it does not know, or whose entries disagree on `enid`
or `typ`. A cached `_apsk` that fails is dropped and fetched once more. When the
`_apsk` has moved to `r.__e` (revoked or superseded) or `d.__e` (deleted or
expired), the signature is refused as withdrawn (`WithdrawnSigningKeyException`).

#### 2.1.3 Two gates

- **Transport gate (atServer, by namespace).** The envelope sits in `<ns>`, so the
  atServer lets only enrollments authorised for `<ns>` write, get, scan or sync it.
  This is the same gate as on the data itself, and it is defence in depth.
- **Crypto gate (the key package private).** The body is sealed to one key
  package, so only the holder of that enrollment's decapsulation key can open it.
  **This is the confidentiality boundary.**

A sender that seals to the wrong key package still cannot put the secret in front
of an enrollment outside `<ns>`. The gate is defence in depth; the seal is the
boundary.

#### 2.1.4 Verify before decrypt

`PairwiseSecretSharing._consume` verifies the signature first, expecting
`at-secret-envelope+jws` and checking against the sender's `_apsk` on the
receiver's own Atsign. It then parses the `SecretEnvelope` and skips the envelope
unless all of these hold:

- `to` is a kpid this client holds;
- the signature's `enid` equals `from.enrollmentId`;
- the signed `ns` equals the namespace in the key name;
- `ns` is a namespace an atKey can carry;
- `suite` is one this build opens;
- `kid` names a key this client holds, current or retired, because a sender may
  have sealed to a key before a rotation.

Only then does it `pqOpen`. `SecretEnvelope.fromJson` reads version 2 only.

**The namespace and the parties are signed and sealed, not read off the key
name.** A received secret is filed under the namespace the sender signed. Because
the seal's `info` names the sender and the recipient as well, a sealed body opens
only for the sending enrollment, recipient and namespace it was sealed for.

#### 2.1.5 Advertised-key authenticity

**Advertised-key authenticity (decision 2026-07-02, [`decisions.md`](decisions.md) [section 6](detail/decisions.md#6-resolved--open-execution-decisions-af)).**
Every advertised encapsulation key is a signed envelope from the enrollment that
generated it:

- an enrollment's key package, at `metadata.keyPackage` on its enrollment record
  ([section 2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)), typed
  `at-key-package+jws`;
- a published nskey advertisement, at `public:__nskey.<ns>@<owner>`, typed
  `at-nskey-ring+jws`.

Verifiers check it against that enrollment's `_apsk`, and do so the same way
whether the key belongs to their own Atsign or another:

- `VerbEnrollmentDirectory` verifies a key package before anything is sealed to
  it (`verifyAdvertisedKeyPackage`). A package that is not a map, does not
  verify, or verifies as another enrollment's is `rejected`. One whose `_apsk`
  cannot be fetched is `unverified`. Nothing is sealed to either.
- `ApkamSignedAdvertisedKeys` verifies a peer's nskey advertisement the same way.
  `PublishedNskeyKeyRing.mintAndPublish` signs the one it publishes.

Signing makes the crypto gate's recipient key authenticated, rather than only
served. For a keypair secret conveyed over the substrate, which is an nskey
private or the signing-root private, the receiver also checks that the private
corresponds to the published public half. That is a secondary check beneath the
signature: `NskeyPrivateFiling._corresponds` for an nskey private, and for the
root a probe signature the published root must verify (`PqSigningRoot._corresponds`).

The signing root is not on this list. Nothing is encapsulated to it, and it is
verified as a signer. What its record, `public:pq_signing_root@<atSign>`, rests
on is set out in [section 7](#7-trust-model).

#### 2.1.6 The `_apsk` forms

`_apsk` has exactly **two** published forms
([`decisions.md` 39](detail/decisions.md#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05)):

- **bare**: an RSA public key string, read as `rsa2048`;
- **array**: `{"v":1,"keys":[{kid,use,alg,pub,status?}]}`, composed by
  `apskAdvertisement` in at_auth and read by `apskSigningKeys`.

The writer chooses by what the enrollment advertises. `bareApskValueOf`
(`lib/src/signing/apsk_composition.dart`) writes the bare form exactly when the
advertisement is a single active `rsa2048` key, and the array otherwise. The
deciding factor is the enrollment's own key material, never the client's version.
The array must fail loudly in an old bare-RSA parser rather than be misread,
which is why a single-RSA enrollment keeps the bare form.

The client composes both forms. At `enroll:request` they ride
`EnrollParams.apskLegacy` (bare) or `EnrollParams.apsk` (array). Afterwards the
enrollment changes its own `_apsk` through `enroll:update`
([section 9.5](#95-enrollupdate)), or republishes it with
`ApkamSigning.publishPublicSigningKey`. Since
[at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) the
atServer composes nothing and publishes only what a request carried, so a new
signing-key shape needs no server release.

A key that has stopped signing stays advertised with `"status": "retired"`, so
what it signed still verifies. Adding a second algorithm's key to an existing
enrollment's `_apsk` is how signature agility works
([`decisions.md` 91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11);
[section 9.3](#93-_apsk)).

#### 2.1.7 Trust nuance

The signature is verified against `_apsk`, which the atServer serves. So while the
atServers serve keys faithfully, it tells a reader which enrollment published a
key, and no enrollment can publish one in another's name. This holds within one
Atsign and between Atsigns alike. It does not check the atServers themselves: an
Atsign's atServer stays trusted for the keys others seal to that Atsign until the
anchor is distributed outside it, which key transparency is on the roadmap to do
([section 7.4](#74-key-transparency-is-on-the-roadmap)). See
[section 7](#7-trust-model) for the trust model, and do **not** describe signing
as removing the need to trust the atServers.

### 2.2 SecretStore, push & pull primitives

**Shared substrate facts (stated once):**

- **`SecretStore.putIfNewer`** is the merge for arriving secrets, keyed by
  `(namespace, name)`. A higher `Secret.version` wins when both carry one, so
  rotations of one logical secret order the same way whatever the clocks say.
  Otherwise, and on equal versions, a strictly later `createdAt` wins. It accepts
  reserved `__` names, which `putSecret` refuses unless `allowReservedName` is
  set. Because arrival is idempotent, push and pull compose: a failed push is
  never fatal, since pull still reaches a missed client later.
- **Per-enrollment secrets.** A name beginning `__en.`
  (`PairwiseSecretSharing.perEnrollmentSecretPrefix`) is addressed to one
  enrollment, for example the signing-root private and an `apkamSymmetricKey`.
  `shareAllSecretsWith` never forwards one. It is served on request only when
  `perEnrollmentSecretRequestGate` allows it. The gate is null by default, and
  null refuses. `PqClientBootstrap` sets it to "the requester's enrollment record
  grants `rw` on both `*` and `__manage`".
- **Transport.** `atClient.put` of the `__ssenv` key, plus a **sync** delivery
  path: a sync-progress listener, and a sweep every `sweepInterval` (1 minute),
  feeding `receivedSecrets`. Each put is followed by an optional, value-less
  **wake-up `notify`** (`sendWakeUpNotification`, default on) addressed to the
  Atsign itself, so a client that does not run sync wakes on its notification
  monitor and sweeps the atServer. This applies to requests and shares alike.
  - The envelope put is **remote-first** (`useRemoteAtServer = true`). The
    wake-up is a direct remote call and is one-shot, so a local-first envelope
    could still be waiting on a sync cycle when a sync-less recipient swept the
    atServer, and that client would then fall back to the pull path.
  - Remote-first costs the *sender's* offline tolerance on this write: an offline
    sender fails rather than queueing. Delivery stays offline-tolerant for the
    **recipient**, which is what the property is for, and `requestSecret` remains
    the backstop.
  - That trade exists because nothing preserves ordering across a keystore write
    and a notification
    ([#2116](https://github.com/atsign-foundation/at_client_sdk/issues/2116);
    [#2117](https://github.com/atsign-foundation/at_client_sdk/issues/2117) is the
    broader intent-based framing). Both are outside this project.
  - On the read side the mirror is `clientRunsSync` (default true). The
    start-up and periodic sweeps read the local store when sync fills it, and the
    atServer when nothing does, so a sync-less client that misses a wake-up still
    picks the envelope up rather than only through `requestSecret`.
  - The wake-up carries the **same expiry as the envelope**, so a nudge the
    atServer replays later never points at a value that has already expired.
    Missed wake-ups are partly covered by that replay of stored notifications.
- **Responder authorisation = namespace authorisation.** A holder serves a
  namespaced secret to requester `R` only if `R`'s key package is listed for that
  namespace by the server-sourced discovery verb
  ([section 2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)), never on the
  requester's own claim. `excludeEnrollmentIds` drops revoked enrollments from
  every roster.
- **The signing root is the no-namespace exception.** It has no namespace to gate
  on. Unlike the legacy default encryption private key it is **not** served to
  every non-revoked enrollment: only fully privileged ones (`rw` on `*` **and**
  `__manage`) hold it, because only they may mint it. `PqSigningRoot` mints it,
  serves it through the per-enrollment gate above, and pulls it with
  `requestPrivateIfAbsent` at every start
  ([`decisions.md` 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).
- **`SecretStore.namespaceAuthorizes`** mirrors the atServer's rule, comparing
  both sides folded: an enrollment is authorised when a grant is `*`, equals the
  namespace, or is a dot-suffix of it.
- **No holder online:** the request waits on the atServer, and a holder answers
  when it next runs. **Many holders at once:** each responder waits a random time
  within `requestAnswerJitter` (2 seconds), then skips the answer if one is
  already there for that request id. The same requester and secret are answered
  at most once per `requestAnswerMinInterval` (5 seconds), and `putIfNewer`
  absorbs duplicates. **Freshness:** a secret may carry a version, and
  `putIfNewer` keeps the newest.

**`requestSecret(namespace, name)` / `waitForSecret` (pull).** A targeted
fan-out, never a keyless broadcast. `requestSecretsFromNamespace` lists the
namespace's key packages through the gated verb
([section 2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)) and sends each
one a request envelope, `{kind: 'request', requestId, want | namePrefix}`. The
request's `from.kpid` tells a holder where to seal the answer. A holder answers
with `shareSecretWith(keyPackage, secret)`, sealed back to that kpid, and the
requester's `waitForSecret` resolves on the first valid secret.

**The start-time self-heal invariant
([`decisions.md` 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).**
At every client start, for each authorised namespace, an enrollment **mints the
nskey if none is published, else pulls the private parts**. It pulls from *any*
current holder rather than from "the creator", who may be long gone: the current
generation to write with, and older generations on demand to read history. A
fully privileged enrollment does the same for the signing root. Before it starts
listening, a client primes the privates it holds into its in-memory secret store
(`PqSigningRoot.hydrateStore`, `NskeySeeding.hydrateStoreFromFiling`), so that it
can answer the pulls its start-up sweep picks up.

**`pushSecretToNamespaceMembers(secret, {excludeEnrollmentIds})` (push).** List
the namespace's members through the verb, seal once per key package, `put` the
envelope, then send the wake-up. This is the steady-state convergence that keeps
reads fast, because the secret is on-device before a client needs it. Minting and
rotating an nskey both use it, through `PrePublishConveyance`, and both push
**before** the new generation is published, so publishing is the commit point. A
key package that did not verify is skipped with a warning, and a failure for one
member does not stop the others.

**Approval-time conveyance.** The approver already holds the new enrollment's id,
its granted namespaces and its key package, so it conveys without a poll or an
enumeration step. In production that is `EnvelopeEnrollmentConveyance`:

- **Before `enroll:approve`:** `conveyMintedApkamSymmetricKey` seals the
  `apkamSymmetricKey` ([section 3](#3-subsystem-c--at_chops-pq-primitives)).
- **After it:** `conveySecretsTo` verifies the key package against the `_apsk` the
  approval published. It then sends the signing-root private to a fully
  privileged enrollment, the nskey privates the approver holds
  (`NskeySeeding.conveyHeldPrivatesTo`), and every held secret its namespaces
  authorise (`shareAllSecretsWith`).

`shareAllSecretsWithEnrollment(enrollmentId, approvedNamespaces)` is the public
helper that finds the package through the directory and runs that last step.

### 2.3 The enroll:listns verb + EnrollParams.metadata

A pusher or puller needs two facts: **who** is authorised for the namespace, and
**what key** to seal to for each. One gated verb returns both.

> **`enroll:listns:<ns>`** returns every **approved** enrollment authorised for
> `<ns>`, with its access level, its APKAM public key and its opaque `metadata`.
> **Gated:** the caller must be APKAM-authenticated, as an approved enrollment
> holding at least read access to `<ns>`. An explicit grant is matched first,
> then `*`. `__manage` must be held explicitly, because `*` does not confer it.

- **Server-sourced and authoritative.** The authorisation comes from the
  atServer's enrollment records rather than from a client's own claim, so the
  member list is complete and trustworthy. That includes **read-only
  enrollments**, which cannot advertise themselves into a namespace they cannot
  write.
- **Self-contained.** The key package travels in the enrollment record beside the
  APKAM public key, and the verb returns both. One gated call yields
  *authorisation and every encapsulation key*, with no separate fetch and no
  public record.
- **Gate scope.** At least `r` is the right bar. Any pusher (the minter, a
  rotator) clears it, and a read-only member learning the roster of a namespace
  it already belongs to learns nothing it is not entitled to.

**Response shape: flat, one element per enrollment (1:1:1):**

```
data:[{ enrollmentId, access, apkamPubKey, metadata }]
```

There is **no nested `apkam[]` array**. Each enrollment has one APKAM keypair and
one key package, so the element is flat. `VerbEnrollmentDirectory` refuses a
response that is not a list, rather than reading it as an empty roster.

**`enroll:infons:<ns>`** sits behind the same gate and returns facts about the
namespace itself: `lastRevokedAt`, and `lastKeyHolderRevokedAt` over only the
enrollments that could have held a namespace private
(`EnrollmentDirectory.lastRevokedAt`). Either can move backwards when an
enrollment is un-revoked, so a caller compares them for change, not growth.

**The key package rides `EnrollParams.metadata`.** It is registered as an opaque
`Map<String,dynamic>` on `EnrollParams.metadata` at `enroll:request` time, a JSON
tail on the existing request with **no grammar change**. The atServer stores it
on the enrollment record verbatim and returns it from the discovery verb. There
is **no `enroll:metadata` verb**. A client that never sent `metadata` gets an
element without it.

**`enroll:update` lets an enrollment change its own record**
([`decisions.md` 68](detail/decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)).
It is self-only: the connection must be authenticated as the enrollment being
updated, and an owner connection is refused. It applies to approved enrollments
only. It reaches the APKAM public key (with a proof of possession of the new
private), `signingAlgo`, the `_apsk` and `metadata`, and never `namespaces` or
the approval state. `metadata` is a per-key set rather than a whole-map replace,
and the atServer forms no opinion on the contents. The client side is
`EnrollmentUpdateRequest` and `EnrollmentUpdater`; the atServer side is the
`update` operation of `enroll:`.

**The key package sits at a singular `metadata.keyPackage`** (1:1:1: one
enrollment, one key package). There is **no format-keyed `keyPackages` map**,
because key and suite agility already live inside the package, in `keys[].alg`,
`KeyPackage.suites` and `KeyPackage.v`. Its value is the signed envelope around
the key-package payload (*Advertised-key authenticity*,
[section 2.1.5](#215-advertised-key-authenticity)). The atServer stores and
returns it and has no opinion on its contents.

The payload is `{v, createdAt, keys: [{kid, use, alg, pub, status?}], suites: [...]}`.

**`status`** is an **open token**. `active` and `retired` are the two this version
knows (`KeyEntryStatus`), and the field is **absent on every entry that is
active**, which is every entry a client that has never rotated writes. So the
four-field spelling above is what a reader sees in practice.

- It is the same field, with the same vocabulary and the same use-neutral
  meaning, on all three records that advertise keys (`_apsk`, the key package,
  the nskey advertisement): *retained, not offered for new operations*.
- A retired entry is skipped when choosing what to seal to or sign with, and kept
  for everything already sealed to or signed by it. An envelope lives seven days,
  so dropping a rotated key's entry would strand a week of traffic. Dropping a
  rotated client data signing key's entry would retroactively unverify everything it ever
  signed.
- A value a reader does not recognise is carried through verbatim. It is neither
  offered for new operations nor trusted to verify what the key already did,
  which is narrower than either known token, in both directions.
- The nskey advertisement's writer publishes one active key per generation, and
  a rotation replaces the record. Its reader honours `status` anyway, so the
  vocabulary means one thing everywhere
  ([`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
  rulings 6–9).

`keys[].alg` says which KEM key a sender encapsulates to. **`suites` says which
sealing constructions the holder can open**, which is a different question.
Today each KEM opens exactly one suite: `x-wing` opens `x-wing-rfc9180-v1`, and
`ml-kem-1024` opens `ml-kem-1024-rfc9180-v1` (`SecretSharingAlgos.openableSuitesFor`).
`suites` is what makes moving the construction a **sender-side** decision rather
than a migration in which every reader must upgrade first. `sendEnvelope` narrows
the candidates to the chosen key's own KEM, intersects them with the package's
list, and derives the `pqSeal` version from the winner. Three rules apply:

- The published list is derived from the package's **own keys**, never from what
  the build supports. A list derived from the build would let a package that
  advertises one KEM claim it can open constructions built on another.
- A payload with **no** `suites` list is refused (`KeyPackage.fromPayload`), so
  nothing is sealed to it.
- Entries this build does not recognise are **kept**, because the field is the
  holder's statement about itself.

`metadata.keyPackage` is written by `enroll:request`, and afterwards only the
enrollment's own self-only `enroll:update` can reach it
([plan 14.6](https://github.com/atsign-foundation/at_client_sdk/blob/8cfd1f4e7247ce15573dfc707ebf822d4da8ba04/docs/projects/pq/detail/implementation-plan.md#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)).
`KeyPackageMinting` republishes the package at start-up when the configured
`keyEstablishmentAlgorithms` have changed, or when the published package does not
match the keys the keyfile holds. So an overstatement is repairable by its own
holder at its next start. It is still nobody else's to repair, which is why an
overstatement is a defect and not a cosmetic one
([`decisions.md` 50.5](detail/decisions.md#505-the-defect-a-widened-list-planted-before-anything-read-it)).

### 2.4 The atServer enrollment record + ML-DSA APKAM auth

**The enrollment record stores a SINGLE `apkamPublicKey` and a `signingAlgo`**
(`rsa2048` | `mldsa65`), 1:1:1 (decision #F). There is **no list of APKAM
keypairs**, no verify-against-any, and no `ApkamPublicKey[]`. PKAM verifies
against that one key, under its stored algorithm. `enroll:update` can move the
record onto a new APKAM keypair, given a proof of possession of the new private
([section 9.5](#95-enrollupdate)).

**ML-DSA APKAM authentication (post-quantum client authentication):**

- **Client.** PKAM is a challenge-response: `from:@alice` returns a
  per-connection challenge, the client signs it with its client authentication
  signing key, and the atServer verifies. at_auth's `signPkamChallenge` picks the
  routine from the key material's algorithm: RSA-2048 with SHA-256, or ML-DSA-65.
- **Wire.** The `pkam:` grammar accepts `signingAlgo:` as `ecc_secp256r1`,
  `rsa2048` or `mldsa65` (at_commons `VerbSyntax.pkam`).
- **atServer.** It verifies under the **record's** `signingAlgo`, never the value
  the client sends on the wire
  ([`decisions.md` 34](detail/decisions.md#34-pkam-is-record-authoritative-and-the-no-rsa-row-reads-narrower-than-it-looks-2026-08-04)),
  so a client cannot switch the verify routine by naming another algorithm. An
  enrollment that records no algorithm is verified as `rsa2048`.
- **at_chops.** ML-DSA-65 is `SigningAlgoType.mldsa65`, implemented by
  `MlDsa65PureDartAlgo` and `MlDsa65FfiAlgo`
  ([section 3](#3-subsystem-c--at_chops-pq-primitives)).

**Scope: a signature swap, not a KEM. Do not over-build.** Client PKAM is
**authentication, not key agreement**, exactly like the inter-server FROM/POL
handshake ([section 8](#8-subsystem-f--inter-server-pq-authentication-is-1)). The
atServer's per-connection challenge already provides freshness and stops replay,
and TLS already secures the channel. So the whole post-quantum change is the
RSA→ML-DSA-65 **signature**: client-side signing and record-authoritative
server-side verification. There is **no KEM, no certificate and no per-connection
key lifecycle**, and none should be added. The 1:1:1 single-key record is the
minimal form; do not grow it into a keyring or a per-session negotiated
handshake.

**The one place a KEM legitimately appears in the enrollment path is the
`apkamSymmetricKey` conveyance at enroll/approve.** That is key *transport* of the
approval bundle, so it is genuine confidentiality, not authentication. It must
not be conflated with the authentication swap, or removed as over-engineering.

**Legacy credentials.** A `pkam:` with no enrollment id authenticates as
`primary`. It is checked against the flat legacy PKAM key while the store holds
one, and otherwise against the `primary` enrollment record, so old clients
authenticate unchanged.

**Cross-tier property (atServer-guaranteed): `_apsk` is published and
write-restricted.** Both envelope sender authenticity and advertised-key
authenticity ([section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify))
rest on `public:_apsk.<enrollmentId>.a.__e@<atSign>`. The atServer guarantees two
things about it:

1. **Published at approval.** The atServer writes the `_apsk` value the
   `enroll:request` carried (`EnrollParams.apsk` or `EnrollParams.apskLegacy`)
   when the enrollment is approved, including the auto-approval of a
   self-enrollment, so a verifier does not race a client's own publication.
   at_auth always sends one. A request carrying neither gets no `_apsk`.
2. **Write-restricted.** Only a connection authenticated as that enrollment can
   change records in its `<enrollmentId>.a.__e` namespace. Any other connection,
   whether CRAM, PKAM or APKAM, is refused with `AT0009`. A client fetches the
   `_apsk` public key and trusts it.

`tests/at_functional_test/test/apsk_server_side_test.dart` asserts both ("the
atServer publishes _apsk itself, and refuses a cross-enrollment overwrite").
Sender authentication and advertised-key authenticity both fail if either
property regresses.

### 2.5 The authenticated self-retrofit flow (fresh, auto-approved enrollment)

**A retrofit is a fresh, self-spawned, AUTO-APPROVED enrollment that replaces the
one it authenticated as, NOT a mutation of an existing one.** The rationale is in
[`decisions.md`](decisions.md), and the testable sequence in
[`acceptance.md`](acceptance.md). Its two enrollments are the **predecessor** and
the **successor**; parent and child name the approver and the enrollment it
approved.

**The flow** (`selfRetrofit` and `retrofitIdentity` in
`lib/src/enroll/self_retrofit.dart`). An authenticated pre-PQ client:

1. **Submits `enroll:request` on its already-authenticated connection**, with **no
   OTP** because it is already authenticated. The atServer assigns the new
   enrollment id. The request carries:
   - a freshly minted APKAM public key, with `signingAlgo` set from
     `AtClientPreference.authenticationKeyAlgorithm` (`rsa2048` under
     `PqPosture.legacy`, `mldsa65` under `pqReady` and `pqActive`);
   - the `_apsk` value;
   - the key package, in `EnrollParams.metadata`
     ([section 2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)).
2. The atServer **auto-approves** it with no human step and no OTP. The successor
   holds **exactly the predecessor's grants**: a request may omit `namespaces` and
   inherit them, or state them and be refused if they differ in any way
   ([`decisions.md` 128](detail/decisions.md#128-a-retrofits-successor-holds-its-predecessors-grants-and-may-not-choose-them-2026-08-31)).
   The successor takes the predecessor's place in the approval graph.
3. **Expiry.** The successor inherits the predecessor's key-expiry term when the
   request states none. A stated term may narrow it but never widen it, and the
   successor never outlives the predecessor's recorded deadline.
4. **Settlement.** At the successor's first PKAM authentication, the atServer
   **settles** the predecessor
   ([`decisions.md` 133](detail/decisions.md#133-a-revocation-follows-approval-and-a-replacement-settles-itself-2026-09-08)):
   - the predecessor's approval children move onto the successor;
   - a predecessor that is not fully privileged is **revoked as superseded**, with
     its own expiry untouched;
   - a fully privileged predecessor keeps its life;
   - the successor is stamped `predecessorSettledAt`.

   Nothing is deleted in place, and there is no grace.
5. The new client acquires the signing root and the namespace nskey privates over
   the substrate ([section 2.2](#22-secretstore-push--pull-primitives)). It
   **mints the root in-flow if it is fully privileged and the Atsign publishes
   none**, and otherwise pulls it. It **verifies correspondence** and files them
   in `AtKeys` through its `AtKeysIo`
   ([section 4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)).
   The mint belongs to this flow rather than to client start. The atServer
   auto-approves a retrofit with no approver client involved, so the approval-time
   conveyance that gives an ordinary new privileged enrollment its root never runs
   for a retrofitted one. A failure in the root step does not fail the retrofit.

**A retrofit is once-off.** The atServer refuses to replace a replacement without
an approver. Once a successor has authenticated, it refuses a second replacement
of a predecessor that is not fully privileged; a sibling clone of that keyfile
enrols over an OTP instead. A fully privileged predecessor can be replaced again,
for example from a copy of its keyfile on another host. Each successor mints its
own APKAM keypair, and the atServer refuses an APKAM key another enrollment
already holds.

**Once per keyfile.** The retrofit is idempotent per keyfile: a keyfile that
already carries an enrollment of the requested algorithm reuses it and mints
nothing. The sequence runs under `retrofitSerializer`, and a `dart:io` process
sets `fileRetrofitSerializer`, which takes a cross-process lock beside the
keyfile. The successor's credentials are filed **in the same keyfile**, beside the
legacy material. Storage ruling (2026-06-24): the copyable `.atKeys` file is the
default, because it is portable and a reused keyfile does not re-mint. OS keychain
storage is opt-in (`KeychainAtKeysIo` in at_client_flutter). Revocation is per
enrollment, and each enrollment carries its own `(appName, deviceName)` label for
administration.

**Legacy retirement.** The **supersession** written at the successor's first
authentication, plus the existing `enroll:revoke`. There is **no per-APKAM-key
delete operation**. For a predecessor that is not fully privileged, the
supersession is what retires the pre-PQ credential, and a copy of the keyfile
that has not upgraded by then is locked out. Revoking a live PQ enrollment's
authentication is `enroll:revoke`. Cutting an enrollment out of future data is
nskey-keypair rotation that excludes it
([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).

**`pq_signing_root` lifecycle.** The record is **mutable, and minted under a
lock**.

- **The lock.** The interlock is `_rootlock@<atSign>` (`MintLock`), a short-ttl
  immutable self key. The atServer refuses a second create of an immutable
  record, a long-standing feature. Release by ttl expiry needs an atServer that
  stops refusing a create once the record has expired; at_server `00c2f9a6`
  (c3.16.2 or later) does this, and the client does not check for it.
- **Who mints.** Only a fully privileged enrollment (`rw` on `*` **and**
  `__manage`) mints. The winner of the lock re-reads the record under it,
  generates the ML-DSA-65 keypair, stores the private half in its own `.atKeys`,
  and publishes. A winner whose lease ran out before publishing retires its pair
  and publishes nothing.
- **Pushing the private.** Once the record is published, the winner pushes the
  private to every other approved, fully privileged enrollment that carries a
  verified key package (`pushToFullyPrivileged`). A failed push never fails the
  mint. The push follows the publish because a receiver files a root private only
  against a published root
  ([UC-A3.7](acceptance.md#47-uc-a37--a-namespace-keys-private-reaches-every-listed-enrollment-before-anyone-can-seal-to-it)).
- **Serving it.** A holder primes the root private into its secret store at every
  start, before its start-up sweep, and serves it on request **only to fully
  privileged enrollments** (the per-enrollment gate in
  [section 2.2](#22-secretstore-push--pull-primitives)), failing closed.
- **Losing the lock.** A loser mints nothing, and retires any pair it filed before
  the publish failed. It **pulls** the private half
  ([section 2.2](#22-secretstore-push--pull-primitives)), and files it only if a
  probe signature verifies against the published root.
- **Reconciling.** A lock is a protocol rather than the atServer's absolute
  refusal, so what backs it is the reconciliation at every start: a held private
  that corresponds to no advertised entry is retired, and the pull asks again.
  The record is rotatable in shape, but no rotation is built, so two roots could
  not be reconciled
  ([`decisions.md` 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)).

Two populations **never** run this retrofit. A new Atsign is PQ-native at
onboarding. A new privileged enrollment receives the root from the approver at
approval.

**Constraints on the flow:**

- **Revocation cascades** along the approval graph
  ([`decisions.md` 129](detail/decisions.md#129-revocation-cascades-to-descendants-and-the-roster-does-the-rest-2026-08-31)).
  Self-enrollment would otherwise let a stolen keyfile spawn an enrollment before
  the theft is noticed, which could outlive the revocation. Each enrollment
  records the enrollment that approved it (`parentEnrollmentId`), and revoking an
  enrollment revokes its descendants.
  - The atServer refuses a revocation that would also revoke the enrollment
    issuing it.
  - It refuses one that would leave the Atsign without a permanent fully
    privileged enrollment.
  - A retrofit's successor inherits its predecessor's place in the graph.
- **Legacy material stays in the keyfile.** The retrofit files the successor's
  keys in the keyfile that already holds the legacy encryption keypair and
  self-encryption key, never a fresh file, and sends no
  `encryptedAPKAMSymmetricKey`, because a request with no OTP needs none
  ([`decisions.md` 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
- **Distinct `(appName, deviceName)` per device.** This is client-side
  discipline, not server-enforced. The atServer skips its duplicate refusal on
  the self-enrollment branch, because a retrofit keeps its own name
  ([`decisions.md` 42](detail/decisions.md#42-the-to-define-list-ruled-2026-08-05)
  item 1). Distinctness is what lets an owner tell one device's enrollment from
  another's in `enroll:list`.
- **No cap on the predecessor, and no grace.** A predecessor is settled once, at
  its successor's first authentication (step 4)
  ([`decisions.md` 133](detail/decisions.md#133-a-revocation-follows-approval-and-a-replacement-settles-itself-2026-09-08)).
  A connection still open as a revoked predecessor is closed at its next command,
  and a copy of its keyfile is refused when it authenticates.
- **For a retrofitted enrollment the start-time pull is the normal path, not a
  backstop.** No approver conveys anything to it. Delivery is store-and-forward in
  both directions, so "heals when each device next runs" is a question of
  latency, not availability
  ([`decisions.md` 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).

---

## 3. Subsystem C — at_chops PQ primitives

The providers and the substrate seal through one post-quantum primitive in
at_chops, `pqSeal`/`pqOpen` (`lib/src/algorithm/encryption/pq_hpke.dart`), over
two KEMs.

**X-Wing KEM** (IANA HPKE KEM id `0x647A`): ML-KEM-768 and X25519 with the
SHA3-256 combiner; 32-byte seed secret keys expanded with SHAKE-256
(`x_wing_core.dart`).

- **Vectors.** It is checked byte-exact against the **IETF HPKE working group's**
  published `0x647A` vectors (`test/vectors/hpke_wg_0x647a_chacha.json`), across
  all three operations: key generation, derandomised encapsulation and
  decapsulation. Both the pure-Dart and the OpenSSL FFI backends are checked
  (`x_wing_algo_test.dart`, `x_wing_ffi_test.dart`).
- **An independent oracle.** Go 1.26's `crypto/hpke.MLKEM768X25519()` vendors the
  same vector file.
- **Where the construction comes from.** It originates in
  `draft-connolly-cfrg-xwing-kem`, an Independent Submission CFRG never adopted;
  cite it for history only. `draft-irtf-cfrg-concrete-hybrid-kems` section 4.2
  states that its `MLKEM768-X25519` "is identical to the X-Wing construction".
- **Its name.** The IANA row reads *X-Wing*, and `draft-ietf-hpke-pq` requests the
  rename to `MLKEM768-X25519`.

**ML-KEM-1024** (IANA HPKE KEM id `0x0042`, FIPS 203) is the option without a
hybrid. It is pure Dart only (`MlKem1024PureDartAlgo`), checked against the
working group's `0x0042` vectors (`test/vectors/hpke_wg_0x0042_mlkem1024.json`).

**`pqSeal` / `pqOpen`** are the one post-quantum public-key encryption primitive:

```
pqSeal(kem, recipientPublicKey, plaintext, {required info, aad, version}) → envelope
pqOpen(kem, recipientSecretKey, envelope, {required info, aad}) → plaintext
```

- **Envelope.** `ver(1) || ctLen(2, big-endian) || kemCt || aeadCiphertext || tag`.
  The framing is internal to the Atsign Protocol. The key schedule inside each
  version is RFC 9180 Base mode, section 5.1 verbatim (`rfc9180_hpke.dart`).
- **Versions** (`pqSealSupportedVersions`): `0x02` is X-Wing with HKDF-SHA256 and
  ChaCha20-Poly1305, and `0x03` is ML-KEM-1024 with HKDF-SHA384 and AES-256-GCM.
  `pqSealDefaultVersion` is `0x02`. A sender chooses the version from the suite
  its recipient advertises
  ([section 2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)). `pqSeal`
  refuses a version this build does not support, and a KEM whose encapsulation
  length is not the version's. Byte-level detail is in [seal-spec.md](seal-spec.md).
- **`info` is required, with no default.** Two protocols therefore cannot share a
  key schedule by both leaving it out. A caller that wants no binding passes
  `Uint8List(0)`.
- **Failures.** `pqOpen` throws `PqOpenException` with `versionMismatch`,
  `malformedEnvelope` or `authFailure`. A wrong `info` is indistinguishable from
  tampering.
- **Stateless and protocol-agnostic.** The KEM instance is passed per call, and
  the AEAD inside `pqSeal` is pure Dart (`AesGcm256Aead` and
  `ChaCha20Poly1305Aead` in `at_aead.dart`). Tested in `pq_hpke_test.dart` and
  `rfc9180_hpke_test.dart`.

`AtChopsImpl`, the key-holding facade, is deprecated ("Use the algorithm classes
directly instead"). at_auth and at_client call the algorithm classes directly.

**ML-DSA-65.** at_chops implements ML-DSA-65 signing and verification as
`MlDsa65PureDartAlgo` and `MlDsa65FfiAlgo`, and `AtPqc.mlDsa65` resolves one of
them. ML-DSA-65 signs PKAM challenges
([section 2.4](#24-the-atserver-enrollment-record--ml-dsa-apkam-auth)), envelope
signatures ([section 2.1.2](#212-the-signed-envelope)) and the signing root.
`SigningAlgoType.mldsa65` names it, and `SigningAlgoType.strongestFirst` ranks it
first.

**Backend policy ([`decisions.md`, rulings of 2026-07-02](detail/decisions.md#rulings--2026-07-02)).**
`AtPqc` resolves the OpenSSL FFI backend where a libcrypto that supports the
algorithm loads, and pure Dart otherwise. A build without `dart:ffi`, such as
dart2wasm, uses pure Dart. Every OpenSSL and FFI class sits behind
`package:at_chops/at_chops_ffi.dart`, so `package:at_chops/at_chops.dart` is pure
Dart (gated in `.github/wasm_gates.yaml`).

**PQ enrollment conveyance**
([`decisions.md` 23](detail/decisions.md#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04)).
Closing the last harvest-now-decrypt-later gap in enrollment means not
RSA-wrapping `apkamSymmetricKey`, and there is no Atsign-level encapsulation
target to wrap it to: `public:pq_signing_root@<atSign>` only signs
([section 1.4](#14-the-nskey-and-the-signing-root)). So when an `enroll:request`
carries a key package and no `encryptedAPKAMSymmetricKey`, the **approver** mints
the `apkamSymmetricKey` and seals it to the **enrollee's key package** over the
substrate (`EnvelopeEnrollmentConveyance.conveyMintedApkamSymmetricKey`). The
atServer changes nothing beyond storing the request's metadata.

- **The order.** The approver seals the key **before** `enroll:approve`, without
  first checking the package against the enrollee's `_apsk`. The approval
  encrypts the enrollee's keys under that key, and the atServer refuses a second
  approval, so sealing first means a stop between the two cannot leave an
  approved enrollment whose key nothing holds.
- **Why no check.** The `_apsk` would come from the same atServer that serves the
  package and receives what the key encrypts, so for this key the check protects
  nothing. The approver does refuse, before approving, a package that is not one
  at all.
- **Everything else is checked.** Links, the root private, nskey privates and app
  secrets go after approval, checked.
- **Retries.** A retried or raced approval leaves several conveyed keys. The
  enrollee's handshake keeps the first that decrypts both keys its approval
  encrypted.

### 3.1 The constructions against the standards

These are standing facts about the standards, checked against original sources.
They are recorded here rather than in the decisions ledger because they are facts,
not rulings. They constrain what any construction here may claim. Re-derive none
of them without an original source:

- **No finalized standard specifies any PQ KEM inside HPKE.** A full RFC-index
  search with a positive control found one HPKE RFC (9180, DHKEM only) and no PQ
  one. So no HPKE-based option (`0x0041`, `0x0042`, `0x0050` or `0x647A`) can be
  described as standards-finalized.
- **X25519's absence from SP 800-56A does not by itself make the composite
  unapprovable.**
  [`decisions.md` 48.4](detail/decisions.md#484-not-switching-the-kem-and-the-fips-story-it-cannot-buy)
  states this too strongly. SP 800-227 section 4.6.2 approves the combiner "if at
  least one shared secret is generated from... an approved KEM", and the other
  component may be "generated in some other (not necessarily approved) manner".
  What closes the FIPS door is **CMVP module validation**, which a pure-Dart
  implementation can never obtain.
- **SP 800-227 section 4.6 names X-Wing** as its worked example of a PQ/T hybrid,
  and cites the X-Wing paper as the authority for why naive combiners fail. The
  construction is not disreputable in NIST's eyes; it is simply not approved.
- **X-Wing's combiner is not SP 800-227's.** The approved `KeyCombineCCA_H` takes
  seven inputs (`K1, K2, c1, c2, ek1, ek2, domain_sep`). X-Wing supplies four,
  omitting `ct_M` and `ek_M`. Any claim that it is "a few bytes away" from
  approval is unsupported and must not be written into a specification. Appendix
  D records that the final SP deliberately moved away from prescribing
  concatenation at all.
- **`draft-irtf-cfrg-concrete-hybrid-kems` is CFRG-adopted**, not an individual
  submission. Its section 4.2 states MLKEM768-X25519 "is identical to the X-Wing
  construction". That is the citation the hybrid should use, rather than
  `draft-connolly-cfrg-xwing-kem`.
- **RFC 9180 and RFC 9106 (Argon2id) are the same status class.** Neither may be
  marked down while the other is treated as a clean citation.
- **What reviewers actually score.** In published NCC Group, Cure53 and Least
  Authority reports, a non-standard algorithm was **never** rated High or
  Critical. A missing *specification* was rated Medium, self-produced test
  vectors were a finding (Cure53 MON-01-004), and weak KDF parameters were rated
  Low. Specification and third-party vectors therefore matter more than further
  algorithm changes.

Two consequences the rest of this document depends on:

- **No HPKE-based option can be described as standards-finalized.** So
  `x-wing-rfc9180-v1` and `ml-kem-1024-rfc9180-v1` are "RFC 9180 Base mode at a
  suite whose KEM code point is registered but draft-specified", never "standard
  HPKE".
- **FIPS is closed to us by CMVP rather than by the choice of algorithm.** Adopting
  ML-KEM-1024 alone buys an approved-algorithms answer to a questionnaire, not a
  validated module. State it that way, or a reviewer will.

---

## 4. Subsystem D — structural design (CryptoProvider seam, AtKeys/AtKeysIo & key stores, WASM barrel)

The seams the other subsystems are built on.

### The CryptoProvider seam

```
abstract class CryptoProvider {
  String get id;
  Future<String> encrypt(CryptoContext context, AtKey atKey, String plaintext);
  Future<String> decrypt(CryptoContext context, AtKey atKey, String ciphertext);
}
```

These live in `lib/src/crypto/crypto.dart`.

- **Providers are stateless.** `CryptoContext` carries the `atClient` and the
  client's `atKeysIo`.
- **Routing.** `CryptoRuntime` routes each put, get, notify and sync to the
  provider named by the key's `appMetadata.providerId`, looked up in the client's
  `CryptoConfig` (`CryptoConfig.forClient`). That config is the one the app set
  on `AtClientPreference.crypto`. When the app left the default,
  `CryptoConfig.eraDefault()`, it is the era default the client adopted from its
  `PqPosture`: `CryptoConfig.legacy`, `CryptoConfig.readsNskeyWritesLegacy` or
  `CryptoConfig.nskey`.
- **The legacy fallback.** A record with no provider id routes to the built-in
  `LegacyCryptoProvider`, which no config needs to list.
- **`CryptoConfig`** holds `defaultProviderId`, `providers`, `keyRing`,
  `ckRotationPolicy`, `supersededCkGrace` and `nskeyRotationPolicy`, and
  `lookup(id)` finds a provider.
- **Metadata.** The wire carries `Metadata.appMetadata = AppMetadata{ providerId,
  additional }`. The SDK **stamps `providerId` and `isEncrypted`** after a
  successful encrypt, so a provider only contributes `additional`.
- **An unknown scheme** throws `CryptoProviderNotRegistered`.
- **Per-operation override.** `PutRequestOptions.cryptoProviderId` chooses the
  provider for one operation, which is the per-destination choice the NoPorts
  walkthrough uses ([section 5](#5-subsystem-e--worked-walkthrough-at_talk)).
  A provider the caller named that declines the key throws, while a defaulted one
  falls back to legacy.
- **Optional provider interfaces.** `PreparesWrites` does work before the write
  pipeline starts. `HandlesSelectively` declines some keys, at write-time
  selection only. `ReportsReadiness` answers `isReadyFor` a destination.
- **Reading the scheme.** A reader tells what a value was sealed under from its
  metadata alone. `atClient.schemeOf(key)` gives the provider and, for a
  post-quantum value, the KEM its content key was conveyed under.
  `AtNotification.receivedUnder` gives a notification's provider, which a reply
  passes as its `cryptoProviderId` to answer in kind
  ([ruling 149](detail/decisions.md#149-how-a-shared-value-was-protected-is-read-from-its-metadata-and-a-reply-goes-in-kind-2026-10-05)).
- **A cached client adopts a new `preference.crypto`.** `AtClient.setPreferences`
  replaces `crypto` with the rest of the preference, and refuses only a change to
  the rollout axes. A re-set for the same Atsign with a new provider config
  therefore applies it, with no `CryptoProviderNotRegistered`.
- **No `CryptoRegistry`, `CryptoPolicy` or `CryptoStorage`**, and **no
  `cryptoRegistry` getter on the `AtClient` spec.**

**Get-path invariants.** `get` respects the `isEncrypted` tri-state
(`GetResponseTransformer`):

- `true` decrypts with the routed provider.
- Absent tries a decryption and falls back to the value as stored.
- An explicit `false` skips decryption unless the value has legacy ciphertext's
  shape: base64 of a positive multiple of 16 bytes, unencoded, under no provider
  but legacy. A value with that shape gets a legacy decryption attempt, and comes
  back as stored if that fails.

The shape test exists because at_client 3.0.10 to 3.2.1 sent no flag, or `false`,
with a value it had encrypted, and the atServer stores a missing flag as `false`.
`shouldEncrypt = false` is a no-crypto path on write. On read, the SDK's own
records of that kind never have that shape: secret-sharing envelopes (JSON),
content-key copies (which name their provider), CK pointers and watermarks.

### `AtKeys`, `AtKeysIo` and the key stores

**`AtKeys`** (at_auth, `lib/src/keys/at_keys.dart`) is the single in-memory holder
of every key the client knows, per enrollment and the Atsign's own. Providers read
keys from it and mint, add and write through it. Ratified 2026-07-06 (#2045); the
retire-never-remove and `flush()` shapes were ratified 2026-07-17 (see
[`decisions.md`](decisions.md)).

- **Material is never removed once live.** It is added with `addKey`. Retiring it
  (`retireKey`, `retireAtSignKey`) moves its status forward only
  (`CryptographicMaterialStatus`: `pending` → `active` → `retired` → `dead`),
  because retired bytes are still needed to decrypt what they protected.
- **The one exception is `pending` material:** an enrollment's keys filed at
  submission and never accepted, which `discardEnrollment` removes.
- **Legacy fields** are deprecated and kept, so call sites can migrate over time.
- `AtKeys` carries a `metadata` map. It is not a wrapper over `AtChops`, which
  at_auth and at_client do not use.

**`AtKeysIo`** is the key source (`read(atsign)`). `WrittenAtKeysIo` adds:

- `write`: create only, for a fresh onboard;
- `flush(atsign, atKeys)`: persist the whole state, so a caller mutates in memory
  and then flushes. On an existing target, `AtKeysAssurance.validateMapUpdate`
  checks first that nothing is lost;
- `update(atsign, mutate)`: read, mutate and flush as one operation, which a store
  that can be shared takes a lock across.

The store a client runs on must be durable. The client's `AtKeysIo` is injected at
construction (`AtClientImpl.create(atKeysIo:)`, exposed as `AtClient.atKeysIo`)
and reaches providers through `CryptoContext.atKeysIo`. A reused cached client
keeps its original key source. Convergence (newest wins, pull recovery) stays in
the secret-sharing substrate, and the stores are **dumb** key-value backends.

**What lives where:**

| Key class | Where | Persistence |
|---|---|---|
| Enrollment material: legacy encryption keypair, PKAM/APKAM keypair, client data signing keys, key-package decapsulation keys, self-encryption key | `AtKeys`, through the client's `AtKeysIo` (`.atKeys` file **or** keychain) | durable; rewritten whole by `flush`/`update` |
| The Atsign's own keys: nskey privates, the signing-root private | `AtKeys`, outside any enrollment | durable, under the same never-lose contract |
| Content keys | `ContentKeyCache`, in memory, re-read from their conveyance records | a cache; evictable |
| Secrets in transit | `SecretStore`, in memory unless an app wires `SecretStorePersistence` | a transit buffer |
| Ephemeral per-APKAM leaf (npt/sshnp throwaway keypairs) | in memory, in the application | write-only; regenerated each run |

**Stores:**

| Store | Package and barrel | Notes |
|---|---|---|
| `InMemoryAtKeysIo` | at_auth, `at_auth.dart` | for tests; not durable |
| `FileAtKeysIo` | at_auth, `at_auth_io.dart` | the `.atKeys` file. `flush` validates and rewrites under an inter-process lock, writes a temporary file and renames it over the target, and keeps the previous state as `<file>.bak`, less any pending enrollment the write removes |
| `KeychainAtKeysIo` | at_client_flutter | the OS keychain; opt-in |

There is no keystore-backed `AtKeysIo`. The extended `AtKeys`, with its injected
`AtKeysIo`, is born at `AtClient` construction and is immutable after.

**Never-lose is a property of the durable key stores, not of every `AtKeysIo`**
(ruling 2026-07-17, [`decisions.md`](decisions.md)). `flush`'s nothing-may-be-lost
contract binds the `.atKeys` file and the keychain. Content keys, whose
**deletion is the B5a coarse forward-secrecy lever**
([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)),
live in an evictable cache rather than under that contract.

### The WASM-safe at_auth barrel

at_auth's main barrel compiles under `dart2wasm`, which refuses any `dart:io`
reachable from the entry point. So at_auth has two barrels:

- **`package:at_auth/at_auth.dart`** (no `dart:io`): `AtKeys`, the `AtKeysIo`
  interfaces, `InMemoryAtKeysIo`, the authenticators (`authenticatorFor`),
  activation (`activateAtSign`), the enrollment flows and handshakes, and the
  registrar on **`package:http`** (no `dart:io` `HttpClient`).
- **`package:at_auth/at_auth_io.dart`**: `FileAtKeysIo`, `fileRetrofitSerializer`
  and the registrar's `dart:io` client. A `dart:io` program imports both.
  `FileAtKeysIo` never leaves at_auth.

at_auth assumes no filesystem. Onboarding requires the caller to supply a
`WrittenAtKeysIo`, and there is no default. at_auth also builds no connection of
its own: the caller hands it an `AtLookupMuxable`, and its atServer check is
at_lookup's neutral `checkAtSignServer` over that lookup. `dart run
wasm_shakedown` holds both barrels to this (`.github/wasm_gates.yaml`,
`tools/wasm_shakedown`).

### OpenSSL backends behind a conditional export (at_client)

at_client's post-quantum data path takes its X-Wing KEM
(`SecretSharingAlgos.kemFor` and `kemForSuite`) and its value AES-256-GCM
(`SymmetricAesGcmProvider`) from `lib/src/crypto/backends/crypto_backends.dart`.
That file applies the FFI auto-resolve default
([`decisions.md`, rulings of 2026-07-02](detail/decisions.md#rulings--2026-07-02))
to at_client, without at_client importing `at_chops_ffi.dart` from anywhere a
dart2wasm build reaches:

- It is a conditional export, `if (dart.library.ffi)`. A native build uses
  at_chops's OpenSSL backends where the loaded libcrypto supports the algorithm
  (AES-256-GCM with any OpenSSL 3, X-Wing with OpenSSL 3.5 or later), and pure
  Dart otherwise. A build without `dart:ffi` takes the pure-Dart branch and never
  reaches `dart:ffi`.
- Every backend takes the persisted seed as its secret key, so a record written
  on a device with OpenSSL opens on one without it, and the other way round.
  ML-KEM-1024 has no OpenSSL backend and stays pure Dart, as does the AEAD inside
  `pqSeal`.
- `packages/at_client/test/crypto_backends_test.dart` pins which backend each
  algorithm takes, and that each direction opens under the other.

### Where the code lives

Within `packages/at_client/lib/src/`:

- `crypto/crypto.dart`: the seam (`CryptoProvider`, `CryptoConfig`,
  `CryptoContext`).
- `crypto/crypto_runtime.dart`: routing.
- `crypto/legacy/`: the legacy provider.
- `crypto/nskey/`: the nskey data path (providers, key ring, CK manager, signing
  root and chain).
- `crypto/backends/`: the conditional OpenSSL or pure-Dart export.
- `crypto/received_scheme.dart`: `schemeOf`.
- `secret_sharing/`: the substrate.
- `signing/`: envelope signing, `_apsk` composition and signing-key minting.
- `mixins/`: `ApkamSigning` and `EnvelopeSigning`.
- `enroll/`: retrofit, `enroll:update` and privilege.

---

## 5. Subsystem E — worked walkthrough (at_talk)

A design-level trace of the nskey data path between two Atsigns, using a chat
app in the `at_talk` namespace as the example. It is not the Given/When/Then
catalogue: the testable form is in [`acceptance.md`](acceptance.md), chiefly
[UC-A4.3](acceptance.md#53-uc-a43--multi-enrollment-both-ends). How NoPorts
would use the same path, and the MLS groups that are a separate provider, are
in [Planned changes](#planned-changes).

### 5.1 Setup

Two Atsigns, several APKAM keypairs each, messages both ways, and keypairs that
join later. Four APKAM keypairs to start: `Ka1`, `Ka2` (`@alice`) and `Kb1`,
`Kb2` (`@bob`), each `rw` on `at_talk`. Each enrollment's record carries its
key package: one encapsulation key (X-Wing by default,
`PqPosture.keyEstablishmentAlgorithms`) in an envelope signed with the
enrollment's client data signing key and checked against its `_apsk`. The key
package is never published; the Atsign's other enrollments find it through the
gated `enroll:listns` verb.

The keys that matter are each Atsign's `at_talk` **nskey**. `@alice`'s public
half is published as `public:__nskey.at_talk@alice` once Alice has minted it, and
`@bob`'s likewise. **There is no group and no epoch key.** Alice→Bob data is
encrypted under a content key (CK), conveyed once via `at/nskey` sealed to
**Bob's published nskey**, at `@bob:<ckKid>.__ck.at_talk@alice`; Bob→Alice is
symmetrical. The same CK is also sealed to Alice's own `at_talk` nskey as a
sibling copy, `<ckKid>.__ck.at_talk@alice`, which names its recipient, so
Alice's other enrollments can open what Alice sent
([ruling 142](detail/decisions.md#142-content-keys-recipients-cache-shared-conveyances-siblings-open-every-key-and-a-key-goes-once-nothing-cites-it-and-its-grace-is-over-2026-09-30)).
CKs are scoped per recipient, so what Alice sends Bob and what Alice sends Carol
use different CKs
([ruling 14](detail/decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)).
A CK is minted the first time a destination is written to.

**Whose nskey a CK is sealed to** is per recipient, not a group:

- Alice writing data **Bob should read** → the CK is sealed to
  `public:__nskey.at_talk@bob`, with a sibling copy sealed to Alice's own nskey.
- Alice writing **self data** → the CK is sealed to Alice's own `at_talk` nskey
  only; it is never shared across Atsigns, so Bob never sees Alice's self data.

There is no "(pair, namespace) group" to scope. The atServer's namespace gate
decides who may *fetch*; the nskey a CK is sealed to decides who can
*decapsulate*. Both are keyed to `at_talk`, so the readers are exactly both
sides' `at_talk`-authorised APKAM keypairs.

### 5.2 How a late-joining APKAM keypair reads

Take `Kb3`, a new `@bob` keypair. It reads in two independent steps.

1. **The nskey private, per APKAM keypair (the substrate).** `Kb3` generates
   its key package locally and sends it on `enroll:request`, where it lands in
   the enrollment record (gated, never published). A holder (`Kb1`) `pqSeal`s
   the `at_talk` nskey **private** to `Kb3`'s key package and writes
   `<msgId>.<inReplyTo>.<kpid(Kb3)>.__ssenv.at_talk@bob`, addressed by `kpid`.
   That happens at approval (`shareAllSecretsWithEnrollment`), at mint or
   rotation (`pushSecretToNamespaceMembers`), or when `Kb3` asks
   (`requestSecret`). Both gates of
   [section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify) protect the
   copy: the transport gate (`Kb3` is `at_talk`-authorised) and the crypto gate
   (sealed to `Kb3`'s key package).
2. **The CK, on ordinary sync.** Once `Kb3` holds the nskey private, it syncs
   the current `__ck` conveyances sealed to `@bob`'s `at_talk` nskey; `at/nskey`
   decapsulates the live CK with the nskey private and caches it by `ckKid`;
   `at/symmetric/AES/GCM` then decrypts the data values. **No epoch rotation on
   join, no per-message key push, no Add+Commit.** For `Ka3` (`@alice`), the
   same nskey private also opens Alice's self CKs and the sibling copies of
   what Alice sent.

**New and past data:**

| APKAM keypair | New data | Past data |
|---|---|---|
| **Kb3** (@bob) | Receives the **current** `at_talk` nskey generation per APKAM keypair (push, or `requestSecret` pull), syncs the current `__ck` conveyances, decapsulates the live CK, and reads all new data. No epoch rotation and no `__ck` re-mint on join. | Reads whatever `__ck` conveyances are still **retained**, pulling any earlier nskey generation a record's `nskeyKid` names on demand. **Retain** → opens past messages. **Delete for forward secrecy** → CKs whose conveyance was deleted on rotation stay opaque. |
| **Ka3** (@alice) | Symmetrical: receives @alice's current `at_talk` nskey generation, reads the current `__ck` conveyances, and reads all new data. The same private also opens @alice's self CKs and sibling copies. | Reads retained `__ck` conveyances, pulling earlier generations as needed; the same retain-or-delete choice. |

### 5.3 What the example shows

- **History is a policy choice, not a missing mechanism.** What carries history
  is the CK conveyance record, not a per-group epoch key. Retain it and any
  `at_talk`-authorised keypair reads history; delete it on CK rotation (and
  evict the cached CK) and that era's data is undecryptable. That is the
  coarse forward secrecy of
  [section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation),
  with post-compromise security from the more expensive nskey-keypair rotation.
- **A new APKAM keypair does not force a rotation.** Joining `at_talk` conveys
  the current nskey generation to the new keypair and lets it read existing
  CKs. Mandatory rotation on join is a property of MLS groups, which this path
  does not use.
- **Join cost is O(1) in rotations.** Only the current generation is pushed;
  earlier ones are pulled on demand, which works because every `__ck` names its
  `nskeyKid`. Without that tag a reader would have to try each generation it
  holds, paying an X-Wing operation per generation.
- **Cross-Atsign forward secrecy is bilateral**
  ([section 1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).

---

## 6. Implementation notes & file-level pointers (consolidated)

Where the design lives in the code: paths and symbols, without line numbers.
What is still owed is in [`implementation-plan.md`](implementation-plan.md); the
Given/When/Then catalogue is in [`acceptance.md`](acceptance.md); the rulings are
in [`decisions.md`](decisions.md).

### 6.1 Client substrate

Paths are under `packages/at_client/lib/src/` unless another package is named.

| Capability | Where |
|---|---|
| `pqSeal`/`pqOpen` of an `__ssenv` envelope: RFC 9180 at the suite the envelope names, with an `info` that binds the label `at_client/secret_sharing/v2`, the sending enrollment and kpid, the recipient kpid and the namespace, each length-prefixed | `secret_sharing/pairwise_secret_sharing.dart`: `PairwiseSecretSharing.sealInfoFor`, `sendEnvelope`, `_consume`; at_chops `lib/src/algorithm/encryption/pq_hpke.dart` |
| Envelope signing, and verification before decryption, against the signer enrollment's `_apsk` | `mixins/envelope_signing.dart`: `EnvelopeSigning.wrapAndSign`, `verifyEnvelopeSignature`; `_consume` verifies before it calls `pqOpenFromBase64` |
| The envelope address and the kpid it carries | `secret_sharing/envelope_addressing.dart`: `EnvelopeAddressing.envelopeKey`; `secret_sharing/secret_envelope.dart`: `SecretEnvelope` |
| A key package per APKAM keypair, keyed by `(enrollmentId, apkamId)`; crypto-agile parsing and `bestKeyFor` | `secret_sharing/key_package.dart`: `KeyPackage`, `PackageKey`; `secret_sharing/algo_ids.dart`: `SecretSharingAlgos` |
| `requestSecret` and `waitForSecret`; request and serve, fanning out by kpid and replying to the carried kpid, after `requestAnswerJitter` | `PairwiseSecretSharing` |
| The mint and rotation push to a namespace's members | `PairwiseSecretSharing.pushSecretToNamespaceMembers(Secret, {excludeEnrollmentIds})` |
| The approval push: no poll, deduplicated by kpid | `PairwiseSecretSharing.shareAllSecretsWithEnrollment` |
| The revocation guard threaded through request, serve and approve | `excludeEnrollmentIds` in `PairwiseSecretSharing` and in `secret_sharing/enrollment_directory.dart`: `EnrollmentDirectory.listForNamespace` |
| Secret ordering and the reserved `__` names | `secret_sharing/secret_store.dart`: `SecretStore.putIfNewer` (higher `version` wins, `createdAt` breaks ties), `SecretStore.putSecret` |
| Namespace authorisation: `*`, an exact match or a dot-suffix, compared folded | `SecretStore.namespaceAuthorizes` |
| Transport: a remote-first put, a sync listener, an optional wake-up notification, `receivedSecrets` | `PairwiseSecretSharing.sendEnvelope`, `sendWakeUpNotification`, `receivedSecrets`; `_EnvelopeSyncListener` |
| Signing and verifying the published nskey advertisement | `crypto/nskey/published_nskey_key_ring.dart`: `PublishedNskeyKeyRing`, `ApkamSignedAdvertisedKeys` |
| Signing and verifying the key package | `secret_sharing/key_package_registration.dart`: `KeyPackageRegistration.signedKeyPackagePayload`; `secret_sharing/enrollment_directory.dart`: `verifyAdvertisedKeyPackage` |
| Discovery over `enroll:listns`: flat records, one signed `metadata.keyPackage` each | `VerbEnrollmentDirectory.listForNamespace` |
| An arriving nskey private, checked against its public half and filed in `AtKeys` | `crypto/nskey/nskey_private_filing.dart`: `NskeyPrivateFiling` |
| The Atsign's signing root: mint, serve and pull | `crypto/nskey/pq_signing_root.dart`: `PqSigningRoot` |
| Key material collected at start, minted if absent and pulled otherwise ([ruling 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)) | `crypto/nskey/conveyed_key_collection.dart`: `collectConveyedKeyMaterial` |

`SecretStore` is the substrate's transit buffer. It is in memory unless an app
supplies a `SecretStorePersistence`; key material that must survive a restart
is filed in `AtKeys`
([ruling 21](detail/decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03)).

### 6.2 atServer side

The atServer is the sibling repository `at_server`. Paths are under
`packages/at_secondary_server/lib/src/` on its trunk.

| What | Where |
|---|---|
| `enroll:listns:<ns>`, gated discovery returning `[{enrollmentId, access, apkamPubKey, metadata}]` | `verb/handler/enroll_verb_handler.dart` |
| The key package riding `enroll:request` as `EnrollParams.metadata`, stored verbatim on the enrollment record's `metadata` | `verb/handler/enroll_verb_handler.dart` |
| Record-authoritative PKAM: one `apkamPublicKey` and `signingAlgo` per enrollment, verified under the record's algorithm | `verb/handler/pkam_verb_handler.dart` |
| `_apsk`, published by the atServer from `EnrollParams.apsk` or `apskLegacy` at approval and on `enroll:update` | `verb/handler/enroll_verb_handler.dart` |
| Writes by one enrollment to another's reserved `<enrollmentId>.a\|r\|d.__e` keys refused | `verb/handler/abstract_verb_handler.dart` |
| `enroll:update`: self-only, approved enrollments only | `verb/handler/enroll_verb_handler.dart`: `_handleEnrollmentUpdate` |
| `enroll:link`, and the link map kept across every other write of `_apsk` | `verb/handler/enroll_verb_handler.dart`: `_handleLink`; `enroll/apsk_links.dart`: `ApskLinks` |
| The 500 KB limit on an enrollment record | `enroll/enrollment_manager.dart`: `EnrollmentManager.maxRecordBytes` |

### 6.3 Verification recipe

On every touched package: `dart analyze --fatal-warnings`, `dart format`, and
`dart test --concurrency=1`. Crypto correctness is pinned by vectors in
`packages/at_chops/test`: X-Wing (`x_wing_test_vectors.dart`), HPKE
(`hpke_wg_kem_vectors.dart`), ML-DSA-65 ACVP (`ml_dsa_65_acvp_vectors.dart`) and
AES-GCM (`aes_gcm_encryption_algo_test.dart`). Functional:
`tests/at_functional_test/runLocal.sh`, which recycles the virtualenv before it
runs. End-to-end: `tests/at_end2end_test/runLocal.sh [BASE_PORT]`. The
Given/When/Then catalogue and its harness mapping are in
[`acceptance.md`](acceptance.md).

---

## 7. Trust model

The atServers are trusted to serve keys faithfully. This section records what rests on
that trust, so nothing elsewhere in the doc set claims more for the advertised-key
signing ([section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify),
[decisions.md §12](decisions.md)) than it gives. Key transparency
([#2293](https://github.com/atsign-foundation/at_client_sdk/issues/2293)) is on the
roadmap as the way a client checks that trust instead of resting on it
([section 7.4](#74-key-transparency-is-on-the-roadmap)).

None of this is specific to post-quantum keys. They make the bytes harvest-resistant;
whom a client trusts for keys is a separate question, and classical Atsign answers it the
same way: a sender fetches `public:publickey@alice` from @alice's atServer and encrypts
to whatever it returns.

### 7.1 What the atServers are trusted for

- **An atSign's keys.** A client gets @alice's advertised keys from @alice's atServer:
  her `nskey` publics and, for an approver, an enrollee's key package, along with the
  `_apsk` each is signed against. Signing chains each advertised key to `_apsk`, and the
  same atServer serves `_apsk`, so the chain's anchor is a key the atServer serves. In
  effect an atSign's atServer is the certificate authority for that atSign's keys.
- **Both directions of an atSign's traffic.** @alice's clients fetch every peer's keys
  through her atServer, which looks them up on the peer's (`plookup`), so a share
  between two atSigns rests on both their atServers, whichever way it goes.
- **The sender of an unsigned payload.** nskey data values and their content-key
  conveyances carry no sender signature, and `pqSeal` is RFC 9180 Base mode, which
  authenticates no sender, so a reader takes the `sharedBy` a record names from the
  atServer that served it, self-data included.

### 7.2 What the signing adds

While the atServers are faithful, no enrollment can publish a key in another
enrollment's name, in its own atSign or another. The atServer lets only the owning
enrollment write its `_apsk`; a client checks the APKAM signature on a peer's `nskey`
advertisement (`ApkamSignedAdvertisedKeys`), and an approver on an enrollee's key
package (`VerbEnrollmentDirectory`), against the `_apsk` served for the enrollment that
signed it. The signing does not check the atServers themselves; that is what key
transparency is for ([section 7.4](#74-key-transparency-is-on-the-roadmap)).

### 7.3 Self-data

A client seals to its own atSign's `nskey` only for a generation whose private it holds,
and only to the public half that private derives, never to the one it was served;
without the private it refuses the write with `NskeyPrivateNotHeldException`. So the
confidentiality of self-data, and of the sender's own copy of a shared content key,
rests on keys the client holds rather than on what its atServer serves; their sender
still rests on the atServer ([section 7.1](#71-what-the-atservers-are-trusted-for)).
The cost is that an enrollment authorised for a namespace cannot write there until its
private arrives, which `holdsPrivate` reports.

### 7.4 Key transparency is on the roadmap

Key transparency ([#2293](https://github.com/atsign-foundation/at_client_sdk/issues/2293))
moves the anchor outside the atServers in two steps. First, a client pins a peer's
signing root on first contact and checks every later advertisement through the chain
back to it; `verifyChain` can walk a chain, but nothing calls it on a peer's
advertisement: its one caller outside tests, `Enrollments.anchoring`, reports on the
client's own enrollments. Then each signing
root is published to a transparency log on the atDirectory
([section 7.5](#75-key-transparency-on-the-atdirectory)), so first contact is checked
too; that step is multi-repo.

Signing content-key conveyances waits on the same anchor: until it exists, a sender
signature would be checked against an `_apsk` the same atServers serve.

### 7.5 Key transparency on the atDirectory

> **Status: design sketch for
> [#2293](https://github.com/atsign-foundation/at_client_sdk/issues/2293), not a D1
> decision.** It belongs to a separate effort (identity and transparency), not the D1
> substrate.

The atDirectory already maps *atSign → atServer address*. Key transparency (KT) adds a
second job: the **atSign → signing-root binding**, published so that a client can check
the keys it is served against it rather than take them on trust. What KT gives comes from
verifiability, witnessing and monitoring, not from trusting whoever runs the log, so it
holds **whoever hosts the atDirectory**, Atsign included.

**What is logged.** The atSign's signing root, `public:pq_signing_root@<atSign>`
([decisions.md 18](detail/decisions.md#18-pq_signing_root-is-the-user-owned-signing-root-2026-08-03)),
the user-owned anchor; the `nskey` and key-package publics chain to it through signatures
([section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify)) and need not be logged
one by one. The root changes far less often than the keys chained to it, so logging it
keeps churn low.

**Structure (CONIKS / Key-Transparency lineage).** A **verifiable key directory**: a
Merkle prefix tree keyed by atSign, giving each atSign an efficient proof of *its current
binding* and of *absence of any other binding*. Each **epoch** the directory publishes a
**signed tree head (STH)** committing to the whole tree; STHs form a hash chain (each
commits to the previous), so the log is append-only and that is *provable*: history
cannot be rewritten without it showing. A **VRF over the atSign** gives the tree a
private index, so the log does not enumerate atSigns (their names stay confidential —
important given atSigns are identifiers); only a party who already knows `@alice` can
request and verify her proof.

**How a client checks a binding — three checks that work together.** No single check is
enough; together they mean every key a client accepts is backed by a binding in the
witnessed, append-only log, where its owner can see it. KT shows a binding its owner did
not make; it does not stop a key under that binding being served (see *What KT gives*
below).

1. **An inclusion proof on every key fetch** ties each key to the log. When a sender
   fetches @alice's advertised key (from her atServer), it also gets a KT **inclusion
   proof** binding @alice → root in a recent STH, plus the signature chain root →
   advertised key, and accepts the key only if all of them verify. A key not backed by a
   root **in the log** is refused, so every accepted key traces to a logged root; checks
   2–3 cover what the log holds.
2. **Witness co-signing gives every client the same tree.** A set of **independent
   witnesses** (community members, self-hosters, an org's own nodes — *not* only Atsign)
   co-sign each STH; clients accept an STH only with a quorum of witness signatures. No
   single party, Atsign included, can then produce a valid STH alone, or show one client a
   different tree from everyone else without the witnesses co-signing it. Gossip of STHs
   (piggybacked on ordinary atServer-to-atServer traffic) reinforces this: two parties
   comparing roots see any difference at once.
3. **Per-atSign monitoring shows the owner every binding.** Checks 1–2 do not stop a
   root @alice never made being logged under her name with a valid inclusion proof.
   Monitoring shows it: @alice (or monitors she delegates to) watches the log for any
   binding under @alice she did not create, and the append-only log means she sees one
   by the next epoch. Trust in the atDirectory then reduces to this: nothing is bound to @alice
   without @alice, or her monitor, seeing it.

**What KT gives — checking, not prevention.** With KT anchoring the root and
[section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify)'s signatures chaining
advertised keys to it, a key served under a binding its owner did not make becomes
**visible and attributable**: the binding is in the log, signed and witnessed. KT does not
stop such a key being served and sealed to during the epoch before its owner sees the
binding, so it checks the trust the atServers and the atDirectory hold rather than
removing it (do not claim otherwise; [section 7](#7-trust-model) exists so the doc set
does not claim more than the design gives). What is left is: Atsign *and* a witness
quorum act together, *or* @alice does not monitor (or delegate monitoring), for one
epoch. Self-hosting the atDirectory and the witnesses (split-horizon, already supported)
takes Atsign out of it entirely for a closed ecosystem; comparing a root's fingerprint
over another channel (QR, voice, printed code) when it is pinned on first contact closes
the one-epoch window for the pairs that need it most.

**Open problems (this is a sketch; a real design must close these).**

- **First contact is trust on first use.** KT protects the *continuity* of a binding, not
  the initial root publication, unless the root's fingerprint is compared over another
  channel when it is pinned.
- **What KT gives is as strong as its witnesses are independent.** A handful of genuinely
  independent witnesses make it hard to show different clients different trees;
  Atsign-only witnesses do not.
- **Checking, not prevention** (restated because it is the crux): a binding its owner did
  not make is seen, but a key under it can be sealed to for one epoch before it is. A
  fingerprint compared over another channel closes that window for the pairs that need
  it most.
- **Root rotation and revocation are unspecified here.** Logging the root means a root
  that is rotated, or lost, needs a *monitored key-change entry* and defined rotation and
  revocation semantics; without them a lost root stays a valid chain anchor.
- **STH freshness is unspecified here.** Clients must reject stale STHs (bound the maximum
  STH age); a client held at an old epoch would miss a legitimate rotation and see a
  binding its owner did not make later than it should.
- **Monitoring is the element most users won't run themselves.** For a typical end user
  the *delegated-monitor* path is the one that actually carries the guarantee — an
  atSign with no monitor (self- or delegated) gets **nothing** from KT. A real design
  must make independent delegated monitoring the default, not an opt-in.

---

## 8. Subsystem F — inter-server PQ authentication (IS-1)

Inter-server authentication is the FROM/POL handshake. It is separate from the
client-to-atServer data path that subsystems A and B secure: it proves that a
connecting atServer holds its Atsign's server authentication signing key
(`signing_privatekey`), while the TLS session secures the channel. The
handshake signs a per-session challenge with RSA-2048, which a large quantum
computer can forge; signatures are not harvest-now-decrypt-later material, so
the exposure is a live forged authentication, and the move to ML-DSA-65 is in
[Planned changes](#planned-changes).

### 8.1 The handshake

Paths are under `packages/at_secondary_server/lib/src/` on at_server's trunk.

1. The connecting atServer, `@alice`'s, sends `from:@alice`. `@bob`'s atServer
   (`verb/handler/from_verb_handler.dart`) answers with a session id and a
   verifier-bound challenge, `pol1.<base64url({"v": "@bob", "n": <uuid>})>`
   (`SecondaryUtil.buildBoundPolChallenge`), which it stores for one minute.
2. `@alice`'s outbound client (`connection/outbound/outbound_client.dart`)
   refuses to sign a bound challenge whose `v` is not the Atsign it dialled. It
   signs the challenge with `signing_privatekey` (RSA-2048 over SHA-256), stores
   the signature under the session id, and sends `pol`.
3. `@bob`'s atServer (`verb/handler/pol_verb_handler.dart`) looks up the
   signature on `@alice`'s atServer and `public:signing_publickey@alice`, spends
   the stored challenge as it reads it, whatever the verification decides, and
   verifies.

An older verifier issues a bare UUID rather than a bound challenge, and a prover
signs that unchanged, so every pairing of versions interoperates.

---

## 9. Subsystem G — signature agility (the auth/signing key split)

Ruled in
[ruling 91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11).
The acceptance rows are
[`acceptance.md` 16](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).

### 9.1 The two roles

| Role | Key | Where the private lives | Where the public is advertised | Lifecycle |
|------|-----|--------------------------|--------------------------------|-----------|
| Authentication | the APKAM keypair (the client authentication signing key) | `auth:<algo>:<n>`, `privateAuthentication` | the enrollment record's `apkamPublicKey` | one active at a time; rotated in place by `enroll:update` |
| Data signing | the client data signing key, one keypair per algorithm | `sign:<algo>:<n>`, `privateSigning` | `_apsk`'s `keys` array | several may be active at once; added and retired by policy |

⚠️ Neither id carries the enrollment. The `enrollments[]` entry the keys sit in
states it once
([ruling 99](detail/decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14),
item 5), so identity is `(enrollment, keyId)` and two enrollments may each hold
`auth:mldsa65:1`.

PKAM verification is record-authoritative: the atServer reads `apkamPublicKey`
off the enrollment record and never reads `_apsk` to authenticate. `_apsk` is
composed client-side. The atServer stores and publishes it, keeps its links
([section 9.8.3](#983-the-chain-one-link-per-key)), and checks only its
structure: on `enroll:request` and `enroll:update` it refuses a list-form value
with an entry lacking a string `kid`, `alg` or `pub`, a `kid` listed twice, or
the enrollment's `apkamPublicKey` listed beside another key (`ApskLinks.settle`
in at_server's `enroll/apsk_links.dart`).

**On a legacy enrollment the two roles are one keypair.** An enrollment created
before the split holds a single rsa2048 keypair: the atServer verifies it for
PKAM, and `_apsk` advertises it as what signs. `ApkamSigning.signingKeys` falls
back to it when the enrollment holds no signing material of its own, and
`apskEntries` advertises it on exactly that condition, so what signs and what is
advertised are one rule and cannot drift apart. A legacy enrollment therefore
never mints a second rsa2048 data signing keypair; the rule, and why it names
rsa2048 alone, is in
[section 9.8.7](#987-a-legacy-enrollments-one-keypair-and-how-the-rules-compose)
([ruling 126](detail/decisions.md#126-the-mint-barrier-is-deleted-legacy-authentication-and-data-signing-are-one-keypair-2026-08-30)).

### 9.2 The keyfile

`CryptographicMaterialRole` has `privateAuthentication` and
`publicAuthentication` beside `privateSigning` and `publicVerification`.
`CryptographicMaterialAlgorithm` tokens are the enrollment's `signingAlgo`
spellings.

`AtKeys.fileApkamMaterial` files an authentication keypair under
`auth:<algo>:<generation>` as `privateAuthentication` / `publicAuthentication`.
`AtKeys.fileSigningMaterial` files a data signing keypair under
`sign:<algo>:<generation>` as `privateSigning` / `publicVerification`. The
generation is per `(role, algorithm)`, so an enrollment moving between
algorithms holds both at generation 1. `AtKeys.keyIdPrefix` and
`AtKeys.isRoleKeyId` own that grammar.

Reading them back is `AtKeys.signingKeysFor(enrollmentId)`, which selects on
that **keyId shape** rather than on the `privateSigning` role. The role is not
unique to an enrollment's client data signing keys: the Atsign-wide signing root is filed
under it too, in the document's own `atsignKeys[]`, which `signingKeysFor` never
reads. The shape filter stays because the role can still be shared within an
enrollment, and a signature made with a key whose public half is in no `_apsk`
verifies against nothing. Both halves must be present and active, with the same
algorithm; an algorithm this build does not know is skipped rather than
refused, because the rest of a keyfile written by a newer client is still
usable.

`AtKeysAssurance.validateKeyMaterials` and `.validateAddKey` filter on status,
and `AtKeysAssurance.refuseSecondLiveEnrollment` carries the
single-active-authentication rule. With one live enrollment per install, a
second active authentication key is a keyfile this build will not write,
whatever algorithm it names.

**The refusal is on the write path only**
([ruling 99](detail/decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14),
item 2). `AtKeys.addKey` calls it; the parse files through a private path that
applies the structural invariants and not this one. A reader that refused a
second entry would make the plurality impossible to enable — the first build to
emit two would break every build before it — and the whole file is somebody's
key material to lose. The ambiguity surfaces instead at
`AtKeys.resolveAuthenticatingEnrollment()`, which throws, naming the candidates,
when a caller asks for the one answer that does not exist.

**The keys name the enrollment**
([ruling 132](detail/decisions.md#132-the-keys-name-the-enrollment-and-primary-names-the-atsigns-own-credential-2026-09-07)).
`AtKeys.enrollmentToAuthenticateAs()` is what at_client asks on every route into
a connection — `Atsign.open` through `AtClientImpl.create`,
`Atsign.authenticatesAs`, and the authenticated lookup an enrollment or a
decision runs on. It answers the one enrollment holding active authentication
material, else the flat stored `enrollmentId`, else `primary`, the atServer's
name for the primary enrollment; it throws rather than pick when several
qualify. `resolveAuthenticatingEnrollment()` is the typed-only half of that
answer. The keys decide because a caller-supplied id, with a cold start falling
back to the flat block, left every keyfile-only caller running as the legacy
enrollment after a retrofit.

`AtKeys.replaceKey(enrollmentId, keyId, replacements)` retires the named
keyId's materials and files the replacements in one call, rolling back if a
replacement is refused, so a rotation is never two caller-sequenced mutations
across a flush. It takes the enrollment because identity is
`(enrollment, keyId)`; `retireAtSignKey` is the Atsign-scope sibling.
`AtKeys.retireSigningKeys(enrollmentId, algorithm)` withdraws an enrollment's
client data signing keypair for one algorithm. The caller names the algorithm
because that is the unit a client data signing key leaves service in, and the `sign:<algo>:<generation>`
grammar is `AtKeys`'s own.

Reading, in order of what a file can contain:

1. no `version` — the legacy flat shape;
2. `version: 1` with `keys: []` and no containers, carrying nothing a legacy
   file does not;
3. `version: 1` with `keys: []` beside `enrollments[]` and/or `atsignKeys[]`.

Writing emits (1) when there is no typed material and (3) otherwise. The
top-level `keys` array is always present and always empty in (3), because
readers in the field may expect it wherever there is a `version`
([ruling 141](detail/decisions.md#141-a-typed-keyfile-carries-an-empty-top-level-keys-array-2026-09-14)).
A `version: 1` document whose top-level `keys` is **populated** is **refused by
name**: no container reads that array, so parsing it would discard the material
and authenticate from the flat block as the wrong enrollment.

### 9.3 `_apsk`

```json
{
  "v": 1,
  "keys": [
    {"kid": "…", "use": "sign", "alg": "mldsa65", "pub": "…"},
    {"kid": "…", "use": "sign", "alg": "rsa2048", "pub": "…",
     "status": "retired"}
  ]
}
```

⚠️ **`kid` is required on every entry.** `apskSigningKeys` skips any entry
lacking one, so a document without it is one every reader treats as empty and
then refuses outright. `apskAdvertisement` writes it.

`status` is **omitted** on a live entry rather than written as `"active"`,
because absent already reads as active and stating the default would change the
bytes of every advertisement in the protocol.

`kid`, `use`, `alg`, `pub` and `status` are `PackageKey`'s spellings
(`packages/at_client/lib/src/secret_sharing/key_package.dart`), so the design has
one vocabulary for a list of keys with algorithms. `status` is the shared
[`KeyEntryStatus`](../../../packages/at_auth/lib/src/enroll/key_entry_status.dart),
which lives in at_auth so that all three advertising records name one type:
at_client depends on at_auth and not the reverse, which is the only direction a
shared type can travel, and `publicKeyKid` sits there for the same reason.
Absent reads as `active`. A value this build does not know is carried through
**verbatim** — read unchanged, and written back unchanged by any writer handed
it, so a record rebuilt by an older build cannot weaken what its owner said
about a key — and it answers **no** to both questions the field exists for: it
is not offered for new operations, and it does not vouch for what the key
already did. Unknown is *more* restrictive than either known value, never less.

A reader accepts this form and the bare string, which is an `rsa2048` key. A
writer emits the bare string only for a single active `rsa2048` key, and this
form otherwise (`bareApskValueOf`). A **`retired` entry is kept by the reader**,
not skipped: this list is what verifies stored envelopes, and a retired key is
precisely what signed the older ones. It is a caller *choosing a key to sign
with* that must exclude it.

The value is composed client-side and travels on `EnrollParams.apsk` (or
`EnrollParams.apskLegacy` for the bare string). The atServer stores it verbatim
on the enrollment record, publishes it at approval, and rewrites it when
`enroll:update` carries a new one; absent means no `_apsk` is published at all.
It checks the structure as [section 9.1](#91-the-two-roles) describes. The
atServer limits the whole enrollment record, `_apsk` and its links included, to
500 KB, and refuses a record that would exceed it rather than truncating it.

**No mint withdraws a client data signing key, which is what makes the
advertisement safe to read at any moment.** A mint adds the algorithms the
in-use set names and the enrollment lacks, and retires the ones it no longer
names, except that a held key stronger than every algorithm the set names stays
active and, while one is held, nothing is minted. A retired entry stays
advertised, because `SigningKeyMinting` publishes the keys being retired
together with everything the keyfile already records as withdrawn, and
`verifyEnvelope` verifies against the key the signature's `kid` names among
every advertised key of the resolved algorithm, retired ones included.
`parseApskValue` keeps an entry only when its status vouches for past
operations: `active` or `retired`.

The one key a mint drops is an **authentication** key. An enrollment that holds
no data signing key signs with its authentication key and advertises it; its
first mint publishes the new key and stops naming the authentication key, so
what that key signed stops verifying. For a legacy rsa2048 enrollment the rule
in [section 9.1](#91-the-two-roles) means no mint happens. An enrollment that
authenticates **post-quantum** and holds no data signing key does reach it; only
a keyfile written before enrollments were given a client data signing key at creation is in
that state.

**No signer waits for a mint.** A signer can sign under a minted key in the
moment before the advertisement names it ([section 9.8.8](#988-what-is-accepted-rather-than-closed)).
Making signers wait deadlocks, because the startup answers inbound secret
requests by signing a reply before its mint step runs
([ruling 126](detail/decisions.md#126-the-mint-barrier-is-deleted-legacy-authentication-and-data-signing-are-one-keypair-2026-08-30)).

### 9.4 The signed envelope

Every signed document in this design except the root link is an **RFC 7515
general JSON serialization** envelope
([ruling 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12),
item 1).

#### 9.4.1 Wire shape

```json
{
  "payload": "<base64url(JSON)>",
  "signatures": [
    {"protected": "<base64url({\"alg\":\"ML-DSA-65\",\"typ\":\"<type>\",\"kid\":\"<keyId>\",\"enid\":\"<enrollmentId>\",\"v\":1})>",
     "signature": "<base64url>"},
    {"protected": "<base64url({\"alg\":\"RS256\",\"typ\":\"<type>\",\"kid\":\"<keyId>\",\"enid\":\"<enrollmentId>\",\"v\":1})>",
     "signature": "<base64url>"}
  ]
}
```

The signing input per entry is `ASCII(protected || '.' || payload)`, all
encodings unpadded base64url. `alg` uses the **JOSE** names — `RS256`, and
`ML-DSA-65` per RFC 9964 — not the `_apsk` array's `mldsa65`/`rsa2048`
spelling; the two vocabularies meet in one mapping function in
`packages/at_client/lib/src/signing/envelope_signature.dart`.

No reader accepts the flat
`{payload, signature, hashingAlgo, signingAlgo, enrollmentId}` envelope that
at_client 3.14.0 wrote through the `@experimental` `AtClientSecretSharing`:
there is no legacy branch, by decision. The bare-string `_apsk` is a *record*,
not an envelope
([ruling 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12),
item 3).

#### 9.4.2 The protected header

`typ` says what the envelope was signed **for**, and a verifier is handed the
type it expects rather than reading this one
([ruling 103](detail/decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)).
It is one of `at-app+jws`, `at-chain-link+jws`, `at-key-package+jws`,
`at-nskey-ring+jws`, `at-secret-envelope+jws`, and `at-verified-advertisement+jws`
for the local record a client keeps of verifying its own advertisement
([section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)); every entry
of one envelope carries the same value, and an envelope naming none is refused.
Without it a signature over one document meant the same thing in every context
that read it, and six uses of this shape are signed by one key.

`kid` names the signing **key**: the advertised `_apsk` entry's own kid, the
first 8 bytes of `SHA256(publicKey)`, hex-encoded. `enid` names the signing
enrollment
([ruling 131](detail/decisions.md#131-the-protected-header-names-the-key-and-the-enrollment-moves-to-enid-2026-08-31)).
A client using the Atsign's own keys, which publishes at `_apsk.primary`, stamps
`enid: "primary"`: the sentinel is deliberate and never absent
([ruling 116](detail/decisions.md#116-proposals-rejected-on-evidence-2026-08-23),
item 15). `enid` is absent on a key package signed at `enroll:request`, before
there is an id to stamp, and on a key package re-published at `enroll:update`,
which signs without the enrollment id it has in scope. Its readers pass the id
in explicitly, so it still verifies.

There is no top-level `v` or `enrollmentId`: both live **inside** each
`protected` header, as `v` and `enid`, where the signature covers them. A
version or signer claim outside the signature could be edited in flight.

#### 9.4.3 Signing and verifying

Signing: one signature per key `ApkamSigning.signingKeys` returns — the
enrollment's active client data signing keys that carry a link while any does,
else every one it holds, else its authentication key — so the envelope carries
what `_apsk` advertises as `active`.

Verifying: resolve the signer's `_apsk`, intersect its entries with the
algorithms this at_chops build implements, take the strongest by
`SigningAlgoType.strongestFirst`, and verify that one signature. If it fails,
**refuse**; do not try a weaker one. Falling through to whichever signature
happens to verify would let whoever altered the envelope choose the algorithm,
and it would read as success in every log.

One algorithm can name **several** advertised keys: a rotation keeps the
superseded key advertised as `retired` beside its successor. The algorithm picks
the signature entry, and that entry's `kid` then picks the key within the
algorithm, which is checked once. An entry naming no key, or a key the
advertisement does not carry, is refused, and the refusal names the key it asked
for.

An envelope whose algorithms share none with the signer's `_apsk`, as this
build reads it, is refused for that reason specifically: it is what a verifier
whose build cannot run the signer's algorithm meets.

#### 9.4.4 The envelope in code

**The envelope is a type, not a map.** `SignedEnvelope`, in
`packages/at_client/lib/src/signing/envelope_signature.dart`, holds the payload
and one `EnvelopeSignature` per entry, and both compare by value.
`SignedEnvelope.fromJson` is called wherever an envelope is read, on the decoded
JSON map, and refuses anything that is not structurally an envelope: a payload
that is not a string, a missing or empty `signatures` array, an entry whose
protected header does not decode. `toJson()` is called wherever an envelope is
written into a JSON structure, rather than putting the object there and relying
on `jsonEncode` to call it, since every in-process reader of that structure
would then meet an object where it expects a map. A change to the shape is a
compile error at every reader, where a string-keyed map compiles and fails at
runtime.

**The wire text is kept as it arrived.** The payload and each entry's
`protected` and `signature` are held as the base64url text they were received
as, never decoded and re-encoded; the decoded header and payload are read from
that text. The signing input is those received characters, so no canonical JSON
form is needed as long as nothing re-encodes them. `toJson()` therefore
reproduces what `fromJson` was given byte for byte, and
`packages/at_client/test/jws_envelope_test.dart` pins that. A test that needs an
altered envelope builds a new one through `fromJson`, so what it alters still
passes the structural checks a received envelope does.

**One signer and one purpose per envelope.** `fromJson` refuses an envelope
whose entries name more than one `enid`, or more than one `typ`. A verifier
picks its entry by algorithm, so entries that disagreed about the signer or the
purpose would let the entry that verified and the entry a caller reads be
different entries. Neither refusal is to be relaxed: a writer that only ever
signs once does not stop a second entry being appended. Two accessors read the
first entry rather than the one a verifier checked: `.signature` is the first
entry, and `.signerEnrollmentId` is its `enid`, which every entry shares.

#### 9.4.5 The root link is not an envelope

A root link is a map, `{v, alg, kid, payload, signature}`, verified against the
root key its `kid` names among those published at
`public:pq_signing_root@<atSign>`, and held in the `_apsk` record's `apskLinks`
map beside chain links, which are `SignedEnvelope`s
([section 9.8.3](#983-the-chain-one-link-per-key)). Having no protected header
to carry a `typ`, it signs `at-root-link:` ahead of its payload instead
([ruling 103.4](detail/decisions.md#1034-the-root-link-is-not-a-jws-so-it-gets-a-prefix)),
through one codec, `PqSigningChain.rootLinkSignableBytes`, used by the signer and
the walk.

### 9.5 `enroll:update`

`enroll:update` is one alternation entry in at_commons `syntax.dart`'s `enroll`
pattern, widened from
[ruling 68](detail/decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)'s
`enroll:updateMetadata`. It reaches `apkamPublicKey`, `signingAlgo`, `apsk`
(or `apskLegacy`) and `metadata`; never `namespaces` or the approval state.

`EnrollParams.apkamPublicKeySignature` is base64 of a signature by the **new**
private key over `enrollmentId|apkamPublicKey|signingAlgo`, which the handler
verifies against the `apkamPublicKey` in the same request before anything is
written. A request changing `apkamPublicKey` without it is refused, as is one
naming an `apkamPublicKey` another enrollment already holds, or changing
`signingAlgo` without a new key.

at_auth's `apkamPossessionSignature` (`lib/src/enroll/apkam_possession_proof.dart`)
produces it through `signPkamChallenge`, the function that signs a PKAM
challenge, because the atServer verifies both through one verifier and the two
must frame a signature the same way: ML-DSA-65 signs the bytes directly, and
RSA-2048 signs their SHA-256. It is the APKAM keypair that signs, never the
encryption keypair, since what is proved is possession of an APKAM
authentication key.

Ruling 68's items 2 through 7 apply unchanged: self-only, approved enrollments
only, a per-key set rather than a whole-map replace, the server keeps no opinion
of metadata contents, superseded material is not retired, and an old atServer
fails loudly because an unknown operation does not match the verb regex.

An enrollment whose authentication private is **lost** cannot rekey: self-only
means the proof of the current key is the authority. That case is a new
enrollment.

### 9.6 Algorithm policy

Three separate things, deliberately in three places:

| Thing | Where | Why there |
|-------|-------|-----------|
| Strength order | at_chops, beside `SigningAlgoType` | A protocol fact every client and the atServer must agree on |
| Verifiable set | derived from what the at_chops build implements | A build cannot claim an algorithm it cannot run |
| Data signing set | `AtClientPreference.dataSigningKeyAlgorithms`, defaulted by `PqPosture` | A rollout decision, which is what posture carries |

The in-use set is a `Set<SigningAlgoType>`, final at construction and
unmodifiable: `{}` under `PqPosture.legacy`, `{rsa2048}` under
`PqPosture.pqReady` and `{mldsa65}` under `PqPosture.pqActive`. Empty is not
"unsigned": an enrollment with no client data signing key of its own signs with its APKAM
authentication key, and that is the key `_apsk` advertises for exactly as long
as it is the signer. It is **not** retained once the enrollment holds signing
keys
([ruling 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14),
item 2): a key is retained for what it *signed*, and the authentication key
signed nothing that outlives the move. What makes that hold is that a posture
move **replaces** the enrollment: a credential whose posture wants a stronger
authentication algorithm retrofits into a new enrollment that owns a client
data signing key from birth
([ruling 134](detail/decisions.md#134-a-posture-move-replaces-the-enrollment-so-the-authentication-key-is-never-retained-2026-09-08)).
A fully privileged predecessor keeps its `_apsk` where verifiers read it; a
non-root predecessor's moves to `.r.__e` when its successor first
authenticates, and what it signed is then refused with that reason
([ruling 144.3](detail/decisions.md#1443-every-move-of-_apsk-stands-and-verification-tells-the-locations-apart)).
Naming an algorithm this build produces no envelope signature for is refused at
construction rather than skipped. The reasoning for each of those is in
[ruling 91.3](detail/decisions.md#913-the-rulings), item 16.

Order: `SigningAlgoType.strongestFirst` — `mldsa65` > `rsa4096` > `ed25519` >
`ecc_secp256r1` > `rsa2048`, pinned by a raw-literal test
(`packages/at_chops/test/signing_strength_test.dart`). It is **total**, covering
every member: a partial order leaves the choice undefined for exactly the pair
nobody thought about, and the pin fails on a new member left unplaced.

When the in-use set names an algorithm the enrollment holds no key for,
`SigningKeyMinting.reconcileSigningKeys` mints one at start, **files it, and
then publishes the updated advertisement**. A client data signing keypair can be
minted unilaterally because it needs no server approval and no change to the
authentication key, which is the practical payoff of the split.

This start-time mint is the **heal path**, not the chief producer: an
enrollment created by a current build already holds its client data signing key
before it is approved ([section 9.8.1](#981-every-door-mints-advertises-and-files-one-keypair)).
What reaches it is an enrollment created before that, or a client whose in-use
set has changed since its last start. It is also the second writer of `_apsk`,
so it obeys the same bare-versus-array rule as the enrollment request: a single
active `rsa2048` key travels as the bare string, in `apskLegacy`, and anything
else as the array. One definition, `bareApskValueOf`, answers that for both.

The order is the design. Filed first, a stop before the publish leaves the key
held and unadvertised, and the next start's republish, composed from the
keyfile, advertises it; an envelope signed in between verifies once either
publish lands. Published first, a stop could leave the advertisement naming a
key nobody holds. An nskey private is filed before its public half is published
for the same reason: an encapsulation key published without its private has
senders sealing data nobody can open.

Which writer depends on whether there is an enrollment record. An enrolled
client sends `enroll:update`, because the atServer is the only writer of an
enrollment's `_apsk`; a client running as the primary enrollment publishes
the record itself, under `primary`.

When an algorithm leaves the in-use set, signing with it stops; the key and its
`_apsk` entry are kept indefinitely as `retired`. One reconcile does both
halves, in an order that matters, inside `serialiseApskWrite`: file the new key,
publish the post-move advertisement, link the new key, then file the
withdrawal. The publish is **handed** the keys being retired rather than
re-reading them, because the keyfile still holds them as active at that point
and a re-read would drop them from the advertisement altogether instead of
moving them to `retired`. Filing the withdrawal first would leave a moment with
no active client data signing key, where the client falls back to signing with its APKAM
authentication key, which the advertisement by then no longer names. An
outgoing key whose link walks to the root stays in service until every key kept
has such a link ([section 9.8.4](#984-who-writes-a-link-and-with-what)).

An **empty** in-use set retires nothing. It is the released posture rather than
"every algorithm has left the set": a client there goes on signing with the key
it holds and advertising it bare, which is what that posture publishes.

### 9.7 Rollout gate

The writer behaviours — minting a separate client data signing key, publishing
the array, and signing with that key — follow from one piece of state,
`AtClientPreference.dataSigningKeyAlgorithms`, which the posture defaults. The
array is a consequence of the enrollment holding anything other than a single
active `rsa2048` key (`apskValueOf`), and `wrapAndSign` signs with the keys the
keyfile holds for the enrollment ([section 9.4.3](#943-signing-and-verifying)).
So a build cannot do one without the others, and there are no independent flags
for them.

**The axes are `PqPosture.authenticationKeyAlgorithm` and
`PqPosture.dataSigningKeyAlgorithms`,** each overridable per
`AtClientPreference`
([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)).
They are two axes because authentication and data signing are different facts.

**`pqReady` is a writer position**, not a reader-only one: the enrollment
authenticates with ML-DSA-65 and owns a fresh RSA-2048 client data signing key
from before it submits, and that key is what `_apsk` advertises. So it writes
something `legacy` does not, and it carries an atServer dependency (ML-DSA PKAM)
that `legacy` does not. A reader needs no gate, which is why the
*advertisement* stays the bare string an older peer parses, but the key it names
changes.

**The ladder swaps; it never overlaps**
([ruling 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)).
Each stage's default set holds at most one algorithm — `{}`, `{rsa2048}`,
`{mldsa65}` — so no posture this SDK ships emits a two-signature envelope. The
multi-signature reader stays: `SignedEnvelope.fromJson`'s refusals of differing
`enid` and differing `typ` stop an entry appended in flight from changing the
signer or the purpose a caller reads
([section 9.4.4](#944-the-envelope-in-code)). It is safe to swap because
*reading* is not staged: a client at `pqReady` verifies a `pqActive` peer's
`mldsa65` envelope, so there is no verifier an overlap would rescue. A swap does
not lose history: the retired key stays advertised, which keeps envelopes
signed before the swap verifiable. An application that names two algorithms in
`dataSigningKeyAlgorithms` itself does get two signatures, one per held key, and
they give only the weaker algorithm's protection, since a verifier takes the
strongest algorithm the envelope still carries and no verifier can insist on the
stronger
([ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28));
narrowing that writer is in [`implementation-plan.md`](implementation-plan.md#todo).

What the stage also carries is the *fleet's* position — the peers' readers have
upgraded — which no client can observe for itself, and which is the
precondition for anyone moving to `pqActive`.

### 9.8 The data signing key an enrollment owns from birth

Sections 9.1–9.7 describe the split. This section describes the key's life:
where it comes from, what names it, and the links that vouch for it. The
rulings behind it are
[ruling 126](detail/decisions.md#126-the-mint-barrier-is-deleted-legacy-authentication-and-data-signing-are-one-keypair-2026-08-30)
and [ruling 127](detail/decisions.md#127-a-client-with-no-enrollment-id-still-mints-and-publishes-its-own-signing-key-2026-08-30).

**Vocabulary, used strictly.** These five words do not overlap, and the
difference between the last two is why an enrollment is created already holding
a client data signing key.

| Term | Meaning | Effect on verification |
| ---- | ------- | ---------------------- |
| **minted** | a keypair is generated | none yet |
| **filed** | the private half is written to the keyfile as typed `sign:` material | `heldSigningKeys` can see it |
| **advertised** | the public half is named in the `_apsk` record | peers can verify against it |
| **retired** | its `_apsk` entry's status becomes `retired`; the entry **stays** | envelopes it signed **still verify** |
| **dropped** | the key stops being named in `_apsk` at all | envelopes it signed **stop verifying, permanently** |

**A data signing key is retired; the APKAM authentication key is dropped.**
"Dropped" has no code path of its own; it is what `apskEntries` does by
omission: it adds the authentication key only while the signing list is empty,
and never places it among the withdrawn entries. So the first mint on an
enrollment that held none stops naming that key, and everything it ever signed
stops verifying.

⚠️ **The gate is `heldSigningKeys.isEmpty`, not "holds an active signing
key".** `heldSigningKeys` is filtered by `canSignEnvelopeWith`, true for rsa2048
and mldsa65 only, so an enrollment holding an active, correctly filed ed25519
client data signing key yields an empty list and advertises its **authentication** key as
the sole active entry.

Two more distinctions: **a record does not sign** — the private half of a key
the record advertises signs; and **the signing root is not a data signing key**
— it is a distinct Atsign-wide ML-DSA-65 key with its own lifecycle
(`PqSigningRoot`), separate from per-enrollment `sign:` material.

#### 9.8.1 Every door mints, advertises and files one keypair

Four request types reach an enrollment, and each carries an
`advertisedSigningKey` whose private half is filed under the id the atServer
assigns: the OTP request, the self-enrollment, the first enrollment, and
activation. Advertising without filing is worse than advertising nothing: the
next start finds the in-use algorithm missing, mints a **second** keypair and
republishes, orphaning the key the record already named.

⛔ **One keypair, not one per algorithm.** `mintAdvertisedSigningKey` refuses a
set naming more than one — *"an enrollment is created holding one data signing
keypair; name one algorithm"* — and `advertisedSigningKey` is a single record
on the request types, so the plural is not expressible.
`reconcileSigningKeys` does mint per algorithm at every start, so a set naming
two is legal to construct and refused at creation; that asymmetry is deliberate
and is why creation and the heal path read differently.

**The algorithm minted is the one the enrollment keeps** — rsa2048 at `pqReady`,
ML-DSA-65 at `pqActive` — so the first start's reconciliation finds `wanted`
already `held`, mints nothing, and does not rewrite `_apsk`.

#### 9.8.2 The form `_apsk` takes follows the algorithm, and nothing else

Exactly one active `rsa2048` key is spelled **bare** — the key itself, which is
what every deployed consumer base64-decodes. Anything else is the **array**.
Two composers apply that rule to one record: at_auth writes it at enrollment
(`EnrollmentSubmitter`), and `apskValueOf` composes it again at every client
start, republishing on any difference.

⚠️ **A second condition on either side makes them disagree about the shape of
the same key**, and the client wins by republishing, which rewrites the record
at its first start. So no other input, a key package included, forces the
array: where the signer is rsa2048 the bare value states exactly that, and
where it is not, the algorithm has already chosen the array.

#### 9.8.3 The chain: one link per key

A link vouches for **one** key the `_apsk` record lists, not for the record's
value. It signs `{v: 2, enrollmentId, kid, alg, pub}` — the enrollment and the
`kid`, `alg` and `pub` of that one entry — and names the `kid` of the key that
signed it. The record keeps its links in `appMetadata` under `apskLinks`, keyed
by the `kid` each vouches for. `enroll:link` is the only operation that writes
one, and the atServer keeps the map across any other write of the record,
dropping the links for keys the new value no longer lists
([ruling 157](detail/decisions.md#157-a-link-vouches-for-one-key-and-the-atserver-writes-it-2026-10-16)).

Whether a link is a **root** link or a **chain** link follows from its signer.
A `kid` among the active or retired keys of `public:pq_signing_root@<atSign>`
makes it a root link, an ML-DSA-65 signature over `at-root-link:` and the
payload, checked against that root key only. Any other `kid` makes it a chain
link, a JWS typed `at-chain-link+jws` carrying the one signature its signer
made, checked against that `kid` in the signer enrollment's `_apsk`, and the
walk goes on from that key. A link that fails its check reads `broken`, and is
never tried as the other kind. The walk compares each link with the entry it is
stored on, `alg` and `pub` as well as `kid`, follows (enrollment, `kid`) pairs,
and reads a cycle, or a chain of more than sixteen keys
(`PqSigningChain.maxDepth`), as `broken`.

`PqSigningChain.verifyChain` answers for an enrollment: **anchored** when every
active key carrying a link walks to the root, **unsigned** when none carries
one, and otherwise the failing key's verdict, naming it.
`Enrollments.anchoring` exposes it; `at_activate list` and
`EnrollmentRequestList` show it.

Because a link names one key, adding or retiring a key leaves the links on the
others standing, and a retired key keeps its link, so what it signed still walks
to the root. While an enrollment has a key carrying a link it signs content
with those keys only, so a key waits for its link before it signs.

⚠️ **An authentication key takes no link and signs none.** It is dropped rather
than retired once its enrollment mints a client data signing key
([section 9.8](#98-the-data-signing-key-an-enrollment-owns-from-birth)), so a
link on it, or one it signed, would stop verifying the moment it leaves the
record. The atServer refuses a link for any listed key equal to the enrollment
record's `apkamPublicKey`, bare or listed, and an enrollment whose `_apsk` is
its authentication key reads `unsigned` until it publishes a client data
signing key.

#### 9.8.4 Who writes a link, and with what

Every writer calls `enroll:link`, which the atServer admits from the target
enrollment itself, or from any caller `enroll:approve` would admit. A voucher
signs with the signing root when it holds the root's private key and is fully
privileged, and otherwise with one of its own active client data signing keys
whose walk reads anchored; never with an authentication key.

| Writer | When | What it links |
| ------ | ---- | ------------- |
| the approver | straight after `enroll:approve` | every key of the enrollment it approved |
| an enrollment that mints a key | in the same reconcile, before an outgoing key is retired | the key it minted, by a chain link signed with one whose link walks to the root, which may be the one retiring, even when it holds the root; an outgoing key whose link walks to the root stays in service until the keys kept have such links, and any other outgoing key retires at once |
| a holder of the root | at every start | its own keys, by root link |
| the sweep, run by a holder of the root (`PqStartupGates.sweepUnanchoredEnrollments`) | at every fully privileged start | every key on the Atsign's other approved enrollments without a sound root link |
| a fully privileged enrollment whose Atsign publishes no root | at start | mints the root, on a key source that can file its private, then links as a holder |

Each call states, per `kid`, the link it found there (`expect`), and the
atServer writes only if that is still what is stored, so two vouchers, or a
voucher and a sweep, cannot lose each other's writes. The client decides what
may replace what: a root link replaces a chain link, or a root link that fails
its check; a chain link replaces only a chain link that does not walk to the
root, never a root link; and a voucher links no key its own chain passes
through. For that rule a link's kind follows its signer's `kid`, as it does for
the walk. Only the first entry under a `kid` is linked, as the atServer reads
the record, and a key not spelt in padded standard base64 takes no link, so
neither can spoil the rest of a call. A refused call is read again and, if the
record has changed, made once more on what it now holds. Every call sends a
line or paragraph separator in its JSON as an escape, so the command stays one
line and a stored link sent back as `expect` decodes to exactly what is stored.
Against an atServer without `enroll:link`, nothing is linked and everything
else completes as before: its first refusal, an `AT0003` for a command the
client's own grammar reads or a reply naming nothing linked, holds for the
client's lifetime, so no later step sends another, and the sweep stops, naming
at warning the enrollments it leaves.

⚠️ **Being fully privileged requires `rw` on both `*` and `__manage`
(`EnrollmentPrivilegeResolver.isFullyPrivileged`), while approval takes only
`__manage`**, so a `__manage`-only approver approves without being fully
privileged, and links with a key of its own that walks to the root. A client
running as the primary enrollment, with no enrollment id or as `primary`,
is fully privileged by construction, but is treated as the Atsign itself, never
as an enrollment
([ruling 132](detail/decisions.md#132-the-keys-name-the-enrollment-and-primary-names-the-atsigns-own-credential-2026-09-07)),
so it sends no `enroll:link`, the sweep passes it by, and `_apsk.primary` takes
no link.

#### 9.8.5 Coherence rules on the preference, and the floor

The first two are constructor refusals in `AtClientPreference`, and both narrow
[ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)'s
"individual axes still win":

- **An empty signing set requires an rsa2048 authentication key.** With no data
  signing key the authentication key is advertised as the sole active entry,
  and only an rsa2048 one can be spelled in the bare form the legacy posture
  exists to keep readable. The rule names the **axes**, not the posture,
  because `posture: pqReady` with an empty set reaches the identical state and
  a custom posture would slip a posture-named check.
- **The authentication axis may not be weaker than the posture it is named
  against.** A posture is a floor; an override lowering an axis below it is
  what a floor prevents. A `dataSigningKeyAlgorithms` weaker than the posture
  names is legal, deliberately: an enrollment holding no stronger client data
  signing key mints rsa2048 and keeps `_apsk` bare; one holding an ML-DSA-65
  key keeps it active and mints nothing, because key material wins.
- **A client never runs below its floor.** The floor is what its enrollment's
  key material sets (`floorOfKeyMaterial`): `pqActive` for an active ML-DSA-65
  client data signing key, and `pqReady` for any namespace-key private. A start
  configured below it warns and is raised per setting
  (`AtClientPreference.raisedTo`): `authenticationKeyAlgorithm`, the strongest
  of `dataSigningKeyAlgorithms`, `configuresPqProviders`, `writesPqByDefault`,
  and `keyExchangeMode`. `seedNamespaceKeys`, `disallowLegacyEncryption`,
  `mintLegacyMaterial`, `sealsToKeyAlgorithms`, `keyEstablishmentAlgorithms`
  and the `allowLegacyCryptoFallback` preference stay as configured. The floor
  is derived from the keyfile at every start and never stored, so a start with
  no atServer applies it too.
  - Seeding and the signing root are never raised: each publishes a permanent
    record for the Atsign that the client's configuration did not ask for. A
    raised client seeds no namespace keys and mints no signing root that its
    configured posture would not, and still reaches its Atsign's keys and the
    root's private by conveyance or by asking.
  - Rejected: raising a named stage to the whole higher stage, which would
    make a `pqReady` client at a `pqActive` floor refuse writes to a
    destination with no namespace key.

#### 9.8.6 A pre-enrollment Atsign retrofits into a first enrollment

An Atsign holding no enrollment predates enrollments — its client runs as
`primary`, the atServer's name for that credential — so it has never
retrofitted. At `legacy` nothing happens, because the signing set is empty. At
a PQ posture the client gives itself a first, fully privileged enrollment and
comes up on it, rather than minting into the shared `_apsk.primary` record and
dropping its own authentication key.

- **appName** is `firstEnrollmentAppName`, a constant shared with the
  activation path so the two cannot drift. **The device name is not
  constant**: it is `firstEnrollmentDeviceName` plus a fresh UUID per call,
  because the atServer refuses a second enrollment naming an
  `(appName, deviceName)` an approved one already holds, and a shared constant
  would let the first clone of a copied keyfile upgrade and leave every other
  refused at every start.
- **Grants are stated, not derived**: `{'*': 'rw', '__manage': 'rw'}` reaches
  the wire as the request's namespaces. A self-enrollment naming no namespace
  is refused, so they cannot be omitted; the connection making the request has
  proved possession of the Atsign's own root credential and is already
  unscoped, so there is nothing narrower to bound it by.
- ⛔ **There is no guard skipping the mint when the client runs as the
  primary enrollment (no enrollment id, or `primary`).**
  [Ruling 127](detail/decisions.md#127-a-client-with-no-enrollment-id-still-mints-and-publishes-its-own-signing-key-2026-08-30)
  rejected one: publishing `_apsk` directly under `primary`, without routing it
  through an enrollment record, is a working, pinned capability, and skipping
  the mint would delete it. The residual that guard was aimed at is recorded
  there as open.

#### 9.8.7 A legacy enrollment's one keypair, and how the rules compose

On a legacy enrollment the authentication keypair **is** the data signing
keypair, and it signs data in memory only; it is never filed as `sign:`
material. `AtKeys.signingKeysFor` cannot see it, because it reads typed
material and a legacy keyfile carries flat fields, so a naive reconcile reports
rsa2048 missing and mints a redundant replacement.
`SigningKeyMinting.reconcileSigningKeys` therefore treats rsa2048 as already
held when the enrollment holds no typed signing material and its
authentication keypair is rsa2048.

⚠️ **Scoped to rsa2048, and the scope is the whole of its correctness.** An
exclusion keyed on *whatever algorithm the authentication keypair reports*
would fire at `pqActive`, where that is ML-DSA-65 on an enrollment holding no
typed material: no ML-DSA-65 client data signing key would ever be minted and the
advertisement would name the authentication key as its sole active entry — the
split collapsing on the posture that exists to create it, with nothing going
red.

The three rules are complementary, not redundant:

| Rule | Covers |
| ---- | ------ |
| minting at creation | every enrollment a current build creates, born holding a data signing keypair |
| the rsa2048 correction | existing **enrolled** legacy enrollments, at any posture whose signing set wants rsa2048 |
| the first-enrollment retrofit | a **pre-enrollment** Atsign at a PQ posture, which has no enrollment to correct |

#### 9.8.8 What is accepted rather than closed

A mint files before it publishes, and `serialiseApskWrite` holds the filing, the
publish and the retirement, so no other **writer** composing from the keyfile
republishes part way. A link is written by `enroll:link`, which the atServer
serialises with every other write of the record, so it needs no lock in the
client. A stop between the filing and the publish leaves a key held that the
advertisement does not name yet, which the next start's `_apsk` republish,
composed from the keyfile, puts right; publishing first could leave a key
advertised that nothing holds. The window left open is against a **reader**: a
signer calling `ApkamSigning.signingKeys` between the two writes signs under the
minted key before the advertisement names it, so the envelope verifies once the
publish lands, or, after a failed publish or a stop, once the next start's
republish does. Nothing makes a reader wait
([ruling 126](detail/decisions.md#126-the-mint-barrier-is-deleted-legacy-authentication-and-data-signing-are-one-keypair-2026-08-30)),
and the window is recorded on `signingKeys` so a reader meets it there.

---

## 10. Record lifetimes and caching

**What the two fields do on an atServer.** `ttl`, in milliseconds, expires a record on
its owner's atServer. An `update` that omits `ttl` or `ttr` keeps the stored values and
the stored expiry, so it does not restart the expiry clock
(`AbstractUpdateVerbHandler._unsetOrRetainMetadata`). `ttr`, in seconds whatever the
server's `ttrMillis` parameter names say, decides whether another atServer may serve its
cached copy: `-1` forever, a positive value until `refreshAt`, absent never. A reader's
atServer keeps no copy of another Atsign's `public:` record that has no `ttr` (or a `ttr`
of 0), apart from its encryption `publickey`, which it keeps with `ttr -1`. A copy kept by
an older atServer goes at the next lookup of the record, or at the nightly refresh
(`AtCacheManager.isCopyNotKept`, since at_secondary_server 3.18.0). A shared record with no
`ttr` is not cached at its recipient at all.

**What each post-quantum record carries.**

| Record | Writer (class.method) | `ttl` | `ttr` | Why |
| --- | --- | --- | --- | --- |
| `@<recipient>:<ckKid>.__ck.<ckNs>@<sender>`, a share's conveyance | `CkManager._cutAndConveyInTurn`, through `ckConveyanceKey` | none | `-1`, with `ccd: true` | The recipient's atServer caches it from the notification, so a restarted recipient opens shares while the sender's atServer is away; `ccd` removes the copy with the original ([142.1](detail/decisions.md#1421-a-shared-conveyance-is-cached-at-its-recipient)) |
| `<ckKid>.__ck.<ckNs>@<atSign>`, a self conveyance | `CkManager._cutAndConveyInTurn`, through `ckConveyanceKey` | none | none | No other atServer holds a copy; `CkManager.collectUnused` deletes it once nothing cites it and `supersededCkGrace` (8 days) has passed ([142.3](detail/decisions.md#1423-a-superseded-key-goes-once-no-record-cites-it-and-its-grace-is-over)) |
| `<ckKid>.__ck.<ckNs>@<sender>`, a share's sibling copy, naming its recipient | `CkManager._conveySiblingCopy`, through `ckSiblingCopyKey` | none | none | A self record, so the sender's other enrollments, and the sender after a restart, open the key from it; deleted with the share's conveyance ([142.2](detail/decisions.md#1422-each-enrollment-keeps-its-own-key-and-its-siblings-can-open-it)) |
| `__ckcur.<destination>.<ckNs>.<enrollmentId>.a.__e@<atSign>` | `CurrentCkPointer.write`, through `currentCkPointerKey` | none | none | Ids only, written unencrypted and remote-first in the enrollment's own namespace, which the atServer moves aside on revocation ([142.2](detail/decisions.md#1422-each-enrollment-keeps-its-own-key-and-its-siblings-can-open-it)) |
| `public:_apsk.<enrollmentId>.a.__e@<atSign>` | at_client `ApkamSigning.publishPublicSigningKeyLocked`; at_server `EnrollVerbHandler._publishApskSigningKey` (`enroll:request`, `enroll:approve`) and `EnrollVerbHandler._writeApsk` (`enroll:update`) | none | none | A `ttl` would expire the key every verifier resolves, and with no `ttr` no reader's atServer keeps a copy ([145](detail/decisions.md#145-a-readers-atserver-caches-no-public-record-without-a-ttr-2026-09-30)); an expired enrollment's record moves to `.d.__e` at its first lookup ([144.4](detail/decisions.md#1444-the-atserver-moves-an-expired-enrollments-data-on-first-sight)) |
| `public:__nskey.<ns>@<owner>` | `PublishedNskeyKeyRing._mint`, for a mint, a rotation and an add | none | none | The sender's 15-minute cache is the only cache, so a rotation is seen within it ([143.1](detail/decisions.md#1431-the-advertisement-carries-no-ttr)) |
| `public:pq_signing_root@<atSign>` | `PqSigningRoot._publish` | none | none | A `ttl` would expire the root every chain anchors to; only the owner reads it, from its own atServer ([145](detail/decisions.md#145-a-readers-atserver-caches-no-public-record-without-a-ttr-2026-09-30)) |
| `_nskeylock.<ns>@<owner>`, immutable, not committed | `MintLock.withLock`, through `ServerMutex.tryAcquireServerMutex` | 2 minutes (`mintLockTtl`); for a mint, rotation or add that conveys first, `PrePublishConveyance.lockTtlFor`: 2 minutes plus 2 seconds per listed enrollment, key and conveyance, at most 15 minutes | none | The `ttl` is the only release, and the refusal of a second immutable create is the interlock ([143.7](detail/decisions.md#1437-minting-needs-at_server-c3162-or-later)) |
| `_rootlock@<atSign>`, immutable, not committed | `MintLock.withLock` from `PqSigningRoot`, through `ServerMutex.tryAcquireServerMutex` | 15 seconds (`signingRootMintLockTtl`) | none | As for the namespace-key lock, sized to how long a root mint takes ([143.7](detail/decisions.md#1437-minting-needs-at_server-c3162-or-later)) |
| `<uuid>.<replyTo>.<kpid>.__ssenv.<ns>@<atSign>` | `PairwiseSecretSharing.sendEnvelope`, through `EnvelopeAddressing.envelopeKey` | 7 days (`envelopeTtl`) | none | An envelope nobody consumes expires; no ruling in 142 to 145 sets it |
| `local:__nskeyverified.<ns>.<enrollmentId>.a.__e@<atSign>` | `VerifiedAdvertisementRecord._remember` | none | none | Local storage only and never synced, so a start with no atServer can trust the bytes it last verified; it carries the re-read rule of [143.3](detail/decisions.md#1433-a-clients-own-advertisement-refreshes-like-a-peers-and-on-sync) across a restart ([section 1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)) |

Every lookup the client builds for an `__nskey` or `_apsk` record sets `bypassCache`,
whatever the caller asked (`LookUpBuilderManager.get`). With the atServer keeping no copy
of these records, that only matters if some other writer gives one a `ttr`
([145](detail/decisions.md#145-a-readers-atserver-caches-no-public-record-without-a-ttr-2026-09-30)).

**What each reader caches.**

| What | Where | Keyed by | Lifetime | Why |
| --- | --- | --- | --- | --- |
| A peer's advertisement | `PublishedNskeyKeyRing._remote`, in memory only | owner + namespace | 15 minutes from fetch (`advertisementTtl`). A re-fetch that fails with anything but not-found serves it for 15 more (`advertisementStaleGrace`), then throws. A not-found drops it at once | Withdrawn keys stop at once, and a blip does not stop writes ([143.2](detail/decisions.md#1432-a-not-found-is-final-any-other-failure-gets-the-grace), [143.4](detail/decisions.md#1434-a-peers-advertisement-stays-in-memory)) |
| This client's own advertisement | `PublishedNskeyKeyRing._remote`, re-read local-first; a copy fetched from the atServer is filed with `LocalSecondary.putIfAbsent` | owner + namespace | As a peer's, and expired early when `dataEvents` report the local copy changed. Bytes already verified are not verified again | A sibling's rotation reaches a running client ([143.3](detail/decisions.md#1433-a-clients-own-advertisement-refreshes-like-a-peers-and-on-sync), [143.6](detail/decisions.md#1436-the-own-advertisement-filing-is-explicit-and-only-if-absent)) |
| Own advertisement bytes verified online | `PublishedNskeyKeyRing._verifiedOnline`, and the `local:__nskeyverified` record | owner + folded namespace; the record by enrollment + namespace | The session; the record until a later verification replaces it | An offline start accepts only bytes it verified before ([143.3](detail/decisions.md#1433-a-clients-own-advertisement-refreshes-like-a-peers-and-on-sync)) |
| Namespace levels with no advertisement | `NskeyResolver._missedAt` | owner + namespace | 15 minutes (`missMemory`) | Only a not-found counts as a miss ([143.5](detail/decisions.md#1435-only-a-not-found-lets-the-resolver-walk-up)) |
| Levels a share found empty | `NskeyResolver._shareMissedAt` | owner + level | 30 seconds (`shareMissMemory`) | A share seals to the most specific key its recipient advertises ([161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02)) |
| `_apsk` values | `EnvelopeSigning.pubKeyCache`, one map per AtClient | `<atSign>#<enrollmentId>` | 5 minutes from the fetch, however often used (`publicKeyCacheSettings`). A cached key that fails verification is dropped and fetched once more | A rotation is picked up at the first mismatch ([144.1](detail/decisions.md#1441-the-verifiers-_apsk-cache-fixed-five-minutes-refetch-on-failure-one-per-atclient)) |
| Content keys | `ContentKeyCache` | owner + namespace + `ckKid` | No expiry. Evicted when a conveyance is deleted, here or by a synced DELETE (`ContentKeyEviction`), and by `CkManager.collectUnused` | The client can re-derive any key from its synced conveyance ([142.4](detail/decisions.md#1424-the-recipients-content-key-cache-stays-as-it-is)) |
| Namespace-key privates | `PublishedNskeyKeyRing._ownPrivates`; the keyfile through `NskeyPrivateFiling`, id `nskey.<ns>.<nskeyKid>` | owner + namespace + generation | Kept | Data sealed to any generation stays readable; no ruling in 142 to 145 sets this |
| Own advertisement kids read on a private miss, and asks sent | `PublishedNskeyKeyRing._kidsReadOnMiss`, `_readOnMissAt`, `_askedAt` | namespace; generation | 5 seconds (`askCooldown`) | Collapses a burst of misses; no ruling in 142 to 145 sets this |
| A shared conveyance, at the recipient's atServer | `cached:@<recipient>:<ckKid>.__ck.<ckNs>@<sender>`, synced to the recipient's clients | record name | Served forever (`ttr -1`); removed with the original (`ccd`) | [142.1](detail/decisions.md#1421-a-shared-conveyance-is-cached-at-its-recipient) |
| A peer's `__nskey`, `_apsk` or other public record with no `ttr`, at the reader's atServer | `AtCacheManager.remoteLookUp` | – | Not kept. A leftover copy goes at the next lookup or the nightly refresh | Nothing ever served those copies ([145](detail/decisions.md#145-a-readers-atserver-caches-no-public-record-without-a-ttr-2026-09-30)) |
| The signing root | not cached; `PqSigningRoot` reads it from the atServer | – | – | Only the owner reads it |

**Pins.** Each of these asserts the value raw, on the command sent or the constant:

- `packages/at_client/test/nskey_minting_test.dart`: every advertisement write has no
  `ttl` and no `ttr`, and the namespace-key lock is `update:nc:ttl:120000:...immutable:true:`.
- `packages/at_client/test/pq_signing_root_test.dart`: the root has no `ttl` or `ttr`, and
  the root lock is `update:nc:ttl:15000:...immutable:true:_rootlock@alice`.
- `packages/at_client/test/ck_manager_test.dart`: a share's conveyance starts
  `update:ttr:-1:ccd:true:`, and a self conveyance carries neither.
- `packages/at_client/test/ck_sibling_copy_test.dart`: the sibling copy's command shape,
  with no `ttl` or `ttr`.
- `packages/at_client/test/current_ck_pointer_test.dart`: the pointer command, raw.
- `packages/at_client/test/pq_signing_chain_test.dart`: an `_apsk` republish sends no
  `ttl` and no `ttr`.
- `packages/at_client/test/verb_builder_test.dart`: `bypassCache:true` on `__nskey` and
  `_apsk` lookups, even when the caller asked for `false`.
- `packages/at_client/test/pre_publish_conveyance_test.dart`: the lock's sized `ttl`.
- `packages/at_client/test/pq_share_level_test.dart`: `advertisementTtl`,
  `advertisementStaleGrace` and `shareMissMemory` defaults.
- `packages/at_client/test/ck_collection_test.dart`: the 8-day `supersededCkGrace`
  default.
- `packages/at_client/test/envelope_signing_test.dart`: the fixed expiry and the
  refetch, with shortened timings.
- `packages/at_client/test/pairwise_secret_sharing_test.dart`: the envelope's `ttl` follows
  `envelopeTtl` (set to one hour in the test).
- `packages/at_client/test/wire_literal_pins_test.dart`: the record names.
- Live: `tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart` checks that the
  recipient's atServer holds the conveyance copy with `ttr -1`.
- at_server: `features/caching/public_records_without_ttr.feature` and
  `features/enrollment/expired_enrollment_data.feature`.

---

## Planned changes

What is still to change in the design, and why. Owed fixes and chores are not here; they are in
[`implementation-plan.md`](implementation-plan.md#todo).

- **The default posture moves to `pqReady` in a 4.x release, and to `pqActive` at 5.0.0.**
  at_client 4.0.x defaults to `PqPosture.legacy`. The first flip makes every rebuilt client
  read post-quantum data and publish its namespace keys while still writing legacy. The second
  makes post-quantum writes the default, makes data signing ML-DSA-65, and sets
  `disallowLegacyEncryption`. Both are default changes carrying no code of their own, staged so
  that by the time writes move, the keys they need are already published
  ([ruling 138](detail/decisions.md#138-the-posture-ladder-moves-back-a-stage-2026-09-08),
  [ruling 56.4](detail/decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults);
  issue [#2016](https://github.com/atsign-foundation/at_client_sdk/issues/2016)). Once the
  second lands, a sender cannot reach a recipient that never published a namespace key: the
  write is refused, not lost.
- **Legacy key material stops by default once the ecosystem is post-quantum.** A later release
  stops minting the RSA encryption keypair and `selfEncryptionKey` at onboarding, stops
  `enroll:approve` conveying them, and stops new Atsigns publishing `public:publickey`, unless an
  app asks. With that, `selfEncryptionKey` and `shared_key.*` are retired for writing. The
  trigger is the ecosystem moving, not a version number, and legacy reads stay
  ([ruling 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05);
  issue [#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128) for the
  approval step).
- **D2: the `at/pqmls` group provider.** A real MLS engine (RFC 9420: TreeKEM, forward secrecy
  and post-compromise security) on post-quantum ciphersuites, added as another provider behind
  the `CryptoProvider` seam and riding the same per-enrollment substrate: its epoch keys travel
  as `__rk.`-prefixed secrets, which `SecretStore.listSecrets(namePrefix:)` already enumerates.
  It adds per-message forward secrecy, O(log n) membership changes and groups whose membership
  is decoupled from namespace authorisation, all beyond what D1's two rotation levers give, and
  mandatory rotation on join belongs to it. Per-value routing means it needs no migration of
  existing data
  ([ruling 2](detail/decisions.md#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted);
  issue [#2015](https://github.com/atsign-foundation/at_client_sdk/issues/2015)). In three
  milestones:
  - **M4, groups within one Atsign:** a `SecureGroup` interface over an epoch engine, with
    per-enrollment leaves and two-lever rotation.
  - **M5, groups across Atsigns, and a Group Delivery Service:** `(pair, namespace)`-scoped
    groups, and a ciphertext-only delivery service on the atServer (wake-then-pull, ordering,
    catch-up, retention) that makes large groups scale.
  - **M6, the MLS engine:** the epoch engine swapped for MLS behind the same interface and
    delivery service.

  D2 also carries what D1 left out: re-encrypting history after a revocation, and resolving
  which enrollment a program runs as from a label, so that several programs can share one
  Atsign with no per-invocation identity arguments. The `pqSeal` construction is reviewed
  against the standards at D2
  ([ruling 46.1](detail/decisions.md#461-pqseal-stays-custom-and-d2-is-when-we-revisit-it), as
  corrected by
  [ruling 48](detail/decisions.md#48-the-standards-question-reopened-and-what-the-check-found-2026-08-06)).
- **NoPorts on the nskey data path.** The production payoff, with no user-visible change: the
  same commands, arguments, setup and authorisation. sshnp and sshnpd carry requests,
  responses and fleet secrets on the nskey data path, so the session key no longer travels
  under RSA alone. The first step needs only D1 and lands in `sshnoports`: a daemon publishes a
  namespace key at exactly `<device>.sshnp`, a client treats a daemon that has one as
  post-quantum capable and one without as legacy, so a fleet can mix, and a daemon replies in
  the scheme the request arrived in
  ([ruling 146](detail/decisions.md#146-keys-an-app-publishes-below-its-grants-are-its-own-and-ensurereachable-reports-holding-them-2026-10-04),
  [ruling 149](detail/decisions.md#149-how-a-shared-value-was-protected-is-read-from-its-metadata-and-a-reply-goes-in-kind-2026-10-05),
  [ruling 161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02)).
  With D2, session keys are derived through the group's `export()` rather than transmitted.
- **Key transparency for signing roots.** A client pins a peer's signing root on first contact
  and checks each later advertisement through the chain back to it; then signing roots are
  published to a transparency log on the atDirectory, so that first contact is checked too and
  key authenticity no longer rests on the atServers alone
  ([section 7.4](#74-key-transparency-is-on-the-roadmap),
  [section 7.5](#75-key-transparency-on-the-atdirectory); issue
  [#2293](https://github.com/atsign-foundation/at_client_sdk/issues/2293)).
- **Signed content-key conveyances.** Each conveyance carries its writer's signature, and a
  reader refuses one that carries none, so the sender of an nskey data value no longer rests on
  the atServer that served it. It waits on key transparency, since until then the signature
  would be checked against an `_apsk` the same atServers serve, and on a ruling on revoked
  signers ([section 7.4](#74-key-transparency-is-on-the-roadmap)).
- **Post-quantum inter-server authentication.** The FROM/POL challenge described in
  [section 8](#8-subsystem-f--inter-server-pq-authentication-is-1) is signed with ML-DSA-65
  instead of RSA-2048 for any peer that publishes a post-quantum server authentication signing
  key, with RSA kept for peers that do not and a configuration switch that forces it. FROM/POL
  is authentication, not confidentiality: the challenge gives freshness and TLS secures the
  channel, so the signature is the only part to change, and there is no KEM, certificate or key
  lifecycle ([decision log, 2026-07-21](detail/decisions.md#7-decision-log--timeline-dated)).
  Tracked in [#2049](https://github.com/atsign-foundation/at_client_sdk/issues/2049); the
  at_server change is the open
  [at_server#2683](https://github.com/atsign-foundation/at_server/pull/2683), and the published
  record's name and shape are settled there.
- **A sibling copy at a broader recipient level.** A share whose recipient's level is broader
  than the sender's own goes without the sender's sibling copy today. A 4.0.x step adds a value
  field naming the copy's level, and a content key per recipient, scope and own level, so that
  case gets its copy
  ([ruling 161](detail/decisions.md#161-a-share-is-sealed-to-the-most-specific-key-its-recipient-advertises-2026-11-02),
  item 7).
- **Keyfile protection at rest.** Once payloads are post-quantum, the `.atKeys` file holding
  the post-quantum privates is the highest-value target on a device, so encrypting those
  privates at rest, with a backup and restore story to match, is the planned answer (KF-1,
  parked in [`implementation-plan.md`](implementation-plan.md#parked); issue
  [#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129)). Not scheduled.
- **Signing-root rotation.** The root record is rotatable in shape — it uses the `_apsk`
  vocabulary, with a `status` per key — but no rotation is built, so a lost or split root
  cannot be replaced today
  ([ruling 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15):
  D1 builds rotatability, not rotation). Not scheduled.
