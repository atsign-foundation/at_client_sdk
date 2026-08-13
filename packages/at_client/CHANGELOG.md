## 3.14.1
- fix: a new enrollment collecting its conveyed `apkamSymmetricKey` uses its
  own key package. The selection took the first `privateDecapsulation` material
  in the keyfile, scoped by neither enrollment nor recency, so on a retrofitted
  keyfile — which carries the legacy enrollment's package beside the new one's
  — it could adopt a co-tenant's, and an nskey private (same part type, filed
  alone) could be adopted as the recipient identity too. Either way the
  enrollment polls an address nobody is writing to until it times out. Now
  routed through `keyPackageMaterial`, which already required both halves under
  one keyId, skipped dead material and ordered active-then-newest.
- fix: a client builds its PKAM keypair from the keyfile it just read, not from
  the algorithm an earlier read recorded. `_createAtChops` consulted the value
  `_resolveSigningAlgoFromKeyMaterial` had stored, and that stores nothing when
  its own read throws — so one transient keyfile failure made a retrofitted
  client authenticate with the *flat* fields' key while its own enrollment's
  typed material sat in the same file. Losing the algorithm is survivable and
  documented as a fallback to the preference; losing the keypair is not, because
  the atServer checks the signature against the enrollment the client named. Now
  routed through `AtKeys.authenticationFor`, the same resolver
  `AtAuthImpl.authenticate` uses — which its comment already claimed.
- **breaking (unreleased surface): the envelope verifier resolves its algorithm
  instead of requiring one.** `verifyEnvelope` takes the strongest algorithm the
  envelope's `signatures` and the signer's `_apsk` have in common, verifies that
  one entry, and refuses on failure — it does not fall through to a weaker
  signature that happens to check out, which would hand the choice of algorithm
  to whoever tampered with the envelope and read as success in every log. It
  took `signatures.first` and required the envelope's `alg` to match the one
  advertised key; the refusal that enforced (`requireAlg`) is gone, replaced by
  a refusal naming both lists when they share no algorithm. `ParsedApsk` carries
  `keys` and `keyFor(algo)`, with `signingAlgo`/`publicKey` surviving as
  strongest-of getters, and the bare RSA form parses to a one-entry list so both
  published forms are one shape to a caller.
- fix: `SignedEnvelope.fromJson` refuses an envelope whose entries name more
  than one signer. `signerEnrollmentId` reads the first entry while the verified
  entry is now chosen by algorithm, so the two could be different entries:
  appending a signature under a stronger algorithm carrying another `kid` would
  make a caller act on a signer whose signature was never checked.
- fix: `parseApskValue` takes the **strongest** signing algorithm an `_apsk`
  advertises that this build implements, by at_chops'
  `SigningAlgoType.strongestFirst`, where it took the first entry listed. The
  order entries arrive in is the signer's choice, so letting it decide handed
  the algorithm to whoever wrote the advertisement — an enrollment advertising
  ML-DSA-65 beside RSA-2048 would have been verified against whichever it
  happened to list first. A retired entry is still read: `_apsk` retains a key
  so that envelopes it already signed keep verifying, and nothing on this path
  signs anything new.
- fix: a client sweeps for, and opens, envelopes addressed to **any** key it
  holds, not only the one it currently advertises. The sweep filter, the wake-up
  subscription and the sync listener all cover every held address —
  `EnvelopeAddressing.regexForAny` / `sweepRegexForAny` are the one-alternation
  forms, and a filter over no addresses is refused rather than emitted, since
  spelled carelessly it matches either nothing or everything. `_consume` then
  opens with the key the envelope names rather than the current one. Without
  the sweep half the rest is decorative: an envelope a client never scans for
  is one it never opens, however willing it is to.
- **breaking (unreleased surface): a client holds a list of encapsulation
  keys, not one.** `PersistedApkamKeys` becomes `{encKeys: [{encSeed, keyAlgo,
  status}]}` — a list of the new `PersistedEncKey` — where it was a single
  `{encSeed, keyAlgo}` pair, and `PersistedApkamKeys.single(...)` is the
  one-key form a client that has never rotated uses. This is the shape apps
  build in their own `loadApkamKeys` / `saveApkamKeys` callbacks, so it is an
  app-facing contract change rather than a codec change. Rotating an
  encapsulation key has to be non-lossy: an unconsumed envelope lives seven
  days, so at the moment a client starts advertising a new key there is up to a
  week of traffic still addressed to the old one, and a client holding only the
  new key could open none of it. `KeyPackageRegistration` expands every held
  key, advertises them all — each carrying its own status — and answers at all
  of their addresses, while `kpid`, `encPublicKey` and `encKeyAlgo` mean the
  **active** key. `encSecretKey` is replaced by `encKeyFor(kid)`, which answers
  for the key an envelope actually names, and `heldKpids` lists every address
  this client can be reached at. Nothing rotates yet; this is the holding a
  rotation will need.
- feat: `keyPackageMaterials` reads every usable key package a keyfile holds
  for one enrollment, active first, and `bindKeyPackageToAtKeys` adopts the
  superseded ones as retired so a restart does not strand what is in flight.
  The status comes from the keyfile's own `KeyPartStatus` rather than from
  `createdAt`: `AtKeys.retireKey` is how a rotation records the transition and
  `AtKeysAssurance` already enforces at most one active `publicEncapsulation`
  material per enrollment and algorithm, so the file answers the question and
  guessing from age would be a second opinion about it. `dead` material is not
  adopted at all — retirement is as close to deletion as a keyfile gets, and
  dead is the end of that road. `keyPackageMaterial` keeps its signature and is
  now the first entry of that list.
- feat: a key entry can say it is `retired` — retained, but not offered for new
  operations. `PackageKey` gains a `status` of `active` or `retired`
  (`KeyEntryStatus`, which lives in **at_auth** so that all three records
  advertising keys name one type for one field — at_client depends on at_auth
  and not the reverse, the same reason `publicKeyKid` lives there; re-exported
  from `secret_sharing.dart`), and `bestKeyFor` on both a key package and an nskey
  advertisement passes a retired key over, because that method answers "which
  key should be used now" for a sender. Retirement withdraws the future and not
  the past: the entry stays in the list so its holder can still open what was
  already sealed to it, where dropping the entry outright would strand every
  record ever sealed under that key. Use-neutral, because `use` already names
  the operation a key serves — a retired signing key still verifies what it
  signed. Emitted only when a key is retired, since absent already reads as
  active, so no record that has never rotated changes a byte. A `status` this
  build does not recognise reads as retired, the one reading that cannot make
  it use a key its owner has withdrawn. Nothing in this release produces a
  retired entry; the reader has to understand the shape before any writer can
  emit it.
- **breaking (unreleased surface): the nskey advertisement carries a list of
  keys, spelled the way the other two advertising records spell theirs.**
  `public:__nskey.<ns>@<owner>` was the last record still describing its key
  its own way — flat `{nskeyKid, publicKey, alg}` beside the `{use, alg, pub,
  kid}` entries that `_apsk` and the enrollment key package already used. It is
  now `{v, createdAt, keys:[…], suites}`, so one vocabulary covers every list
  of keys with algorithms in the protocol and a reader learns one shape rather
  than three. The list is a capability rather than ceremony: an atSign could
  not advertise both X-Wing and ML-KEM for a namespace while the advertisement
  held exactly one key by construction. `NskeyAdvertisement` becomes a class
  with one codec — `toPayload`/`fromPayload` — replacing a map literal in the
  minting path and a hand-rolled parser in the verifying path that sat 250
  lines apart and had to be kept in step by eye. `v` stays 1: nothing is
  released, so there is no advertisement in the old shape for a version 2 to
  distinguish this from.
- feat: an nskey advertisement offering a key-establishment algorithm this
  build does not implement is read past rather than refused, and a sender
  encapsulates to the strongest algorithm it implements that the owner offers.
  This is the half that has to ship first: a reader assuming one key would
  throw on the first advertisement carrying two, so nobody could publish a
  second algorithm without cutting off every peer that predates it. An
  advertisement whose entries are *all* unusable is still refused outright —
  no downgrade, and no fallback to a key derived some other way. A malformed
  entry beside a usable one refuses too, because sealing to the good one would
  be reading past evidence that the owner's publishing is broken.
- fix: a signed nskey advertisement carrying a key that is not its algorithm's
  length is refused, rather than sealed to. A key id is the SHA-256 prefix of
  whatever bytes it is computed over, so a forged advertisement carries a
  matching one for free and the id check could never see this. The reader
  checked the signature, matched the id and handed the bytes on; the first sign
  of trouble was inside the KEM one seal later, on a stack naming neither the
  owner nor the advertisement it came from. `SecretSharingAlgos
  .publicKeyLengthFor` answers the length from each KEM's own constant rather
  than restating a number, and a test over `keyAlgos` pins it against `kemFor`
  so an algorithm cannot gain a KEM without gaining a length.
- feat: `PackageKey.fromBytes` and `PackageKey.pubBytes` — a key entry built
  from raw material, and the material read back out. Every consumer that hands
  a key to a KEM wants bytes while the wire carries base64, and decoding in one
  place is what keeps a key from being decoded two ways.
- **breaking (unreleased surface): `v`, `alg` and `suites` are required on an
  nskey advertisement, and `suites` on a key package.** Each had an
  absent-means-the-shape-that-predates-it hatch, defending against a
  predecessor that never shipped. What the hatches did in practice was answer,
  on the owner's behalf, questions the owner had not answered — which KEM some
  bytes belong to, and which construction they can unwrap — and a sender acts
  on both immediately. `KeyPackage.legacySuites` and `legacyNskeySuites` go
  with them: two constants with identical values in different files, naming
  what an absence meant.
- refactor: one suite negotiation, `SecretSharingAlgos.bestSuiteBetween`. The
  key-package path and the nskey path each walked the same list, and a
  negotiation that disagrees with itself picks different constructions for the
  same two parties depending on which substrate is asking. The sender's list
  is the preference order and the recipient's is a membership test, which is
  what makes this negotiated agility rather than release-ordered agility.
- **breaking (unreleased surface): a key id is the SHA-256 prefix of the key's
  raw bytes, everywhere.** `PackageKey.computeKid` and `nskeyKidOf` were two
  derivations that disagreed about the preimage — the first hashed the base64
  text, the second the decoded material — and both called themselves "the
  SHA-256 of the public key". They are one function now (at_auth's
  `publicKeyKid`), so a kid means the same thing on an `_apsk` entry, a key
  package and an nskey advertisement. Every kpid changes value; nothing
  published reads one. A `pub` that is not valid base64 now fails loudly at
  construction, which only a writer can do — the read path requires an explicit
  `kid` and never derives one.
- **breaking (unreleased surface): the signed envelope is a `SignedEnvelope`,
  not a `Map`.** `signEnvelope` returns one; `verifyEnvelope`, `wrapAndSign`
  and `verifyEnvelopeSignature` take one; `envelopePayloadOf` and
  `envelopeSignerOf` are replaced by `.payload` and `.signerEnrollmentId`.
  `SignedEnvelope.fromJson` validates the structure once at the read boundary
  and `toJson()` is the wire form — both members are held as the base64url
  text they arrived as, so a round trip reproduces the signed bytes exactly.
  The type exists because reshaping a `Map`-shaped envelope breaks consumers
  the analyzer cannot see: a `['signature']` read on a shape that moved its
  signature one level down compiles and yields null. `EnvelopeSignature`
  carries one entry's `protected`, `signature` and decoded header; both
  classes have value equality.
- fix: `enrollmentKeyPackageBuilder` puts the envelope's **JSON** into
  `EnrollParams.metadata` rather than the envelope object. The map is
  JSON-encoded onto the wire, so the object survived encoding only because
  Dart's default encodable calls `toJson` for you — while every in-process
  reader got something it could not index.
- fix: `PqSigningChain.publishPendingLink` compares the conveyed link against
  the published one **whole**, rather than by a top-level `signature` member
  the envelope does not have. It read null on both sides, so `null == null`
  made every existing link match every new one and a genuinely different link
  conveyed later was silently never published — indistinguishable from
  "already published", since both are the same early return.
- feat: `parseApskValue` reads the `_apsk` array form
  (`{"v":1,"keys":[{kid,use,alg,pub}]}`) an enrollment publishes, skipping
  entries whose `use` or `alg` this build does not know and refusing outright
  when it understands none — no downgrade, and no fallback to a key derived
  some other way.
- **breaking (unreleased surface): `encodeTaggedApsk` and the single-key
  tagged `_apsk` form are removed.** Nothing ever published that shape — the
  array supersedes it, and it is the only structured form a reader now
  accepts, alongside the bare RSA string.
- docs (known limitation): `AtClient.uploadFile` and `AtClient.shareFiles`
  cannot go post-quantum, and throw under `disallowLegacyEncryption`. Both
  build their atKey as `file_transfer_<uuid>` with no namespace, and every
  post-quantum provider is `(owner, namespace)`-scoped — `NskeyCryptoProvider`
  and `SymmetricAesGcmProvider` each decline a namespace-less key — so the
  resolved provider falls back to legacy and the AES file key inside the
  `FileTransferObject` travels RSA-wrapped. A client that set
  `disallowLegacyEncryption` (including via `ReleasePosture.postQuantum()`)
  gets `LegacyEncryptionRefusedException` from the notify instead. The file
  bytes themselves are AES-encrypted and unaffected; it is the key conveyance
  that stays classical. Giving the SDK's own namespace-less writes a reserved
  namespace is a 4.0 change, because the atKey is what the receiver matches on.
