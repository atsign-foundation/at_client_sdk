## 3.4.0-rc1

- feat: `authenticatorForCramSecret` - the fourth credential shape, a CRAM
  secret with no keystore behind it. `authenticatorFor` already falls back to
  CRAM, but only for a caller with an `AtKeysIo` to read, because it decides by
  that read throwing. at_lookup's ladder served the keystore-less caller from
  its own `cramSecret` field, and removing the ladder without this would take
  CRAM away from anyone setting `AtClientPreference.cramSecret`.
- refactor: at_auth builds its lookups with `AtLookUp.withSecureSocket` and
  installs authenticators through `AtLookupMuxable`, so nothing here names
  at_lookup's implementation class. Two casts turned out to be unnecessary all
  along - `close()` and `cramAuthenticate()` are both on `AtLookUp`.
- feat: add `authenticatorForChops`, the third credential shape at_lookup's
  ladder supported: an `AtChops` and nothing else - no keyfile, no private
  key, the material living inside the signer. A client built from an
  `AtClientPreference` plus an injected AtChops is exactly this, and it can use
  neither `authenticatorFor` (no keystore to read) nor
  `authenticatorForPrivateKey` (no key of its own). Found because the
  private-key path provably did not move the ladder count: predicted no change,
  measured no change, and the model that explained why named this shape.
- feat: add `authenticatorForPrivateKey`, the legacy credential as an
  authenticator - a PKAM private key and no keystore at all. That is the shape
  at_lookup's ladder supported, and without it deleting the ladder would make
  an `AtKeysIo` mandatory to authenticate, breaking every consumer that builds
  a client from a preference alone. Signs with an empty public half exactly as
  the ladder did, `AtPkamKeyPair.create('', privateKey)`, since RSA signing
  needs only the private key. Always rsa2048: a keyless caller has no
  enrollment record to name an algorithm, and rsa2048 is what at_lookup signed
  with by default. It still refuses a challenge that does not name its atSign.
- feat: `AtEnrollment.approve` accepts `approverChops`, the approving client's
  own crypto. What approval needs is not authentication - the atSign's
  encryption private key and its self-encryption key - so it should not come
  from a network object. While null the approver still falls back to
  `atLookUp.atChops`, so every existing caller is unaffected; at_client now
  passes its own. Pinned: given `approverChops`, the approver completes an
  approval and **never reads** `atLookUp.atChops`, which is what lets that
  field be deleted. Given neither, it still refuses.
- feat: `AtAuthImpl.onboard` and `EnrollmentHandshake` install authenticators
  too, finishing at_auth's side of the seam. Both inject their signer rather
  than let the keystore resolve one: a PQ-native activation signs with a
  keypair minted moments earlier that is in no keyfile, under an enrollment the
  atServer has not created yet, and the handshake's keys are deliberately
  incomplete because the symmetric key is what it is there to fetch.
  `authenticatorFor` gained an explicit `signingAlgo` for the first case - the
  rsa2048 default would otherwise sign an ML-DSA key with the RSA routine.
- fix(docs): the previous entry said a functional pass left "4 ladder
  authentications". That figure was read through a log filter: the ladder logs
  at `finer` and the functional harness sets the root level to `shout`, so
  almost all of them were invisible. Measured with both routes at `shout`:
  **57 through the injected route and 201 through the ladder**. The remaining
  ones are at_client's `remote_secondary`, which every AtClient verb goes
  through, and at_onboarding_cli.
- feat: `AtAuthImpl.authenticate` installs an `AtAuthenticator` on the lookup,
  so authentication runs on this side of the seam rather than out of
  at_lookup's credential fields. The keystore it reads follows the same
  precedence this method already used - an explicitly supplied `AtKeys` beats
  an `AtKeysIo`, so the authenticator reads what the rest of the method read
  rather than re-resolving and possibly differing. `atChops` is still set
  alongside it, because `EnrollmentApprover` reads that field for work that is
  not authentication at all. Measured against a live atServer: the injected
  route ran 17 times in a functional pass, with 4 ladder authentications left
  at the call sites still to migrate.
- feat: `authenticatorFor` accepts an injected `AtChops`. `AtAuth` has always
  let a caller bring its own signer, through `AtAuth.create(atChops:)` and its
  mutable `atChops` field, so an authenticator that ignored one would break a
  consumer holding a hardware-backed key. When supplied, only the *algorithm*
  is read from the keyfile - resolving its own signer eagerly would throw on a
  keyfile missing material such a caller never needed.
- feat: add `authenticatorFor`, which builds the `AtAuthenticator` at_lookup
  now accepts. It reads credentials from an injected `AtKeysIo` and decides
  which one applies by what the keystore has: an `AtKeysSourceAbsentException`
  means this atSign is not onboarded yet and CRAM is the only credential that
  exists; keys mean PKAM, signed with the algorithm those keys name for the
  enrollment. The keystore is re-read on every invocation rather than captured,
  so one closure held for an instance's lifetime answers CRAM during onboarding
  and PKAM afterwards without anyone telling it the phase changed - and cannot
  disagree with the keystore, because it holds no second copy of the answer.
  Both legs are ported from `AtLookupImpl` unchanged, including CRAM's tighter
  timeouts and the fact that CRAM does not validate the `from:` challenge where
  PKAM does.
- feat: `AtKeysSourceAbsentException` — the one read failure that means "this
  atSign has no key source yet" rather than "this process cannot read what is
  there". `FileAtKeysIo.read` throws it for a missing file and
  `AtKeysNotInMemoryException` now extends it, so a caller can tell a cold
  start from a truncated document, a passphrase that was not supplied, or a
  validation refusal. **Additive, not a fourth break**: it is a new subtype of
  the `AtException` that path already threw, so every existing `catch` still
  catches it.
- feat: `AtKeys.keyIdPrefix(role, algorithm)` and
  `AtKeys.isRoleKeyId(keyId, role)` — the `<role>:<algorithm>:<generation>`
  keyId grammar, composed and parsed in one place.
  - Every id this class writes now goes through `keyIdPrefix`, and the parse
    that used to be private (`sign:` only) reads back exactly what it writes.
    A caller assembling the string itself held a second copy of a shape that
    has to agree with this one, and at_client was doing that for the atSign's
    signing root.
  - `isRoleKeyId` matches the **shape**, not the material's part type, which is
    ambiguous both ways: an enrollment can hold `privateSigning` material under
    more than one keyId, and the atSign's signing root is `privateSigning` too
    while belonging to no enrollment. It deliberately does not match the
    algorithm — a caller asking "is this a root slot" wants every generation of
    every algorithm, which is what makes a key of one algorithm replaceable by
    a key of another.
