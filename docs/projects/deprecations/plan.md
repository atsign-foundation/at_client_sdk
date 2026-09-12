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
#
# ⛔ THE WORKSPACE IS NOT THE REPO: 17 of 49 packages. The absentees are the
# example trees and the legacy Flutter packages, and three at_client_flutter
# examples hold 18 uses no figure in this plan counted until 2026-09-11 - one
# of them a caller of a member family H had already removed. So enumerate
# every pubspec, not the workspace:
# ⛔ `dart analyze` REJECTS --no-fatal-infos ("Cannot negate option", exit 64)
# and greps to a silent zero; only `flutter analyze` takes it. Print the exit
# code beside every count so a zero has to earn belief.
printf '%-52s %5s %5s\n' PACKAGE EXIT USES
for d in $(find . -name pubspec.yaml -not -path '*/.dart_tool/*' -not -path './pubspec.yaml' \
             -not -path '*/build/*' | xargs -n1 dirname | sort); do
  if grep -q '^  flutter:' "$d/pubspec.yaml"; then
    out=$( (cd "$d" && flutter analyze --no-fatal-infos 2>&1) ); rc=$?
  else
    out=$( (cd "$d" && dart analyze 2>&1) ); rc=$?
  fi
  n=$(printf '%s' "$out" | grep -c deprecated_member_use)
  [ "$n" -gt 0 -o "$rc" -gt 3 ] && printf '%-52s %5s %5s\n' "$d" "$rc" "$n"
