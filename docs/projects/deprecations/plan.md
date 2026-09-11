# Deprecation debt across the release train

The packages in this workspace don't publish while their own code and tests
carry hundreds of `deprecated_member_use` warnings. This plan takes them to
zero, package by package, in an order the dependencies allow.

Every figure here came from `dart analyze`, never from a grep: the deprecated
members are reached through many differently-named receivers, and only the
analyzer resolves a receiver's type. Re-derive before acting on any of them:

```bash
# EVERY member, enumerated from the root pubspec rather than hand-listed: a
# hand-listed set is how the 2 CLI packs were recorded at zero while one held
# 47. at_client_flutter needs the Flutter analyzer, which dart analyze is not.
for p in $(sed -n '/^workspace:/,/^[a-z]/p' pubspec.yaml | sed -n 's/^ *- *//p'); do
  [ "$p" = packages/at_client_flutter ] && continue
  (cd $p && printf '%-46s %4s\n' $p \
    "$(dart analyze 2>/dev/null | grep -c deprecated_member_use)")
done
(cd packages/at_client_flutter && printf '%-46s %4s\n' packages/at_client_flutter \
  "$(flutter analyze --no-pub --no-fatal-infos | grep -c deprecated_member_use)")
# a member's own split, from inside it: dart analyze lib | test | example | tool
# per symbol, from any of the above analyses saved to a file:
#   grep deprecated_member_use an.txt | sed -E "s/.*'([^']+)' is deprecated.*/\1/" | sort | uniq -c | sort -rn
```

The per-symbol and per-file counts quoted below all come from that last
line run over the analysis they describe, on 2026-09-11.

Line numbers in this plan are as of 2026-09-11 and will have moved; the
symbols beside them are the addresses.

## The acceptance gate

`dart analyze --fatal-infos lib test` exits 0 in every Dart member of the
workspace, `flutter analyze` reports no `deprecated_member_use` in
at_client_flutter, and the 4 live packs (`tests/at_functional_test`,
`tests/at_end2end_test`, `tests/at_onboarding_cli_functional_tests` and
`tests/at_onboarding_cli_functional_tests_proxy`) are green.

The workspace is the 17 members the root `pubspec.yaml` lists: 12 packages,
the 4 live packs and `tools/wasm_shakedown`. Of those, at_commons, at_utils,
at_chops, at_lookup, at_server_status, at_policy, at_cli_commons,
`wasm_shakedown` and the CLI *proxy* pack are at zero today.
⚠️ `tests/at_onboarding_cli_functional_tests` is **not**: it holds 47, all in
`test` — 22 `AtClientPreference` storage fields, 6 `isLocalStoreRequired`, 4
`AtLookupImpl`, 8 flat keyfile fields and 7 keyfile accessors. This plan
recorded both CLI packs at zero until 2026-09-11, because the re-derivation
loop above hand-listed 6 members and reached neither.
The other `packages/*_flutter` directories are not members; the 10 of them
with a `lib` carry 17 between them (at_events_flutter 6, at_follows_flutter 3,
at_contacts_group_flutter 2, at_login_flutter 2, one each in at_chat,
at_contacts, at_location and at_theme; count with
`for d in packages/*_flutter; do (cd $d && flutter analyze --no-pub --no-fatal-infos | grep -c deprecated_member_use); done`),
none in this plan's families, and 4 of them fail `flutter analyze` for
unrelated reasons. They are listed so the figure is true, not because this
plan clears them.

## 1. Where the debt is

| member                              | in-tree version | lib | test |
| ----------------------------------- | --------------- | --: | ---: |
| at_auth                             | 4.0.0-rc2       |  56 |   86 |
| at_client                           | 3.15.0-rc1      |  46 |  359 |
| at_onboarding_cli                   | 1.17.0-rc1      |  31 |  239 |
| at_client_flutter                   | 1.1.5-rc1       |   7 |   41 |
| tests/at_functional_test            | (unpublished)   |   6 |  272 |
| tests/at_end2end_test               | (unpublished)   |  45 |   80 |
| tests/at_onboarding_cli_functional_tests | (unpublished) | 0 | 47 |
| at_contact                          | (see pubspec)   |   0 |    4 |