- feat: `AtKeys.retireSigningKeys(enrollmentId, algorithm)` — withdraws every
  active signing keypair an enrollment holds for one algorithm, returning the
  keyIds it moved. Both halves move to `retired` and nothing is removed, so
  the public half goes on being advertised by `retiredSigningKeysFor` and what
  the key signed still verifies.
  - The caller names the **algorithm**, not the keyId: a signing key leaves
    service because its algorithm left a client's in-use set, and the
    `sign:<algo>:<generation>` grammar is this class's own. A caller
    reconstructing it would be holding a second copy of that grammar.
  - Selects the same material `signingKeysFor` returns — the keyId shape, not
    the `privateSigning` role, which the atSign's own signing root shares and
    an enrollment can hold material under for more than one reason.
- feat: `AtOnboardingRequest.advertisedSigningKey` — the activation-time form
  of the field below. An atSign's first enrollment owns a signing key from
  birth, `_apsk` advertises it, and `AtAuthImpl` files it under the id the
  atServer assigns.
- feat: `EnrollmentRequest.advertisedSigningKey` — a signing keypair the
  enrollment owns from birth. When supplied, `_apsk` advertises **that key**
  instead of `apkamPublicKey`, and the request files it into the enrollment's
  key material under `sign:<algorithm>:<generation>`.
  - Supplied by the caller rather than minted here, because whether an
    enrollment holds one is a rollout position and at_auth cannot see a
    preference. Absent, every path behaves exactly as before.
  - A single active `rsa2048` signing key is advertised in the **bare** form
    even when a key package rides the same request. A key package used to
    force the array because the package's signer was the APKAM key, whose
    algorithm is whatever the enrollment authenticates with — which a bare
    value, meaning `rsa2048` by convention, cannot state.
  - ⚠️ **Whatever signs the enrollment's key package must be this key.**
    `_apsk` is what a peer resolves to verify that package before sealing any
    secret to the enrollment, so a package signed by the APKAM key while the
    record names this one verifies against nothing — and the enrollment is
    created and then receives no conveyed material at all.
- feat: `AtKeys.retiredSigningKeysFor(enrollmentId)` returns the **public**
  half of every signing keypair that enrollment has retired, strongest
  algorithm first — the entries an `_apsk` advertisement carries as `retired`
  so that envelopes signed before a key was withdrawn still verify.
  - Public-only: a retired key exists to verify what it already signed and
    must never sign again, so its private half is not handed back.
  - The private half is not required to be *present* either. A build that
    wipes a withdrawn key's private material is doing the hygienic thing, and
    dropping the advertisement entry when it does would retroactively
    unverify everything that key signed.
  - Selected on exactly `KeyPartStatus.retired`. `dead` material was never
    adopted and has nothing to verify; a status this build has never seen is
    skipped rather than guessed at.
- feat: a keyfile holding more than one live enrollment is **read**, and only a
  writer refuses to create one. The single-active-authentication rule moves off
  `AtKeysAssurance.validateKeyMaterials` onto a new
  `.refuseSecondLiveEnrollment`, which only `AtKeys.addKey` calls; the parse
  files through a path that applies the structural invariants without it.
  - A reader that refused a second entry would make the plurality
    unenableable: the first build to write two breaks every build that
    predates it, so no build could ever start. The ambiguity surfaces at
    `resolveAuthenticatingEnrollment()` instead — where a caller is asking for
    the one answer that does not exist — rather than taking a whole keyfile
    down at parse.
  - Where it moved to, it got stricter: the refusal is owner- and
    algorithm-agnostic, so one enrollment holding an active `auth:rsa2048:1`
    *and* an active `auth:mldsa65:1` is refused. The per-(role, algorithm)
    rule structurally cannot see that pair, since the two name different
    algorithms.
- fix: a keyfile written by at_auth 3.3.0 is read, not refused. Its
  `enrollments[]` guard rejected any document carrying a top-level `keys`
  array — including an **empty** one, which is the only shape 3.3.0 ever
  wrote: that version never populated the array (`addKey` has no caller
  outside `AtKeys` there), so every keyfile it onboarded carries `"keys": []`
  with the real material in the flat block. Measured, not assumed: a keyfile
  CRAM-onboarded with published 3.3.0 was refused here, and deleting only the
  empty array made the same file load with the right atsign and enrollmentId.
  An empty array is now dropped and the document read; a POPULATED one is
  still refused, because reading that silently would authenticate as the
  wrong enrollment.
- **BREAKING** feat: the `.atKeys` typed document groups by enrollment. The
  flat document-wide `keys[]` becomes `enrollments[]` — one entry per
  enrollment, carrying its id, its `namespaces`/`appName`/`deviceName`
  snapshot, and its own keys — plus a top-level `atsignKeys[]` for material
  that belongs to the atSign rather than to any enrollment (the signing root,
  an nskey private). Key entries no longer carry an `enrollmentId`: the
  container states it once, and two stored copies of one fact can disagree
  with nothing to arbitrate.
  - **Identity is `(enrollment, keyId)`.** A keyId is unique within its
    container, not across the document, so `getKey`, `keysForKeyId`,
    `retireKey` and `replaceKey` now take the enrollment beside the keyId, and
    `getAtSignKey` / `atSignKeysForKeyId` / `retireAtSignKey` address the
    atSign's own container. Nothing defaults: a caller reaching for atSign
    material with a bare keyId would otherwise compile while searching an
    enrollment and find nothing. `addKey` is unchanged — a material states its
    own owner, and a null `enrollmentId` routes it to the atSign.
  - Structured keyIds normalise to `<role>:<algo>:<generation>` —
    `auth:mldsa65:1`, `sign:rsa2048:1`, `root:mldsa65:1` — with the generation
    counted per `(role, algorithm)`. Kid-addressed entries are unchanged: a kid
    is a digest of the key and is addressed by value.
  - `activeEnrollmentId` is replaced by `enrollmentIds`,
    `authenticatableEnrollmentIds` and `resolveAuthenticatingEnrollment()`.
    The removed getter answered `firstOrNull`, so a file holding two live
    enrollments picked one silently; the replacement is invoked by name and
    **throws** rather than guessing when several qualify.
  - A `version: 1` document carrying a top-level `keys` is refused by name.
    `keys` is no longer a reserved field, so parsing one would sweep its whole
    array into `metadata` as a legacy value — leaving the document reading as
    untyped and the caller authenticating from the flat block as the legacy
    enrollment, with the live enrollment's credentials sitting unread beside
    it.
  - Nothing released has ever written a typed keyfile, so there is nothing at
    rest to migrate and `version` stays 1. Keyfiles this project's own live
    runs generated do carry the old shape and must be regenerated.