done
# a member's own split, from inside it: dart analyze lib | test | example | tool
# per symbol, from any of the above analyses saved to a file:
#   grep deprecated_member_use an.txt | sed -E "s/.*'([^']+)' is deprecated.*/\1/" | sort | uniq -c | sort -rn
```

The per-symbol and per-file counts quoted below all come from that last
line run over the analysis they describe, on 2026-09-11.

⚠️ **This exact trap has now bitten this pass twice**, once in a hand-listed
loop that recorded two live packs at zero, and once in the recipe above, which
carried `--no-fatal-infos` into `dart analyze` for a day: every Dart package
reported zero and only the Flutter ones were really measured. **Neither zero
looked wrong.** That is why the exit code is printed.

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

⛔ **Nor are the `example/` and `examples/` trees, and those are not merely
uncounted — they are ungated.** No workflow analyses or builds any of them, and
`at_client_sdk.yaml` fetches at_client_flutter's dependencies with
`--no-example`, so nothing in CI can go red on one. Three of them use this
plan's families: `at_client_flutter/example` 8, `examples/todos` 5,
`examples/dockerstats` 5. That is where family H's removal broke a caller while
this plan recorded it as having none. Treat an example as a member for counting
and for compiling, and remember two of them are red for reasons that predate
this work: `example/` imports three packages its pubspec never declares, and
its `apkam_example.dart` has omitted a required `signingAlgo` since
`4.0.0-rc1`. `examples/todos` is a canonical example the tree tells authors to
copy, so it is the one that has to end up showing the right thing.

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
its approval key material, its handshake and its `atChops` field deprecated,
with 14 `lib` uses left in at_auth, which is its floor for this pass: every
one is decided and named in the table under step 3, and all but two are the
injected-signer machinery that waits for the live packs. Step 4 is done
apart from `LocalSecondary`'s `AtChops` tier, which waits for the live packs;
`AtClient.atChops` is `@Deprecated`. Step 5 is done: the readers of the
enrollment id ask the client. All four live packs have run green on everything landed;
their first runs found two defects, recorded under step 4, one of them from
the pass before this one. Step 6's at_onboarding_cli half is done and its four
packs are green, and step 7's three at_client_flutter readings are resolved.
[Step 8](#step-8-removal--at_auth-now-the-others-at-their-majors) is under
way: gkc ruled that at_auth's surface is cleaned in this rc, and its families
E, H, A and G are removed; B's callers have moved with its surface held; C
and D are open on one design question.

**What is owed, in order.** Step 8's C and D — the *enrollment* request and
response — which turn on the question
[stated below](#what-c-and-d-turn-on); then the remaining test-tree work in
steps 6 and 7; then `LocalSecondary`'s `AtChops` tier.

⛔ **Start by settling whether C and D are held the way B was.** They very
likely are: the published at_client_flutter example reads
`AtEnrollmentResponse.atAuthKeys` at `onboarding.dart:77`, one line above its
`AtAuthRequest(atAuthKeys:)` — so family **D is app-facing by measurement**,
not by argument, and gkc's rule is that an application's packages do not
break. If the hold applies, C and D become what B became: move every caller in
this repository onto the session, leave the surface deprecated and standing. Two of those wait on gkc rather
than on code, and both are stated where they arise: whether F's seven flat
fields keep an annotation no caller can act on (step 8), and where an enrolled
app's keys should land if `apkam_dialog.dart` supplies a session (step 7).

⚠️ **Re-derive every figure here before quoting it.** The counts on
2026-09-12, from the corrected recipe above — `lib` / `test`: at_auth **16 /
70** with **20** annotations left in `lib`; at_client **30 / 256**;
at_onboarding_cli **21 / 182** (plus 36 outside both); at_client_flutter **0 /
36**, its `lib` zero being four ignores with reasons rather than a clearance.
Whole-package totals, which include `example/` and `bin/`: at_auth 87,
at_client 287, at_onboarding_cli 239, at_client_flutter 36, the functional pack
272, e2e 116, the onboarding-CLI pack 47, at_contact 4, and 16 spread over six
legacy `*_flutter` packages this plan does not clear.

The annotation count is what measures the removals: **28 to 20** across
families A, E, G and H.

⚠️ **A THIRD kind of movement that is not progress: a reinstatement.**
at_client's `lib` went 28 to 30 on 2026-09-12 while the tree got *better* —
`ApkamSigning`'s reinstated accessors return `AtPkamKeyPair`, which at_chops
deprecates, so the import and the return type each report. Restoring a
published signature costs deprecated uses, and that is the correct trade.

⚠️ **Three of those movements are not work, and one of them is a RISE.** Two
are gkc's `setCurrentAtSign(atChops:)` deprecation: at_onboarding_cli gained
one, because the CLI passes the parameter through, and at_client **lost three**,
because a parameter's own type annotation stops reporting once the parameter is
deprecated. The third is at_auth's `lib` going **14 to 16** across family A,
which removed code and reported more: taking `@Deprecated` off the `atChops`
field makes that declaration's own `AtChops` type annotation visible, and
turning the constructor's `this.atChops` into an explicit `AtChops? atChops`
gives it a type annotation it never had. Both are the invisibility step 3
records, running backwards. So the count can fall without work and rise
without regression, and neither direction is progress on its own.

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

⚠️ **An override may keep a parameter its interface has dropped.** Removing
`approverChops` from `AtEnrollment.approve` left four at_client test doubles
declaring it in their own `approve` overrides, and `dart analyze` named none
of them: an override carrying an **extra** optional named parameter is still a
valid override. Measured — the only error the removal raised anywhere in
at_client was in at_client's own `enrollment_service_impl`. The reverse does
hold, and the at_lookup consolidation plan probed it: an override **missing** a
named parameter the interface declares is `invalid_override`. So a removal is
compiler-enumerable in one direction only, and doubles that kept the parameter
have to be found by grepping its name.

**What remains of this step**, measured 2026-09-11, is 16 uses in `lib` and 70
in `test`, from 56 and 92 (`dart analyze` in `packages/at_auth`, counting the
`deprecated_member_use` lines by path). The `lib` figure rose by two across
step 8's family A for the annotation reason the status section above explains,
not because anything moved the wrong way. Twelve of the test uses are in
`auth_wiring_test.dart` on purpose: it asserts that `atChops` and
`signingAlgoType` are never written on a lookup that takes an authenticator
and are written on one that cannot, and a test cannot assert a member is
untouched without naming it. One more was `approver_key_material_test.dart`'s
arm through the deprecated `approverChops` door. Step 8's family A removed
that door and the arm with it; what the arm asserted — that the material comes
with the call — is now an interaction control that names no deprecated member.

| file | uses | what they are |
| ---- | ---: | ------------- |
| `at_authenticator.dart` | 8 | the two injected-signer branches, and `AtChops` in three signatures |
| `at_auth_impl.dart` | 6 | the `AtChops` onboarding builds for the injected-signer branch and for `AtAuthResponse.atChops`, plus the private field's own type and `AtAuth.create`'s parameter |
| `at_auth.dart` | 1 | `AtAuth.create`'s `atChops` parameter: the injection door, which keeps its type because a hardware-backed signer has no other door yet |
| `at_keys.dart` | 1 | `authenticationFor`'s return type |

Deprecated names are ignored with their reason rather than counted in two
places, both of which exist only for a lookup without the authenticator seam:
the two credential ladder writes inside `AtAuthImpl._installAuthenticator`,
and `EnrollmentHandshake._installLadder`, which builds the ladder's `AtChops`
around the APKAM keypair alone. There were three until family A: the approver's
read of `atLookUp.atChops` was the third, and requiring `approverKeys` closed
it. The handshake's seven are gone: it hands
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
The three signatures are clear because `approverChops` is gone (step 8, family
A). While it existed its `@Deprecated` did the same job, for the reason this
step records above: the analyzer treats a parameter's own type annotation as
inside the deprecated declaration. `file_io.dart`'s three are gone: the keyfile's legacy fields
are self-encrypted through `AESEncryptionAlgo` directly, and
`legacy_field_self_encryption_test.dart` pins the at-rest bytes against
openssl and re-encrypts the committed legacy fixture byte-for-byte.

⚠️ **The two injected-signer branches in `_pkam` are the ones to leave until
the live packs run.** One of them names the algorithm precisely because the
keyfile cannot answer — a PQ-native activation signs with a keypair minted
moments before, under an enrollment the atServer has not created — and that
resolution is exercised by no unit test. The rest are reachable from unit
tests. `AtAuthImpl.authenticate` hands
`authenticatorFor` only a signer the caller injected through
`AtAuth.create(atChops:)`, and `_pkam`'s injected-signer branch now applies
one rule wherever a signer arrives beside a keyfile: the keyfile's keypair
signs when it holds one for the enrollment, the injected signer when it holds
none. So at_auth's own mainstream authentication signs from the keypair, and
`onboard` is the algorithm-naming branch's last caller. The bytes are
identical by design, so `auth_wiring_test.dart` holds the openssl PKAM pin on
the authenticator `authenticate` installs and holds the rule from both sides:
an injected signer signs for a keyfile holding no keypair, and a keyfile
holding another atSign's keypair outranks the injected signer, checked with
at_chops' verifier. Flipping the rule back reddens exactly that second arm.

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
`AtAuth.atChops` is `@Deprecated` (the responses' `atChops` already was), and
the packages that read it gained infos on purpose — at_onboarding_cli 31 to
32 in `lib` and 204 to 211 in `test`, at_functional_test 272 to 279 in
`test`, at_end2end_test none — which is the work of steps 5 and 6, now
visible to the analyzer. The factory's `atChops` parameter is not deprecated:
it is the door a caller with a hardware-backed signer comes through, and step
0 stopped this package deprecating what it has no replacement for.

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

`apkam_signing.dart`'s `authenticationSigningKey` now reads the enrollment's
APKAM keypair from the keyfile — typed material first, the flat pair as
`rsa2048` otherwise — and takes the client's `AtChops` only for a client built
without a key source; it became asynchronous, since a keyfile is read rather
than held, and its four callers followed. Three arms in
`apkam_signing_keys_test.dart` were red against the old getter (a keyfile-only
client hit its null check; the keyfile's key lost to an injected `AtChops`)
and are green now. `RemoteSecondary` hands the authenticator the
client's `AtChops` beside its keyfile, and at_auth's rule decides: the
keyfile's keypair signs when it holds one, the `AtChops` when it holds none.
Sync's own remote, built through `SyncServiceImpl.remoteSecondaryFor`, gets
the same two sources. `remote_secondary_wiring_test.dart` tells the two apart
with at_chops' RSA verifier — two different keypairs, and which public key
the PKAM signature verifies under says which signed — and its
keyfile-plus-`AtChops` arm was red against the old wiring. ⚠️ **The first
form of this change dropped the `AtChops` whenever a keyfile was present, on
the premise that a keyfile client's `AtChops` was derived from that keyfile.
The functional pack falsified it: 36 of its tests went red, every one with
"AtKeys holds no authentication keypair for this atSign's own credential",
because its fixtures hand the client an empty `AtKeys()` as the key source
beside an `AtChops` holding the keys — the stand-in that carries the shape but
not the substance, which this plan's own caution names and this pass did not
enumerate.** The rule above is the fix, and `remote_secondary_wiring_test.dart`
now holds that shape too: an empty keyfile beside an `AtChops` signs with the
`AtChops`. The pack re-ran on the same `at_virtual_env:local` image,
`./runLocal.sh 27000` in `tests/at_functional_test`: +200, all passed. The
e2e pack followed, `./runLocal.sh 26000` in `tests/at_end2end_test` (the bare
run, `test -x legacy-server`, 21 files): +73, all passed, `retrofit_e2e_test`
among them — so step 5's post-retrofit agreement assertion ran live and held.
⚠️ **Then the two onboarding-CLI packs, and each had two red on the enrollee's
side of an enrollment: the approval landed and no keyfile was written.** The
CLI's `enroll` read `_atLookUp!.atChops!` after `awaitApproval`, and nothing
had set it since the handshake started installing an authenticator instead of
writing the ladder — the fix that landed on 2026-09-10 with the packs owed.
Nothing went red until now because the CLI's unit tests stub the lookup's
`atChops`, and the pack test hides the enroll future's error behind a
`whenComplete` assertion on the keyfile. `enroll` now builds its client from
the keys the handshake completed, through `toAtChops()`, which is counted
rather than ignored: it is the bridge step 6 replaces with the keyfile.
at_onboarding_cli's `lib` goes 33 to 34 for it (`dart analyze` in
`packages/at_onboarding_cli`, counted by path): the ladder read gone, the
bridge counted. Both CLI packs re-ran green with it — `./runLocal.sh 47000`
in `tests/at_onboarding_cli_functional_tests`: +21; `./runLocal.sh 48000` in
`tests/at_onboarding_cli_functional_tests_proxy`: +4 — so all four live packs
have run green on this tree, on `at_virtual_env:local`. The ladder fields on the lookup are still written, as
step 5's ruling on `remote_secondary.dart` says. `AtClient.atChops` is
`@Deprecated`, getter and setter, with the replacement in the text. at_client's
`lib` went 46 to 41 (`dart analyze` in `packages/at_client`, counting
`deprecated_member_use` by path); its own test tree stayed at 276, because a
package's tests are the same package and the analyzer reports none of the
stubs there — a grep finds 42 `.atChops` references across 23 test files, some
of them `AtLookUp`'s or `RemoteSecondary`'s, and those fixtures are found by
grep, not by a count, like the `hiveStoragePath` ones above. The packages that
read the field gained infos on purpose: at_onboarding_cli 32 to 33 in `lib`,
at_functional_test 279 to 283 in `test`, at_end2end_test 45 to 48 in `lib`,
the two CLI packs and at_client_flutter none. What remains of step 4 is the
`AtChopsKeys` getter on `LocalSecondary` and its "from atChops" tier — which
waits for the live packs, since a client built from an `AtChops` and no
keystore keys is a shape only they can show. Of the 41, by member: 15 are
`atLookUp.enrollmentId` reads, which are step 5's; 11 are `AtChops` as a type
in the carrier's own plumbing (`remote_secondary.dart`, `at_client_impl.dart`,
`at_client_manager.dart`); 4 are the lookup's ladder fields, which step 5's
ruling keeps; and the rest are the key classes `_createAtChops`'s Hive branch
and the nskey seeding build, the bridge for a client that has no keyfile.

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

**Done, 2026-09-11.** The probe first, as a question about writers rather
than a reading: the lookup's id has one writer in at_client, `RemoteSecondary`'s
constructor, which takes it from the client's field at every build and
rebuild, the retrofit's included. Outside at_client the analyzer finds three
writers in at_onboarding_cli — one from the client's field, two on the CLI's
own lookup before a client exists, which a client is then built around and
re-stamps — and two test fixtures, the e2e pack's own handshake lookup and a
functional fixture that sets the client's and the lookup's together. So the
two agree by construction wherever the tree writes them, and the moment they
could part is a completed retrofit, which no unit test drives: the e2e
retrofit test now asserts the agreement right after one, for the live-pack
run this work owes. A completed retrofit only happens live.

Then ten readers moved to `atClient.enrollmentId`: `nskey_rotation.dart`,
`nskey_seeding.dart` twice, `pq_signing_root.dart`, `apkam_signing.dart`'s
getter with its `primary` sentinel preserved exactly,
`enrollment_privilege_resolver.dart`, `envelope_enrollment_conveyance.dart`,
`key_package_minting.dart`'s `enrolment` alias, and `signing_key_minting.dart`
twice. The four in `remote_secondary.dart` stay as ruled above, and the
fifteenth `enrollmentId` the analyzer listed is `AtKeys.enrollmentId` in
`enrollment_symmetric_key.dart`, the keyfile's flat field and F3's, not a
lookup read. In the tests, twenty-four `when(() => lookUp.enrollmentId)`
stubs in thirteen files became stubs on the client's id, each lookup mapped to
its client by following the `getRemoteSecondary()` and `atLookUp` stub chain.
⚠️ The first search for them was case-sensitive and missed the file whose
receiver is spelled `lookup`; the full suite found it, and the sweep that
found the rest is `grep -rliE 'when\(\(\) => \w*look\w*\.enrollmentId\)'`
over `test/`, which now returns nothing. Putting one reader back on the lookup
reddens 22 tests, which is what says the fixtures now exercise the client's
field. at_client's `lib` went 41 to 31 and its `enrollmentId` uses 15 to 5;
its test tree 276 to 252 (`dart analyze` in `packages/at_client`, counted by
path).

### Step 6: at_onboarding_cli, the live packs and at_contact (no API change)

**Done for at_onboarding_cli, 2026-09-11.** `_initAtClient` takes `atKeysIo`
as a required named parameter and `atChops` as an optional one, and does
nothing to the lookup: the client's own connection installs the authenticator
from that source and stamps what a lookup from before the seam reads, so the
whole ladder block — `atChops`, `enrollmentId`, `signingAlgoType`,
`hashingAlgoType`, and the `authenticatorFor` call the service made itself —
is gone, along with the private `_keysIo` that fed it. `enroll` writes its
keyfile first and builds the client from it, where it used to build the
client and write the keyfile afterwards; `authenticate` hands over the source
at_auth just read.

`AtOnboardingService.atChops` is NOT deprecated, and that is a correction to
this step as written: it is the door for a signer that is not a keyfile — a
secure element's — which is the same shape at_auth's `_pkam` keeps for
exactly that reason, and step 0's ruling says this tree does not deprecate
what it has no replacement for. `_initAtClient` passes it through.

One test changed contract rather than fixture:
`authenticated_client_keeps_its_algorithm_test.dart`'s second arm asserted
that a lookup the service built keeps the **preference's** `rsa2048`, because
enrolment had no keyfile to resolve from at that moment. It now has one, so
both arms assert the keyfile's `mldsa65` and the arm names the authenticator
it expects beside it. Three mutations hold the rest: building the client with
no key source reddens 3 tests, building it before the keyfile is written
reddens 2 (the checkpoint and the local-secondary detail), and stamping the
preference's algorithm again reddens 3.

at_onboarding_cli's `lib` goes 34 to 22 deprecated uses and its test tree 211
to 186 (`dart analyze` in `packages/at_onboarding_cli`, counted by path); 78
unit tests pass. This moves a client-construction seam, so all four live packs
ran against it on `at_virtual_env:local`, and all four are green: the
onboarding-CLI pack +21, its proxy +4, functional +200, e2e +73.

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

**The three readings, resolved on 2026-09-11.** All three came out as the
readings suspected, and none was a rename.

- **The approve path's branch is dead, and is deleted.** Confirmed from three
  sides: at_auth's `EnrollmentApprover.approve` constructs its response with
  the id and the status alone, at_client's `EnrollmentServiceImpl.approve`
  returns that object unchanged, and the dartdoc on
  `enrollment_service_approve_test.dart` already said so. `keychainAtKeysIo`
  existed only for that branch and goes with it. ⚠️ Re-adding the branch
  reddens nothing, which is what says it was unreachable rather than merely
  unused — so what makes the deletion right is the contract, not a test. The
  `verifyNever` that stated "the approver files nothing" only existed because
  the field did; the claim moved onto the precondition that makes filing wrong
  — `expect(response.atAuthKeys, isNull)` — which reddens when the mocked
  approval is made to carry keys.
- **`auth_service.dart`'s backup keeps reading the response's keys** for now,
  because at_auth populates a session only for a request that supplied an
  `atKeysIo`, and a caller that passed `atAuthKeys` would have nothing backed
  up. ⚠️ **That is a gap in at_auth, not a limit on the caller** — see the
  correction below.
- **`enrollment_service.dart`'s submit path is the same shape**: it files the
  keys the submission minted, and the request this service builds carries no
  session for the response to carry one.
- **`apkam_dialog.dart` keeps its loose `atSign` and `rootDomain`**, because
  supplying a session moves the persisting of the enrolled app's keys into
  at_auth's handshake — `AtEnrollmentRequest`'s dartdoc says its `atKeysIo` is
  where they land — from the service that writes them today. A decision about
  where those keys land, which is the question this step now carries.

⛔ **Correction, same day: "a legitimate caller cannot reach the replacement"
was wrong, and it was mine.** gkc asked why every `AtEnrollmentRequest` caller
cannot supply a session and every `AtAuthRequest` caller an `AtKeysIo`. They
can, both:

- `InMemoryAtKeysIo` is exported from at_auth's barrel, so a caller holding an
  `AtKeys` wraps it in three lines. Measured across the tree: **32 of 36
  `AtAuthRequest` constructions already pass a source**, and the 4 that pass
  keys alone are at_client_flutter's examples and one widget test, all taking
  keys straight from an approved enrollment.
- at_auth **already builds that wrapper itself**, in `AtAuthImpl._keysSourceFor`,
  for exactly the `atAuthKeys`-only case. So the comment beside the session
  block — *"The legacy atAuthKeys-only path has no source to hand across, so it
  gets no session"* — is false: it has one, built a few lines earlier. Handing
  it over is what makes every successful authentication carry a session, and
  then `auth_service.dart`'s backup reads `session.atKeysIo`.
- An enrollee can construct an `AtAuthSession` too: its atSign, its root
  domain, and an `AtKeysIo` destination. What stops the dialog is not
  reachability but consequence — at_auth's handshake then persists the
  enrolled keys into that source, replacing the write the flutter service does
  after submit.

So the four ignores rest on a gap and a design choice, not on an unreachable
replacement, and both are fixable. The annotations stand.

**The count, decomposed.** at_client_flutter's `lib` reports 0 deprecated uses,
from 7, and that figure is mostly annotation: one use was deleted with the dead
branch, two pairs of reads became two single reads hoisted into locals (a real
reduction, since each pair read the same field twice), and the resulting 4 uses
carry `// ignore: deprecated_member_use` with the reasons above. ⛔ Read as
"decided and stated", never as "cleared": the analyzer cannot see any of them
now, so this list is the only record that they exist. Its test tree still holds
41, which is step 7's mechanical remainder. Its 40 unit tests pass, and
`flutter analyze --no-pub --no-fatal-infos` is clean.