- docs: `PublishedNskeyKeyRing.mintAndPublish` no longer describes itself as a
  rotation. Its dartdoc said calling it again for the same namespace "is a
  **rotation**", which `rotate` exists to deny: on a lost mint lock
  `mintAndPublish` adopts the winner's advertisement and returns success, so a
  second call can rotate nothing and report that it did. Correct for a cold
  start; for a rotation it leaves the enrollment being rotated away from
  holding the live generation, and rotation is the revocation lever. No
  behaviour change — `mintAndPublish` is the cold-start mint, `rotate` is the
  rotation lever, and the doc now says so.
- feat: `ReleasePosture` — the four post-quantum rollout flags as one value,
  set on `AtClientPreference(posture:)`. `ReleasePosture.migration()` (the
  default) is the 3.x column of the rollout table; `postQuantum()` runs the
  4.0 defaults today: the era `CryptoConfig` writes PQ, legacy writes are
  refused, the posture names the pq enrollment key exchange, and an argless
  `selfRetrofit` mints ML-DSA.
  Adopting `postQuantum()` early is a deliberate, eyes-open move — see its
  dartdoc: destinations without seeded namespace keys are refused, and the
  SDK's own namespace-less internal writes are refused until the 4.0
  release settles them.
  Every axis is still individually overridable — an explicit constructor
  argument, an assigned `crypto`, a per-request `keyExchangeMode` or a
  per-call `signingAlgo` each beat the posture for that one axis. A bare
  preference is byte-identical to the pre-posture SDK.
  `EnrollmentKeyExchangeMode` is re-exported (show-narrowed) on the main
  barrel so the per-axis override is nameable without importing at_auth.
  There was a fifth axis, the signed-envelope shape. It is gone with the
  second shape: one envelope shape means nothing left for a posture to
  choose.
- fix: a secret-sharing broadcast identifies itself by **enrollment** rather
  than by kpid. `pushSecretToNamespaceMembers` and
  `requestSecretsFromNamespace` skipped the roster entry for this client by
  comparing key-package ids, but a kpid is a reader's choice — it is the first
  key in this build's preference order — so an instance whose enrollment
  changed under it, or any package advertising more than one key, could fail
  to recognise itself and address an envelope to a kpid it is not listening on.
- feat: `selfRetrofit` gains the retrofit signing-algo selector — one of
  the rollout axes, a per-operation parameter defaulting to `rsa2048`
  (the rollout-window mode: a fresh RSA keypair under a new enrollment
  id, no ML-DSA anywhere; the 4.0 posture flips the default to
  `mldsa65`). And it now threads
  `AtClientPreference.keyEstablishmentAlgo` into the key package it
  advertises: the enrollment's KEM previously silently defaulted to
  X-Wing whatever the preference said, and the package is frozen at
  `enroll:request`, so the wrong KEM was permanent for that enrollment.
- feat: a fully privileged approver conveys a **root** link at approval,
  so the enrollments it approves are born anchored rather than healed
  later by the sweep; an approver outside that class keeps signing the
  provisional chain link, and a privileged approver that has not yet
  received the root private conveys no link (the sweep anchors once
  possession heals). The symmetric key and every other conveyance are
  unaffected by which way the link goes.
- feat: the unanchored-enrollment sweep signs **root** links instead of
  chain links, and upgrades enrollments carrying only a provisional chain
  link. Any fully privileged enrollment (`rw` on `*` and `__manage`) —
  the class entitled to hold the signing root — anchors the enrollments
  it vouches for directly to the root, one ML-DSA-verified hop, rather
  than adding a chain hop attributed to itself; a privileged sweeper
  that has not yet received the root private conveys nothing and heals
  by pulling. A conveyed root link is verified against the published
  signing root before the receiving enrollment stamps it.
- fix: a conveyance refusal no longer discards the approval it follows.
  When a server-side approval succeeds but the secret conveyance to the
  new device refuses — a key package that does not verify, an approver
  with no registered package to seal from, an enrollment with no ordinary
  namespace to carry the envelope — `approve()` now throws
  `EnrollmentConveyanceException`, an `AtEnrollmentException` subtype
  carrying the successful `AtEnrollmentResponse` and the advertised
  package's `KeyPackageStatus`, so a caller can tell "approved but the
  device cannot decrypt; consider revoking" from "the approval failed"
  instead of losing the response inside a generic throw.
- refactor: `EnrollmentPrivilegeResolver` gains
  `isEnrollmentFullyPrivileged(enrollmentId)`, and the secret-sharing
  substrate's per-enrollment request gate is wired to that seam by the
  client's startup composition instead of the substrate resolving
  privilege itself. A directly constructed `AtClientSecretSharing` no
  longer self-installs the production gate: its gate starts null, which
  fails closed, until a composition wires one.
- fix: an envelope whose payload handler fails after delivery is no
  longer re-emitted on `receivedEnvelopes` by the next sweep. The claim
  is kept and the envelope left in place for a fresh process to retry,
  honouring the sweep's own never-emitted-twice contract; only failures
  *before* delivery release the claim for an in-process retry.
- feat: `CryptoRuntime.prepareWrite()` — the resolve/stamp/prepare
  sequence every encrypting write path runs before composing anything,
  as one entry point (the put pre-pass passes `stampProviderId: false`
  because its legacy fallback must not leave a key claiming a provider
  that declined it).
- refactor: the approval-time secret conveyance and the unanchored-
  enrollment sweep live behind a new injected seam,
  `EnrollmentConveyance`, with the envelope-sealing production
  implementation extracted out of `EnrollmentServiceImpl`. `approve()`'s
  signature and behaviour are unchanged apart from the carrying
  exception above.
- fix: an nskey private conveyed to the atSign's other enrollments is now
  the generation's **seed**, never the expanded decapsulation key. The
  receiver validates an arrival by re-deriving the advertised public half,
  which only the seed can do — under ML-KEM the expanded form was refused
  on arrival, so no other enrollment ever received a conveyed generation
  (X-Wing was unaffected: its seed and secret key are the same bytes). The
  two forms are now distinct types (`NskeySeed`,
  `NskeyDecapsulationKey`) on the `NskeyKeyRing`/`NskeyPrivateFiling`
  surfaces, so the confusion is a compile error.
- feat: `PqClientBootstrap` — one owner per client for the PQ startup's
  key ring, private filing, secret sharing, signing root and chain, run
  as one ordered fire-and-forget task of named steps (awaitable via
  `startupComplete`; `AtClient.stop()` now halts it at the next step
  boundary, where before a stopped client kept publishing). Each active
  step sits behind a `PqStartupGates` bool, all defaulting on.
  `PqSigningChain` is constructed per client now
  (`PqSigningChain(atClient)`), with the wire vocabulary still static.