- **BREAKING** fix: `KeyPartStatus` becomes a constants class and
  `AtKeysMaterial.status` an open `String`, so a `.atKeys` document carrying a
  status this build does not recognise is **read and round-tripped unmodified**
  rather than refused. It was an `enum` parsed through a throwing
  `expectEnum`, which meant a keyfile written by a newer client was rejected in
  its entirety — not the entry, the whole document, and the document is the
  user's key material. Adding a status value was therefore a breaking at-rest
  change forever, which is how this was found. `keyAlgorithmType` and
  `keyPartType` beside it were already open Strings for exactly this reason;
  `status` was the one field that broke the promise their documentation makes
  for the whole document.
  - Callers comparing `material.status == KeyPartStatus.active` need no
    change: the constant is a `String` and the comparison is source-identical.
    What breaks is code relying on enum-ness — `KeyPartStatus.values`,
    `status.name`, and `KeyPartStatus` as a type annotation (now `String`),
    including the `to:` parameter of `retireKey` and `replaceKey`.
  - `KeyPartStatus.rankOf` is new and states the forward order
    (`active` → `retired` → `dead`) that declaration index used to supply
    implicitly. An unrecognised status has **no** rank: it is never selected as
    active, and a transition involving one is refused rather than assigned a
    direction, since guessing would let a future value silently reactivate a
    key its owner withdrew. Reordering the declarations no longer redefines
    every transition check in the package.
- feat: add `AtEnrollment.update` — the `enroll:update` caller, with
  `EnrollmentUpdateRequest` and `EnrollmentUpdater` beside the approver. An
  approved enrollment can now amend its own record: the APKAM authentication
  key, the `_apsk` signing keys it advertises, and its metadata. Nothing sent
  an `enroll:update` anywhere, so a signing key minted after the enrollment
  request had no way to reach the record. The operation is self-only and cannot
  reach the namespaces or the approval state, so an enrollment amending itself
  cannot widen its own grant.
- feat: add `apkamPossessionSignable` and `apkamPossessionSignature` — the
  proof an `enroll:update` carries when it installs a new `apkamPublicKey`,
  base64 of a signature by the **new** private key over
  `<enrollmentId>|<apkamPublicKey>|<signingAlgo>`. The connection proves
  possession of the enrollment's current key and nothing else proves possession
  of the new one, so without this a compromised-but-authenticated client could
  install a key whose private half is held by someone else and lock the
  legitimate holder out while the record still looked valid. Signed through the
  path a PKAM challenge is signed through, because the atServer verifies both
  through one verifier: `mldsa65` signs the message bytes directly while
  `rsa2048` signs their SHA-256, so an implementation that hashed for both
  fails on the post-quantum path alone.
- feat!: `apskAdvertisement` composes an array from a list of keys rather than
  one key from `(apkamPublicKey, signingAlgo)`. The record has been an array
  since it shipped, but nothing could put a second entry in it, which is what
  signature agility needs — an enrollment adds a second algorithm's key beside
  the first rather than replacing it, because envelopes are stored durably and
  a key that stops signing must still verify what it already signed. `status`
  is emitted only for a retired key, so an advertisement that has never
  rotated is byte-identical to what the single-key composer wrote.
  `ApskSigningKey.forPublicKey` is how a writer builds an entry: the `kid` is
  a function of the key material and is never a caller's to supply, because
  two spellings of it verify nothing and both compile.
- feat: add `AtKeys.signingKeysFor(enrollmentId)` — every active signing
  keypair an enrollment holds, one per algorithm, strongest first. A
  multi-signature writer needs one keypair per algorithm, and nothing
  enumerated them. Entries are selected by the keyId shape
  `fileSigningMaterial` writes rather than by the `privateSigning` role,
  because that role is shared: the atSign-wide PQ signing root is filed under
  it too, with no enrollment id, and a role filter would hand an enrollment a
  key that was never its own. A half pair, a retired pair, an algorithm this
  build does not know, and a keyId whose two halves disagree about their
  algorithm are each skipped rather than refused — the rest of a keyfile
  written by a newer client is still usable. That last case is reachable:
  the invariants are per `(keyPartType, keyAlgorithmType)`, so a keyId's two
  halves are never compared with each other, and handing the pair out would
  sign under one algorithm while advertising the other's public key.
- fix: `authenticationFor` refuses an enrollment whose typed authentication
  material names an algorithm this build cannot sign with, instead of falling
  back to the flat fields. The keypair is still that enrollment's, so the flat
  fields are a *different* enrollment's on a retrofitted keyfile — and
  at_lookup's default is `rsa2048`, so the fallback signed the wrong key with
  the wrong routine. "This enrollment has no typed material" remains a separate
  answer and still reaches the flat fields. A keyfile written by a newer client
  is how this arises.
- fix: two active authentication keys carrying no enrollment id are refused,
  as two carrying one already were. `validateKeyMaterials` used a single
  variable as both the enrollment id it had seen and the flag for *whether* it
  had seen one, and `enrollmentId` is optional in the keyfile document — so a
  first key with none left the check armed with null and the second passed.
  That is the document-wide rule `resolveAuthenticatingEnrollment()` relies on
  for its answer to be unique, which is the whole argument for deriving it
  rather than storing a pointer. (This entry named `AtKeys.activeEnrollmentId`,
  which a later change in this same unreleased version removed.) A single key
  with no enrollment id is still fine: it is a legacy shape, not a corrupt
  keyfile.