### Step 8: removal — at_auth now, the others at their majors

at_client 4.0 removes `AtClient.atChops`, `create(atChops:)`, the manager
parameters and `RemoteSecondary.atChops`. The at_lookup major removes the
ladder, gated as the consolidation plan records.

⛔ **at_auth removes its own deprecated surface in this rc, and that corrects
what this step said** — it read *"at_auth removes `toAtChops` and the `atChops`
fields in its next major after 4.0"*. gkc ruled on 2026-09-11 that with only
`4.0.0-rc1` published, further breaking changes inside the major are free:
*"let's do it right; let's clean up all of the at_auth surface now."* So the
removals below are this pass's work, not a later release's. Steps 1 to 7 move
the callers; this deletes what they moved off.

**The surface, measured.** 36 `@Deprecated` annotations in at_auth's `lib`, in
eight families. The counts are cross-package uses from `dart analyze` per
package, plus `flutter analyze` for at_client_flutter, taken after step 7's
readings. ⚠️ **at_auth's own uses are absent from every count**, because a
same-package deprecated use raises nothing in this tree — measured as zero
`deprecated_member_use_from_same_package` diagnostics in every analyze this
pass. For at_auth's own callers the instrument is deletion: remove the
declaration and the analyzer enumerates them.

| family | members | cross-package uses | decision |
| ------ | ------- | -----------------: | -------- |
| E | the registrar's `ActivateApiEndpoint`, `login`, `validate` aliases | 0 | remove |
| G | `AtKeys.copyWith` | 0 | ✅ removed — dead code: its declaration was its only occurrence in the repo |
| G | `AtKeys.toAtChops`, `.toAtChopsForEnrollment` | 0 | ✅ removed from the public API, by becoming library-private |
| H | `KeyIOMixin` and its four serialization helpers | 0 | remove |
| A | `AtAuth.atChops` and `approve`'s `approverChops` | 7 | ✅ removed |
| B | `AtAuthRequest.atAuthKeys` + `AuthResponse.atAuthKeys` | 35 | ⛔ **kept** — callers moved, surface held |
| B | `AuthResponse.atLookUp`, `AuthResponse.atChops` | 10 | ″ |
| C | `AtEnrollmentRequest.atSign` | 24 | ″ |
| C | `AtEnrollmentRequest`'s `rootDomain`, `apkamPublicKey`, `encryptedAPKAMSymmetricKey` | 1 | free once C's `atSign` moves |
| D | `AtEnrollmentResponse.atAuthKeys` | 55 | blocked — see below |
| D | `AtEnrollmentResponse.atSign`, `.rootDomain` | 0 | free |
| F | the seven flat `AtKeys` fields | 332 | ⛔ **not removable** — see below |