1319 uses, down from 1403 when this plan was written. The right-hand column is
everything outside `lib` that the member's
own `dart analyze` sees, so it carries at_auth's and at_client_flutter's 1
`example` use each, at_onboarding_cli's 35, and at_client's 1 in `tool` — the
figure a CI analyze step would report, rather than a `lib`-plus-`test` subset.
The table read 1317 on 2026-09-11 before [step 0](#step-0-done-at_auth-stops-deprecating-what-it-has-no-replacement-for), and it was wrong
in three ways beyond that: it gave the two live packs 0 in `lib` where they
hold 6 and 45, it omitted the CLI pack's 47 entirely, and it counted only
`lib` and `test`.

The test figures are downstream of the lib figures almost entirely:
a test names `AtChops` because the client it builds takes one, and it stubs
`atLookUp.enrollmentId` because production reads it. The tests clear when the
libs clear, so this plan's steps are lib steps and each member's tests fall in
behind its step. The two live packs are the biggest single consumer of the
surface being removed, and they are members, so they clear in step 6 rather
than being a blast radius.

⚠️ One class of use the analyzer cannot show: `deprecated_member_use` is
silent inside the package that declares the member, so at_client's own 30
test files that set `AtClientPreference.hiveStoragePath` report nothing, and
at_client's own `sync:` declarations likewise. Those are found by grep, or by
the compiler once the member is deleted.

## 2. Five families, not one

The 1317 uses are 5 unrelated deprecations that happen to arrive together.

A triage on 2026-08-26, kept as [section 14.11 of the PQ plan](../pq/implementation-plan.md#1411-deprecated_member_use-findings-across-the-workspace),
split the same debt into lettered buckets and ruled that only the
credential-ladder bucket (its B) was D1 work, with the at_auth response
family (its D) waiting for v5; the bucket table itself was cut from the live
plan on 2026-08-23. gkc's ruling of 2026-09-11 supersedes that reading: all of
it gates publication. The 5 families below replace the buckets as the
partition, and F2 is that triage's B and F3 its D. Its two cautions survive
where they bite, in step 2.

### F1, the AtChops compatibility API (declared in at_chops)

`AtChops`, `AtChopsImpl`, `AtChopsKeys`, `AtChopsUtil`, `AtEncryptionKeyPair`,
`AtPkamKeyPair`, `AtEncryptionResult`, `AtSigningInput`, `AtSigningMode`,
`AtSigningResult`, `PkamSigningAlgo` and `RsaSigningAlgo`. Every one says
*"removed in the next major release"*, and together they are the bulk of every
package's count.

AtChops plays two roles in this tree, and they come apart differently. As an
*engine* it encrypts, decrypts and signs (`encryptString`, `decryptString`,
`sign`). at_client makes 9 encrypt and decrypt calls on it, and 6 of them pass
their own `encryptionAlgorithm:`, so for those the wrapper's whole contribution
is `utf8.encode` on the way in and `base64.encode` on the way out, and that
part of the role can go today with no new API anywhere. The other 3
(`legacy_encryption.dart:134` and `:152`, `legacy_decryption.dart:232`, all
`EncryptionKeyType.rsa2048`) pass no algorithm and let AtChops pick RSA using
its own encryption key pair, which makes them carrier uses in disguise. As a
*carrier* it is the object that gets key material from a keyfile to the code
that uses it (`atChopsKeys.atPkamKeyPair`, `atChopsKeys.selfEncryptionKey`).
`AtKeys` hands out `CryptographicMaterial` (a role, an algorithm and bytes)
and, for signing keys, `signingKeysFor` returns the algorithm with the public
and private halves as strings, which `apkam_signing.dart` already reads. What
it lacks is the same getter for the authentication and encryption key pairs: the
only members that yield those as usable objects are `toAtChops()`,
`toAtChopsForEnrollment()` and `authenticationFor()`; the first two return an
`AtChops` and the third a record carrying one beside the algorithm. That gap
is what step 3 builds, and the place to build it is at_auth.

### F2, the AtLookUp credential ladder (declared in at_lookup)

`atLookUp.enrollmentId`, `.atChops`, `.signingAlgoType`, `.hashingAlgoType`
and `AtLookupImpl`. The replacement exists and is in use: at_auth's
`authenticatorForChops()` and `authenticatorFor()`, which `RemoteSecondary`
already installs. What remains are readers asking the *network object* which
enrollment the *client* is.

The consolidation plan holds the full enumeration and two cautions, in
[its own section](../at-lookup-consolidation/plan.md#blocks-the-major--atlookupenrollmentid-has-51-uses-not-the-7-first-recorded).
What this plan adds is the equivalence that makes the move safe, read from two
sites in `at_client_impl.dart`: `buildRemoteSecondary()` passes
`enrollmentId: enrollmentId`, the client's own field, and
`_rederiveFromEnrollment` rebuilds the remote after the retrofit reassigns
that field. The lookup's id is therefore a copy of the client's, taken at
construction and again at rederive, and `remote_secondary.dart` holds the only
writer. Reading the client's field is reading the source. Step 5 turns that
reading into a probe before anything moves.

In tests it isn't equivalent. `apkam_authorization_test` sets
`atClient.enrollmentId = …` after construction without rebuilding the remote,
so the lookup keeps its old value. Moving the readers changes what those tests
observe, which is the exposure to expect rather than a regression.

### F3, the flat keyfile fields (declared in at_auth)

`AtKeys.apkamPublicKey`, `.apkamPrivateKey`, `.apkamSymmetricKey`,
`.defaultEncryptionPublicKey`, `.defaultEncryptionPrivateKey`,
`.defaultSelfEncryptionKey` and `.enrollmentId`, whose annotation says
*"hard-coded keys are legacy, see new methods"* and names no version; and
`atAuthKeys`, `atSign` and `rootDomain` on the request and response models,
which point at `session`. So at_auth has scheduled the model fields past its
current major and left the flat fields' removal unstated.

432 uses after [step 0](#step-0-done-at_auth-stops-deprecating-what-it-has-no-replacement-for): at_onboarding_cli 15 in `lib`, 150 in `test`
and 18 in `example`; at_client_flutter 7 and 40; at_end2end_test 21 and 53;
at_functional_test 107 in `test`; at_client 3 and 18. The typed replacement is
`AtKeys`'s `CryptographicMaterial` surface, which the CLI already uses on its
PQ paths.

⚠️ **That replacement reaches a typed keyfile only.** `AtKeys.fromJson` sends a
document with no `version` field to the legacy decoder, which fills the flat
fields and `metadata` and files no `CryptographicMaterial` at all — so for a
legacy keyfile the flat fields are the only reader there is.
`at_keys_test.dart`'s *"a legacy document files no typed material"* pins it,
with a typed document as its control: the legacy fixture decodes to an empty
`keys`, an empty `atSignKeys`, no enrollment ids and an empty
`keysForEnrollment`, while the flat field holds the value.
`holdsAuthenticationMaterial` answers true there only by falling back to the
flat `apkamPrivateKey`. Every site that reads or writes a legacy keyfile is in
this position: the CLI's `_generateAtKeysFile` and
`_persistKeysLocalSecondary`, at_client_flutter's keychain atSign fallback,
and every test that builds a legacy fixture.

### F4, the inert `sync:` flag (declared in at_lookup)

Already written up as [section 14.46 of the PQ plan](../pq/implementation-plan.md#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries), which
enumerates all 6 declarations, at_lookup's 2 and at_client's 4, and holds the
4.0 deletion. What this plan adds is only the count that matters here: the 3
remaining uses are all in at_auth's tests (`enrollment_test.dart:41` and
`:108`, `first_enrollment_test.dart:196`), all of at_lookup's flag, all
deletable now.

### F5, the `AtClientPreference` storage fields (declared in at_client)

`isLocalStoreRequired` (*"LocalStore is always required"*), `hiveStoragePath`
(*"Supply an `AtClientStorage` instead"*) and `commitLogPath` (*"Nothing reads
this; the client is commit-log-free"*), all removed in the next major. Visible
to the analyzer only outside at_client: 12 in `tests/at_functional_test`, 7 in
`tests/at_end2end_test`, 4 in at_contact's `test_util.dart` and 1 in
at_client_flutter. Inside at_client the analyzer is silent, and 30 of its
own test files set `hiveStoragePath`; those are found by
`grep -rl hiveStoragePath packages/at_client/test`. The replacement is the
`storage:` argument to `AtClientImpl.create`, which chooses backend and
location together, with `closedByClient: true` where the client is meant to
close it.

## 3. Decisions this plan needs, and the ones it makes

Made here: the carrier replacement is typed getters on `AtKeys`, not a new
wrapper type. `CryptographicMaterial` already carries role, algorithm and
bytes, and what's missing is the last step from bytes to an algorithm object;
`signingKeysFor` already takes it for signing keys.
at_auth's `4.0.0` line is in prerelease (`4.0.0-rc1` is on pub.dev, `4.0.0-rc2`
is in tree), so adding those getters and changing `authenticationFor`'s return
type are changes between release candidates inside a major, not a new major.

Made here: removing `AtChops` from at_client's public surface is a major.
That surface is `AtClient.atChops` (getter and setter),
`AtClientImpl.create(atChops:)`, the 3 `AtClientManager` parameters and
`RemoteSecondary.atChops`, and at_client is at `3.15.0-rc1`. So the plan takes
at_client to zero internal uses, marks the public surface `@Deprecated` in
3.15 with the replacement named, and removes it in 4.0. The in-tree blast
radius of that removal is small and measured: none of the 11 Flutter packages
that have a `lib` directory (330 Dart files) names `atChops`, while
`at_client_mobile` and `at_onboarding_flutter` have no `lib` and no tracked
files in this checkout at all; and at_tools, working tree on `trunk`, names
neither `atChops` nor `AtChops` in any of its 40 Dart files. The 4 live packs
are the largest in-tree consumer of the surface (`enrollment_setup.dart` in
the e2e pack sets `atLookUp.atChops`, builds an `AtChopsImpl` and calls
`AtAuth.create(atChops:)`), and they are workspace members, so they move in
step 6 rather than counting as blast radius. The consumer that removal does
break is whoever builds a client from a preference alone with an injected
`AtChops`, which is the bridge the consolidation plan already holds open.

Settled by the code on 2026-09-11 rather than by gkc: at_chops does not
export `AtHashingAlgorithmFactory`. The factory carries a deprecation of its
own — *"Instantiate hashing algorithm classes directly instead"* — so it was
never the replacement this plan read it as, and no deprecation in at_chops
names it. Exporting it would have frozen a name already scheduled for
removal and handed a consumer a warning on arrival. at_client maps the
runtime type itself, in [step 1](#step-1-at_clients-two-hashing-calls-leave-atchopshashwith).

Ruled by gkc on 2026-09-11: F3 clears in this pass, and the annotations with
no replacement behind them come off first. 45 of the family's 477 uses could
not be cleared by a consumer at all. 31 name `AuthResponse`,
`AtOnboardingResponse` or `AtAuthResponse`, which `AtAuth.authenticate` and
`AtAuth.onboard` return while carrying no deprecation themselves, so a caller
that names the return type in its own signature — as at_client_flutter's
service class does — had nothing to move to. The other 14 name
`AtKeys.metadata`, whose annotation promises new methods that do not exist.
[Step 0](#step-0-done-at_auth-stops-deprecating-what-it-has-no-replacement-for) narrows both; the remaining 432 are consumer work, in steps 6
and 7.

For gkc, and new on 2026-09-11: whether at_auth files a legacy keyfile's flat
material as `CryptographicMaterial` on read. The paragraph under F3 measures
that it does not, which leaves every legacy-handling site with no replacement
to move to — so steps 6 and 7 cannot reach zero by rewriting alone. Filing it
would make the flat fields genuinely redundant and let all 432 clear, at the
cost of changing what a legacy document becomes in memory, which the round-trip
pins govern. The alternative is that those sites keep the flat fields under an
ignore naming the reason, and only the typed-keyfile sites move. The split
between the two is not yet counted.

## 4. Order of work

Each step lands with its own gates (`dart analyze --fatal-infos` on the
changed package, the unit suite, and the format gate under CI's Dart in
Docker), and each step's test tree clears in the same commit as its lib. A
step that touches a lifecycle seam runs all 4 live packs before it commits.

**Where this stands on 2026-09-11.** The workspace measured 1206 uses, from
1403, before the keyfile and lookup-wiring changes below landed in at_auth; that
figure is re-derived, never trusted. Steps 0, 1 and 2 are done; step 3 has its
accessors, its signing path, its keyfile self-encryption, its lookup wiring,
its approval key material and its handshake, with 16 `lib` uses left in
at_auth; step 4 has its key-material half, which is what unblocked at_client's
test tree. What is owed, in order: the rest of at_auth's 16, then the rest of
step 4 (`apkam_signing`, `sync_service_impl`, and
deprecating `AtClient.atChops` itself), then steps 5 to 7. Step 7 is no longer
blocked by the legacy question, which step 3 answered, but it is blocked on the
three at_client_flutter readings recorded under it.

**What has been built, so it is not built again.** Four things this plan now
depends on:

- **`AtKeys.authenticationKeyPairFor`, `.encryptionKeyPair`, `.selfEncryptionKey`**
  (at_auth) — the typed form of what an `AtChops` carried. The last two prefer
  typed atSign material and fall back to the flat fields, so key material can
  be both written and read without naming a deprecated member.
- **`signPkamChallenge`** (at_auth's `at_authenticator.dart`) — signs a PKAM
  challenge, or an `enroll:update` possession proof, from a keypair. Both call
  it, which is how their framing is kept identical.
- **`typedKeyfile`** (at_client's `test/test_utils/ml_dsa_keyfile.dart`) — an
  `InMemoryAtKeysIo` holding an `AtKeys` filed entirely through `addKey` and
  `fileApkamMaterial`, for `AtClientImpl.create(atKeysIo:)`. `mlDsaKeyfile` is
  its narrow case.
- **`stubEncryptionKeyPair`** (at_client's `test/test_utils/mocks.dart`) — the
  same thing for a mocked client: it answers the local secondary's key
  getters, which is where a client looks.
- **`ApproverKeyMaterial` and `approve(approverKeys:)`** (at_auth) — the
  key-material form of what the approver read off an `AtChops`. at_client
  fills it from `LocalSecondary`'s three-tier getters, so a client built from
  a keyfile approves without ever holding an `AtChops`.
- **`test_utils/pkam_pin.dart`** (at_auth) — the one home of the
  openssl-captured PKAM signature and its challenge, so every path that signs
  a PKAM challenge is held to the same bytes; `at_authenticator_test.dart` and
  `enrollment_handshake_test.dart` both assert it.

⛔ A fixture helper is only worth having if it goes through the replacement.
One that wrapped the deprecated construction would drop the count while
leaving the new path exercised by nothing, which is the opposite of the point.
(gkc, 2026-09-11.)

### Step 0 (done): at_auth stops deprecating what it has no replacement for

The deprecation on `AuthResponse`, `AtOnboardingResponse` and `AtAuthResponse`
moves onto the fields that have replacements, and `AtKeys.metadata` loses its
annotation; at_auth `4.0.0-rc2` carries both, with its CHANGELOG entries. 45
uses cleared across at_onboarding_cli, at_client_flutter and the two live
packs, and every other deprecation in those members still reports — 1317
before, 1272 after. The same commit adds the legacy-document pin that the
second decision above rests on.

### Step 1: at_client's two hashing calls leave `AtChops.hashWith`

`AtChops.hashWith` is a static on the deprecated `AtChops` class, so both of
at_client's callers were naming it. `legacy_encryption.dart` now hashes with
`SHA512HashingAlgo` directly, and `legacy_decryption.dart` maps a record's
`pubKeyHash.hashingAlgo` through an exhaustive switch over `HashingAlgoType`:
every arm's class is exported and none is deprecated. 2 uses cleared,
at_client 419 to 417.

The suite covers both sites as a pair. Hashing the write with sha256 instead
reddens 3 tests in `legacy_shared_key_encryption_test.dart` and
`legacy_encryption_decryption_test.dart` on *"Public key has changed"* —
which is the reader recomputing what the writer stored, through the switch.

### Step 2: at_client's engine role (no API change)

**A shared fixture helper, built on the non-deprecated path** (gkc,
2026-09-11): `typedKeyfile` in at_client's test utils returns an
`InMemoryAtKeysIo` holding an `AtKeys` whose material is filed through
`addKey` and `fileApkamMaterial` — no deprecated member is named building it —
and a test passes it as `AtClientImpl.create(atKeysIo:)`, which derives the
client's own `AtChops` the way production does. `mlDsaKeyfile`, which
predated it, is now the narrow case of it. `at_client_impl_test.dart`'s 12
client constructions moved onto it: 25 warnings to 0 in that file, and 12
constructions that exercise the derivation instead of bypassing it with a
mock. ⚠️ The helper is only ever right if it builds through the replacement:
one that wrapped the deprecated construction would leave the new path
exercised by nothing and the count would fall anyway.

**The encryption half is done.** The 6 `encryptString` and `decryptString`
calls that already passed an algorithm now call the `AESEncryptionAlgo` and
`RsaEncryptionAlgo` objects they build, through two helpers in
`crypto/legacy/string_crypto.dart` that carry the `utf8` and `base64` steps
the wrapper did. The helpers keep the wrapper's exception mapping rather than
inlining the conversions 6 times: every call site handles
`AtEncryptionException` or `AtDecryptionException`, and a direct call would
have thrown the cipher's own type past those handlers and lost the `severe`
log with it. `AtEncryptionResult` left with them, which is where the 5 cleared
warnings came from — the calls themselves named no deprecated member, because
they reach `AtChops` through `AtClient.atChops`, which step 4 deprecates.
Both legacy files now report zero. at_client's `lib` is 58 to 51.

The suite covers the helpers: returning the decrypted bytes reversed instead
of utf8-decoding them reddens 15 tests.

The 3 `rsa2048` calls that pass none wait for step 4, since they need the
encryption key pair.

**The signing half is done too**, and it is not the rename it looks like:
`RsaSignatureAlgo` is built by `.rsa2048()` or `.rsa4096()`, takes its key
per call as DER bytes rather than in the constructor, and has `verifyBytes`
rather than `verify`. Both sites in `envelope_signature.dart` moved, and so
did `_signPublicData` in `put_request_transformer.dart`, which carried
`AtSigningInput`, `AtSigningMode` and `atChops!.sign` between them.
`signBytes` is async where the old `sign` was not, and `signEnvelope` is
synchronous by design, so at_chops gained `RsaSignatureAlgo.signBytesSync` —
the pair `MlDsa65PureDartAlgo` already had, for the same reason. at_client's
`lib` is 51 to 46, and `benchmark` 2 to 0.

**Both signatures are byte-identical across the move, measured rather than
argued.** The committed JWS vector re-signs to the same envelope, and a probe
that signed one value with both classes and the same key printed equal
base64. `dataSignature` had no pin at all — `put_request_test.dart` mocked
`atChops.sign` and then compared two mocked values with each other — so this
step adds one: a fixed private key, a fixed value, and the base64 signature
as a raw literal. Signing it under sha512 instead reddens that pin with both
strings in the failure.

Two decisions the plan left open, both settled here.

**Off-size RSA keys are refused, rather than carried over.** `RsaSignatureAlgo`
throws when a key's modulus is not its constructor's size, where
`RsaSigningAlgo` checked nothing. Envelope signing is rsa2048-only —
`_joseAlgFor` returns nothing for any other RSA size, so `signEnvelope` throws
before the algorithm is reached — which means the check can only fire on key
material that disagrees with the algorithm its own envelope names. A signature
made that way never verified against a reader that trusts the label, so the
refusal turns a silent cross-implementation failure into a local error.

**The public-data signature signs with the caller's encryption private key**,
not with an APKAM signing key. The plan read `_signPublicData` as moving to
`ApkamSigning.authenticationSigningKey`; that would have changed which key a
reader must verify against, which is wire-breaking. `AtSigningMode.data`
resolves to `DefaultSigningAlgo(atChopsKeys.atEncryptionKeyPair, sha256)`, so
the key is and stays the encryption private key — and the method already
received it as a parameter it did nothing with but null-check. It uses that
parameter now, which drops one more reader of `AtChops`.

Still owed by this family, and nowhere else in the plan: nothing
non-deprecated dispatches from a `SigningAlgoType` to an algorithm the way
`AtChopsImpl.sign` does, so any *other* path that asks AtChops to choose
between RSA and ML-DSA has to write that two-way branch itself
(`MlDsa65PureDartAlgo` is the PQ half). Neither site in this step needed it:
the envelope already switches on the type, and public data is RSA by
definition.

Already done in this pass: the `AtChopsUtil` IV and symmetric-key helpers
became the key classes' own statics (12 uses).

### Step 3: at_auth builds the carrier (inside 4.0.0-rc2)

**The getters are built.** `AtKeys.authenticationKeyPairFor` is the typed form
of `authenticationFor` — same resolution, same refusal, returning the
algorithm and both halves instead of an `AtChops` — and `.encryptionKeyPair`
and `.selfEncryptionKey` give the rest of what one carried, as `RsaKeyPair`
and `AESKey`. `toAtChopsForEnrollment` is now `@Deprecated` beside
`toAtChops`, both naming the three.

⚠️ **Only the APKAM pair has a typed source.** Nothing in at_auth or at_client
files an atSign encryption keypair (`publicEncryption`/`privateDecryption`) or
a self-encryption key (`symmetricEncryption`) as typed material — measured by
grepping the role tokens for writers, which found only the vocabulary that
defines them. So those two getters read the flat fields, and a typed branch
would have been code nothing produces. The dartdoc says so and names what a
writer would have to change. This is also the answer to the legacy question in
[section 3](#3-decisions-this-plan-needs-and-the-ones-it-makes): the getters
are where the legacy shape is known, so a consumer moves onto them and the
flat fields stay a detail of at_auth rather than becoming typed material.

⚠️ **Deprecating a method hides its own uses.** `toAtChopsForEnrollment`
carried 6 deprecated uses, and annotating it dropped at_auth's `lib` count from
62 to 56 without one of them moving — a deprecated member used inside a
deprecated declaration raises nothing, the same way `KeyIOMixin`'s 13
`AtChopsUtil` calls never appeared. The acceptance gate below is satisfiable by
annotating rather than fixing, so a step that reports a drop has to say which
kind it was.

**What remains of this step**, measured 2026-09-11, is 16 uses in `lib` and 73
in `test`, from 56 and 92 (`dart analyze` in `packages/at_auth`, counting the
`deprecated_member_use` lines by path). Twelve of the test uses are in
`auth_wiring_test.dart` on purpose: it asserts that `atChops` and
`signingAlgoType` are never written on a lookup that takes an authenticator
and are written on one that cannot, and a test cannot assert a member is
untouched without naming it. One more is `approver_key_material_test.dart`'s
arm through the deprecated `approverChops` door, which stays until the major.

| file | uses | what they are |
| ---- | ---: | ------------- |
| `at_authenticator.dart` | 8 | the two injected-signer branches, and `AtChops` in three signatures |
| `at_auth_impl.dart` | 5 | the `AtAuth.atChops` field, and the `AtChops` onboarding builds to fill it; both go with that field's deprecation |
| `at_auth.dart` | 2 | `AtAuth.atChops`, the interface field |
| `at_keys.dart` | 1 | `authenticationFor`'s return type |

Deprecated names are ignored with their reason rather than counted in three
places, each of which exists only for a lookup without the authenticator seam
or a caller that has not moved: the two credential ladder writes inside
`AtAuthImpl._installAuthenticator`; `EnrollmentHandshake._installLadder`,
which builds the ladder's `AtChops` around the APKAM keypair alone; and the
approver's read of `atLookUp.atChops`, the door a caller that has not moved to
`approverKeys` still comes through. The handshake's seven are gone: it hands
`authenticatorFor` the enrollee's keys alone, since `authenticationKeyPairFor`
reads only the APKAM keypair and those keys always hold it, and
`enrollment_handshake_test.dart` asserts the openssl PKAM pin on the
handshake's own authenticator and verifies an ML-DSA enrollment's signature
with at_chops' verifier. Its write of the unwrapped symmetric key onto its own
`AtChops` was removed first, alone, and every test stayed green: nothing read
it.
The approver's own four are gone: `approve` takes `ApproverKeyMaterial`, the
encryption private key and self-encryption key that are all it reads, and
`approver_key_material_test.dart` opens what it seals with the enrollee's own
`StringAESEncryptor`, a different AES implementation from the one that seals.
The `@Deprecated` on `approverChops` is what cleared the three signatures: the
analyzer treats a parameter's own type annotation as inside the deprecated
declaration. `file_io.dart`'s three are gone: the keyfile's legacy fields
are self-encrypted through `AESEncryptionAlgo` directly, and
`legacy_field_self_encryption_test.dart` pins the at-rest bytes against
openssl and re-encrypts the committed legacy fixture byte-for-byte.

⚠️ **The two injected-signer branches in `_pkam` are the ones to leave until
the live packs run.** One of them names the algorithm precisely because the
keyfile cannot answer — a PQ-native activation signs with a keypair minted
moments before, under an enrollment the atServer has not created — and that
resolution is exercised by no unit test. The rest are reachable from unit
tests. `AtAuthImpl.authenticate` no longer feeds them: it hands
`authenticatorFor` only a signer the caller injected through
`AtAuth.create(atChops:)`, so at_auth's own mainstream authentication signs
from the keypair, and `onboard` is the branches' last caller. The bytes are
identical by design, so `auth_wiring_test.dart` holds the openssl PKAM pin on
the authenticator `authenticate` installs and holds that an injected signer
still wins; which branch of `_pkam` ran is not observable from outside and is
not claimed.

**The method that worked, for whoever picks this up.** Every change to a
signing or key-resolution path went: capture the wire bytes with an
independent instrument first (`openssl dgst` for RSA, or a verifier that
mimics the atServer), see the pin green against the OLD code, change, see it
green again, then mutate the change and read the failure message. Three
findings came out of the mutation step and none would have come out of the
diff. ⛔ Never annotate a use to make the count fall: an ignore is for a use
that is decided and stated, and the plan says which those are. The enrolment handshake now installs an authenticator and falls back
to at_lookup's ladder only for a lookup that cannot take one; it used to set
both, and the lookup prefers the authenticator, so the ladder fields were
written and never read.

⚠️ **That wiring was covered by nothing**, and the check that found it is
worth repeating elsewhere: removing the authenticator outright left every
handshake test green, because the lookup is mocked past the point where it
would be used. A test asserting which wiring is installed catches it now, and
`AtAuthImpl.authenticate` and `onboard` were moved the same way with the same
test shape, `auth_wiring_test.dart`, each arm mutated. Any other place this
plan moves an authentication seam deserves the same mutation before it is
believed. The PKAM signing path and the possession proof moved (above), and the
12 inside the two private `AtChops` assemblers are now ignored with their
reason rather than counted: their only caller is the deprecated `toAtChops`,
so they are the carrier being built and leave with it. What is left is
in the table under "What remains of this step" above, which is its one home.
Then `AtAuthResponse.atChops` and `AtAuth.atChops`
go `@Deprecated` beside `atAuthKeys`, which is where a consumer should have
been reading all along.

**The PKAM signing path is done**, and it is the first production caller
`authenticationKeyPairFor` has. Where the keyfile is the whole answer — the
mainstream case, and `authenticatorFor`'s — `_pkam` now takes the keypair and
signs it with `RsaSignatureAlgo` or `MlDsa65PureDartAlgo` directly, taking the
algorithm from the material rather than from a caller. The bare-private-key
authenticator does the same. The two injected-signer branches deliberately do
not: an injected `AtChops` is the shape that injection exists for, and one of
them names the algorithm precisely because the keyfile cannot answer, which is
a resolution only the live packs exercise.

⚠️ The PKAM signature is a wire contract and had no pin. It has one now, and
it is worth copying: the expected base64 was captured with
`openssl dgst -sha256 -sign <key> -keyform DER`, so it does not come from the
code it checks. It was green against the old signing before the change and
green after, which is how byte-identity was established rather than argued;
signing the challenge under sha512 instead reddens it with both strings in the
failure. at_chops' barrel now exports `MlDsa65Sizes`, because the diagnostic
that names a mismatched enrollment needs the FIPS 204 length.

⚠️ This is the authentication path, so the rest of this step still cannot land
on unit-green: all 4 live packs before the PR. Nothing here has run them.

### Step 4: at_client's carrier role (no API change)

**The key-material half of this step is done**, and it was indeed what
unblocked at_client's test tree. `LocalSecondary`'s three encryption getters
gained the client's key source as a middle tier, the legacy self-key paths
stopped reaching into `atChops` before falling back to them, and the three
`rsa2048` calls step 2 left behind now build their algorithm from that
material — unwrapping with the private half alone, which is all RSA decryption
reads. `stubEncryptionKeyPair` in the test utils is the fixture side: it
answers a mock local secondary's key getters, which is where a client looks.
at_client's test tree went 358 to 268 and its five legacy-crypto files to
zero.

What remains of step 4 is the rest of the plan's list below — `apkam_signing`,
`sync_service_impl`, the `AtChopsKeys` getter on `LocalSecondary`, and
deprecating `AtClient.atChops` itself.

Two observations from flipping the fixtures that could move:

- A client whose only key source answers an **empty** `AtKeys` throws
  *"PKAM mode requires defaultEncryptionPrivateKey"* out of `_createAtChops`.
  `StubAtKeysIo` in at_client's test utils answers exactly that, so it only
  ever worked beside an injected `AtChops`, and three tests using it went red
  the moment the injection came out. A stub that cannot carry a client through
  construction is not a stand-in for a key source.
- `AtClientPreference.hiveStoragePath` and `commitLogPath` raise nothing
  inside at_client, so flipping its own fixtures onto `storage:` is invisible
  to the analyzer and still worth doing — the 30 files the plan names are
  found by grep, not by a count.

With step 3's getters available, `apkam_signing.dart`'s
`authenticationSigningKey` reads the enrollment's authentication keypair from
`atKeysIo`, as `heldSigningKeys` in the same file already does.
`LocalSecondary.atChopsKeys` and the "from atChops if we have it" branch in its
4 key getters go; the getters read the keystore, and the callers that need
keyfile material (`legacy_*`, `encryption_service.dart`) take it from
`atKeysIo`, and the 3 `rsa2048` encrypt and decrypt calls step 2 left behind
build their `RsaEncryptionAlgo` from that key pair. `sync_service_impl.dart`
stops handing `atClient.atChops` to sync's
own `RemoteSecondary`, since `_installAuthenticator` derives from the keyfile.
`_createAtChops` shrinks to its Hive branch alone (that branch is the
preference-only bridge), and the only remaining reader of what it returns is
`_installAuthenticator`'s no-keystore leg.

At the end of this step at_client's lib names `AtChops` only on its public
surface, which is then marked `@Deprecated` with the replacement in the text:
pass `atKeysIo`, and the client derives what it needs from the keyfile.

### Step 5: at_client's enrollment-id readers (no API change)

First a probe, not a reading: build a client, retrofit it, and assert at both
moments that `atClient.enrollmentId` and `atLookUp.enrollmentId` agree. If
they ever don't, that difference is the finding and the readers stay.

Then the 8 readers the consolidation plan enumerates, plus
`key_package_minting.dart`'s `enrolment` alias, read `atClient.enrollmentId`.
The 3 authenticator-feeding reads and the one writer in
`remote_secondary.dart` stay: they build the ladder's replacement and go with
the ladder in the at_lookup major. `apkam_signing.dart`'s manufactured
sentinel, `EnrollmentConstants.primaryEnrollmentId` (which is the string
`primary`, defined in at_commons's `enrollment_constants.dart`), is preserved
exactly, as the consolidation plan's caution asks.

In the tests, the `when(() => lookUp.enrollmentId)` stubs come out, and each
fixture that sets `atClient.enrollmentId` after construction is read for what
it now observes.

### Step 6: at_onboarding_cli, the live packs and at_contact (no API change)

`_initAtClient(AtChops atChops, …)` drops the parameter and passes `atKeysIo`
alone; the 7 `atLookUp.*` ladder uses between `:180` and `:220` go through
`authenticatorFor`; and `AtOnboardingService.atChops` (2, on the interface) is
marked `@Deprecated`. Then the CLI's tests: the `AtChopsImpl` constructions and
the `atChops` stubs come out with the parameter.

The two live packs follow the same moves on their own fixtures: at_functional
carries 117 F1 uses (`AtChopsKeys` 24, `AtPkamKeyPair` 23,
`AtEncryptionKeyPair` 21, `AtChopsImpl` 20, `AtChopsKeys.create` 16, and the
signing and util members) and 34 F2 (`AtLookupImpl` 25, `atChops` 9); at_e2e
carries 29 F1 and 8 F2, with `enrollment_setup.dart` the file that sets
`atLookUp.atChops`. Their F3 uses (at_functional about 107, at_e2e about 87)
wait for step 7. Both packs and at_contact also clear F5 here by passing
`storage:` instead of the three preference fields, and at_client's own 30
test files do the same, since the analyzer will never list them.

### Step 7: at_onboarding_cli's and at_client_flutter's flat fields

The CLI's onboarding paths (`_generateAtKeysFile`,
`_persistKeysLocalSecondary`, `authenticate` and
`enrollment_checkpoint.dart`) and at_client_flutter's `auth_service.dart`,
`enrollment_service.dart`, `keychain_storage.dart` and the two dialogs read
[step 3](#step-3-at_auth-builds-the-carrier-inside-400-rc2)'s accessors, and
take the atSign and root domain from `session`, instead of the flat fields and
the response models. Both packages' tests follow, and so do the live packs' F3
uses.

⚠️ **at_client_flutter's 7 `lib` uses are not the mechanical moves this step
assumes.** Read on 2026-09-11, each carries a question of its own, and none of
them is answered by the accessors:

- `auth_service.dart` backs the authenticated keys up to the caller's
  `backupKeys` from `atAuthResponse.atAuthKeys`. The annotation points at
  `session`, but `session` is populated only when the request supplied an
  `atKeysIo` — and `authenticate`'s own dartdoc says a request may carry
  `atAuthKeys` instead — so a caller that passes keys directly would lose its
  backup silently. `session.atKeysIo.read(atSign)` is also not the object the
  response carried: for a generated io it is a different read entirely.
- `enrollment_service.dart`'s approve path writes `atEnrollmentResponse`'s
  keys to the keychain, and the NOTE directly above it says the approver holds
  no enrollee key material — the enrollee files its own. If that is right the
  branch is dead, and moving it preserves dead code.
- `apkam_dialog.dart` passes `atSign` and `rootDomain` to
  `AtEnrollmentRequest`, and the deprecation asks for a `session` instead. An
  OTP enrolment is the pre-authentication door, so the enrollee has no session
  to pass — it would have to construct one, and its `atKeysIo` decides where
  the newly enrolled app's keys land. That is a design choice, not a rename.

⚠️ The third of those is [step 0](#step-0-done-at_auth-stops-deprecating-what-it-has-no-replacement-for)'s
shape again: `AtEnrollmentRequest`'s `atSign` and `rootDomain` are deprecated
in favour of a `session` that one of its two constructors' callers cannot
have. Before moving any caller, the annotation is worth the same test step 0
applied — is there a replacement this caller can reach?

### Step 8: removal, in the majors

at_client 4.0 removes `AtClient.atChops`, `create(atChops:)`, the manager
parameters and `RemoteSecondary.atChops`. at_auth removes `toAtChops` and the
`atChops` fields in its next major after 4.0. The at_lookup major removes the
ladder, gated as the consolidation plan records.

## 5. What each step clears

The splits are estimates from reading the sites on 2026-09-11, not analyzer
output; the command at the top gives per-member totals, and each step's real
figure replaces its row here as it lands.

| step | package           | lib uses cleared      | test uses that fall in behind          |
| ---- | ----------------- | --------------------- | -------------------------------------- |
| 0    | at_auth           | 0 here, 45 in its consumers | counted in those members         |
| 1    | at_client         | 2 of 58               | none                                   |
| 2    | at_client         | 12 of 58; and 2 in `benchmark` | ~50, the engine-only fixtures |
| 3    | at_auth           | 18 so far; 56 owed    | 7 so far; 85 owed                      |
| 4    | at_client         | ~23                   | ~250, every `AtChopsImpl(` built only to hand over |
| 5    | at_client         | 11 of 15; 4 stay as the bridge | the `enrollmentId` stubs      |
| 6    | at_onboarding_cli | ~19 of 34             | ~30                                    |
| 6    | the two live packs | 0 (no lib)           | ~190: their F1, F2 and F5              |
| 6    | at_contact        | 0 (no lib)            | 4                                      |
| 7    | at_onboarding_cli | 15 of 31              | 150, and 18 in `example`               |
| 7    | at_client_flutter | 7                     | 40                                     |
| 7    | the two live packs | 21, at_e2e's `lib`   | 107 functional, 53 at_e2e              |

Step 7's two figures are a ceiling rather than a target until the legacy
question in [section 3](#3-decisions-this-plan-needs-and-the-ones-it-makes) is
settled.

The 4 or so that survive in at_client until its major are the public surface
and the ladder bridge, both `@Deprecated` by then with the replacement named.
One one-off outside every family stays listed so it is not lost:
`stopCompactionJob` (2, at_e2e). The 14 `atSign` uses in at_functional and 5
in at_e2e that this section filed as `AtOnboardingResponse`'s are
`AtEnrollmentRequest.pq(atSign:)`'s, and they belong to F3.

## 6. Filed, not scheduled

`AtLookUp.enrollmentId` isn't `authenticatedAsEnrollmentId`. The first is what
the next authentication will use and the second is what a live socket holds.
Step 5 moves readers to the client's field, which is the first; any reader that
meant the second is a separate finding.

The preference-only bridge, `_createAtChops`'s Hive branch and
`_installAuthenticator`'s no-keystore leg, exists for a client with no
`AtKeysIo`. Deleting it is the at_lookup major's decision, recorded in the
consolidation plan rather than here.

`AtHashingAlgorithmFactory` erased its own type parameters, and step 1's
switch keeps that erasure: `Argon2idHashingAlgo` takes a `String` where the
SHA and MD5 classes take `List<int>`, so a record whose
`pubKeyHash.hashingAlgo` reads `argon2id` fails on a type at runtime rather
than at compile time. Nothing here writes that value — the only writer emits
`sha512` — but `at_notification.dart`, `sync_service_impl.dart` and
at_commons' `update_verb_builder.dart` each build a `PublicKeyHash` from the
wire, so it is reachable in principle. Typing the switch
`AtHashingAlgorithm<List<int>, String>` would refuse it at compile time, and
needs a decision on what a malformed record should do.

The inert `sync:` flag's 4.0 deletion is [section 14.46](../pq/implementation-plan.md#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries)'s, not
this plan's. One detail found on 2026-09-11 that it does not record: the two
`remote_secondary.dart` declarations write `sync = false` with no type, so
they infer `dynamic` where the interface says `bool?`.