- feat: add `AtKeys.authenticationFor(enrollmentId)` and
  `authenticationAlgorithmFor(enrollmentId)` — the one place either half of an
  APKAM keypair is resolved. Typed material wins wherever the keyfile holds it
  for that enrollment; the flat `apkamPublicKey`/`apkamPrivateKey` answer only
  where it holds none, which is where four shipping shapes still keep the
  keypair: a keyfile written before the typed section existed, an `rsa2048`
  first onboard, an OTP enrollment, and an onboard handed its keys by the
  caller. Which way round matters on a retrofitted keyfile, the one shape
  holding both — the flat fields there are a *different*, capped enrollment's
  credentials, so resolving to them signs the PKAM challenge as the wrong
  principal. `authenticationAlgorithmFor` answers without building an AtChops,
  because a caller holding an injected one still has to name the algorithm and
  `toAtChops` throws on a keyfile missing material that caller never needed.
- feat: add `KeyEntryStatus` — `active` or `retired`, the status every
  advertised key entry in the protocol carries — and read it on `_apsk`, where
  `ApskSigningKey` gains a `status`. It lives here rather than in at_client
  because at_auth is the lower package: all three records that advertise keys
  carry the same field with the same two values, at_client depends on at_auth
  and not the reverse, so this is the only direction a shared type can travel.
  `publicKeyKid` sits here for the same reason. Absent reads as `active`, and a
  value this build does not recognise reads as `retired` — an unknown state is
  narrower than "offered for new operations", and the permissive reading is the
  one that can make a build use a key its owner has withdrawn.
- feat: `apskSigningKeys` **keeps** a retired entry rather than skipping it.
  This list is what verifies stored envelopes, and the keys an enrollment has
  retired are precisely the ones that signed its older ones, so filtering here
  would retroactively unverify them. Excluding them is the job of a caller
  choosing a key to sign something new with, and that caller does not exist yet.
- **breaking (unreleased): `apskKid` becomes `publicKeyKid(Uint8List)`, and it
  hashes the key's raw BYTES.** It hashed the base64 text as published, while
  at_client's `nskeyKidOf` hashed the decoded bytes — two derivations, both
  documented as "the SHA-256 of the public key", agreeing for nothing but a key
  whose published form IS its material. One function now, for every record that
  advertises keys; `publicKeyKidOfBase64` is the convenience for a key held as
  base64, over the same preimage. Every kid on an `_apsk` array and a key
  package changes value; nothing published reads them.
- feat: add `apskAdvertisement`, `apskSigningKeys`, `ApskSigningKey` and
  `publicKeyKid` — the one definition of the `_apsk` signing-key advertisement,
  composed and parsed in one place. The atServer stopped composing `_apsk`
  (at_server#2744): it publishes what a request sends and nothing when a
  request sends none, so an enrollment that advertised a key package and sent
  no `_apsk` had it rejected by the approver, which verifies the package
  against that value.
- feat: every `enroll:request` now carries its `_apsk`. A plain-legacy
  enrollment sends the bare RSA key on `apskLegacy` — exactly what the
  atServer used to compose for it, so the published record is unchanged —
  and everything else sends the array on `apsk`.
- fix: `waitForApproval` no longer polls forever on a refusal it cannot
  resolve. The handler matched `AT0401`/`AT0026` (not yet decided, keep
  waiting) and `AT0025` (denied, throw) and had no other branch, so any other
  refusal — an enrollment revoked while the wait was running answers
  `AT0027` — was neither logged nor thrown, and the poll ran every
  `retryInterval` for the life of the process saying nothing. Such a refusal
  is now logged at `warning`, tolerated for a short run in case it is
  transient, and ends the wait with an `AtEnrollmentException` carrying the
  atServer's own message once an unbroken run exceeds `maxRetries`.
- fix: the two `keys:get` commands the enrollment handshake sends after an
  approval are logged at `finer` rather than `shout`. They are routine
  protocol traces, not emergencies, and at `shout` they printed the
  enrollment id, the atSign and which private-key record was being fetched
  into every deployment's log output unconditionally.
- docs: `AtEnrollment` publishes its defaults as constants —
  `defaultRetryInterval` (2 seconds), `defaultMaxRetries` (15),
  `defaultLogProgress` (true) and `defaultOtpExpiry` (5 minutes) — and both
  the interface and `AtEnrollmentImpl` now state those rather than literals.
  The interface had been declaring a different regime for `waitForApproval`
  (48 retries a minute apart, silent) which no implementation applied: Dart
  resolves a default in the method that runs, not from the static type at the
  call site, so `AtEnrollmentImpl`'s values were always the ones in effect.
  Those are the values that land here, so nothing changes behaviour. The
  `waitForApproval` dartdoc no longer claims that `maxRetries` bounds the
  polling, and says instead that the wait for a decision is unbounded.
- fix: `waitForApproval`'s `maxRetries` is a budget for consecutive failures
  to reach the atServer, which is what its name has always claimed. It used
  to count total polls and never reset, so a wait tolerated connection
  trouble for its first `maxRetries` polls and was then fatal to a single
  blip for as long as it ran. An answer from the atServer — including a
  refusal, which is an answer about the enrollment — now costs nothing and
  restores the budget. The wait for a pending decision stays deliberately
  unbounded (`maxRetries` never bounded it, whatever the dartdoc said), and
  an atServer unreachable from the first poll still gives up after exactly
  the same number of attempts.
- fix: a legacy atKeys document that names its own atSign can be upgraded to
  the typed-keys shape. `AtKeysAssurance.validateMapUpdate` strips the
  reserved top-level keys (`version`/`atsign`/`keys`) from a typed document
  but not from a legacy one, which has no reserved names — so an existing
  document carrying a top-level `atsign` offered it as a legacy value the
  candidate had already stripped, and the first flush onto it was refused
  with `map.legacy.atsign is not preserved`. The upgrade re-homes that value
  into the reserved field rather than dropping it, so it is now checked
  against the candidate's `atsign` (normalized on both sides, since
  `AtKeys.fromJson` normalizes the reserved one) and taken out of the legacy
  comparison; a candidate naming a different atSign is still refused. That is
  what every keychain entry a published `at_client_flutter` wrote looks like,
  so the first flush of an nskey private, a key package or the signing root
  threw on every device already in the field.
- feat: `AtEnrollmentRequest.pq(...)` is the pq-mode constructor and the
  default constructor is the legacy-mode one; `keyExchangeMode` is no longer
  a parameter. The mode and the two callbacks a pq request cannot work
  without — `metadataBuilder`, which advertises the public half the approver
  encapsulates to, and `apkamSymmetricKeyResolver`, which collects what was
  encapsulated — used to be chosen independently, so at_auth refused the
  mismatched combinations at submission time. `.pq` requires both and reports
  `EnrollmentKeyExchangeMode.pq`; the default constructor takes no resolver
  and reports `legacy`. Both source the atSign identically (a `session`, else
  the deprecated loose `atSign`), so a request that only inspects what it
  advertised still needs no session. The submit-time refusal for a missing
  resolver is gone along with the state it guarded; the refusal for a builder
  that returned no key package stays, since that is a property of the
  builder's output that no constructor can promise.