⛔ **Every figure in this plan excluded 32 packages, and one of them held a
caller of something already removed.** The re-derivation loop enumerates the
root `pubspec.yaml`'s `workspace:` block — 17 members — and the repo has 49
packages with a pubspec. The 32 absentees are the `example/` and `examples/`
trees and the legacy Flutter packages, holding 316 Dart files. Three
at_client_flutter examples carry **18** deprecated uses between them, none of
which any count in this plan has ever included. Worse, `example/`'s
`at_backup_key.dart` called `encryptAtKeysWithSelfEncKey`, so **step 8's
family H broke it** — this step recorded *"No caller outside at_auth named any
of them"*, and that was false the moment it was written. Fixed in the same
pass, back to the error count it had before the mixin went.

⚠️ **CI cannot see them either**, which is why nothing went red: no workflow
analyses or builds any example package, and `at_client_sdk.yaml` fetches
at_client_flutter's dependencies with `--no-example`. So an example is not a
gate — it has to be analysed deliberately. Two of them cannot be made green
here at all: `example/` imports three packages its own pubspec never declares
and `apkam_example.dart` has omitted a required `signingAlgo` since
`4.0.0-rc1`, both predating this pass.

⛔ **THE RULE THIS STEP MISSED, and gkc had to state twice.** A package an
application depends on directly **does not break** — at_client_flutter,
at_onboarding_cli, at_cli_commons and at_client — because *"our ideal
objective is that most applications will be able to migrate to PQ without
needing to modify any line of code"* (gkc, 2026-09-11, on the two-rollout
sequence `pqReady` then `pqActive`). at_auth is the exception only in that
almost nothing uses it directly; the moment one of its members is reachable
through at_client_flutter's own API, removing it breaks an app just the same.

