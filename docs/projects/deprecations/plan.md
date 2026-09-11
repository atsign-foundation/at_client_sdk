# Deprecation debt across the release train

The packages in this workspace don't publish while their own code and tests
carry hundreds of `deprecated_member_use` warnings. This plan takes them to
zero, package by package, in an order the dependencies allow.

Every figure here came from `dart analyze`, never from a grep: the deprecated
members are reached through many differently-named receivers, and only the
analyzer resolves a receiver's type. Re-derive before acting on any of them:

```bash
# the workspace's members are the root pubspec.yaml's `workspace:` list
for p in packages/at_auth packages/at_client packages/at_onboarding_cli \
         packages/at_contact tests/at_functional_test tests/at_end2end_test; do
  (cd $p && printf '%-40s lib:%4s test:%4s\n' $p \
    "$(dart analyze lib  2>/dev/null | grep -c deprecated_member_use)" \
    "$(dart analyze test 2>/dev/null | grep -c deprecated_member_use)")
done
# a Flutter package needs the Flutter analyzer; dart analyze never sees it
(cd packages/at_client_flutter && flutter analyze --no-pub --no-fatal-infos \
  | grep -c deprecated_member_use)
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
`wasm_shakedown` and the 2 CLI packs are at zero in `lib` and `test` today.
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
| at_auth                             | 4.0.0-rc2       |  74 |   92 |
| at_client                           | 3.15.0-rc1      |  58 |  358 |
| at_onboarding_cli                   | 1.17.0-rc1      |  34 |  209 |
| at_client_flutter                   | 1.1.5-rc1       |  22 |   55 |
| tests/at_functional_test            | (unpublished)   |   0 |  280 |
| tests/at_end2end_test               | (unpublished)   |   0 |  131 |
| at_contact                          | (see pubspec)   |   0 |    4 |

1317 uses. The test figures are downstream of the lib figures almost entirely:
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
`atAuthKeys` on the request and response models, which says *"remove in v5"*.
So at_auth has scheduled the model fields past its current major and left the
flat fields' removal unstated.

This family is most of at_onboarding_cli (15 of its 34 lib uses and most of
its 209 test uses) and all of at_client_flutter's 22 lib uses (`metadata`,
`AtOnboardingResponse`, `AtAuthResponse` and `atAuthKeys`, 5 each, plus one
`atSign` and one `rootDomain`) and 55 test uses. The typed replacement is
`AtKeys`'s `CryptographicMaterial` surface, which the CLI already uses on its
PQ paths.

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

For gkc: whether at_chops exports `AtHashingAlgorithmFactory` at all. It is
the replacement its own deprecation names, but an export is frozen public API
the moment `3.6.1`'s successor publishes, and the alternative is for
at_client to use the exported `sha.dart` classes directly and drop the one
call that maps a runtime `HashingAlgoType.fromString(...)` to an algorithm.
The plan assumes the export; the decision is a one-line change either way.

For gkc: whether F3 clears in this pass or waits for at_auth 5. at_auth's own
annotation says v5 for the model fields. Clearing it now means moving the CLI's onboarding
paths off the flat fields, which is real work on a package at `1.17.0-rc1`;
leaving it means at_onboarding_cli publishes with about 180 of its 209 test
warnings, at_client_flutter with all 77 of its, and the two live packs keep
about 240 between them. This plan schedules it last so the decision can be
taken with everything else done.

## 4. Order of work

Each step lands with its own gates (`dart analyze --fatal-infos` on the
changed package, the unit suite, and the format gate under CI's Dart in
Docker), and each step's test tree clears in the same commit as its lib. A
step that touches a lifecycle seam runs all 4 live packs before it commits.

### Step 1: at_chops exports what its own deprecations point at

`AtHashingAlgorithmFactory` is the named replacement for `AtChops.hashWith`,
and the barrel doesn't export it. One line in the barrel and one CHANGELOG
entry, once the decision recorded for gkc above is taken.

### Step 2: at_client's engine role (no API change)

The 6 `encryptString` and `decryptString` calls that already pass an
algorithm become direct calls on the `AESEncryptionAlgo` and
`RsaEncryptionAlgo` objects they construct, with the `utf8` and `base64` steps
the wrapper did made explicit; `AtEncryptionResult` goes with them (5 uses).
The 3 `rsa2048` calls that pass none wait for step 4, since they need the
encryption key pair. `AtChops.hashWith(…)` becomes
`AtHashingAlgorithmFactory.withHashingAlgorithm(…)` (2). `RsaSigningAlgo`
becomes `RsaSignatureAlgo` in `envelope_signature.dart` (3), which isn't a
rename: the new class is built by the named constructors `.rsa2048()` and
`.rsa4096()`, keys move from the constructor to the call, and its
`verifyBytes` is async and takes the public key per call (there is no
`verify` on it). Two cautions from the 2026-08-26 triage bite here and are
confirmed in source. `RsaSignatureAlgo` refuses any key whose modulus is not
its constructor's size (`rsa.dart` throws at the `_modulusBits` check when
signing and yields no verification key on a mismatch), while `RsaSigningAlgo`
checks nothing, so an enrollment holding an off-size RSA key stops signing and
verifying where it used to; the constructor has to be chosen from the key's
modulus, and whether to keep accepting off-size keys is a decision to take,
not inherit. And nothing non-deprecated dispatches from a `SigningAlgoType` to
an algorithm the way `AtChopsImpl.sign` does, so any path that today asks
AtChops to choose between RSA and ML-DSA writes that two-way branch itself
(`MlDsa65PureDartAlgo.signBytes` and `verifyBytes` are the PQ half). The
envelope signature is a wire contract, so its bytes get pinned before and
after.
`_signPublicData` in `put_request_transformer.dart` (`AtSigningInput`,
`AtSigningMode`, `atChops!.sign`) moves to the same `RsaSignatureAlgo`, signing
with the key `ApkamSigning.authenticationSigningKey` already resolves; the
`dataSignature` metadata is a wire contract too, and gets a raw-literal pin
first.

Already done in this pass: the `AtChopsUtil` IV and symmetric-key helpers
became the key classes' own statics (12 uses).

### Step 3: at_auth builds the carrier (inside 4.0.0-rc2)

Typed getters on `AtKeys` for what at_client actually reads: the authentication
keypair for an enrollment, the encryption keypair and the self encryption key,
as `RsaKeyPair`, `AESKey` and the PQ key classes, resolved from
`CryptographicMaterial` by role and algorithm. `signingKeysFor` is the model,
since it already does this for signing keys. `authenticationFor` returns the
algorithm and the key rather than an `AtChops`. `toAtChops()` and
`toAtChopsForEnrollment()` are marked `@Deprecated` pointing at the getters and
stay for 4.x's consumers.

Then at_auth's own F1 uses move onto its own getters: `at_keys.dart` (19),
`enrollment_handshake.dart` (11), `at_authenticator.dart` (10),
`at_auth_impl.dart` (9), `apkam_possession_proof.dart` (6), `file_io.dart` (5),
`enrollment_approver.dart` (4), `onboarding_mint.dart` (4),
`enrollment_submitter.dart` (2), `at_auth.dart` (2), `at_enrollment_impl.dart`
(1) and `at_enrollment.dart` (1), which is all 74. `AtAuthResponse.atChops` and
`AtAuth.atChops` go `@Deprecated` beside `atAuthKeys`, which is where a
consumer should have been reading all along.

### Step 4: at_client's carrier role (no API change)

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

### Step 7: the F3 decision, then at_onboarding_cli's flat fields

If cleared now, the CLI's onboarding paths (`:478` to `:751`) and
at_client_flutter's `auth_service.dart`, `enrollment_service.dart` and
`keychain_storage.dart` read `CryptographicMaterial` by role instead of the
flat fields and response models, and both packages' tests follow. If deferred, this row moves to "filed" with at_auth 5 as its gate, and
the package publishes carrying that family's warnings alone.

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
| 1    | at_chops          | 0, unblocks 2         | none                                   |
| 2    | at_client         | ~18 of 58             | ~50, the engine-only fixtures          |
| 3    | at_auth           | 74, onto its own getters | 92                                  |
| 4    | at_client         | ~23                   | ~250, every `AtChopsImpl(` built only to hand over |
| 5    | at_client         | 11 of 15; 4 stay as the bridge | the `enrollmentId` stubs      |
| 6    | at_onboarding_cli | ~19 of 34             | ~30                                    |
| 6    | the two live packs | 0 (no lib)           | ~190: their F1, F2 and F5              |
| 6    | at_contact        | 0 (no lib)            | 4                                      |
| 7    | at_onboarding_cli | ~15                   | ~180                                   |
| 7    | at_client_flutter | 22                    | 55                                     |
| 7    | the two live packs | 0                    | ~190: their F3                         |

The 4 or so that survive in at_client until its major are the public surface
and the ladder bridge, both `@Deprecated` by then with the replacement named.
Two one-off deprecations outside every family stay listed so they are not
lost: `stopCompactionJob` (2, at_e2e) and `AtOnboardingResponse`'s `atSign`
(14 in at_functional, 5 in at_e2e).

## 6. Filed, not scheduled

`AtLookUp.enrollmentId` isn't `authenticatedAsEnrollmentId`. The first is what
the next authentication will use and the second is what a live socket holds.
Step 5 moves readers to the client's field, which is the first; any reader that
meant the second is a separate finding.

The preference-only bridge, `_createAtChops`'s Hive branch and
`_installAuthenticator`'s no-keystore leg, exists for a client with no
`AtKeysIo`. Deleting it is the at_lookup major's decision, recorded in the
consolidation plan rather than here.

The inert `sync:` flag's 4.0 deletion is [section 14.46](../pq/implementation-plan.md#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries)'s, not
this plan's. One detail found on 2026-09-11 that it does not record: the two
`remote_secondary.dart` declarations write `sync = false` with no type, so
they infer `dynamic` where the interface says `bool?`.