- feat: `AtKeys.fileApkamMaterial` and `AtKeys.adoptMaterials` — the two
  operations by which an enrollment's key material enters a keyfile. Filing
  an APKAM keypair (both halves under `apkam:<enrollmentId>`, sharing one
  creation timestamp) and adopting what a request's metadataBuilder minted
  (re-tagged with the enrollment id it now belongs to, every other field
  untouched) were open-coded at both writer sites — the first enrollment of
  an onboard, and the self-enrollment retrofit — which is two chances to
  disagree about an at-rest shape.
- fix: `InMemoryAtKeysIo.write` honours the interface's create-only
  contract — a second write for the same atSign throws
  `AtKeysFileOverwriteException`, exactly as the file store does, instead
  of silently replacing. `flush` remains the replace/mutate verb. The
  divergence made the double lie as a stand-in: double-writing code
  passed against memory and threw in production.
- fix: three raceable paths in `AtKeysFileLock` — a token write that
  fails after the exclusive create now takes the lock back down and
  propagates the IO failure (an empty lock could never be released by
  token comparison, stalling every contender until staleness); breaking
  a stale lock that vanishes mid-break contends instead of crashing the
  acquire; and release claims the lock by rename before checking the
  token, closing the window in which it could evict a live holder that
  replaced a stale-broken lock.
- fix: `waitForApproval` decrypts a key record that carries no `iv` field —
  a record written by a legacy approver, encrypted under the zero IV —
  instead of crashing on the absent field. The record's vintage is the
  writing approver's, not the fetching client's.
- feat: `waitForApproval`'s `atLookup` parameter is on the `AtEnrollment`
  interface (it was an implementation-only extra, invisible to callers
  holding the interface type) and is typed `AtLookUp`, which is all the
  handshake uses.
- feat: `AtSelfEnrollmentRequest.signingAlgo` selects the algorithm of the
  APKAM keypair a self-enrollment mints — `mldsa65` (the default, today's
  PQ retrofit) or `rsa2048` for a rollout-window retrofit that needs no
  ML-DSA anywhere; either way the keypair is fresh, never the legacy key
  object. The keyfile idempotence check is per requested algorithm, so a
  keyfile holding a PQ enrollment can still take the RSA retrofit and a
  rerun of either mode reuses its own.
- fix: a refused onboarding enrollment's `AtAuthenticationException` carries
  the server's reason; it previously interpolated a `toString` tear-off, so
  the message read `Closure: () => String...` instead of the cause.
- fix: an aborted self-retrofit denies the pending enrollment it created.
  Against an atServer without the self-retrofit auto-approve, the
  `enroll:request` is accepted and parked as `pending`, and the client then
  threw — leaving a record nobody would ever act on, and leaving one more per
  retry. It now denies that enrollment before giving up.
  Best effort by necessity: denying needs `__manage`, which the parent
  enrollment the connection authenticated as may not hold. The thrown message
  says which happened, so a scoped parent that could not tidy up reports the
  leftover rather than implying the server was left clean.
- feat: `WrittenAtKeysIo.update(atsign, mutate)` — read, mutate and persist as
  **one** operation, and the call an addition should now go through instead of
  a hand-rolled `read` → mutate → `flush`. Those three steps interleave: two
  callers running concurrently both read the same state, and the second
  `flush` presents a candidate missing the first's addition. `flush` is right
  to refuse it — nothing may be lost — so the outcome is a thrown assurance
  exception and one addition silently gone. `FileAtKeysIo` holds its keyfile
  lock across all three steps, which serialises coroutines inside one process
  as well as separate processes; the default on the interface is
  read/mutate/flush, no worse than the form it replaces. The mutation returns
  whether anything changed, so a caller that finds the material already there
  — re-delivery is the substrate's normal mode — writes nothing.
- feat: a CRAM activation can be **PQ-native**. Setting
  `AtOnboardingRequest.signingAlgoType` to `mldsa65` mints an ML-DSA-65 APKAM
  instead of an RSA one and files it as **typed material** under the enrollment
  id the atServer assigns, leaving the flat `apkamPublicKey`/`apkamPrivateKey`
  fields empty. `AtAuthImpl.authenticate` already prefers the typed path, so
  every later connection resolves the algorithm from the keyfile with nothing
  caller-supplied anywhere.
  Empty flat fields are the point: a reader that calls `AtKeys.toAtChops()`
  gets a loud failure rather than an ML-DSA key signed with the RSA routine.
  That is also why this is **opt-in** rather than the default — it is a
  behaviour change no minor release may impose on existing consumers, and the
  SDK's own onboarding path is what opts in.
- feat: `AtOnboardingRequest.mintLegacyMaterial`, an **opt-out**. Null resolves
  to true, not false: legacy material is retained until the *ecosystem* is
  post-quantum, not until this atSign is, and whether a brand-new atSign will
  ever need a legacy peer is decided by the apps that adopt it. Set false and
  no RSA encryption keypair, `selfEncryptionKey` or `apkamSymmetricKey` is cut
  and **`public:publickey` is not published** — publishing an absent key would
  be worse than publishing nothing, since a legacy peer would encrypt to it and
  produce ciphertext nobody can read. The CRAM secret is deleted either way.
- feat: `AtOnboardingRequest.metadataBuilder`, so a first enrollment can
  advertise a key package. `metadata.keyPackage` is written by the request that
  creates the enrollment record and never again, so activation is the only
  moment it can be set at all.
- feat: `FirstEnrollmentRequest` carries `signingAlgo` and `metadataBuilder`,
  so the enrollment CRAM onboarding submits can be PQ-native from activation
  rather than only after a retrofit. `signingAlgo` defaults to `rsa2048` and an
  empty metadata map is dropped before the wire, so a legacy onboard is
  byte-unchanged. A builder additionally requires the request to carry the
  `atKeys` being enrolled — it both reads the APKAM keypair it signs with and
  writes the material it minted back into them, so handing it a copy would
  advertise an encapsulation key whose private half nobody kept. That is
  refused rather than allowed to succeed on the wire and fail on a read months
  later.