⛔ **And the baseline for "does this break" is the PUBLISHED version on
pub.dev, not this branch's starting commit** (gkc, 2026-09-11). This step
audited against `957010e9f` and found almost nothing, because the branch point
already carried a year of unreleased change. Published is what an application
compiles against: at_client_flutter **1.1.4** (on at_auth `^3.2.0`),
at_onboarding_cli **1.16.0**, at_cli_commons **3.1.1**, at_client **3.14.0**.
Everything in tree is an rc ahead of those.

**The instrument, which beats reading diffs.** A published package ships its
own example apps, and those are application code written against the published
API. Extract the archive, point one at the in-tree packages with absolute
`dependency_overrides`, and analyse it:

```bash
curl -s https://pub.dev/api/packages/at_client_flutter \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['latest']['version'])"
curl -sL https://pub.dev/api/archives/at_client_flutter-1.1.4.tar.gz | tar xz -C <scratch>
# replace the example's own dependency_overrides with absolute paths into the
# repo, add at_client_flutter itself, then:
flutter pub get && flutter analyze --no-fatal-infos
```

**Measured on 2026-09-11, against this tree**: at_client_flutter 1.1.4's
`examples/todos` gives **0 errors** and 7 deprecation infos (`atAuthKeys` ×2,
`atChops` ×2, `atLookUp`, `commitLogPath`, `hiveStoragePath`); at_client
3.14.0's `example`, 22 files of application code, gives **0 errors** and 3.
The zero means something because the same rig reports errors when a member
really has gone — a consumer file written against published `ApkamSigning`
failed on exactly two of its six members in the same run.