- feat: the signed envelope is RFC 7515 JWS **General** JSON Serialization —
  `{payload, signatures: [{protected, signature}]}` — and that is its only
  shape. `alg` (`RS256` / RFC 9964's `ML-DSA-65`), the signer's enrollment id
  (`kid`) and the envelope version (`v: 1`) all sit inside the signed
  protected header rather than unauthenticated beside the signature, so none
  of the three can be edited in flight. The document carries no member of our
  own, which is what lets an off-the-shelf verifier check it whole.
  There is no version parameter and no rollout flag: two earlier shapes — a
  bespoke tagged wrapper and RFC 7515 *Flattened* — were deleted rather than
  carried, because nothing released reads or writes an envelope and there was
  no reader to stay compatible with. The numbering restarts with the shape,
  so `signedEnvelopeVersion`, `jwsEnvelopeVersion`, `envelopeVersionOf`,
  `signEnvelope`'s `version` parameter and `EnvelopeSigning.envelopeVersion`
  are all gone; `envelopeVersion` is the one constant that remains, and it is
  the value carried in `protected`.
  `envelopePayloadOf` and `envelopeSignerOf` are the reads — a direct
  `envelope['payload']` gets undecoded base64url — and every base64url decode
  normalises padding first (Dart's decoder throws on unpadded input at
  RSA-signature lengths, so a naive decode fails on every classical envelope
  and no PQ one). An envelope carrying no `signatures`, or an empty array, is
  refused rather than verifying vacuously. The shape is adjudicated by a
  third-party verifier over committed vectors
  (`test/vectors/jws_envelope.json`, `tool/verify_jws_vectors.mjs`).
- fix: a deleted conveyance record now evicts the cached content key under
  the nskey owner the record names (`sharedWith ?? sharedBy` — the same scope
  every cache writer uses) instead of this client's own atSign. Previously an
  outbound share's CK (`@bob:<ckKid>.__ck.<ns>@alice`, cached under bob)
  survived the deletion on the deleting client's sibling devices, so the
  coarse forward-secrecy lever silently missed exactly the shared data it was
  most needed for. `ContentKeyEviction`'s constructor drops its atSign
  parameter — the scope now comes from the parsed key.
- fix: startup namespace-key seeding files the minted private durably before
  publishing the advertisement. The seeding path built its key ring without
  the private filing the data path gets, so the mint skipped the filing and
  published anyway — the only copy of the private lived in process memory,
  and the first restart discarded what every peer was already sealing to.
- feat: `makeActivationPqNative` and `mintSigningRootAfterActivation`, exported
  from `at_client_mixins.dart` — the two halves of a post-quantum activation,
  for a caller that builds its own onboarding request (`at_onboarding_cli`
  carries retry options, a keyfile path and its own completion step, so it
  cannot just call `pqNativeOnboard`). `pqNativeOnboard` is now those two plus
  the CRAM onboard, so there is one definition of what "PQ-native" means rather
  than two that can drift.
  Stamping is deliberately all-or-nothing: setting `signingAlgoType` alone
  mints an ML-DSA APKAM with **no key package**, and `metadata.keyPackage` is
  written by the `enroll:request` that creates the enrollment record and never
  again — so such an atSign could never be repaired, only abandoned.
- fix: the signing-root and nskey-private filing paths persist through
  `AtKeysIo.update` rather than a hand-rolled `read` → mutate → `flush`. A
  client's start fires the namespace-key seeding and the conveyed-key filing as
  two *unawaited* sibling tasks, each of which read the keyfile, added its own
  material and flushed — so whichever flushed second presented a candidate
  without the first's addition, assurance refused it, and that key material was
  lost. On the file store `update` holds the keyfile lock across the read as
  well as the write, which closes the window for coroutines in one process and
  for separate processes alike.
- feat: `pqNativeOnboard` — CRAM-activate a brand-new atSign post-quantum from
  the start, and get back a manager whose client runs under its first
  enrollment. The greenfield counterpart of `selfRetrofit`: that upgrades an
  atSign that already exists, this starts one in the shape a retrofit would
  have produced, with no legacy generation in between.
  It mints an ML-DSA-65 APKAM (filed as typed material, so the flat keyfile
  fields stay empty and a reader that cannot handle a PQ enrollment fails
  loudly rather than signing with the wrong routine), advertises the first
  enrollment's key package on the `enroll:request` that creates the record —
  the only moment `metadata.keyPackage` can be set, which is why the
  enrollment's KEM is frozen there at whatever
  `AtClientPreference.keyEstablishmentAlgo` says — and immutable-creates the
  atSign's ML-DSA-65 signing root, which a first enrollment is entitled to do
  because the atServer grants it `__manage`.
  Legacy material and `public:publickey` are still cut **by default**: whether
  this atSign will ever talk to a legacy peer is decided by the apps that adopt
  it, which is unknowable at activation. `mintLegacyMaterial: false` is the
  opt-out, and it makes a legacy peer's send unsupported.
  The signing-root step sits inside its own guard. The activation has already
  succeeded by then and the CRAM secret is spent, so failing the whole onboard
  over a step a later mint retries would report a live atSign as unactivated
  with no way to run it again.
- feat: the nskey advertisement names its key-establishment algorithm, and the
  conveyance path follows it. `NskeyAdvertisement` and `ResolvedNskey` carry
  `alg`, the published payload carries `alg`, and `PublishedNskeyKeyRing` mints
  under `AtClientPreference.keyEstablishmentAlgo`. An advertisement without the
  field reads as the hybrid — which is what every one published before this was,
  by construction, since no other KEM existed. One that names an algorithm this
  build cannot encapsulate to is **refused rather than guessed at**: a sender
  cannot tell an X-Wing encapsulation key from an ML-KEM one by looking, and
  getting it wrong produces a conveyance the owner can never open.
- feat: a second conveyance provider id, `at/nskey/MLKEM1024/AES/GCM`, exactly
  as `nskeyCryptoProviderId`'s own documentation anticipated. Both are
  registered on every client regardless of what this atSign mints, because a
  *recipient's* KEM is the recipient's choice; `CkManager` routes a write by
  the destination's advertised algorithm, and every read routes by the id the
  record already carries — so a conveyance written under either KEM keeps
  opening, with no flag day.
- feat: the advertisement also carries a `suites` list — what the owner of that
  generation can **open** — so the conveyance version is negotiated rather than
  fixed. A sender picks the strongest construction both sides handle: a modern
  X-Wing owner now receives `ver 0x02` (RFC 9180) where it received `0x01`, an
  advertisement published before the field existed declares
  `legacyNskeySuites` and keeps receiving `0x01`, and ML-KEM-1024 conveys at
  `0x03`. No shared construction is a refusal rather than a fallback to the
  sender's own preference.
  Without this the version could only ever be raised by a flag day: every
  conveyance already written stays readable, but an owner on a build predating
  the new construction would find new ones unopenable, with nothing having told
  the writer to hold off. It is the same mechanism `KeyPackage.suites` gives
  the secret-sharing envelope, and it is why both paths can move now.
- fix: an nskey private is persisted as its **seed**, with the algorithm
  alongside, and expanded to a decapsulation key on the way out
  (`NskeyKeyRing.privateHalf` now returns what `pqOpen` takes, which is what it
  always meant). Byte-identical for X-Wing; for ML-KEM the decapsulation key is
  expanded and cannot be turned back into a public half, so filing it would
  have left the generation unopenable after a restart. The correspondence check
  on an arriving private re-derives through the advertised KEM rather than
  assuming X-Wing — `NskeyPrivateFiling.publishedPublicKey` becomes
  `publishedGeneration` and hands back the whole advertisement, since a seed
  arrives as bare bytes and 32 or 64 of them are valid for one KEM or the other.
- feat: a client mints and advertises the KEM its deployment configured.
  `KeyPackageRegistration` and `enrollmentKeyPackageBuilder` take the algorithm
  from `AtClientPreference.keyEstablishmentAlgo` (the builder as an explicit
  parameter — it runs before the enrollment exists and has no client), stamp it
  on the advertised key, and let `suites` derive from it. So an atSign set to
  `ml-kem-1024` advertises a 1568-byte ML-KEM key claiming only
  `ml-kem-1024-rfc9180-v1`, and peers seal to it at `ver 0x03`.
  **A key that already exists keeps its own algorithm**, whatever the
  preference later says: the kpid is the address peers seal to and it is frozen
  in an enrollment record that is never rewritten, so re-minting would move the
  client to an address nobody writes to. Changing the preference takes effect
  on the next enrollment.
- fix: the enc keypair is persisted as its **seed** rather than its secret key,
  and the seed now travels with the algorithm that produced it. The two are the
  same 32 bytes for X-Wing — so existing keyfiles are unaffected — but ML-KEM's
  secret key is a 3168-byte expanded decapsulation key that nothing turns back
  into a public half, so storing it would have left the key unrecoverable at
  the next start. 32 and 64 bytes are both valid seeds for *some* backend, so
  the bytes alone cannot say which, hence `PersistedApkamKeys.keyAlgo`
  (`xWingSeed` is renamed `encSeed`, and `xWingPublicKey`/`xWingSeed` on the
  mixin become `encPublicKey`/`encSecretKey` — the latter is now the
  decapsulation key, derived at `register()` time, not the seed).
- fix: the key-package lookups accept any key-establishment algorithm this
  build implements rather than X-Wing alone —
  `keyPackageMaterial` and the enrollment-time symmetric-key resolver. An
  X-Wing-only filter would have made an ML-KEM-minted keyfile invisible, and
  the client would then mint a fresh key and answer at a kpid its enrollment
  never advertised, so nothing addressed to it could arrive.
- feat: a sender follows the recipient's advertised construction instead of
  stamping the only one it knows. `sendEnvelope` takes the KEM from the
  recipient key's `alg`, the suite from the strongest entry both sides list
  (`KeyPackage.bestSuiteFor`, which until now had no production caller), and
  the `pqSeal` version from that suite. The candidate suites are narrowed to
  the chosen key's own KEM first, so a suite can never be picked that the key
  cannot decapsulate.
  **This moves the wire.** Two clients that both advertise RFC 9180 now
  exchange `ver 0x02` envelopes where they exchanged `0x01`. A peer whose key
  package predates the `suites` field still receives `0x01`, because an absent
  field means exactly the one suite that existed when it was written — which
  is what lets the construction change without upgrading every reader first.
  No mutually supported suite is a refusal, not a guess: sealing under this
  client's own preference would hand the recipient an envelope it cannot
  unwrap, and the failure would surface on their side as an opaque AEAD error.
- feat: the receive paths resolve the KEM from the envelope's declared suite
  rather than assuming X-Wing — `pairwise_secret_sharing` and
  `enrollment_symmetric_key`. `pqOpen` reads the version byte itself, but the
  KEM instance is the caller's to supply, and a hybrid envelope decapsulated
  with ML-KEM fails indistinguishably from a tampered one. Resolving the KEM
  also replaces the separate membership test against
  `SecretSharingAlgos.suites`:
  one lookup instead of two lists that have to agree, where a suite in the list
  but absent from the mapping would pass the guard and then have nothing to
  open with.
- feat: `AtClientPreference.keyEstablishmentAlgo` — which key-establishment
  algorithm this atSign **mints and advertises**. Two options, and the choice
  belongs to a deployment rather than to a message: the ML-KEM-768 + X25519
  hybrid (the default), which keeps a classical hedge but has its combiner
  specified only in an IETF draft; or pure ML-KEM-1024, whose specification
  chain contains no draft at all and which is CNSA 2.0's mandated parameter
  set. It does **not** restrict who this client can talk to — a sender always
  follows what the recipient advertised, and every build produces and opens
  both suites — so an atSign configured for ML-KEM-1024 still seals to a
  hybrid peer, because the peer's key is the peer's decision. Configuration
  rather than negotiation because SP 800-227 §4.6.3 names the downgrade
  attacks that per-message choice invites. Changing it re-keys nothing already
  published: an atSign moves options by rotating, which is the only moment an
  advertised algorithm can change.
- feat: `SecretSharingAlgos.kemFor` and `kemForSuite` — the algorithm id a
  record states, resolved to the implementation that realises it. Pure-Dart
  backends specifically, because the FFI ones return an opaque
  process-lifetime handle as an ML-KEM secret key and every key reached
  through here has to survive a restart. Both X-Wing suites map to one KEM:
  they differ in key schedule and AEAD, not in decapsulation. An id this build
  does not implement returns null rather than a default — sealing under a
  guessed KEM produces a record only the recipient ever discovers is broken.
- feat: `SecretSharingAlgos` is exported from the main `at_client.dart` barrel
  as well as `at_client_mixins.dart`. A preference on the main barrel whose
  values could only be named by importing the experimental secret-sharing
  library is a knob most apps would never find.
- feat: `SecretSharingAlgos` names the second key-establishment option
  (`ml-kem-1024`) alongside the hybrid, with a sealing suite for each and the
  mapping between a suite and the `pqSeal` envelope version it produces. The
  KEM fixes the suite — nothing can seal ML-KEM-1024 to a hybrid encapsulation
  key or the reverse — so a recipient's advertised `alg` is what decides the
  construction a sender uses. `keyAlgos` and `suites` become ordered sender
  preferences rather than single entries.
- feat: `KeyPackage.suites` — the sealing suites a package's holder can
  **open**, strongest first, with `bestSuiteFor` for the sender to negotiate
  against. `keys[].alg` says which KEM key to encapsulate to; it never said
  which envelope construction the holder could unwrap, so a sender stamped the
  one suite it knew and a second suite could only arrive by upgrading every
  reader first. A package with no `suites` field means exactly the one suite
  that existed when it was written (`KeyPackage.legacySuites`), which must
  never grow — enrollment key packages are write-once, so that reading is
  permanent for those enrollments. No overlap returns null rather than falling
  back to the sender's own preference, which would hand the holder an envelope
  it cannot unwrap and surface as an opaque AEAD error on the far side.
- fix: a key package's `suites` is derived from the keys it advertises, not
  from the list this build supports. `SecretSharingAlgos.suites` is what this
  client can produce and open *given the right key*; what a package's holder
  can open is fixed by the keys it actually carries. Once that list grew past
  one entry the two stopped meaning the same thing, and a package advertising
  a single X-Wing key began claiming it could unwrap ML-KEM-1024 envelopes —
  which nothing it holds can. Enrollment key packages are write-once, so the
  claim froze into the enrollment record. An X-Wing key now yields both X-Wing
  constructions (same decapsulation; only the key schedule and AEAD differ),
  an ML-KEM-1024 key yields the ML-KEM-1024 one, and a key whose algorithm
  this build does not recognise yields none — a sender acts on the claim, so
  it fails closed rather than open. `SecretSharingAlgos.openableSuitesFor` and
  `openableSuitesForAll` expose the mapping.
- feat: the nskey advertisement payload carries a version field
  (`nskeyAdvertisementVersion`). It and the signed envelope were the only two
  signed structures in the PQ design without one, so a reader had nothing to
  dispatch on if the construction changed. On the read side an advertisement
  payload with no `v` is still accepted as the older shape, because records
  published before this live on peers' atServers until each owner next
  rotates; a version this build has no code for is refused rather than read as
  v1, since a later version's fields might mean something else and sealing to
  a key resolved from a misread payload is not recoverable. The envelope's own
  version ended up inside its protected header instead — see the
  general-serialization entry above.
- **the envelope no longer names a hash at all.** `signEnvelope` loses its
  `hashingAlgo` parameter and `verifyEnvelope` loses the allowlist that
  policed the claim, because `alg` names the hash: `RS256` **is**
  RSASSA-PKCS1-v1_5 with SHA-256, and ML-DSA signs the message directly. The
  allowlist existed because `hashingAlgo` was an envelope member sitting
  outside the signature — an unsigned field naming a cryptographic routine.
  Nothing unsigned selects a routine in this shape, so there is nothing left
  to police rather than a check having been relaxed.
- feat (experimental): **nskey-keypair rotation and the revocation it composes
  with** — the post-compromise-security lever, deliberately not the
  forward-secrecy one. `PublishedNskeyKeyRing.rotate` mints the next
  generation and overwrites the published advertisement; `NskeyRotation`
  (`NskeyRotation.forClient(atClient)`) adds the conveyance, carrying the
  successor private to the namespace's other enrollments and skipping any the
  caller excludes. Every earlier private is retained by construction, so
  retained `__ck` records sealed to a superseded generation still open —
  rotation replaces the key, it does not decrypt or re-encrypt the past.
  Losing the mint lock **fails** a rotation rather than adopting what it
  finds, which is the one difference from the cold-start mint that matters: a
  rotation reporting success without rotating leaves the excluded enrollment
  holding the live generation.
- feat (experimental): `NskeyRotation.revokeEnrollmentAndRotate` — revoke,
  then rotate every namespace the enrollment could read, excluding it. The
  **ordering is the enforcement**: revoking first drops the enrollment out of
  `enroll:listns`, so by the time any rotation runs it is absent from every
  roster and refused at every serve, including pulls answered by holders that
  never heard of the operation. Rotate first and the same enrollment could
  pull the successor from another holder in the gap. Rotation is never
  automatic — store-and-forward cannot tell "no holder exists" from "the
  holder is offline", so a failed pull must not re-mint; recovering a
  namespace whose last private-holder is lost is an explicit rotation, and the
  records sealed to the lost generation stay unreadable.
- feat (experimental): **content-key rotation** — the cheap forward-secrecy
  lever, and the only one that reaches data already written.
  `CkManager.rotateContentKey` cuts a fresh CK and conveys it (O(1): one
  record, unwrapped by every client with the namespace's nskey private).
  `deleteSuperseded: true` then deletes the record carrying the old CK, after
  the successor is durable and never before, so nothing can unwrap it again —
  data written under it becomes undecryptable **by design**. Default off:
  retaining the conveyance is what lets a late-joining enrollment read
  history. A delete that fails is logged at `severe` and does not roll back a
  good rotation, because writes are correct from there on and what was lost is
  the forward secrecy, which the caller has to be told about.
- feat (experimental): a client now **evicts a cached content key when it
  observes that key's conveyance record being deleted** (`ContentKeyEviction`,
  registered on the client's sync service). Deleting the record stops anyone
  unwrapping the CK again but says nothing about clients that already did —
  they hold the plaintext and would go on reading the data the deletion was
  meant to close off. Sync carries the deletion; this turns arrival into
  eviction, which is what makes coarse forward secrecy fleet-wide rather than
  local to the deleting client. It is bounded by eviction *reachability*: a
  device that never resyncs keeps its copy.
- fix (experimental): an envelope whose signer has **no readable `_apsk`** is
  now skipped instead of failing the whole enrollment. The skip caught only
  `AtSigningVerificationException`, but an absent `_apsk` arrives as a thrown
  AT0015 and a malformed one throws out of base64 — so the revoked-enrollment
  case the code documents as its intended skip instead killed
  `waitForApproval`, and one stale envelope from a revoked enrollment could
  fail every later enrollment that scanned past it.
- chore: `SyncServiceImpl.progressListeners()` (`@visibleForTesting`) — the
  SDK now registers a listener of its own, so a bare
  `syncProgressListenerSize()` no longer says anything about which app
  listeners survived an atSign switch.
- feat (experimental): the self-retrofit runs the **signing-root step in
  flow**. A fully privileged retrofit — privilege read off the atServer's
  enrollment record, never the grants the call requested — mints and
  publishes `public:pq_signing_root@<atSign>` when the atSign has none, and
  anchors itself to it. It has to happen here: the retrofit is auto-approved
  by the atServer with no approver client in the loop, so nothing else would
  ever give a retrofitted enrollment a root. A scoped retrofit skips the
  step, and a failure in it does not fail the retrofit.
- fix (experimental): a **holder can now answer** a signing-root or nskey
  pull after a restart. Both are answered out of an in-memory secret store
  that a restart empties, and nothing re-primed it, so the pull broadcast to
  holders none of which could reply. The supply side (`hydrateStore` for the
  root, `hydrateStoreFromFiling` for nskeys) now runs at start — and, the
  second half of the same defect, runs **before** the start-time sweep
  rather than after it: a sweep consumes and deletes the requests it finds
  and answers them from that store, so hydrating afterwards destroyed
  exactly the requests it was meant to serve.
- fix (experimental): **per-enrollment secrets are no longer served on
  namespace authorization alone.** The signing-root private travels under a
  reserved `__en.` name, and the answer path checked only that the requester
  was approved for the namespace — a bar any enrollment clears — so a
  namespace-scoped enrollment could ask for the key that vouches for every
  enrollment on the atSign and be handed it. `PairwiseSecretSharing`
  `perEnrollmentSecretRequestGate` decides instead, failing closed when
  unset; `AtClientSecretSharing` wires the resolver that requires the
  requester's enrollment record to grant `rw` on `*` and `__manage`.
- fix (experimental): a conveyed signing-root private is **verified against
  the published root** before it is filed — it signs a probe the record's
  public half must verify. Previously any bytes were stored, and with the
  record immutable and the root never rotating, wrong bytes stuck for good.
- fix (experimental): a **failed publish of the signing root is no longer read
  as a lost create.** The refusal of a second create and a dropped connection
  on a write that landed throw identically; the catch now reads the record to
  tell them apart, keeps the pair when the published key is its own, and —
  when the record cannot be read at all — keeps the pair and logs at `severe`
  rather than retiring on an unknown outcome. Retiring the private for a root
  this client did publish would leave the atSign with an immutable,
  non-rotating record nobody holds the key to.
- fix (experimental): the signing-root pull works **across app namespaces**.
  The root is atSign-level and carries no namespace, but a holder files it in
  its store under whichever namespace it runs in, and the answer path listed
  the store filtered by the requester's namespace — so two privileged
  enrollments of one atSign in different apps never matched and the request was
  silently never answered. Explicitly named per-enrollment secrets are now
  answerable from any namespace the holder holds them in; a prefix or bare
  request still cannot reach another app's material.
- fix (experimental): every start now **reconciles a held signing-root private
  against the published record** and retires one that corresponds to nothing.
  Such a private is not inert: it satisfies the pull's "already holding it"
  guard so the enrollment never asks, makes `store` drop a correct private
  conveyed to it, gets signed into the chain link, and is offered to other
  enrollments. The reconciliation existed only inside the mint, which runs
  once per keyfile — so the "a later start reconciles it" the logs promise is
  now true.
- fix (experimental): the holder's start-time priming reads the **keyfile**
  rather than asking the atServer which namespaces this enrollment is
  authorised for. That lookup goes through `enrollmentService`, which
  `AtClientManager` wires only after client construction and whose getter
  throws until then — so for every APKAM-enrolled client the priming silently
  did nothing. What a holder can answer with is what it holds.
- fix (experimental): the loser of the signing-root create no longer keeps
  the private it filed before publishing. Left active it satisfied the pull's
  "already holding it" guard forever, so the one heal a loser has could never
  fire; it is now retired (dead, never removed), as is a held private that
  does not correspond to a published root. Both halves of a minted pair are
  filed, so a crash between filing and publishing republishes the held pair
  instead of minting a fresh one over a private nobody could match.
- fix (experimental): `selfRetrofit` carries the session's namespace onto the
  re-authentication, so the switched-to client's start-time self-heal — the
  root pull, the nskey pulls, the store hydration — actually runs. Without
  it a retrofitted client did none of them while looking healthy.
- feat (experimental): the self-retrofit orchestration. `selfRetrofit(...)`
  runs submit → re-authenticate → switch, handing back a manager whose
  current client runs under the new ML-DSA enrollment as a NEW
  `(atSign, enrollmentId)`-keyed instance — the enrollment never changes
  under a live client, so per-client caches cannot go stale (the deferred
  kpid-staleness item, discharged by construction). The client's PKAM signing
  algorithm is resolved from the keyfile's typed material as an explicit init
  step and threaded to every connection the client owns — verb
  (`RemoteSecondary` takes a resolved override instead of clobbering with the
  preference), monitor, and sync — and `wrapAndSign` signs with it, so a
  retrofitted client's envelopes verify against the tagged `_apsk` its record
  published. The algorithm is a fact about the key material, so
  `AtClientPreference.signingAlgoType` is now `@Deprecated`, consulted only
  for a legacy keyfile with no typed signing material; the `AtClient`
  interface deliberately gains no member for it (the published interface has
  none, and adding one would break every external `implements AtClient`) —
  `AtClientImpl.signingAlgoOf(atClient)` answers for interface-typed callers. Key-package
  adoption is enrollment-scoped: on a retrofitted keyfile each principal
  adopts its OWN package (its tagged one first, the untagged pre-id-era one
  as fallback, never a co-tenant's).
- feat (experimental): `signEnvelope` signs ML-DSA-65 when asked
  (`signingAlgo: mldsa65`, key material as base64 of the raw keys), pairing
  the mldsa65 verify branch `verifyEnvelope` already carried; and
  `enrollmentKeyPackageBuilder` gains a `signingAlgo` parameter so a
  self-retrofit's key package is signed by the freshly minted ML-DSA APKAM
  keypair the enrollment will authenticate with.
- feat (experimental): the nskey privates **self-heal** — mint if none exists,
  else pull from any current holder. Before this, the only delivery was the
  mint-time push to whoever held a key package at that instant, so an
  enrollment created after the mint (the ordinary second device) met
  `no nskey private held` with no request, no retry and no recovery. Now: at
  every client start, a client that can file the answer asks the namespace's
  other enrollments for any published generation it lacks, files the answer
  into `AtKeys` the moment it lands, and primes its own in-memory store from
  `AtKeys` so *it* can answer others — the answer path serves from the store,
  which is empty after every restart, so a holder that had restarted answered
  with nothing (found by the live two-enrollment test; no unit fixture could
  see it). A read that misses an own generation fires the same ask, once per
  generation. And approval now conveys the approver's *held* privates read
  from `AtKeys`, not just whatever the transit store happens to hold.
- feat (experimental): the **chain sweep** — a fully privileged client signs
  and conveys approval-chain links for approved enrollments that lack one. A
  scoped enrollment cannot anchor itself and its approver may be a legacy
  enrollment that can sign nothing, so unanchored was a permanent state, not a
  transient. The enrollment stamps the conveyed link onto its own `_apsk` at
  its next start; the sweep is convergent and runs at privileged client start.
- feat (experimental): envelope verification honours the signing algorithm.
  The envelope's `signingAlgo` field was decorative — verify always ran RSA.
  It now branches, with the *published key's own declaration* authoritative
  over the envelope's claim: `_apsk` values parse in both forms — the bare RSA
  string published today (unchanged, and everything 3.x publishes), and the
  tagged self-describing JSON form 4.x enrollments will publish
  (`{"v":1,"signingAlgo":"mldsa65","publicKey":…}`), which is deliberately
  unmistakable to an old bare-RSA parser. A lie about `signingAlgo` fails the
  verify; an algorithm this build has no code for is refused by name.
- feat (experimental): `AtClientPreference.disallowLegacyEncryption` (default
  false; 4.0 flips it). A client that sets it never encrypts **new** data with
  the legacy provider: it takes a post-quantum path or refuses the write, so a
  destination only legacy can reach is refused rather than silently written in a
  scheme that can be harvested now and opened later. Legacy **reads** are always
  available, `shouldEncrypt = false` is unaffected, and public keys are signed
  rather than encrypted and unaffected too. `allowLegacyCryptoFallback` does not
  survive it — the two switches say opposite things and this one wins. Final at
  construction: a flag governing what a client may write must not be flippable
  mid-run. While it is false, every client creation says so at SHOUT.
- fix: `AtClientImpl`'s client cache is keyed by `(atSign, enrollmentId)` rather
  than the atSign alone. A client authenticated as one enrollment is a different
  principal from one authenticated as another, or as the atSign's own keys — a
  different APKAM keypair, different granted namespaces, and the atServer
  answers different verbs for it. Keying on the atSign alone silently handed
  every caller the first client built for that atSign, so two enrollments of one
  atSign could not exist in a process: they were `identical`, and the enrollment
  id never reached the connection because the remote secondary was already set.
  A null enrollment id keeps the bare atSign as the key, so the common case —
  a client using the atSign's own keys — is unchanged.
- feat (experimental): `PqSigningRoot.requestPrivateIfAbsent` asks the atSign's
  other enrollments for the signing-root private, and runs at client start. An
  enrollment that was offline when it was approved had no route to the root at
  all: it is atSign-level and carries no namespace, so it never rides the
  `enroll:listns` fan-out, and it is immutable and never rotates, so nothing can
  mint a replacement. It broadcasts and returns rather than waiting — this runs
  on every launch, and the answer is filed by the arrival path whenever a holder
  comes online. Three guards, cheapest first: already holds it, no enrollment id
  (such a client cannot enumerate holders and would mint rather than ask), not
  fully privileged.
- feat: the SDK now supplies a crypto config when an app names none, and that
  default reads the nskey data path while still writing legacy
  (`CryptoConfig.readsNskeyWritesLegacy`). The asymmetry is the point: a record
  arrives stamped with the provider that wrote it, so a client that cannot
  resolve that id fails on data someone already sent it, whereas writing the new
  scheme is a fleet-wide commitment — read support lands everywhere first, and
  the write default flips once, later. `CryptoConfig.forClient` is
  correspondingly no longer a constant: the nskey providers hold per-atSign
  state, so the set is built once per client at construction and looked up.
  An app that sets `AtClientPreference.crypto` still wins, unchanged. Covered
  cross-atSign: a client that names no config at all opens a record another
  atSign sealed to its namespace key.
- fix: an encrypted notification no longer races the content key it needs. The
  conveyance was written local-first, so it reached the recipient's atServer
  only when the sender's sync got round to it — 31 seconds later in a captured
  reproduction — while the notification went out immediately over the monitor.
  The recipient resolved the key inline on arrival, found nothing, and the
  `ContentKeyUnavailableException` was swallowed at `finer`, dropping the
  notification silently with nothing to retry it. Both notify entry points now
  route the conveyance remote-first, as a `put` already did by passing its own
  routing through: a notification is remote-only by construction, so anything it
  cites must be too.
- fix: a notification a subscriber cannot be given is now logged at `warning`,
  naming the key and the subscriber's regex. At `finer` it was indistinguishable
  from a notification that was never sent — which is how the race above survived
  a green unit suite and a green e2e suite.
- feat: `benchmark/crypto_bench.dart` — the durable perf instrument the PQ work
  is meant to be measured by, rather than reasoned about. Run it with
  `dart run benchmark/crypto_bench.dart [--iterations N] [--json]`. It reports
  three groups on three **different bases** and deliberately does not combine
  them: per record (AES-256-GCM vs the legacy AES-256-CTR path, what every
  put/get pays once a content key exists), per (owner, namespace) conveyance
  (X-Wing `pqSeal`/`pqOpen` vs RSA-2048 wrap — paid once, then covering every
  record in scope), and per authentication (the ML-DSA-65 ↔ RSA-2048 signature
  swap, paid per connection). A single "PQ is N% slower" figure across them
  would be arithmetic on incomparable denominators. Medians and p90s, not
  means, and the harness's own loop overhead is reported rather than silently
  subtracted.
- fix: key material conveyed to an enrollment now reaches its keyfile.
  `collectConveyedKeyMaterial` runs at client start and is what
  `NskeyPrivateFiling` was always missing: its only entry point was a
  `receivedSecrets` subscription nothing subscribed. Two further gaps had to
  close for that to mean anything, since either alone leaves the fix inert.
  `bindKeyPackageToAtKeys` backs the registration mixin's enc keypair with
  `AtKeys`, so a running client's `kpid` is the one its enrollment advertised
  rather than a fresh keypair per process — a client whose address moves listens
  where nobody writes. And the collection sweeps before it files, because the
  `SecretStore` is in memory and the sweep is its only populator, so a client
  that never swept read an empty store however much had been conveyed to it.
  Adoption only — a keyfile holding no package is left untouched, since a
  package is discovered from the enrollment record and one generated locally
  would be an address nobody can learn. This also repairs
  `PqSigningRoot.filePendingPrivate`,
  which read the same empty store. `NskeyPrivateFiling.start`/`stop` are
  replaced by `filePending`, matching the store-check shape the signing root
  already used — no lifecycle to own, and no stream that has to still be
  listening at the right moment.
- feat: `PqSigningChain.verifyChain` walks the approval chain upward and reports
  how far it holds, as a `ChainResult` carrying a `ChainVerdict` and the path it
  walked. `anchored` reached a root link verified against the atSign's signing
  root; `chained` verified every hop but ran out below the root; `unsigned` found
  no link at all — the ordinary state during the changeover. A fourth,
  `broken`, is deliberately **not** folded into `chained`: an absent link means
  nobody has vouched yet, a bad one means something claimed to and the claim does
  not hold, and reporting the second as the first would hide it. Every hop checks
  three things, since a signature alone proves only that the parent said
  something: that the link verifies against the enrollment it names as signer,
  that it vouches for the enrollment it is attached to, and that it covers the
  key actually published for it. Cycles and over-long chains end the walk as
  `broken` rather than being treated as impossible — the chain is assembled from
  records a compromised enrollment partly controls.
- feat: a fully privileged enrollment anchors itself to the signing root.
  `PqSigningChain.publishOwnRootLink` signs its own `_apsk` with the held root
  private and stamps the result under `apskRootLink` — its own field, because a
  root link is ML-DSA-65 verified against `public:pq_signing_root@<atSign>`
  where every other link is RSA verified against an `_apsk`, so the field name
  settles which of the two a verifier holds before it reads anything. Self-signed
  rather than conveyed: the signer is always the record's own writer here, which
  is exactly what a chain link can never be. It runs at mint and at every start,
  and that single rule covers the minter, a privileged peer predating the root,
  one approved afterwards, one approved by a non-root-holding approver, and a
  root minted late — the retro case needs no migration because it is not a
  special case. Possession of the private is checked before privilege, since the
  first is a local read and the second a round trip; holding the private is not
  sufficient, because only the granted namespaces decide the class. Both link
  kinds coexist on one record.
- feat: the signing root's private half reaches the enrollments entitled to it.
  A **fully privileged** enrollment (`rw` on both `*` and `__manage`) is
  conveyed the root private when it is approved, so it can anchor its own key
  rather than waiting to be vouched for; a namespace-scoped one never is, since
  the root vouches for every enrollment on the atSign. It travels under a
  per-enrollment name so `shareAllSecretsWith` cannot forward it onward — the
  case that would otherwise hand it to whichever enrollment happened to share
  the envelope's namespace. `PqSigningRoot.filePendingPrivate` moves an arrived
  private out of the secret store and into `AtKeys` at client start: the store
  is an in-memory transit buffer, and a root that only ever lived there would be
  lost on restart with no way back, the record being immutable and non-rotating.
- feat: `PqSigningChain` — the approval chain's link. The enrollment that
  approves a device signs that device's APKAM public key, so a verifier can
  walk upward from any key toward the atSign's signing root without an approval
  graph being published anywhere: the link is an ordinary APKAM-signed envelope,
  which already names its signer and is already verified against that signer's
  published `_apsk`, so a forged parent claim fails against the parent it names.
  **The parent signs and the child publishes**, because `_apsk` accepts writes
  only from its own enrollment's connection — the approver conveys the link over
  the substrate at approval and the child stamps it onto its own record's
  `appMetadata` on first run. Until it does, verifiers see a bare key, which the
  transition rule already tolerates. Signing is best-effort: an approval that has
  already happened is never failed over an additive field.
  The child half runs at client start via `PqSigningChain.publishPendingLink`,
  and needs no preference to gate it because it is self-gating: an enrollment
  nobody vouched for has no link waiting and writes nothing, so a client that
  will never have one pays an in-memory lookup and no atServer traffic. It
  refuses to publish a link that names a different enrollment, one whose
  signature does not verify against the parent it names, or one vouching for a
  key other than the one actually published — this record is the enrollment's
  advertised identity, and a bad link on it is worse than no link. Idempotent,
  so restarts do not rewrite it. A link arriving after start is published at
  the next one.
- fix: a secret conveyed to one enrollment is no longer forwarded to the next
  one that enrollment approves. Received secrets are stored like any other —
  `SecretStore.putIfNewer` accepts reserved names deliberately, so that system
  secrets such as namespace rotation keys reach a newly approved device — and
  `shareAllSecretsWith` iterates that same store. So an enrollment holding its
  own conveyed `apkamSymmetricKey` would have handed it on. Secrets carrying the
  new `PairwiseSecretSharing.perEnrollmentSecretPrefix` (`__en.`) are addressed
  to exactly one enrollment and are never forwarded, while the rest of the
  reserved `__` space keeps flowing as before.
- feat: enrollment approval can convey the `apkamSymmetricKey` in the
  post-quantum direction, removing the last RSA wrap from the enrollment path.
  `EnrollmentServiceImpl.approve` now reads the pending record **before**
  approving: an enrollment that sent no wrapped key is one whose enrollee
  expects the approver to mint it, and that absence is the only signal — an
  advertised key package is *not*, since every mode carries one for ordinary
  secret conveyance. When it applies, the approver generates the symmetric key,
  approves with it, and seals it to the enrollee's key package over the
  secret-sharing substrate, ahead of the enrollment's other secrets because
  nothing else is usable until it lands.
- feat: `enrollmentApkamSymmetricKeyResolver` — the enrollee half, for
  `AtEnrollmentRequest.apkamSymmetricKeyResolver` (at_auth 3.4.0). Built on
  `AtLookUp` rather than an `AtClient`, because at that point in enrollment
  there is no client and cannot be one: a client is constructed *from* the keys
  this is fetching the last piece of. Polls for the envelope addressed to this
  enrollment's key package, verifies its APKAM signature against the signing
  enrollment's published `_apsk`, and opens it with the key package's private
  half. A revoked signer needs no special case — the atServer has moved its
  `_apsk` out from under the address, so verification fails of its own accord.
- feat: `PairwiseSecretSharing.sealInfo` is public, so the same
  domain-separation context binds envelopes opened outside an `AtClient`.
- build: the `at_auth` floor rises to `^3.4.0` — the version that introduces
  `EnrollmentRequestDecision.approvedWithMintedKey` and the request-side
  conveyance seams this release first uses.
- feat: `PqSigningRoot` mints this atSign's user-owned root of trust,
  `public:pq_signing_root@<atSign>` — ML-DSA-65, a signer only, with nothing
  ever encapsulated to it. Written **immutable**, so the atServer refuses a
  second create and exactly one root is ever published; that matters more here
  than anywhere else, because the root never rotates and two roots would leave
  half an atSign's enrollments chaining to one the other half rejects, with no
  later event able to reconcile them. Only a fully privileged (`rw *` plus
  `__manage`) enrollment mints it. The private is filed before the record is
  published — an immutable record cannot be retried with a different key — and
  losing the create is not an error but the guarantee working.
- feat: `AtClientPreference.seedNamespaceKeys` (default **false**) makes a
  client mint and publish its namespace keys at start. It is its own knob
  rather than following `crypto` because seeding is a rollout action, not a
  crypto-path one: the release sequence has clients minting while still
  writing legacy, so gating it on the PQ path being active would seed nothing
  until the moment seeding stopped being useful. Off by default because
  minting publishes a permanent, discoverable record on the atSign. The work
  is not awaited — a client's startup must not wait on, or fail because of, a
  rollout action, and a namespace missed now is minted at the next start.
- feat: `NskeySeeding` mints and publishes this atSign's namespace keys and
  conveys each private to its other enrollments. It seeds at client start
  rather than on first write, because the rollout mints while clients are
  still writing legacy — minting on first write would seed only as traffic
  happened, leaving early senders cold-starting against recipients who simply
  had not written yet. A legacy client seeds the one namespace it can name
  (`preference.namespace`); those clients are most of the fleet during the
  rollout. A `*` enrollment seeds nothing at start, since "every namespace" is
  not a list that can be minted, and mints on demand instead. Conveyance sends
  **every** generation a client holds, not just the current one: data written
  under a superseded key is opened only by the private it was sealed under.
  Reads come from `AtKeys` rather than the secret store, which is in-memory by
  design — an approver relying on it would convey a newly approved enrollment
  nothing at all after a restart. Not yet called at startup.
- feat: an arriving nskey private is checked against the published public half
  before it is filed. An X-Wing secret key **is** its seed, so the public
  derives from it exactly — the check is precise, not heuristic. It is
  subordinate to the signature that already authenticated the envelope, and
  catches what a signature cannot: a private genuinely from this atSign and
  genuinely an nskey private, but the wrong one — a stale generation, or a
  truncation. Filing that would leave the client believing it can open a
  namespace it cannot, with the failure surfacing later on data as corruption
  rather than as a bad key. With no lookup supplied, or one that throws, the
  private is filed on the signature alone rather than refused.
- feat: minting a namespace key takes a lock and makes its private durable
  before publishing. `NskeyMintLock` is a short-ttl immutable self key taken
  **remote-first** — the atomicity is the atServer refusing a second immutable
  create, so a local-first put would let two of an atSign's enrollments each
  believe they had won and collide only at sync. The loser does not wait: it
  re-reads and adopts the winner's advertisement, because minting a second key
  would rotate the first out from under every peer that had already fetched it.
  The private is filed into `AtKeys` first, and a mint that cannot store it
  **publishes nothing** — the advertisement is the promise that a private
  exists, and rotation replaces a key rather than decrypting what was written
  while none existed. `privateHalf` reads the durable copy, so a restart
  recovers rather than losing the namespace.
- feat: `NskeyPrivateFiling` moves an arriving nskey private out of the
  secret-sharing transit buffer and into `AtKeys`, keyed by namespace **and**
  kid — kids are truncated hashes and are not unique across namespaces. Losing
  an nskey private is unrecoverable: every conveyance record sealed to it
  becomes unopenable, and with it every value those content keys protect. That
  is what separates it from a content key, which is only ever a cache. It has
  no producer until nskey minting conveys one; the `Secret` name it consumes is
  `__nskey.<nskeyKid>` in the key's own namespace.
- fix: a restart no longer cuts a fresh content key for every destination. The
  sender records which `ckKid` is current per `(recipient, namespace)` — the id
  only, never key material, so it needs no protection at rest — and a cold
  write recovers that CK from its own conveyance record instead of minting.
  Previously each restart left one more permanent `<ckKid>.__ck.<ns>@<owner>`
  record, each protecting only the values written between two restarts, and
  none of them ever removable because old data still needs them. The pointer is
  an ordinary self key, so an atSign's devices converge on one CK per
  destination rather than one each.
- fix: `SecretStore` serialises its calls into `SecretStorePersistence.save`.
  Every mutation persists the whole list and the save is async, so two
  concurrent puts could each snapshot and then land in either order — leaving
  an older snapshot on top of a newer one and silently dropping a secret the
  store still believed it held. An in-memory backend never shows this; any real
  async one would. The seam's dartdoc now also states that the SDK ships no
  implementation on purpose: key material that must survive a restart is filed
  into `AtKeys`, so an app-supplied backend never holds this atSign's private
  keys.
- feat: pull requests are answered after a random wait
  (`PairwiseSecretSharing.requestAnswerJitter`, default 2s, `Duration.zero` to
  disable), and a responder stays quiet if an answer is already waiting for the
  requester. Every authorised holder sees the same request, so previously N
  holders meant N seals and N writes for a secret the requester needs once;
  `requestAnswerMinInterval` did not help, being per responder. Suppression is
  deliberately coarse — the envelope names no secret and its payload is sealed
  to the requester — which is sound because a responder answers every matching
  secret in one pass, so any single answer is already complete.
- feat: approving an enrollment now shares this atSign's secrets with it.
  `EnrollmentServiceImpl.approve` seals every secret the new enrollment's
  namespaces authorise to the key package it advertised on its
  `enroll:request`, so an approved device can read what it was just authorised
  for. It runs after the approval, because the atServer publishes the
  enrollment's `_apsk` at that point and the package cannot be verified before
  it exists. A package that was advertised and **refused** throws — the
  approver should learn it has approved a device that can decrypt nothing, and
  can revoke; one that was never advertised, or that this version cannot read,
  is left alone. `Enrollment.metadata` carries the advertised package, which
  the read path previously discarded.
- **behaviour change**: `at_client_flutter` and `at_onboarding_cli` now approve
  through at_client's `EnrollmentService` rather than calling at_auth directly.
  Approving is also when secrets are conveyed, so the direct calls would have
  produced enrollments that authenticate normally and decrypt nothing, with
  nothing in the code saying so.
- feat: `NamespaceMember.keyPackageStatus` says **why** a member has no usable
  key package — `present` / `absent` / `rejected` / `unsupported`. A null
  `keyPackage` alone could not be acted on, because these call for opposite
  responses: `absent` is ordinary (an older client, or the self-retrofit path,
  which needs no conveyance), `rejected` is the one case a caller must refuse
  rather than skip (not a map, signed by a different enrollment, or a signature
  that fails against `_apsk`), and `unsupported` — signed and genuinely that
  enrollment's, but shaped in a way this version cannot read — behaves like
  `absent`, because it means the other end is running a newer client and
  refusing would block work nobody here can fix.
- **behaviour change**: a key package that carries **no** `enrollmentId` claim
  now verifies, against the `_apsk` of the enrollment whose record it appears
  on. A package riding `enroll:request` is signed before the atServer has
  assigned an id, so there is nothing truthful to stamp; rejecting it would
  refuse every such package. A claim that is present but disagrees with the
  record stays a hard rejection. `verifyEnvelopeSignature` gained
  `signerEnrollmentId` for callers that already know whose envelope it is.
- feat: `enrollmentKeyPackageBuilder(atSign)` builds the signed X-Wing key
  package that rides an `enroll:request` — pass it to at_auth's
  `AtEnrollmentRequest.metadataBuilder`. It runs at the only moment this is
  possible: the APKAM keypair exists and the enrollment record does not, so it
  is the sole opportunity to put anything on that record (metadata is written
  by the request that creates it and never afterwards). The X-Wing private half
  is recorded as typed material on the very `AtKeys` at_auth flushes into the
  app's keyfile on approval, so it lands beside the APKAM key — publishing an
  encapsulation target whose private half nobody kept would leave every sender
  sealing to a key that can never be opened. The envelope carries **no**
  `enrollmentId` claim, because the atServer has not assigned one yet and the
  payload never carried it anyway; a verifier's authority is the signature
  checking out against that record's own `_apsk`. `KeyPackage.payloadFor(...)`
  exposes the same payload `toJson()` produces, for a package whose enrollment
  does not exist yet.
- refactor: envelope signing and verification are now functions taking the key
  material as an argument (`signEnvelope` / `verifyEnvelope`), instead of
  reaching through a client's `AtChops` object. Key state belongs in `AtKeys`,
  held by an `AtKeysIo`; `AtChops` is a collection of stateless operations over
  material handed in per call. The at_chops surface this uses —
  `RsaSigningAlgo` and `RsaKeyPair` — is the one its own deprecations on
  `PkamSigningAlgo` and `AtPkamKeyPair` point at. Verification needs no keypair
  at all: the signer's public key is the whole input, so it works on a client
  holding no keys. `ApkamSigning` exposes the material as `signingKeys` and no
  longer publishes `privateSigningKey`, which had no callers. Behaviour is
  unchanged — the envelope bytes, algorithms and failure modes are identical.
- feat: `PairwiseSecretSharing.clientRunsSync` (default true) decides where
  `startListening`'s initial and periodic sweeps read from. Envelopes reach the
  local store only via sync, so on a client that does not sync those sweeps were
  reading a store that could never contain anything — leaving the wake-up
  notification as its only automatic path to an envelope, and a wake-up missed
  past its expiry stranding a message that was still sitting readable on the
  atServer for the rest of its ttl. Set it false and the sweeps read the
  atServer, which is the lazy-fetch path for those clients. Left true, behaviour
  is unchanged: sync already delivers envelopes locally, so remote sweeps would
  be traffic for nothing.
- fix: the secret-sharing substrate writes its `__ssenv` envelope to the
  atServer directly rather than local-first. The wake-up notification that
  follows the put is a direct remote call, so a local-first envelope was still
  waiting for a sync cycle when a sync-less recipient — the only kind the
  wake-up exists to serve — woke and swept the atServer for it. The sweep found
  nothing, and the wake-up is one-shot, so that client fell back to the pull
  path and the notification bought it nothing. Writing remote-first orders the
  two by construction. An offline sender now fails this write instead of
  queueing it; delivery remains offline-tolerant for the recipient, and
  `requestSecret` is still the backstop. The unit fixture backs local and
  remote storage with one map and so cannot see this class of defect on the
  read side, so the write's routing is now asserted directly.
- fix: `PublishedNskeyKeyRing` no longer reports its own atSign's published
  namespace as cold start. It short-circuited to an in-memory map that only
  `mintAndPublish` populates, so another enrollment — or the same one after a
  restart — saw nothing while the advertisement sat on the owner's atServer, and
  a client that "fixed" that by minting would have rotated the key out from
  under every peer that had already fetched it. The owner's own advertisement is
  now served by the same lookup a peer uses, **signature check included**, which
  is what makes the design's "one verify path, same-atSign and cross-atSign"
  true rather than aspirational. What this client minted itself still costs no
  lookup.
- **breaking**: the nskey data path resolves a nested namespace by walking up,
  and its records now state their namespaces. A sender writing to
  `someid.d.c.b.a@alice` tries `d.c.b.a`, `c.b.a`, `b.a`, `a` and seals to the
  first published nskey; the content key and its conveyance live at *that*
  namespace, so one `<ckKid>.__ck.<ckNs>@<owner>` record serves everything
  beneath it. This is required rather than an optimisation: `AtCollection`
  composes sub-collection namespaces with a per-**item** id, so an exact-match
  rule would need a keypair and a per-enrollment conveyance per item. Walking up
  cannot cross an authorisation boundary, because it goes the same direction as
  the atServer's own suffix rule.
  - `appMetadata` gains **`ns`** on every record of this path — the record's own
    namespace — because `AtKey.fromString` splits at the last dot and a
    multi-segment namespace cannot be recovered from the wire string at all. A
    data value additionally carries **`ckNs`**, the namespace its content key
    lives at. Neither is derivable from the other.
  - The AAD now binds the record's full address rather than namespace and key as
    two fields, so it no longer depends on where that split fell.
  - Values and conveyances written by an earlier build of this unreleased path do
    not decrypt under it.
- feat: an advertised key package is APKAM-signed, and verified before anything
  is sealed to it. `KeyPackageRegistration.signedKeyPackagePayload()` produces
  the value to store at `metadata.keyPackage`, and `VerbEnrollmentDirectory`
  checks it against the advertising enrollment's `_apsk` — rejecting an
  unsigned package, a tampered one, one signed by a different enrollment, and
  one that merely *claims* to be the advertising enrollment's. A key package is
  an encapsulation target: whoever's X-Wing key ends up in one is who this
  atSign's other clients seal their secrets to, so accepting it on the server's
  word alone would let whoever served the enrollment record choose who can read
  the atSign's secrets. A rejection drops that member alone rather than failing
  the whole listing — the member is then never sealed to, and one bad record
  cannot deny every other enrollment its secrets. **The stored value's shape
  changes**: `metadata.keyPackage` now holds the signed envelope, with the
  package as its `payload`.
- feat: cold start on the nskey path now fails by name and can be asked about
  in advance. A destination that has never used or authorised a namespace has
  no key to seal a content key to, and there is no post-quantum fallback — the
  only atSign-level key is a signing root, which cannot receive an
  encapsulation. Three parts:
  - `NamespaceKeyUnavailableException` carries the `atSign` and `namespace`, so
    an app can say "@bob hasn't enabled this yet" instead of surfacing an
    encryption error for a case where nothing went wrong.
  - `CryptoRuntime.isReadyFor(atSign, namespace)` answers the same question
    before a user composes anything, via the new `ReportsReadiness` provider
    seam. Schemes with no such precondition — legacy among them — answer true.
  - `AtClientPreference.allowLegacyCryptoFallback` (default **false**) lets a
    write fall back to legacy rather than fail. It is off by default because a
    silent downgrade to RSA is what this work exists to prevent, and it is
    forward-only: the check runs per write, so the first write after the
    destination publishes a key is post-quantum again, with no flag to flip.
    Records already written under the fallback stay legacy.
- `AtClientPreference.crypto` now defaults to `const CryptoConfig.eraDefault()`,
  a distinguished marker meaning "whatever this SDK release encrypts with by
  default". The field keeps its published non-nullable type. Almost every app
  should leave it alone: the default is the SDK's to move as the post-quantum
  migration proceeds, and an app that named `CryptoConfig.legacy()` only
  because the field demanded a value would find itself pinned to the old
  scheme after the release that changed it. Assign a config only to register a
  custom provider or to hold a scheme deliberately — assigning
  `CryptoConfig.legacy()` is now an explicit opt-out, distinct from the
  default. Reading the field back no longer answers "what will this client
  encrypt with" — `CryptoConfig.forClient(atClient)` does, and is the single
  place the era default lives. The SDK does not write its resolution into the
  app's preference object; read as a config, the marker behaves exactly like
  `CryptoConfig.legacy()`, which is the value the field's default held in
  3.14.0.
- fix: the notify request path copies metadata through `Metadata.copy()`
  (at_commons 5.14.0) instead of a hand-rolled field list, then clears the few
  fields a sender has no business asserting — the atServer-derived timestamps,
  `sharedKeyStatus`, and the local read-model flags. The polarity is the point:
  a field added to `Metadata` later now travels by default rather than being
  dropped until somebody notices, which is how `immutable` and `appMetadata`
  went missing here. The bytes on the wire are unchanged.
- feat: a published nskey advertisement is APKAM-signed, and a sender verifies
  it before sealing anything to it. `PublishedNskeyKeyRing` wraps what it
  publishes with `wrapAndSign`; `ApkamSignedAdvertisedKeys` — now the default
  verifier — fetches the signing enrollment's `_apsk` from the owner's atServer
  and checks the signature, rejecting an unsigned, tampered or wrong-signer
  advertisement, and rejecting a `nskeyKid` that is not the digest of the key it
  names. The advertised key is what an attacker most wants to substitute: a
  sender never sees a recipient's decapsulation fail, so sealing a content key
  to the wrong nskey would go unnoticed indefinitely. This replaces the
  placeholder that accepted advertisements unverified. **The published value's
  shape changes** — advertisements written by an earlier build of this
  unreleased path are rejected, and must be re-minted.
- feat: `AtClientEnvelopeSigner` composes `ApkamSigning` + `EnvelopeSigning` on
  their own, so signing or verifying an advertised key no longer means
  constructing a whole secret-sharing instance with its own X-Wing keypair,
  secret store and envelope listener.
- fix: `at/symmetric/AES/GCM` binds a value's ciphertext to the record it was
  written under, as AES-GCM additional authenticated data over
  `providerId:sharedBy:sharedWith:<full at-key name>`. A content key covers every
  record in its `(owner, namespace)` scope, so without this a valid ciphertext
  could be moved between records in that scope by anyone able to write the
  store and would still authenticate — the AEAD tag proves the key, not the
  address. The HPKE `info` binding on the conveyance layer does not reach
  values. Values written by an earlier build of this unreleased path do not
  decrypt under it.
- fix: a failed advertisement re-fetch no longer serves the cached nskey
  generation forever. `PublishedNskeyKeyRing` gains `advertisementStaleGrace`
  (15 minutes by default): inside it, a blip does not cost a working key; past
  it, the ring answers with nothing and the write fails rather than sealing to a
  generation the recipient may have rotated away from. Re-fetching is the only
  way a sender learns of a rotation, so failing open here made the stated "one
  TTL plus one content key" exposure unbounded — in exactly the case that
  matters, since a peer that rotated because of a revocation is the peer a
  sender most needs to stop sealing to.
- fix: a content key is made *current* only once its conveyance record is
  durable. It was promoted inside `encrypt`, which runs in the put transformer
  with the write still to come — so a failed conveyance write left a current CK
  whose record did not exist, `CkManager.ensureCurrent`'s already-current guard
  then skipped conveying on every retry, and every value written afterwards
  cited a key nobody was ever sent.
- fix: the notify path resolves the key's namespace *before* selecting a crypto
  provider. Selection is namespace-sensitive — the nskey path declines a key
  without one — so a key relying on the preference default silently fell back to
  legacy, while `put` on the identical key used `nskey`. A received
  notification's `AtKey` now also carries its namespace, without which the nskey
  providers refuse the value outright.
- fix: a content-key conveyance follows the routing of the write it serves.
  `PreparesWrites.prepareForWrite` takes `useRemoteAtServer`, so a value written
  remote-only can no longer cite a conveyance that exists only on the device.
- fix: a conveyance record that is present but will not open — a failed AEAD, a
  malformed envelope, a `ckKid` collision — is reported as the integrity failure
  it is. A bare `catch` folded all of them into `ContentKeyUnavailableException`,
  whose documented contract tells the caller to retry later.
- fix: the nskey types are exported from the package barrel. `CryptoConfig.nskey`
  takes a **required** `NskeyKeyRing`, and this entry tells callers to catch
  `ContentKeyUnavailableException` — none of which could be named through
  `package:at_client/at_client.dart`.
- fix: the notify request builder carries `isBinary`, `immutable`, `encoding` and
  `dataSignature`. It copies metadata field by field, and those four were
  missing — a provider chooses its wire format from `isBinary`, so losing it made
  a binary notification decode as text. The server-derived timestamps and
  `sharedKeyStatus` stay out by design, as the sync push leaves them out.
- fix: sweep the remaining hand-rolled metadata deserializers, the same defect
  class as the sync-push drop below. `AtClientUtil.prepareMetadata` — behind
  every remote get/lookup — and the sync **pull** both dropped `immutable`, so
  it read back as a constant false for any record fetched from an atServer; and
  `AtNotification.fromJson` dropped `isBinary`. `metadata_converter_sweep_test`
  pins the `Metadata` field inventory, so a field added upstream now fails a
  test rather than being silently absent on one side.
- feat: `nskey` data path providers — `at/symmetric/AES/GCM` encrypts
  application data with AES-256-GCM under a symmetric content key (CK), and
  `at/nskey` conveys that CK by X-Wing-sealing it to the namespace's `nskey`
  and writing it as a discrete `<ckKid>.__ck` record. Data values cite the CK
  by `ckKid` and carry no sealed key inline; the CK cache is keyed
  `(owner, namespace, ckKid)`, and only the client that cut a CK makes it the
  key new writes use. Binary values honour `isBinary` and round-trip byte-exact.
  A cited CK that has not arrived yet raises `ContentKeyUnavailableException`,
  which a caller can distinguish from a hard decryption failure and retry.
  `NskeyKeyRing` is the seam the secret-sharing substrate lands behind — an
  experimental surface, not yet routed by `CryptoRuntime` (#2089, #2090).
- feat: crypto agility on both layers. A `providerId` now names the role and then
  every algorithm a reader needs code for, so the CK-conveyance provider is
  `at/nskey/XWING/AES/GCM` rather than the bare `at/nskey` (`at/nskey` remains the
  family prefix). Reads stay universal; what the id adds is that a writer can decide
  whether a recipient can read a scheme, which makes an algorithm change rollable.
- feat: `nskey` generations. `public:__nskey.<ns>@<owner>` is published at mint and
  overwritten on rotation, so a client holds several nskey privates at once; every
  `at/nskey` conveyance names the one it was sealed to in `appMetadata.nskeyKid`.
  `NskeyKeyRing` becomes `currentPublic(owner, ns)` + `privateHalf(owner, ns,
  nskeyKid)`.
- fix: the record owner and the nskey owner are different atSigns on any inbound
  record. `sharedBy` binds the HPKE `info`; `sharedWith ?? sharedBy` selects the
  key and scopes the CK cache. Selecting by `sharedBy` made a recipient look up
  the *sender's* namespace private, so cross-atSign reads could not work.
- fix: the sync push dropped `appMetadata` and `immutable`. `SyncServiceImpl`
  built the `update:` command with its own hand-rolled metadata serializer,
  which had fallen behind `Metadata.toAtProtocolFragment`; a synced record
  therefore reached the atServer with no `appMetadata`, so a cross-atSign
  `lookup` returned no `providerId` and the reader fell back to `legacy` and
  hunted a `shared_key` the write never created. This affected **every**
  provider's synced writes, not only the new ones. The duplicate is deleted —
  the push now delegates to the one canonical serializer.
- build: raise the `at_chops` floor to `^3.4.0` — the nskey providers name
  `AtKemAlgorithm` through the `at_chops` barrel, which only exports the
  algorithm interfaces from 3.4.0.
- fix: `AtCollection` — resolve received (shared-in) items in the id-scoped
  read path. `Query.watch()` (delta path), `getOrNull` / `get(id, owner)` and
  `exists(id, owner)` missed items stored locally as
  `cached:@<self>:<id>.<ns>@<owner>` because the scan regex allowed only one
  key-wrapper segment; it now allows the two a received copy carries (#2032).
- fix: `AtCollection` — end-anchor owner-scoped scans and deletes so a concrete
  owner (`@bob`) can't prefix-match a longer atSign (`@bobby`), which could
  return another atSign's items or delete a same-id received copy.
- fix: `AtCollection.cleanupOrphans()` no longer deletes a live self-owned item
  under a received parent when offline — the ancestor presence check reads the
  local cached copy instead of routing to a remote lookup.
- fix: `AtCollection` rejects a top-level item id containing `.` at write time
  (it was stored intact but read back truncated at the first dot).
- fix: `AtCollection` — a reader's own `markReadByMe` no longer emits a spurious
  self `CReadReceipt` on the data-event path.
- fix: `AtCollection.availableEvents` now fires `CItemAvailable` for an item
  whose `availableAt` is still in the future when its create/update event
  arrives (the scheduler read filtered them out, and the value-less placeholder
  crashed for a non-nullable item type).
- fix: `AtCollection` reads no longer duplicate the preceding item when a key
  expires or is deleted between the scan and its per-key read.

## 3.14.0
- feat (experimental): per-APKAM same-atSign secret-sharing substrate —
  `AtClientSecretSharing` / `PairwiseSecretSharing` (mixins `KeyPackageRegistration`,
  `EnvelopeSigning`), `SecretStore`, `KeyPackage`, `SecretEnvelope`, and the
  `EnrollmentDirectory` seam. Secrets travel in X-Wing-sealed (`pqSeal`),
  APKAM-signed `__ssenv` envelopes addressed by `kpid`; key packages are
  enrollment-internal (conveyed via `enroll:request`, discovered via the gated
  `enroll:listns` verb) and never published. The whole surface is
  `@experimental` — the wire shape is subject to change pending the atServer
  verb work — and requires `at_chops ^3.3.0` (`pqSeal`/`pqOpen`).

## 3.13.0
- feat: add `AtClientPreference.networkTimeout` — when set on the preference used
  to create an `AtClient`, it becomes the process-wide network-timeout default
  (`AtNetworkTimeouts.defaultTimeout`, capped at 60s), bounding every atServer
  connect / atDirectory lookup / operation so a dead network can't hang the SDK.
  Supersedes the misnamed `outboundConnectionTimeout` (a socket idle time).
  Requires `at_commons ^5.13.0` (#1923).
- chore(deps): `at_lookup: ^3.6.0`, `at_auth: ^3.2.0` — the bounded socket
  connects and the deadline-driven `validateAtServer` live in those versions;
  with older ones resolved, `networkTimeout` would set a policy nothing reads.
- refactor: migrate the local keystore to `at_persistence_secondary_server`
  5.0.0 — the client is now commit-log-free. The client no longer maintains a
  local commit log or runs commit-log compaction; sync tracks its progress
  with a persisted pull cursor, and key-expiry processing is driven by the
  keystore's `nextExpiresAt` / `peekNewlyAvailable` surface. Requires
  `at_persistence_secondary_server ^5.0.0`.
- deprecated: `AtClient.startCompactionJob` and `AtClient.stopCompactionJob`
  are retained for source compatibility but are now no-ops (a commit-log-free
  client has no commit log to compact); they will be removed in a future
  major release.
- deprecated: `FileTransferService` and `FileTransferObject` are now marked
  `@Deprecated`. The SDK file-sharing API (`uploadFile` / `downloadFile` /
  `shareFiles` / `reuploadFiles`) has moved to the app layer and will be
  removed, along with the `archive` dependency, in the next major version
  (#1113).
- chore(deps): remove the unused `cron` dependency — it was only used by the
  commit-log compaction that the `at_persistence_secondary_server` 5.0.0
  migration removed, and nothing in the client imports it (#1378). `uuid` is
  already on `^4.0.0`.

## 3.12.0

Several significant enhancements to the API to make it much easier to use.
- feat: New feature - Collections - a clean API for storing, sharing, 
  unsharing and deleting objects in named collections, with sub-collections, 
  event streams, built-in support for read receipts, live queries with 
  incremental delta maintenance, and more. For detail, see the READMEs, 
  dartdocs and examples
- feat: added a new method, `send`, to NotificationService which is much 
  easier to use than the old (still fine to use) `notify` method.
- feat: added `factory AtRpc.server` to make it much simpler to create AtRpc 
  servers. 
- feat: added preference-time crypto provider configuration via
  `AtClientPreference.crypto`, `CryptoConfig`, and
  `CryptoProvider`.
- feat: added `CryptoStorage` to provider context for provider-owned local /
  remote state, plus `CryptoPolicy.onProviderNotFound` for lazy
  provider registration with a single retry.
- fix(AtCollection): notification-path sub-item dispatch now recovers
  ancestor owners directly from the decrypted notification payload
  (which IS the envelope) instead of round-tripping through the local
  keystore. Eliminates a class of null-owner `CSubItemUpdated` events
  that surfaced under `EventSource.notifs` (and `EventSource.both`)
  when the keystore mirror landed under a key shape the readback
  couldn't resolve, or raced ahead of sync writing the bare key.

Major documentation uplift
- docs: Rewrote the main README
- docs: Added many examples in the [example](example/README.md) directory

And some tech debt cleanup
- feat: explicit AtClient lifecycle control — cleanly stop and resume atClients without
  re-initialising storage or keys
- feat: outgoing AtClient's sync and notification services will now be garbage collected
- chore: deprecated `atClientManager` param in the factories of AtClient, NotificationService, and SyncService
- fix: added null guards to AtClient service getters
- perf(SyncServiceImpl): when a `sync:from:` request returns no entries because
  the entire `(lastReceivedServerCommitId, serverCommitId]` range was filtered
  out server-side (apkam namespace scope, syncRegex, or skipDeletesUntil),
  advance the persisted server-commit cursor to the sync-start `serverCommitId`
  snapshot instead of breaking out without advancing. Subsequent sync rounds
  no-op until the server actually advances past it, rather than re-probing
  the same filtered range every round.
- perf(SyncServiceImpl): round 1 of fsync - push to server based on a simple 
  queue mechanism. Also fixed a bunch of related bugs. Note that a follow-up 
  PR will fully remove the use of the "Commit Log" part of the 
  at_persistence package on the client side; commit log was never the 
  appropriate vehicle mechanism to support client-side sync push

## 3.11.0     

- chore(deps): at_auth ^3.0.0
- chore(deps): at_chops ^3.0.0

## 3.10.0

- build(deps): Updated archive dependency to ^4.0.7
- feat: Add RemoteLocalPref enum and AtClientPreference.remoteLocalPref field
  to enable apps to easily default to using the remote atServer
- fix: ensure AtRpcResp and AtRpcReq `.toString()` methods are JSON serialized
  strings
- feat: use responseJson variable so that log is consistent
- fix: fixed rare race condition caused by the handling of legacy shared 
  symmetric keys
- feat: improved resilience of the notifications monitor to weird network 
  conditions

## 3.9.2

- fix: AtRpc - prevent NACK/ACK race when handling request mutex acquisition

## 3.9.1

- chore: removed `@experimental` annotation from AtRpc and AtCollection
- chore: added `// ignore: experimental_member_use` for usages of the 
  still-experimental AtTelemetry

## 3.9.0

- feat: introduce single-responder mode in AtRpc enabling redundancy support in
  request-response services relying on AtRpc. This feature is coupled with
  `enableRequestMutex` flag that controls it.

## 3.8.0

- feat: add optional `useRemoteAtServer` flag to AtClient `getKeys` and
  `getAtKeys` so that apps can ask to fetch directly from atServer rather
  than the local datastore.
- fix: set `isClient` to true and `isServer` to false in AtRpcClient,
  enabling same atSign communication of AtRpc clients and servers.
- fix!: fixed a bug where at_rpc was adding the AtClientPreference's namespace
  to the notifications used by at_rpc
  (https://github.com/atsign-foundation/at_client_sdk/pull/1670).

## 3.7.0

- chore(deps): uuid ^4.0.0
- chore(deps): at_commons ^5.5.0
- chore(deps): at_persistence_secondary_server ^4.2.0
- chore(deps): http ^1.2.1
- chore(deps): remove unused dependencies
- chore(deps): move collection to dev_dependencies

## 3.6.0
- feat: deprecate the (misleadingly named)
  `AtClientPreference.Atsign ProtocolEmitted` and change its default value
  from 1.5.0 to 2.0.0

## 3.5.3
- feat: fetch various atKeys keys from atChops if we have it (which we always 
  do, now) instead of going to the keyStore
- refactor: some deprecations for readability / maintainability

## 3.5.2
- fix: ensure that namespaces in `notify` requests aren't messed up by 
  multipart namespaces in AtClientPreference (e.g. namespace of `foo.bar`)

## 3.5.1
- fix: ensure that namespace is preserved if it happens to be repeated in a 
  notification's key (e.g. `@bob:foo.my_app.my_app@alice` )

## 3.5.0
- feat: add `atLookUp` parameter to AtClientManager.setCurrentAtSign,
  AtClientImpl.create, etc. so we can inject an existing AtLookUp instance if 
  we have one rather than having to create a new one and authenticate again

## 3.4.4
- fix[performance]: when fetching `public:publickey` of another atSign from
  atServer, cache it in local storage instead of depending on sync to take
  care of that (since programs can disable sync)

## 3.4.3
- build[deps]: update dependencies including at_persistence major version 
  changes
- fix: tightened up code for handling `AtKeyNotFoundException`s in 
  `AtCollectionQueryOperationsImpl`
- fix: Enable the same atSign to be used on both sides (client and server) 
  of an AtRpc interaction
- fix: LocalSecondary.isEnrollmentAuthorizedForOperation now checks if the 
  key in question is a `local` key, in which case the answer is always yes.

## 3.4.2
- build[deps]: update dependencies (at_commons, at_lookup, at_auth)

## 3.4.1
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 3.4.0
- feat: Allows clients to skip delete commits until a specific commitID during initial sync
## 3.3.1
- fix: isInSync bug fix for apkam connection
- fix: remove deprecated isPaginated param from SyncVerbBuilder in SyncServiceImpl
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.1.2
- feat: Introduce "publicKeyHash" which uses SHA hashing to verify change in the encryption public key
## 3.3.0
- feat: add the AtClientBindings mixin which was initially added to the 
  noports_core package but has broader applicability.

## 3.2.2
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.0.0
  - at_utils to v3.0.19
  - at_lookup to v3.0.49
  - at_auth to v2.0.7
  - at_persistence_secondary_server to v3.0.64
  - at_chops to v2.0.1
## 3.2.1
- feat: add optional param `encryptValue` to notify method
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v4.1.1
  - at_utils to v3.0.18
  - at_lookup to v3.0.48
  - at_auth to v2.0.5
  - at_persistence_secondary_server to v3.0.63
## 3.2.0
- feat: add `allowAll` flag (defaults to false) to AtRpc
## 3.1.0
- feat: add `useRemoteAtServer` flag to `GetRequestOptions` to allow clients 
  to fetch directly from the atServer rather than the client-side synced 
  cache. This flag was added to `PutRequestOptions` and 
  `DeleteRequestOptions` in version 3.0.60
- fix: Ensure that `NotificationResponseTransformer` does not attempt to 
  decrypt when `atNotification.isEncrypted == false`
## 3.0.78
- chore: publish clean version 3.0.78
## 3.0.77+1
- fix: remove incorrect version 3.0.78 from changelog
## 3.0.77
- fix: Fix the keys expiry job not being triggered
- chore: deprecate NotificationParams.forText()
- feat: Store enrollment details in local key
- fix: Add "sharedKeyEnc" to the metadata
## 3.0.76
- feat: Introduce mechanism to identify and delete expired keys
- feat: Introduce enrollment service to support enrollment operations:
  - Submit enrollment request(s)
  - Approve, Deny and Revoke enrollment request(s)
## 3.0.75
- feat: Introduce feature to fetch enrollment requests from the server
## 3.0.74
- build[deps]: Upgraded dependencies for the following packages:
  - at_chops to v2.0.0
  - at_lookup to v3.0.45
## 3.0.73
- build[deps]: Upgraded dependencies for the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_lookup to v3.0.44
    - at_chops to v1.0.7
    - at_persistence_secondary_server to v3.0.60
- feat: Replace encryption methods from EncryptionUtils with AtChops method 
## 3.0.72
- chore: Minor change to allow us to support dart 
  versions both before and after 3.2.0 specifically for this
  [Dart breaking change](https://github.com/dart-lang/sdk/issues/52801) 
  which was
  [introduced](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md)
  in dart 3.2.0
## 3.0.71
- feat: Replace decryption methods from EncryptionUtil with AtChops methods
## 3.0.70
- build[deps]: Upgraded dependencies for the following packages:
  - asn1lib: `>=1.4.1 <=1.5.0`, crypton: `>=2.1.0 <=2.2.1`, encrypt: `>=5.0.1 <=5.0.3`, crypto: `^3.0.3`
## 3.0.69
- feat: Add AtRpcClient for a much cleaner developer experience for sending AtRpc requests
## 3.0.68
- feat: have AtRpc use ephemeral notifications
## 3.0.67
- feat: Make enrollment available to SyncService/NotificationService for authentication
## 3.0.66
- feat: make namespace NOT mandatory for local keys
- feat: deprecate useAtChops experimental flag and remove fallback code using private key from preferences/EncryptionUtil methods
- updated at_commons to `'3.0.57'`, at_chops to `'1.0.5`, at_persistence_secondary_server to `'3.0.59'` 
## 3.0.65
- feat: apkam changes for at_onboarding_cli
- build: updated at_commons to `'3.0.55'`, at_chops to `'1.0.4`, at_lookup to `'3.0.40'` 
## 3.0.64
- Made ConnectivityListener configurable, and removed some unnecessary network 
  availability checks
- fix: wrap Monitor's call to `socket.listen()` in a runZonedGuarded block
## 3.0.63
- fix: Fixed bug in AtRpc.sendRequest which was causing repeat sends of requests
## 3.0.62
- fix: skip reserved keys during sync conflict checking
- build: updated dependency on http package to `'>=0.13.5 <2.0.0'`
## 3.0.61
- fix: ensure key exchange functions properly when the sync service is not
  being used
- feat: Add AtRpc - A simple rpc request-response API which uses Atsign Protocol
  notifications under the hood.
## 3.0.60
- feat: Add `useRemoteAtServer` to PutRequestOptions. When set, the update
  request will be sent directly to the remote atServer
- feat: Introduce DeleteRequestOptions
  - Add new optional named parameter `deleteRequestOptions` to AtClient.delete
  - Add `useRemoteAtServer` to DeleteRequestOptions. When set, the delete
    request will be sent directly to the remote atServer
- fix: Incorrect commitId gets updated against commit entry when a sync-batch skips an entry
- fix: Sync/Monitor bug while running onboarding_cli with at_chops using pkam from secure element
## 3.0.59
- fix: Sync running into infinite loop when an invalid key is present in the entries to sync into client
- fix: Redundant logs generated for an internal key (lastReceivedNotification)
  while sending notifications
- chore: Reduced log_level of AtKey lower case enforcement message from INFO to FINER
- feat: Introduce clientId, appName, appVersion and platform to distinguish requests from several clients in server logs.
## 3.0.58
- chore: upgrade dependencies. at_commons to 3.0.43, at_utils to 3.0.12, at_lookup to 3.0.36 and at_chops to 1.0.3
## 3.0.57
- feat: Initial support of additional encryption metadata enabling encryption future-proofing
- fix: Expose priority, strategy, notifier, latestN and notificationExpiry in NotificationParams
- fix: Fixed issue where NotificationResponseTransformer would duplicate sharedWith and sharedBy
  when logging `AtKey`s
## 3.0.56
- fix: AtClient.put() throws null-check error when key's namespace is null
## 3.0.55
- fix: Amend Monitor's socket message handler so that it separates multiple 'simultaneous' responses correctly.
- fix: Sync to local fails to delete a cached key
- feat: Introduce CommitOp(CommitOperation) to the KeyInfo to describe key update or delete upon sync
- feat: consume changes in at_commons v3.0.35 that enforce lowercase on AtKey
- build: upgrade dependency at_persistence_secondary_server to v3.0.46
## 3.0.54
- fix: ensure forText notifications are decrypted successfully when using at_commons 3.0.35 or greater
## 3.0.53
- feat: Introduce commit log compaction to keep size of commit log thin
- fix: Fixed a bug where switch atSign event is notified multiple times
- fix: Add AtChops as optional argument to AtServiceFactory.atClient
## 3.0.52
- feat: Introduce AtServiceFactory to make AtClientManager more reusable and more testable
- feat: Make AtChops instance (if any) available everywhere that it can/should be used
## 3.0.51
- feat: Add atSign to AtSignLoggers' names when relevant, so that log messages are clearer
- feat: Made notificationService and syncService available via AtClient to enable cleaner simpler code elsewhere
- fix: Fixed clearing of sync progress listener while switching atsign.
- fix: Remove the inactive listeners from AtClientManager._changeListeners list.
- fix: Reverted back path,async packages to older version
## 3.0.50
- feat: Introduce commit log compaction to keep size of commit log thin
- feat: changes for at_chops uptake
- chore: upgrade at_persistence_spec, at_persistence_secondary_server, at_commons version
## 3.0.49
- fix: Enable AtKey.namespace overrides the namespace in AtClientPreference in AtClient delete method
- fix: Fixed a bug where initial notifications fails to decrypt - invalid pad block issue
## 3.0.48
- feat: Added `lib/src/client/request_options.dart` to provide access to the `RequestOptions` and `GetRequestOptions` classes.
## 3.0.47
- fix: Enable deletion of local keys
## 3.0.46
- fix: Ensure that we handle any and all exceptions related to sending heartbeat request
- feat: Made NotificationServiceImpl's retry delay into a public instance variable, so it can be set by application code
- feat: Changed NotificationServiceImpl's retry delay (from when monitorRetry() is called to when Monitor.start() is called) from 15 seconds to 5 seconds
- fix: Fixed a bug where client could 'miss' notifications while starting up
- fix: Ensure that exceptions related to sending heartbeat request are always caught correctly
- feat: Added experimental telemetry feature
## 3.0.45
- fix: Fix sync running into infinite loop when invalid keys does not sync into local storage
- fix: Upgrade persistence secondary to version 3.0.43 to fix empty batch request being sent to cloud secondary
## 3.0.44
- feat: Introduce fetch method to NotificationService to fetch the notification using id.
- fix: Replace latestNotificationId with local key to store/fetch last received notification
## 3.0.43
- chore: upgrade persistence secondary to version 3.0.42 and persistence spec to 2.0.9
## 3.0.42
- fix: Improved performance of getKeys (and getAtKeys) when sharedBy is specified, by using the existing 
RemoteSecondary connection rather than creating a new one
- fix: Do not try to decrypt empty or null serverEncryptedValue when generating SyncConflict info
- fix: put try-catch around most of the `SyncServiceImpl._checkConflict` method so sync is not impeded if
_checkConflict encounters an exception
- fix: fix null pointer exception in monitorResponse due to delayed server response
- fix: Skip reserved keys from decryption in the notification callback
- fix: Update at_commons to 3.0.29 which fixes AtKey sharedWith attribute has incorrect value for public keys
## 3.0.41
- chore: upgrade persistence secondary to version 3.0.38 which reverts sync of signing keys and statsNotificationKey
## 3.0.40
- chore: upgrade at_commons to 3.0.26
- fix: check isEncrypted flag in sync conflict
- docs: Fixed broken links
## 3.0.39
- chore: upgrade 3rd party dependencies except hive
- chore: upgrade persistence secondary to version 3.0.36
## 3.0.38
- fix: Add client sending config changes to server
- fix: NotificationService.subscribe to return existing listener on same regex
## 3.0.37
- fix: Revert sending client config changes to server
## 3.0.36
- fix: Add metadata validation to put request on client SDK  
- fix: Added unit tests for sync failure
- fix: Export SyncProgressListener to track the SyncProgress. 
- fix: setCurrentAtsign() throws an exception when an invalid atsign is passed.
- feat: Encode new line characters in public-key value
- feat: Send clientConfig to the cloud secondary 
## 3.0.35
* fix: Reverted dependency on 'meta' package to ^1.7.0 as flutter_test package requires 1.7.0 
## 3.0.34
* fix: Ensure _syncFromServer rethrows caught exceptions once it's handled the exception chaining
* feat: Add enforceNamespace (default value true) to AtClientPreference
## 3.0.33
- feat: Upgrade lints version to 2.0.0 
## 3.0.32
- fix: while syncing keys from server to local if there is an issue syncing a key, continue syncing rest of the keys
- fix: do not sync statsNotificationID from client to server
- feat: KeyStreams
- fix: do not create new instance of CacheableSecondaryAddressFinder in at lookup 
- [optional] Users can set SecureSocket's securityContext and store current session TLS keys through AtClientPreferences
## 3.0.31
- Enhance notify text to send text message encrypted
- Upgrade at_persistence_secondary_server to v3.0.30
- Upgrade at_commons version to v3.0.20 for encrypt notify text message
- Upgrade at_lookup version to v3.0.28 for adding mutex to authenticate methods
- feat: Add to NotificationService.notify() signature:
    * added new optional callback parameter, onSentToSecondary
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * and updated code documentation for NotificationService.notify() method
## 3.0.30
- Added bypassCache option in get method
- Added sync conflict info to sync progress callback
- Added security policy
- Fix for skipping reserved keys while checking for sync conflict
- Upgrade at_lookup to v3.0.27 for outbound message listener timeout enhancement  
## 3.0.29
- Added additional attributes in SyncProgress for improved sync observability
## 3.0.28
- Upgrading dependency at_persistence_secondary_server to version 3.0.29 to sync public hidden keys
- Upgrade at_commons to 3.0.18 to enable scan to display hidden keys when showHiddenKeys set to true
## 3.0.27
- Upgraded dependency at_persistence_secondary_server to version 3.0.28
## 3.0.26
- Uptake AtException hierarchy
- Introduce exception chaining
- Fix for Server stuck on old value even though syncing is happening. at_server Issue #721
- Export notification_service.dart file
## 3.0.25
- Fix for regex issue in notification service. Issue #523
- Fix for namespace issue in notify method.Issue #527
- Fix for handling empty sync responses from server. App issue #624
## 3.0.24
- Update the @platform logo
- Default the AtKey.sharedBy to currentAtSign
## 3.0.23
- Fix for at_client issue #508 - getLastNotificationTime bug while trying to decrypt old data
## 3.0.22
- Fix for getKeys in local secondary not returning keys
## 3.0.21
- Cache secondary url returned by root server
## 3.0.20
- Remove print statements
## 3.0.19
- Update at_commons,at_persistence and at_lookup version to remove print statements
## 3.0.18
- Generate Notification id in SDK
## 3.0.17
- Fix self encryption key not found
- Fix for _getLastNotificationTime method returning null
- Added heartbeats to Notifications Monitor to detect and recover from
  dead socket. Heartbeat interval is customizable via AtClientPreference
- Fix for os write permission issue: give app option to pass the path where
  the encrypted file will be saved on disk
## 3.0.16
- Decrypt notification value in SDK
- Support for shared key and public key checksum in notify
- Deprecated methods related to filebin
## 3.0.15
- Fix public key checksum in metadata does not sync to local.
## 3.0.14
- Support for shared key and public key checksum in metadata
- Chunk based encryption/decryption for files up to 1GB
- Change in pubspec to fetch the exact version of atsign packages
## 3.0.13
- Sync deleted cached keys to cloud secondary
- at_lookup version upgrade for increase in outbound connection timeout
## 3.0.12
- Fix automatic sync not working
## 3.0.11
- at_lookup version upgrade for outbound listener bug fix
- added functional test to verify outbound listener bug fix
## 3.0.10
- Uptake at_persistence_secondary_server changes
- Uptake at_lookup changes for AtTimeoutException
- Handle error responses from server
- Refactor put method to use request and response transformers
- Provide callback for sync progress
## 3.0.9
- Uptake at_persistence_secondary_server changes
- Refactor decryption service
- Introduce request response transformers
- Refactor get method to use request response transformers
## 3.0.8
- Updated readme and documentation improvements
## 3.0.7
- Uptake at_persistence_secondary_server changes
- Resolve dart analyzer issues
- Run dart formatter
## 3.0.6
- Uptake AtKey validations
## 3.0.5
- Uptake at_persistence_secondary_server changes
## 3.0.4
- Uptake Hive Lazy Box changes
## 3.0.3
- Sync pagination limit in preference
## 3.0.2
- Expose isSyncInProgress in SyncService
## 3.0.1
- Reduce wait time on monitor connection
- at_lookup version upgrade
## 3.0.0
- Resilient SDK changes and bug fixes
## 2.0.4
- Improve notification service
- Improve monitor
- sync on a dedicated connection
## 2.0.3
- at_commons version upgrade
## 2.0.2
- filebin upload changes
## 2.0.1
- at_commons version upgrade
## 2.0.0
- Null safety upgrade
## 1.0.1+10
- Provision to request for a new outbound connection.
- Minor bug in stream handlers
## 1.0.1+9
- Third party package dependency upgrade
- gitflow changes
- Auto restart monitor connection
- Stream encryption
- Bug fixes
## 1.0.1+8
- Delete cached keys
- Encrypt Stream data
## 1.0.1+7
- Self keys migration issue fix
## 1.0.1+6
- Notification sub system introduced
## 1.0.1+5
- Added automatic refresh of monitor connection
## 1.0.1+4
- Provided multiple atsign support in at client SDK. Introduced batch verb to improve sync performance
## 1.0.1+3
- onboarding changes for server activation and deactivation Backup keys implementation sync improvements
## 1.0.1+2
- sync improvements and at_utils, at_commons, at_lookup version changes
## 1.0.1+1
- Minor changes in at_persistence_spec and at_persistence_secondary_server
## 1.0.1
- pubspec dependencies version changes
## 1.0.0
- Initial version, created by Stagehand