- feat: `KeyAlgorithmType.mlKem1024` — the key-material token for pure
  ML-KEM-1024 privates, alongside `xWing`. Additive, and the enum was already
  an open string set whose contract is never to reject an unknown value.
- fix: the `.atKeys` passphrase envelope derives its AES key from a random
  per-file salt. It previously passed **the passphrase itself** as the Argon2id
  salt, so derivation was deterministic — two users who chose the same
  passphrase got the same key, and one precomputation table served all of them.
  Argon2's memory-hardness still charged an attacker per guess, but the
  property that makes salting worth doing was absent. New envelopes carry
  `v: 1`, a 16-byte random `salt` and a `kdfParams` object, and use OWASP's
  current Argon2id floor (m=19456 KiB, t=2, p=1) rather than the old
  m=10000/t=2/p=2. Measured on an M-series Mac: 68.5ms against the old
  configuration's 18.4ms, so about 3.7x the work per guess for an unlock nobody
  will notice.
- **Compatibility:** envelopes without a `v` field keep the old derivation
  exactly, including its UTF-16 `codeUnits` salt, so every key file already
  written still opens. Those files cannot be rewritten from here, since the
  passphrase belongs to the user, so an individual file migrates when its owner
  next sets a passphrase. Note the converse: a file written by this version
  does **not** open in an older client. `encode` takes
  `legacyUnsaltedDerivation: true` for callers that must produce one that does.
- fix: `kdfParams` is read back off the file rather than assumed, so the
  Argon2id cost can be raised again later without orphaning files written now.
  The old format recorded no cost at all, which is why its parameters could
  never be changed.
- fix: a version 1 envelope can only be written with Argon2id. The `md5`,
  `sha256` and `sha512` arms are a single unsalted pass and give a passphrase
  almost no protection; they are still accepted on read so nobody is locked out
  of an existing file.
- feat: `AtSelfEnrollmentRequest` — the client half of the PQ self-retrofit.
  Submitted on an APKAM-authenticated connection with no OTP, it mints an
  ML-DSA-65 APKAM keypair (at most once per keyfile, serialised by an
  advisory lock sized for the network round trip), sends `enroll:request`
  with `signingAlgo:mldsa65` and the key package as metadata, and on the
  auto-approved response persists the new enrollment's material into the
  SAME keyfile as typed materials under the new enrollment id — the legacy
  flat fields untouched, so the original enrollment keeps authenticating
  until the atServer's expiry cap retires it.
- feat: `AtKeys.toAtChopsForEnrollment` and
  `AtKeys.signingAlgorithmForEnrollment` — AtChops built from an
  enrollment's typed signing material (sharing the keyfile's flat
  encryption keys), and `AtAuthImpl.authenticate` resolves them
  automatically: authenticating with a retrofitted enrollment's id
  ML-DSA-signs PKAM with no caller-supplied algorithm.
- fix: `FileAtKeysIo.write`/`flush` take an inter-process advisory lock
  (`<keyfile>.lock`, O_EXCL create) around the whole read-validate-write.
  The rename inside was already atomic and `validateMapUpdate` already
  *detects* a candidate that drops existing key material — but two processes
  sharing one `.atKeys` file that both read before either writes both pass
  validation, and the second rename silently discards the first's addition.
  The severe case is a conveyed namespace-key private that appears filed and
  is not: records that can never be read, presenting weeks later as
  corruption. Several CLI apps sharing one keyfile is the ordinary
  deployment, not an edge. A lock older than 30s is presumed abandoned and
  broken (a crashed holder must not deadlock every later run); acquisition
  waits up to 10s and then fails loudly, naming the lock file. Breaking claims
  the stale file by rename and re-checks its age before deleting — a bare
  delete could evict a fresh lock that replaced the corpse between the
  staleness check and the delete — and the lock file's content doubles as the
  holder's release token, so a holder whose lock was broken while it ran
  cannot delete its successor's lock on exit.
- feat: `AtEnrollmentRequest.keyExchangeMode` — an `EnrollmentKeyExchangeMode`
  choosing how the enrollment's `apkamSymmetricKey` travels. `legacy` (the
  default) is today's behaviour unchanged: the enrollee generates the key and
  RSA-encrypts it to the atSign's default encryption public key. `pq` reverses
  the direction — the approver mints the key and encapsulates it to the key
  package the request advertised, so **nothing RSA-wrapped rides the request**
  and an adversary recording it harvests no symmetric key. The default becomes
  `pq` in the next major version.
  Mode is deliberately explicit rather than inferred from whether a key package
  is advertised: a package is *also* how an approver seals this atSign's
  existing secrets to a new device, so every mode may carry one and its
  presence says nothing about how the symmetric key travels.
  `pq` additionally requires `AtEnrollmentRequest.apkamSymmetricKeyResolver`, a
  callback run inside `waitForApproval` once PKAM authentication succeeds,
  which collects the key the approver encapsulated. A `pq` request missing
  either the package or the resolver is refused before it reaches the atServer,
  rather than producing an enrollment that authenticates and can then decrypt
  nothing. `pq` needs an approver that conveys and an atServer that does not
  insist on the wrapped key, and fails closed against either.
- feat: `EnrollmentRequestDecision.approvedWithMintedKey` — approves an
  enrollment with a symmetric key the approver generated, for a request that
  sent none. The encryption private key and the self-encryption key are wrapped
  under it exactly as on the RSA path; only the key's origin and its route to
  the enrollee differ.
- feat: `AtEnrollmentRequest.metadataBuilder` — an optional callback, invoked
  once after this request's APKAM keypair has been generated and before the
  request is sent, with an `AtKeysIo` holding that keypair. Whatever it returns
  is attached to the request as `EnrollParams.metadata` unchanged; at_auth
  ferries it and never inspects it. It exists because some material must be
  **signed by the new APKAM key** — the secret-sharing key package is the first
  such case — and that is impossible for the caller to do alone: the keypair
  does not exist until the request is being assembled, and the metadata is only
  ever written by the request that creates the enrollment record, so it cannot
  be added afterwards either. The keys the callback receives carry **no
  `enrollmentId`**, because the atServer assigns that in its response to this
  very request; anything the callback builds must be valid without one. A
  callback that returns null or throws is logged and the request proceeds
  without metadata — the payload is opaque and additive, so failing an
  enrollment over it would be the worse outcome. Internally the `AtKeys` object
  is now assembled before the request is sent rather than after, since
  everything but the `enrollmentId` is already known at that point.