⚠️ **A failed `pub get` makes this instrument lie loudly.** `dart analyze` on
an unresolved package reports hundreds of `uri_does_not_exist` and
`undefined_class` errors that read exactly like API breaks — 900 of them here,
from one missing override. **Check the `pub get` exit code before reading the
analysis at all.** Two of these examples need care: at_client's pins
`at_onboarding_cli: ^2.0.0`, which nothing published satisfies, so its
own override has to be kept; and `at_chat_flutter/example` pins
`at_auth: ^3.0.0` against a tree on 4.0.0-rc2 and cannot resolve at all, so
nothing can analyse it — it has been that way since at_auth 4.

⚠️ **Do not hand-roll a regex API differ instead.** One was tried here and
reported 65 "removed members" for at_onboarding_cli, nearly all of them local
variables and cascade assignments sitting at two-space indent inside method
bodies (`rethrow`, `while`, `commitLogPath`). Compiling real application code
is both sounder and less work.

**B's callers moved and B's surface stayed, 2026-09-11 — the second ruling.** It was blocked on
where an enrolled app's keys land, because `AuthResponse.atLookUp` and
`.atChops` had no user anywhere except three example apps, in a branch whose
own comment said what it was: *"Transitional fallback for flows that hand back
only atAuthKeys with no AtKeysIo source (e.g. APKAM enrollment)"*.

⛔ **gkc ruled on 2026-09-11: the caller supplies the key destination, and it
is required.** `ApkamActivationDialog` takes an `AtKeysIo` and puts it on the
request as a session, so at_auth's handshake writes the completed keyset there
— the keys plus the encryption private key and self-encryption key the
approval releases — and hands a session back. Before that the completed keys
lived only in memory on the response, while the keychain held the
*pre-approval* set that nothing ever reads back: `EnrollmentData`'s only reader
is `validateEnrollment`, a presence-and-expiry check.

The removal was built, gated and run past all four live packs — and then held,
because it breaks an application. `AtAuthRequest.atAuthKeys` and
`AuthResponse.atAuthKeys`/`.atLookUp`/`.atChops` **stay**, deprecated exactly
as they were; `atKeysIo` stays optional with its runtime refusal. What the
work kept is everything non-breaking:

- **every caller in this repository reads the session** — `session.atKeysIo`
  for the keys, `enrollmentId` for the enrollment — which is what a
  deprecation pass is for, and leaves the fields exercised by nothing but an
  external app;
- **`InMemoryAtKeysIo.holding(atSign, keys)`**, for a caller that has keys and
  needs a source. at_auth wraps a fixed key set this way internally, so it is
  the same object the authentication would have built;
- **`AuthResponse.enrollmentId` answers from the session as well as the keys**
  — same signature, and it now works for a keyfile-sourced authentication,
  which previously reported no enrollment at all because it read the keys
  alone. ⚠️ That getter is **derived from a deprecated field and is not itself
  deprecated**, so a later removal of the field leaves it live and broken
  unless it is re-pointed first — the shape the rules call *deleting the mover
  leaves Y live but unexercised*.

⚠️ **What the removal measured before it was held**, so a later pass need not
re-derive it: 35 uses of `atAuthKeys` across at_auth, at_onboarding_cli's lib,
at_client_flutter and three packs, plus 10 of `.atLookUp`/`.atChops` confined
to example apps; all four live packs green on the removed shape (functional
200, e2e 73, onboarding-CLI 21, proxy 4).

Two things found while moving the callers, neither of them family B:

- **at_client_flutter's `AuthService.authenticate` never awaited its backup
  writes**, and the test that claimed authentication saves keys to the
  keychain passed **no `backupKeys` at all** and asserted on a mock `read`
  stubbed to answer the same keys whatever happened — green with the backup
  path deleted. It asks for the backup and asserts what the double was handed;
  emptying the loop reddens it.
- **`at_chat_flutter/example` cannot be analysed by anything.** It pins
  `at_auth: ^3.0.0` against a tree on `4.0.0-rc2`, so `flutter pub get` fails
  version solving — since at_auth 4, long before this pass. It held two of the
  removed reads; they are moved onto the session, and that edit is **unverified
  by any analyzer**, which is stated in the commit. The pin is a separate
  question: whether at_chat_flutter supports at_auth 4 at all.

⚠️ **A scripted edit on a CRLF file rewrites every line.** That example is
CRLF; read and written in text mode the diff became all 165 lines. Read and
write such a file in binary, and assert the line count has not moved.

⛔ **G is not blocked, and the caveat below saying it waits is wrong.** It reads
as though removing the two builders forces a decision about what
`authenticationFor` returns. It does not: the assembly is already in two
library-private functions, `toAtChops` and `toAtChopsForEnrollment` are thin
public wrappers over them, and `authenticationFor` is in the same library. Make
the two private and `authenticationFor` keeps returning exactly what it returns
today. What G actually costs is relocating eleven at_auth tests onto
`authenticationFor`, which is the public route through the same code — and for
the flat-field fixtures those tests use, `authenticationFor(null)` resolves a
null algorithm and calls the same builder, so every assertion survives.
`copyWith` is simply dead.

**Order, by risk.** E and H first: no consumer anywhere outside at_auth, so
the only open question is at_auth's own use of them, which deletion answers.
Then A and G, both removed, and B, whose callers moved while its surface
stayed — what each cost is below. **C and D are one change rather than two**,
and they turn on a question this step now states. F last, and as a ruling
rather than a refactor.

**What A cost, and the correction to the sentence that scoped it.** This step
said A's seven uses were *"all functional-pack fixtures reading
`atAuth.atChops`"*. Wrong in two ways, both of which mattered. One of the
eight sites is at_onboarding_cli's own mock stub of the getter — inert since
step 6 moved the CLI off it. And `approverChops`'s population is not in the
analyzer's count at all: four at_client test doubles *declare* the parameter
in an `approve` override, at_auth's own test exercised it, and at_lookup's
dartdoc named it. None of those is a deprecated *use*, so the count could not
see them — and an override declaring a parameter its interface no longer has
is not an error either, so the compiler could not see the four doubles.

Two decisions inside A, both wider than the family:

- **`approverKeys` is required, not merely preferred.** That closes at_auth's
  own read of `atLookUp.atChops` in the same move — a connection is not where
  an app's key material lives — and hands the enumeration of call sites to the
  compiler rather than to a refusal at run time. Every real caller already
  passed it: at_client's `EnrollmentServiceImpl`, and at_auth's own test. What
  was `approve`'s runtime refusal is now its signature.
- **That refusal moved to at_client**, because `_approverKeys()` could return
  null and at_auth's throw was what caught it — its dartdoc said so in as many
  words. at_client is the better place: it knows whether the local secondary
  is absent or holds neither key, and it refuses before the approval command
  goes out rather than after it. Removing the throw reddens the guard test
  with the mutant proceeding to fail at conveyance, which is the hazard the
  refusal exists for.

Five of A's seven pack sites passed `atChops: auth.atChops` to
`setCurrentAtSign` beside the very keyfile they had just authenticated from,
so the argument was redundant — the keyfile is what the client resolves from.
The two in `enrollment_test.dart` passed no key source at all and now take the
session's `atKeysIo`, which moved them off two family-B reads as well.

**G is done, 2026-09-11, and the reason it looked blocked is worth keeping.**
This section used to say: *"G is not free, and its zero is why.
`AtKeys.authenticationFor` is not deprecated, is at_client's route to a
client's `AtChops`, and its two-line body calls exactly the two methods G
would remove. So G waits for the decision about what `authenticationFor`
returns once nothing wants an `AtChops`."* Every fact in that was true and the
conclusion did not follow. Removing a member from the public API is not the
same act as changing what a method returns: the assembly is in two
library-private functions, `toAtChops` and `toAtChopsForEnrollment` were thin
public wrappers over them, and `authenticationFor` sits in the same library —
so making the two private removes them from the surface while
`authenticationFor` returns exactly what it always did, and at_client is
untouched. `copyWith` was dead: its declaration was its only occurrence in the
repository.