## 3.3.0
- feat: add `AtAuthSession` (exported) — the explicit auth→client hand-off artifact: the confirmed subset of an auth request that client creation actually needs (`atSign`, `rootDomain`, `namespace`, `atKeysIo`, `enrollmentId`), promoted to its own type so "request" no longer doubles as "session". Keys cross the boundary as an `AtKeysIo` *source*, not as live crypto state: the client derives its own `AtKeys` via `atKeysIo.read(atSign)` rather than adopting auth's `AtChops`/`AtLookUp`. The session also carries auth's already-authenticated `atLookUp` so a caller can *opt in* to reusing that connection (`AtClientManager.fromAuthSession(session, reuse: true)`) and skip a second PKAM handshake; the default hand-off rebuilds a fresh connection.
- feat: `AtAuthImpl.authenticate(...)` and `.onboard(...)` populate the new `AuthResponse.session` on success whenever the request supplied an `atKeysIo` — pass it straight to `AtClientManager.fromAuthSession(...)`. The legacy `atAuthKeys`-only path has no key source to hand across, so it gets no session and keeps behaving exactly as before.
- feat: `AtEnrollmentRequest` now takes a `session` (the requesting app's atSign, rootDomain and the `atKeysIo` its new keys will be persisted into) in place of the individual `atSign`/`rootDomain`/`apkamPublicKey`/`encryptedAPKAMSymmetricKey` params. On approval, `waitForApproval(...)` flushes the completed keyset into `session.atKeysIo` (when it is a `WrittenAtKeysIo`) and hands back a ready-to-use `AtEnrollmentResponse.session`. Supplying neither `session` nor the deprecated `atSign` throws `ArgumentError`. The legacy path (no session, or a read-only `AtKeysIo`) leaves `atAuthKeys` populated for the caller to persist and sets `session` to null.
- deprecation: everything the `AtAuthSession` hand-off replaces is marked `@Deprecated(... 'remove in v4')` and still fully functional in 3.3.0 — `AuthResponse` and its `AtAuthResponse`/`AtOnboardingResponse` subclasses, the `atAuthKeys`/`atLookUp`/`atChops` response fields, `AtEnrollmentResponse.atSign`/`.rootDomain`/`.atAuthKeys`, and the `AtEnrollmentRequest` params listed above. No runtime behaviour changed; this release is additive so consumers can migrate to `session` before at_auth 4.
- feat: add `AtKeysMaterial` — the only key type `AtKeys`'s API deals in (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`, `retireKey`, the `keysList` constructor param, ...). It's fully self-describing: `keyId`/`enrollmentId` plus `keyPartType` (an open `String` — the mechanical crypto role; known tokens in `CryptographicKeyType`: symmetric encryption/authentication and the public/private halves of encryption, verification/signing, encapsulation/decapsulation and key agreement), `keyAlgorithmType` (an open `String` — the algorithm family; known tokens in `KeyAlgorithmType`: `aes256`/`rsa2048`/`ecc_secp256r1`/`ed25519`/`x25519`/`mlkem768`/`mldsa65`/`xwing`, matching the pkam/enrollment `signingAlgo` literals), `bytes`, `operations`, `createdAt`, and `status` (`active`/`retired`/`dead`; `withStatus(...)` copies a material at a new status). Both token fields are deliberately Strings, not enums: unknown tokens are preserved and round-tripped, so a keyfile written by a newer client stays readable — and losslessly flushable — by an older one; whether an algorithm is classical, post-quantum or hybrid is carried by the algorithm token (e.g. `xwing`), not a separate role axis. The wire's nested `keys[].keyParts[]` document shape — grouping the materials sharing a `keyId` (e.g. the public+private halves of a keypair) — is produced/consumed by `encodeAtKeysDocument`/`parseAtKeysDocument` (also exported), not a separate model type. Keys produced by one enrollment are grouped by an optional `enrollmentId` and queried via `AtKeys.keysForEnrollment(...)`; at most one material of a given `CryptographicKeyType` may share an `enrollmentId`.
- feat: `AtKeys.toJson()`/`.fromJson(...)` now produce/consume the versioned typed-keys document shape (`version`, `atsign`, `keys`, with legacy fields flat at the top level — upgrading a legacy file to the typed-keys document is additive, not a format swap), replacing the former codec/resolver/document layer. Backward compatible: `fromJson` accepts json without a `version` field as the legacy flat shape, and throws `AtKeysUnsupportedVersionException` on an unknown version. Typed materials are looked up via `AtKeys.getKey(keyId, type)` and `.keysForKeyId(keyId)`.
- feat: add `WrittenAtKeysIo.flush(Atsign, AtKeys)` — the runtime persist operation: mutate the in-memory `AtKeys` (`addKey`, `retireKey`, ...), then flush the complete state. On an existing file, flush safety-checks the rewrite (`AtKeysAssurance.validateMapUpdate` — nothing may be lost: every existing `(keyId, keyPartType)` must survive with identical fields, though `status` may move forward `active` → `retired` → `dead` and new materials may be added), then rewrites; flushing a legacy `.atKeys` file upgrades it in place to the typed-keys document format (legacy fields preserved byte-for-byte). On a missing file, flush creates it. `write(...)` stays the create-only initial persist. (The `append`/`save` methods that existed briefly during this release's development are gone — never published.) `FileAtKeysIo` writes are atomic (write-to-temp + rename, so a crash can never truncate the keyfile) and a flush over an existing file first preserves it as `<file>.bak`.
- feat: `AtKeysAssurance` is now the single home for all atKeys validation — both the low-level `expect*`/`optional*` value/type checks used by `AtKeysMaterial.fromJson`/`AtKeys.fromJson`, and the structural invariants (`validateKeyMaterials`: duplicate `keyId`, one material of each `CryptographicKeyType` per enrollment, the flush-safety check `validateMapUpdate`).
- feat: add passphrase envelope support via `AtKeysPassphraseEnvelopeCodec` (`encode`/`decode`/`isEnvelope`, argon2id key derivation), and add `InMemoryAtKeysIo` for in-memory/test flows (both exported).
- fix: `AtKeys.==`/`hashCode` now also cover `atsign`, `metadata` (compared structurally — nested maps/lists by value, not identity) and the typed key materials (order-insensitive).
- chore(deps): require `at_chops` ^3.4.1 for hashing algorithm barrel exports used by AtKeys passphrase handling.
- fix: `RegistrarService` now fails loudly on a bad API key instead of reporting
  an ordinary negative result. The constructor throws `AtException` when `apiKey`
  is empty or whitespace-only, and every registrar call that requires
  authentication throws `AtException` naming the endpoint and status code when
  the registrar answers 401/403. Previously a rejected key surfaced as
  `sendActivationOtp()` returning `false` (or an empty atsign list), which is
  indistinguishable from a legitimate "no" — callers that treated a falsy result
  as an expected outcome will now see an exception (#1909).

## 3.2.0
- feat: bound `AtAuthImpl.validateAtServer` with a single overall deadline so a
  dead network can no longer hang authentication/onboarding. `RetryOptions` gains
  an optional `overallTimeout`; when null the default depends on the request:
  authentication uses `AtNetworkTimeouts.effectiveDefault` (30s) so a dead network
  fails fast, while ONBOARDING uses `AtNetworkTimeouts.defaultOnboardingTimeout`
  (5 min) because a newly-registered atSign can take minutes to be provisioned.
  The loop is deadline-driven — it retries every `retryDelay` until the budget is
  spent, then throws `AtTimeoutException`; each inner network call (the atDirectory
  lookup and the connectivity probe) is bounded by the remaining budget and capped
  at 60s. **`RetryOptions.maxRetries` no longer bounds this loop** (the deadline
  does) (#1923). Requires `at_commons ^5.13.0`.
- chore(deps): `at_lookup: ^3.6.0` — `validateAtServer` passes the `timeout`
  parameter that `SecondaryAddressFinder.findSecondary` gained in at_lookup
  3.6.0, so this version does not compile against at_lookup ≤3.5.x.

## 3.1.1
- refactor: route enrollment RSA (encrypt/decrypt `apkamSymmetricKey` under the default encryption keypair) through at_chops (`RsaEncryptionAlgo`) — `crypton` no longer imported in `lib` and moved to `dev_dependencies` (only the enrollment test still uses it for RSA keypair fixtures). Same framing, byte-identical by construction.
- fix: `decodeAtKeys()` now reliably throws `AtDecryptionException` on an incorrect passphrase. The `jsonDecode` of the decrypted bytes now runs inside the decrypt try/catch, so wrong-passphrase garbage no longer escapes as an uncaught `FormatException` (an intermittent failure in `at_keys_io_test`).

## 3.1.0
- feat: `validateAtServer()` now emits progress events and probes atSign connectivity before returning
- fix: `decodeAtKeys()` now throws when an invalid passphrase is provided
- fix: `FileAtKeysIO` now encrypts the key file with a passphrase when one is available
- fix: throws `AtAuthenticationException` when the atSign is already onboarded
- feat: use AtBytes.equals in `AtKeys` (requires at_commons: ^5.9.0)

## 3.0.1
- feat: improve `AtEnrollmentImpl`
- feat: introduce `NamespacePermission`
- fix: ensure directory when writing keys in FileAtKeysIo

## 3.0.0 

- chore(deps): at_chops ^3.0.0
- refactor: remove all singletons, injecting dependecies via `AuthRequest`
- feat: `AtKeysIo` interface which defines interaction between stored/generated keys and at_auth
- feat: `FileAtKeysIo` class which defines implementation
- feat: authentication returns `AtLookup` and `AtChops` via `AuthResponse`
- feat: `AtAuth` exposes a `ProgressStream` to consume status of at_auth

## 2.4.0

- chore(deps): at_commons ^5.5.0

## 2.3.0
- feat: add `AtLookUp? atLookUp` to the `AtAuth` interface so that it can be 
  reused (e.g. by AtClient) once auth is complete

## 2.2.0

- feat: enable callers of `AtAuth.onboard` to control post-auth activation
  completion (set the encryption public key on the server, delete the "cram"
  secret)

## 2.1.0
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 2.0.10
- fix: Replace legacy IVs with random IVs for encrypting "defaultEncryptionPrivateKey" and "selfEncryptionKey" in APKAM flow
## 2.0.9
- fix:Enable caching of encryption public key
## 2.0.8
- feat: Add "passPhrase" in "AtAuthRequest" to support password protected atKeys file
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.2
  - at_auth to v2.2.0
  - lints to v5.0.0
  - test to v1.25.8
  - mocktail to v1.0.4
## 2.0.7
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.0
  - at_lookup to v3.0.49
  - at_utils to v3.0.19
  - at_chops to v2.0.1
## 2.0.6
- fix: Add "apkamKeysExpiryDuration" to "EnrollmentRequest" to support auto expiry of APKAM keys
## 2.0.5
- fix: set atChops in atLookup before pkam auth in AtAuthImpl
- build[deps]: Upgraded the following packages:
  - at_commons to 4.0.11
  - at_lookup to 3.0.47
- feat: Add signing SigningAlgoType and HashingAlgoType in AtAuthRequest, AtOnboardingRequest
## 2.0.4
- fix: Add "revoke" to the "AtEnrollmentBase" to support enroll:revoke operation
## 2.0.3
- fix: Add optional parameters to the "atAuth" method in "AtAuthInterface"
## 2.0.2
- fix: set default value for app name and device name if they are not passed in the onboarding request.
## 2.0.1
- fix: deprecate enableEnrollment flag in OnboardingRequest and removed the check in AtAuthImpl
## 2.0.0
- build[deps]: Upgraded the following packages:
  - at_commons to 4.0.5
  - at_lookup to 3.0.46
- Implement new methods for enrollment operations within AtEnrollmentImpl and remove older methods.
- Enhance readability by renaming the current classes associated with EnrollmentRequest.

## 1.0.5
- build[deps]: Upgraded the following packages:
  - at_chops to v2.0.0
  - at_lookup to v3.0.45
## 1.0.4
- build[deps]: Upgraded the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_chops to v1.0.7
    - at_lookup to v3.0.44
## 1.0.3
- fix: upgrade at_lookup to 3.0.43 since 3.0.42 has breaking change for private key reference
## 1.0.2
- feat: enrollment common code from at_client_mobile and at_onboarding_cli
- chore: upgrade at_lookup to 3.0.42 and at_demo_data to 1.0.3
## 1.0.1
- feat: Introduce "submitEnrollment" and "manageEnrollment" methods for APKAM
## 1.0.0
- Implemented onboard and authenticate methods.