What it actually cost was the eleven at_auth tests that named the two
builders — ten in `at_keys_test.dart` and one in `at_self_enrollment_test.dart`
— which now go through `authenticationFor`, the public route into the same
code. Their assertions are unchanged and they exercise the replacement instead
of the thing removed. Coverage was checked by mutation rather than assumed:
deleting `_createPkamChops`'s `defaultEncryptionPrivateKey` guard reddens
*"MPKAM AtKeys to AtChopsImpl -> throws"*, and it fails in the shape that
matters — a `_TypeError` null check rather than the `AtException` asserted,
which is what that guard was holding back.

⚠️ **And it raised at_auth's count by 7 before settling back.** Undeprecating
the two builders made their own return types and four at_chops calls in
`_toAtChopsForEnrollment` visible for the first time; they were always there,
inside declarations the analyzer would not look into. They carry
`// ignore: deprecated_member_use` with the reason the two private assembly
functions beside them already give, so at_auth's total is 92 either side. That
is the third time in this step that the count moved for annotation reasons
rather than work — see the status section. **Read a movement's cause before
reading it as progress.**

**E and H are done, 2026-09-11.** The registrar's three aliases went with no
caller anywhere. `KeyIOMixin` and its four helpers went too, and
`WrittenAtKeysIo`/`GeneratedAtKeysIo` stopped mixing it in — a supertype
change, so the suites that matter are the ones loading the *subclasses*:
at_client's `StubAtKeysIo` and four more doubles, at_client_flutter's
`KeychainAtKeysIo`, at_auth's own two stores. All analyze clean and all pass
(at_auth 402, at_client 1858, at_onboarding_cli 78, at_client_flutter 40; every
live pack analyzes at exit 0). Deletion named one user, as it was meant to:
`at_keys_io_test.dart`'s `matchesEncryptedAtKeys` decrypted the at-rest
document by hand through two of the helpers. It reads back through
`FileAtKeysIo.read` now, which is a round-trip rather than an at-rest
assertion — and the at-rest form is pinned harder elsewhere, in
`legacy_field_self_encryption_test.dart`, against openssl's ciphertext and the
committed legacy fixture. at_auth's `lib` annotations go 36 to 28.

⛔ **F is not a removal, and this step must not pretend otherwise.** A legacy
`.atKeys` document decodes into the flat fields and files no
`CryptographicMaterial` at all — `at_keys_test.dart`'s *"a legacy document
files no typed material"* pins it, with a typed document as the control — so
for every keyfile already on disk those seven fields are the only reader there
is, and `toJson`, `fromJson` and `file_io`'s at-rest self-encryption are built
on them. Deleting them drops support for every keyfile in the world. What is
open for F is the **annotation**: step 0's ruling is that this tree does not
deprecate what it has no replacement for, and a legacy keyfile has none.
Whether the seven keep an annotation no caller can act on is gkc's call, and
this step carries it as a question rather than answering it.

### What C and D turn on

**Measured 2026-09-11**, by deprecation message rather than by member name,
because the names collide across families:

| member | uses | where |
| ------ | ---: | ----- |
| `AtEnrollmentRequest.atSign` | 24 | at_functional 14, at_end2end 5, at_onboarding_cli 3, at_client_flutter's example 2 |
| `AtEnrollmentRequest.apkamPublicKey` | 1 | at_client_flutter's `apkam_example.dart` |
| `AtEnrollmentRequest.rootDomain`, `.encryptedAPKAMSymmetricKey` | 0 | — |
| `AtEnrollmentResponse.atAuthKeys` | 55 | including at_auth's own handshake |
| `AtEnrollmentResponse.atSign`, `.rootDomain` | 0 | — |

**The design question, which is not the same as B's.** A session carries a key
*destination*, and an enrollment request that only submits has none — the
`AtEnrollmentRequest.pq` dartdoc says so itself: *"A request that only wants
the key exchange — one that inspects what it advertised and never waits for
approval — has nowhere to persist keys and needs no session."* Almost every
one of C's 24 sites is that kind: a refusal test that submits an invalid or
reused OTP and never waits. Requiring a session there means inventing an
`InMemoryAtKeysIo` that nothing ever writes to — a fixture that says "keys go
here" where no keys go, which is the deception this plan's helper rule exists
to stop.

So one of three shapes, and the choice belongs to gkc:

1. **Hold, as B was held** — move the callers that genuinely have a
   destination, leave the loose `atSign`/`rootDomain` deprecated and standing
   for the submit-only case. Consistent with the app-facing rule, and family D
   is app-facing by measurement.
2. **Require a session** and accept the empty destination at every
   submit-only site.
3. **Undeprecate `atSign` and `rootDomain` on the request**, on the grounds
   that every request needs an atSign and a session is not the only honest
   carrier — and deprecate only what the session really supersedes. ⚠️ This
   would drop C's count by 24 with nothing moved, which is the annotation
   artefact this plan warns about, arriving as policy rather than accident.

⚠️ Each family lands with the gates the rest of this plan uses, and B, C and D
run all four live packs before they commit: they change what an authentication
and an enrollment hand back, which every pack fixture reads.

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
