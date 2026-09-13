# The client lifecycle: at_client owns onboarding, login and enrollment

An application should reach a working `AtClient` (activated, logged in, or
newly enrolled) through at_client alone, and manage its atSign's enrollments
through the client it holds. Today it can't: at_client_flutter and
at_onboarding_cli each orchestrate at_auth their own way, hand back at_auth's
own request and response types, and leave an app declaring `at_auth` in its
pubspec to name them. This document records what gkc ruled on 2026-09-12,
what each package keeps and loses, the shape a developer sees, and what is
owed to get there. The rulings themselves are one row each in
[`decisions.md`](decisions.md).

How far the build has got is in the [status](#status) below. The figures
were measured on 2026-09-12 and every one carries the command that
reproduces it in [section 9](#9-re-deriving-the-figures).

## Status

Every step of [section 7](#7-what-is-owed-in-order) is done. at_auth keeps
`activateAtSign`, `AtEnrollment.submit`, `approve` and `waitForApproval`,
the `.atKeys` store and the registrar: `AtAuth`, `authenticate` and the six
DTOs are gone, `AtAuthSession` carries no connection, `deny`, `revoke`,
`list` and the passcodes are `client.enrollments` on the client's own
connection, and `EnrollmentUpdater` is at_client's. at_onboarding_cli's and
at_client_flutter's own consumers of at_auth's DTOs went with steps 4 and 5;
their CHANGELOGs, READMEs and example trees from step 6 went with them, and
so did at_client's and at_auth's. The functional and e2e packs build their
clients through `open` (their fixtures, and every test that authenticated or
onboarded through at_auth), which is what `open` refusing a second client
per **principal** rather than per atSign was needed for: an owner client and
an enrolled client of one atSign in one process. `Atsign.authenticatesAs` is
the client-less check ruling 2 allowed for, added because six pack tests
assert exactly that. `AtClientManager.setCurrentAtSign` and `fromAuthSession`
are deprecated, removed in 4.0, now that the live packs' fixtures are on
`open`. The `npt_flutter` port is built on sshnoports branch
`gkc-client-lifecycle-port` (not pushed): acceptance item 1 measures no
`package:at_auth` import under its `lib/` and no `at_auth` dependency in its
pubspec, its analyzer reports no error and only warnings trunk already
carried, and its 359 tests pass. The port found that the keychain store
reported an atSign it did not hold as unreadable rather than absent, which
refused every first enrollment on a fresh keychain; fixed in
at_client_flutter. Acceptance item 2 was measured on 2026-09-13: against this
tree, at_client_flutter 1.1.4's `examples/todos` fails on 23 errors, every
one in its `onboarding.dart` and every one a member the 2.0.0-rc1 CHANGELOG
names (`AuthService`, the at_auth request and response types the barrel
used to re-export, and the dialogs' `show` signatures); at_onboarding_cli
1.16.0's examples fail on 10 errors, all named in its 2.0.0-rc1 CHANGELOG
(`AtOnboardingService.onboard`, `enroll`, `close` and `atLookUp`, and
`HomeDirectoryUtil.getCommitLogPath`); at_client 3.14.0's example, 22
files, reports no error and 3 deprecation infos that predate this work.
Acceptance item 3, all four live packs green, was met at the at_auth shrink
(functional 200, e2e 52 and 21, onboarding-CLI 21, proxy 4). The durable
copy of the atServer address came last: the address the atDirectory answers
is kept in the client's storage and a start that cannot reach the
atDirectory connects to it, on every connection the client holds. A
walk-through of every decision on 2026-09-13 confirmed them and added:
`open` refuses a second client on a storage location another holds;
`authenticatesAs` refuses with the cause `open` reports; the deprecated
`getAtClient()` is gone; the CLI inherits at_client's posture default on
every command; the pq key exchange of `enroll` is unit-tested. The
communications leg of the platform bundle
([section 10](#10-the-communications-leg-of-the-platform-bundle)) was built the same
day: the verbs take `lookUps:`, every connection a client opens comes from
it, and the four live packs were re-run green at that tip (functional 200,
e2e 52 and 21, onboarding-CLI 21, proxy 4), the proxy pack being the live
proof of `proxyLookUps()`. The work is a
**P0** row in the PQ table
([`../pq/implementation-plan.md`](../pq/implementation-plan.md)), since it
gates at_auth 4.0 final, at_client_flutter 2.0, at_onboarding_cli 2.0 and the
NoPorts `npt_flutter` port. It is built on `gkc-client-lifecycle`, cut from
`gkc-test-pack-speedup` on gkc's instruction of 2026-09-12 (ruling 7,
amended); that branch merged to trunk the same day as PR #2229, and the
lifecycle branch was rebased onto trunk. It supersedes families B, C and D
of the deprecation plan
([section 8](#8-relationship-to-the-other-plans)).

Those three families, one sentence each, so this document reads without the
plan. **B** is `AtAuthRequest.atAuthKeys` and `AuthResponse.atAuthKeys`,
`.atLookUp` and `.atChops`: the fields through which an app hands
authentication a fixed key set and gets back the keys, a live connection and
a crypto engine. **C** is the loose `atSign`, `rootDomain`, `apkamPublicKey`
and `encryptedAPKAMSymmetricKey` parameters of `AtEnrollmentRequest`'s
constructors, deprecated in favour of a `session` that carries the atSign and
a key destination. **D** is `AtEnrollmentResponse.atSign`, `.rootDomain` and
`.atAuthKeys`: the enrollment's identity and its completed keys, handed back
on the response rather than written to the store the app named.

## 1. The problem, measured

Five things, each observed in source rather than argued.

**An app uses B and D as one chain.** at_client_flutter 1.1.4's published
`examples/todos/lib/onboarding.dart` does, in 40 lines:
`ApkamActivationDialog.show(...)`, then read
`enrollmentResponse.atAuthKeys!` (line 77), then build
`AtAuthRequest(atAuthKeys:)` (line 81), then `PkamDialog.show(...)`, then
`setCurrentAtSign(..., atChops: response.atChops, atLookUp:
response.atLookUp)` (lines 116 and 117). `dockerstats` and
`example/lib/walkthrough.dart` do the same. That is every member of
deprecation families B and D, in the pattern the package's own examples
teach.

**The app declares at_auth itself.** That example's pubspec pins
`at_auth: ^3.0.0` and imports `package:at_auth/at_auth.dart`, because
at_client_flutter's signatures name `AtAuthRequest`, `AtAuthResponse` and
`AtEnrollmentResponse` while at_client's barrel re-exports one at_auth symbol
(`EnrollmentKeyExchangeMode`). In-tree at_client_flutter 1.1.5-rc1 requires
`at_auth: ^4.0.0-rc2`, so every such app already has to edit its constraint
to take the next at_client_flutter. Outside this repository, 12 working-tree
pubspecs declare at_auth: 6 in sshnoports (`npt_flutter`, `sshnoports`,
`noports_core`, `admin_api`, `npe2e`, `ve-verify`), plus at_talk, nptools,
at_widgets' at_onboarding_flutter, Private_Messaging_Armis and at_server's
e2e tests.

**NoPorts' authorisation UI approves through at_auth, so it conveys nothing
post-quantum.** `npt_flutter`'s `authorisation_hub_controller.dart` (trunk at
`138e2c6d8`) calls its own `AtEnrollment.create().approve(...)` on
`atClient.getRemoteSecondary()!.atLookUp` (lines 225 to 257). Against
published at_auth 3.3 that compiles and conveys the legacy key pair only, so
the approved device authenticates and can decrypt no PQ material. Against
this tree it is a compile error (`approverKeys` is required), which is the
compiler catching what the layering didn't. The same file uses
`FlutterEnrollmentService` for listing, OTP and SPP, and fishes the connection
out of the client for `list`. Its 17 at_auth symbols are enumerated in
[section 9](#9-re-deriving-the-figures); the app also knows that
`AtAuthImpl` caches its lookup (`multi_activation_cubit.dart:268`) and closes
`response.atLookUp` itself "because nothing else owns it".

**Two orchestrations of at_auth exist, and the one operation that forced a
better shape already has it.** `AuthService` and `FlutterEnrollmentService`
in at_client_flutter, and `AtOnboardingService` in at_onboarding_cli, cover
the same 8 capabilities with different names and key-destination behaviour.
`FlutterEnrollmentService.approve` delegates to
`atClient.enrollmentService!.approve(request)` with a NOTE saying why:
approving seals this atSign's secrets to the enrollee's key package, which
only the client's enrollment service can do. Its `deny`, `revoke`, `list`,
`waitForApproval`, `setSpp` and `generateOtp` still call at_auth directly.

**The listing verb is parsed twice and typed three ways.** at_client's
`EnrollmentServiceImpl.fetchEnrollmentRequests` builds its own
`enroll:list` and parses into `Enrollment` (mutable, all-nullable, carrying
`metadata`, which the conveyance and privilege resolver consume). at_auth's
`list` parses the same verb into `ServerEnrollmentRequest` (immutable, typed
`NamespacePermission`s, a status enum, no `metadata`), which `npt_flutter`
names 31 times. The typedef `EnrollmentServerResponse` is the third name.

Two facts about versions frame all of it. Every app-facing package is
delivering PQ as a **minor** (at_client 3.15.0-rc1, at_client_flutter
1.1.5-rc1, at_onboarding_cli 1.17.0-rc1); only at_auth is a major
(4.0.0-rc2, with rc1 published). And at_auth's `authenticate` is already
redundant with client creation: `AtClientManager.fromAuthSession` and
`setCurrentAtSign(atKeysIo:)` PKAM from an `AtKeysIo` through the same
`authenticatorFor` primitive.

## 2. The rulings

Seven, made in one sitting on 2026-09-12. The ledger has each as a row; this
is the reasoning.

**Ruling 1, scope.** The whole lifecycle goes into at_client. at_auth stays
as the protocol layer under it, shrunk to what happens before there is a
client plus approve; no new package, nothing absorbed. gkc: *"I am unhappy
with the current approach where applications have to directly import at_auth
to deal with onboarding, enrollment requests and enrollment management ... I
believe at_client should have an API surface which deals with all of that,
which at_onboarding_cli and at_client_flutter use."* The three constraints
that shaped the answer were what NoPorts needs from at_client_flutter, the
simplest shape of at_auth, and a shape that makes sense to application
developers. What at_client_flutter lacks turned out not to be Flutter at all
but headless orchestration, which at_onboarding_cli lacks and re-implements
too, so at_client is where it goes.

**Ruling 2, login is client creation.** `AtAuth.authenticate` and its six
DTOs (`AuthRequest`, `AtAuthRequest`, `AtOnboardingRequest`, `AuthResponse`,
`AtAuthResponse`, `AtOnboardingResponse`) go. at_auth keeps
`authenticatorFor`; at_client's `open` builds the client and PKAMs as it
already does. A client-less "do these keys still work" check, if wanted, is a
small at_client function over the same primitive.

**Ruling 3, ownership.** `open`, `activate` and `enroll` return an `AtClient`
the caller owns and stops. `AtClientManager.getInstance().use(client)` makes
one current, and that is the only way a client becomes current; the manager
stops building clients and keeps the current one plus the switch listeners.
This fixes the muddle `AuthService.createClient`'s dartdoc describes (an
owned client filed in `AtClientImpl.atClientInstanceMap` is adopted, has its
services replaced, and is stopped on the next switch), and it gives NoPorts'
bulk activation, which never wants a client, a clean `stop()` or nothing.

**Ruling 4, open works offline, and reports how it went.** gkc: *"an app
should still be able to get a functional AtClient albeit functional only for
everything which can use the local AtClientStorage ... we just need to be able
to distinguish, upon 'open my AtClient', between (1) I've made a remote
connection and am fully functional and (2) I've not made a remote connection
but am fully functional for offline behaviour."* There are three outcomes,
not two: **online** (connected and PKAM accepted, readable today from
at_lookup's `AtConnection.isAuthenticated`), **offline** (no atServer
reached: no network, atDirectory or atServer unreachable), and **refused**
(atServer reached, credentials rejected: revoked AT0027, unauthenticated
AT0401, invalid enrollment AT0029). The state is a current value plus a
stream on the client, since the network arrives after open and revocation
lands mid-life. On refusal: **the first open of a principal on a device must
be online**, so with no local store yet for that (atSign, enrollment) a
refusal throws a typed exception naming the reason and hands nothing back;
with a store present the client comes back in `refused(reason)` and the app
decides, the same transition the stream emits when revocation lands later.
One rule, not two. A stopped client reports `offline(stopped)` as its last
change and then stops recording: `stop()` closes the state before it closes
the services and the remote, so the failures the stop itself causes are not
reported as the atServer being unreachable.

**Ruling 5, the key destination is the resume store.** `enroll(keys:)` files
the minted keypair under the new enrollment id as `pending` typed material,
with app, device and namespaces on the slot (the submitter already stamps
those, `enrollment_submitter.dart:90` and `:329`). Resume finds the pending
slot for (app, device) in the same store; approval flushes the completed keys
and moves it to `active`; denial or expiry removes it. The CLI's
`EnrollmentCheckpoint` file and the keychain's `EnrollmentData` go. This adds
one token to `CryptographicMaterialStatus`, an at_auth-owned at-rest
vocabulary that was made an open, forward-ranked `String` on 2026-08-14 so
that adding a value would stop being a breaking change: an older build
round-trips a token it doesn't know, ranks it nowhere, treats the material as
not active (`at_keys.dart:435`) and refuses transitions on it, which is the
right reading of a pending keypair.

**Ruling 6, at_onboarding_cli keeps a three-member adapter.** Across the 7
sibling repositories that name `AtOnboardingService`, the receiver-matched
call sites are `.authenticate()` 19, `.getAtClient()` 9, `.atClient` 5,
`.onboard()` 3 and `.enroll()` 3 (both sshnoports only), and nothing else. So
`AtOnboardingServiceImpl(atSign, preference)`, `authenticate()` and
`atClient` stay with their present meaning (the deprecated `getAtClient()`
goes too, ruled 2026-09-13), implemented over
at_client's `open` (a `FileAtKeysIo` from `atKeysFilePath` and `passPhrase`)
and the manager's adopt; `authenticate()` returns true only for the online
outcome. The other ten members and the live-object getters go. Seven
repositories migrate by dependency bump; `CLIBase` moves onto `open` directly.

**Ruling 7, where it lands.** This directory, a P0 row in the PQ table, and
the branch `gkc-client-lifecycle`: cut from `gkc-test-pack-speedup` on gkc's
instruction and rebased onto trunk once that branch merged (the ledger has
the amendment). Acceptance is in [section 6](#6-acceptance).

## 3. What each package keeps, gains and loses

### at_auth (4.0.0, from rc2)

| keeps | why |
| ----- | --- |
| the artefact: `AtKeys`, the `.atKeys` format (`serialization/`), `AtKeysIo` with the file and memory stores | what activation and enrollment produce and login consumes; 2,729 of at_auth's 8,851 lines, and the format's owner shouldn't move |
| the primitive: `authenticatorFor` (keys to a PKAM signer) | at_client's `RemoteSecondary` already builds its connection from it |
| the registrar client | gkc's list |
| activation (CRAM onboarding, key minting) | gkc's list |
| enrollment submission and `waitForApproval`, including self-enrollment and the retrofit | gkc's list; a retrofit is an enrollment variant |
| approve: the `enroll:approve` verb plus the legacy key pair the approver seals | gkc's list, in his words: *"the actual issuance of the approve command on an authenticated AtLookup plus conveying the legacy keys"* |
| `CryptographicMaterialStatus.pending` | ruling 5 |

| loses | replaced by |
| ----- | ----------- |
| `AtAuth.authenticate` and the six auth DTOs | at_client's `open` (ruling 2) |
| `atLookUp`, `atChops` and the mutable `AtAuth.atLookUp` on responses and the interface | nothing: no app holds a connection at_auth opened |
| `list`, `deny`, `revoke`, `update`, `generateOtp`, `setSpp` and the `AtLookUp` parameter each takes | at_client, on its own `RemoteSecondary` (a recommendation, [section 5](#5-recommendations-that-are-not-yet-rulings)) |
| deprecation families B, C and D wholesale | gone with the DTOs; family F (the seven flat fields) is a separate question and stays open in the deprecation plan |

### at_client (3.15.0, a minor)

Gains a pre-client surface (`open`, `activate`, `enroll`, resume) that
returns owned clients, a connection state with its stream, a pending
enrollment handle, `AtClientManager.use(client)`, one enrollment listing type
that carries `metadata`, a typed exception for AT0027, and a durable copy of
the atServer address in client storage (today's
`CacheableSecondaryAddressFinder` is memory-only, so a cold offline start
cannot resolve where to reconnect to). Keeps `buildAtClient` underneath the
new verbs. The verbs and `buildAtClient` take `lookUps:`, the factory every
connection the client opens is built with
([section 10](#10-the-communications-leg-of-the-platform-bundle));
`AtClientPreference.decryptPackets`, `tlsKeysSavePath` and `pathToCerts` are
deprecated in favour of the factory's config. `setCurrentAtSign(atChops:)`
stays deprecated until 4.0, as the deprecation plan already records.

### at_client_flutter (2.0.0)

Deletes `AuthService` and `FlutterEnrollmentService` (their orchestration is
what moved; their only external consumer is `npt_flutter`, which is being
reworked). Keeps `KeychainStorage`, `KeychainAtKeysIo` and the dialogs under
their current names, rewritten over at_client's verbs (Private_Messaging_Armis
and kryzapp use the dialogs and the keychain, nothing else). The dialogs and
`AtsignFlows` take `lookUps:` and pass it to the verbs. Re-exports what
at_client re-exports, so one import covers an app.

### at_onboarding_cli (2.0.0)

Keeps `at_activate`, `at_register` and the `auth_cli` sub-commands, thin over
at_client and at_auth's registrar; keeps the three-member
`AtOnboardingService` adapter (ruling 6); drops `EnrollmentCheckpoint`
(ruling 5) and the eleven other service members. `AtOnboardingPreference.lookUps`
is `proxyLookUps()` when the root domain names a proxy and TLS otherwise, and
every command passes it to the verbs.

### at_cli_commons

`CLIBase` builds on `open`, takes `lookUps:` (the preference's with none)
and awaits the connection state with a budget
instead of looping on a bool. sshnoports' `admin_api` and `sshnoports` go
through it; `noports_core` and `sshnoports` also name the service directly.

## 4. The developer's view

One import, four verbs, no request or response objects. Names are
placeholders (see [section 5](#5-recommendations-that-are-not-yet-rulings)
for the one that matters):

```dart
final client = await Atsign('@alice').open(keys: FileAtKeysIo(...), preference);
client.connection.current;                 // online | offline | refused(reason)
client.connection.changes.listen(...);

final client = await Atsign('@alice').activate(cramSecret: s, keys: keysIo, preference);

final pending = await Atsign('@alice').enroll(otp: otp, app: 'noports',
    device: d, namespaces: {...}, keys: keysIo, signingAlgo: SigningAlgoType.mldsa65);
pending.progress.listen(...);              // pending, approved, denied
final client = await pending.client(preference);
// after a restart:
final pending = await Atsign('@alice').resumeEnrollment(app: 'noports', device: d, keys: keysIo);

// the manager holds the current client; nothing else builds one
AtClientManager.getInstance().use(client);

// the approving side, on an authenticated client, conveyance included
await client.enrollments.pending();
await client.enrollments.approve(id);   // .deny(id)  .revoke(id)  .otp()  .spp(...)
```

The at_auth types an app still names are its own key-store choice
(`AtKeys`, `AtKeysIo`, `FileAtKeysIo`, `KeychainAtKeysIo`), the listing
shape, and `NamespacePermission`; at_client re-exports them.
`ApkamActivationDialog` becomes UI over `enroll(...)`, and so does NoPorts'
own `onboarding_apkam_dialog.dart`, whose `_waitForApprovalAndFinish` (a raw
`AtEnrollment.create().waitForApproval` because `awaitApproval` took no retry
parameters, then the D-to-B chain) becomes `await pending.client(preference)`.
NoPorts' `AtClientMethods.activateFromAuthResponse` becomes `use(client)`.

## 5. Recommendations that are not yet rulings

Each is my recommendation with its reason; any of them can be overturned in
the ledger without touching the rulings above.

The handle should be **extension methods on at_commons' `Atsign`**, not a new
type. `Atsign` is already an extension type over `String`
(`packages/at_commons/lib/atsign.dart`), so `Atsign('@alice').open(...)`
reads naturally and adds no class; a new `AtSign` would collide with it in
everything but case.

The authenticated-side verbs (`list`, `deny`, `revoke`, `update`, OTP and
SPP) should move to at_client and go from at_auth. Each is one verb on a
connection the client already holds; at_client already parses `enroll:list`
itself; and the one listing type has to be at_client's `Enrollment`, since the
conveyance needs `metadata` and at_auth's `ServerEnrollmentRequest` doesn't
carry it. That leaves at_auth with exactly gkc's list.

`open` should make one bounded connect attempt with a short default budget
(seconds, not the 30 s authentication timeout), return the client with the
initial state, and let the stream carry the rest. The connection state
should follow `AtReachabilityResult`'s shape (an outcome enum, a result
object, a predicate to read instead of comparing outcomes).

`activate` and `enroll` should take a `WrittenAtKeysIo`, since they write;
`open` takes an `AtKeysIo`, since it reads. The type system then says what
`AtAuthSession.atKeysIo` had to say in a NOTE.

at_auth's own request objects for submission can stay as internal shapes; the
public verbs are parameter lists, so families C and D collapse without
anything replacing them one for one. The registrar client is re-exported
as it is, being an HTTP client to the registrar that an app drives directly.
Progress events ride the pending handle and `activate`, as
`AtAuth.progressStream` and `AtEnrollment.progressStream` do today.

The four live packs' fixtures build clients through the old paths (the
functional pack alone has 14 uses of family C) and migrate onto `open` with
everything else; they are consumers like any other.

An enrolled client offline authorises its local reads and writes from the
keyfile's `AtKeysEnrollment` snapshot when `enroll:fetch` cannot reach the
atServer, logging at `warning` that the grants are the last ones seen. Before
this the check refused outright (the measurement in
[section 7](#7-what-is-owed-in-order)), which made ruling 4 true only for
the atSign's own credential. The snapshot is refreshed on every authenticated
start and a stale grant costs nothing the atServer would not catch: a
local-first write is refused at sync if the grant has since narrowed, exactly
as it would be with the record fetched live. A refusal from an atServer that
answered is not a fallback case, and a client with no snapshot yet (a keyfile
written before the snapshot existed, on its first start) keeps the refusal.

`SecondaryNotFoundException`, the atDirectory answering that this atSign has
no atServer, is neither a transport failure nor a credential refusal. It
should be a typed cause on the connection state rather than text, since
NoPorts already tells it apart from "no network"; under the first-open rule
it counts as refused (the atSign has never worked on this device), and with a
store present it is reported as offline carrying that cause. Whether it
deserves a fourth outcome instead is gkc's call.

## 6. Acceptance

Three measurements, not a review:

1. `npt_flutter` compiles against the tree with **no** `package:at_auth`
   import in `lib/` and **no** `at_auth:` line in its pubspec, using the
   absolute `dependency_overrides` its working tree already carries.
2. The published-example rig from the deprecation plan (extract a published
   package's archive, point its example at the tree, `pub get`, analyse)
   reports the **expected** breaks for at_client_flutter 1.1.4 and
   at_onboarding_cli 1.16.0, each named in their 2.0 CHANGELOGs, and none
   for at_client 3.14.0's example.
3. All four live packs green on the new paths, with `--concurrency=1`.

## 7. What is owed, in order

1. **Today's offline open, measured.** `buildAtClient` returns in 52 to
   57 ms with no atServer reachable, whether the atDirectory refuses the
   connection, cannot be resolved, or drops packets: nothing in
   `AtClientImpl._init` awaits the network. The client then serves everything
   local storage holds, a `put` in about 22 ms and the `get` that reads it
   back in about 6 ms, and `stop()` returns in under 5 ms. What the client
   does **not** do is say so: its connection reports
   `isConnectionAvailable() == false` and no authentication, the warm-start
   sync logs its failure at `warning` half a second later (or after the 30 s
   connect timeout against a blackhole, by which time a short-lived process
   has moved on), and the monitor never starts, because the stats
   subscription delays it 30 s. That silence is the gap ruling 4 fills.
   Pinned by `packages/at_client/test/lifecycle/offline_open_test.dart`,
   which builds a client against a refused local port; the three variants
   were run by hand on 2026-09-12 against
   `tests/at_functional_test/test/testData/@alice🛠_key.atKeys` and a
   temporary Hive path.

   **Only for the atSign's own credential.** The same build as an enrolled
   client (`enrollmentId` other than `primary`) throws on its first `put`:
   `LocalSecondary` authorises every non-`local:` read and write against the
   enrollment record, fetches that record with `enroll:fetch` and, in its
   own words, keeps "deliberately no durable cache", so with no atServer the
   check cannot run and the write is refused as
   `Failed to fetch the enrollment record`. Every app-enrolled client, which
   is every NoPorts device, is in this population. The keyfile already holds
   a durable copy of the grants, the `AtKeysEnrollment` snapshot the PQ
   startup refreshes on each authenticated start, and the client now
   authorises from it when the fetch cannot reach the atServer
   ([section 5](#5-recommendations-that-are-not-yet-rulings) has the
   reasoning); the same test file pins the granted, the ungranted and the
   no-snapshot cases.
2. at_client's pre-client surface and connection state, over `buildAtClient`
   and `fromAuthSession`; `use(client)`; the AT0027 exception; the durable
   address; the pending enrollment over `CryptographicMaterialStatus.pending`
   and `recordEnrollmentSnapshot`.
3. at_auth shrinks: the six DTOs and `authenticate` go, the live objects go,
   the authenticated-side verbs move, `pending` lands.
4. at_client_flutter 2.0: the two services deleted, dialogs rewritten,
   keychain kept.
5. at_onboarding_cli 2.0: the adapter, the binaries, `EnrollmentCheckpoint`
   removed; at_cli_commons' `CLIBase` onto `open`.
6. CHANGELOGs, READMEs and both example trees; then the port of
   `npt_flutter`, which is acceptance item 1.
7. The communications leg of the platform bundle
   ([section 10](#10-the-communications-leg-of-the-platform-bundle)): `AtLookUpFactory`
   and its default, `lookUps:` on the verbs and everything under them, the
   proxy factory, the preference's TLS fields deprecated.

## 8. Relationship to the other plans

The deprecation plan's step 8 recorded families B, C and D as held or open
on the question of whether an app-facing package may break. This design
answers it differently: the types those families annotate are removed with
`AtAuth.authenticate`'s DTOs, and the app-facing packages take a major to do
it, so there is nothing to hold and no caller to migrate one field at a
time. The plan's rows for B, C and D point here; its remaining owed work
(the test-tree remainder of steps 6 and 7, then `LocalSecondary`'s `AtChops`
tier, and the open question on family F's annotation) is unchanged and stays
a P1 row.

The PQ table carries this as a P0 row because it is on D1's critical path.
The motivation is PQ conveyance: an approval issued through at_auth alone
conveys the legacy keys and nothing else, which is what NoPorts does today.

## 9. Re-deriving the figures

All counts are over working trees under `~/dev/atsign/repos/`, so each is a
claim about the checkout's current branch; `sshnoports` was on `trunk` at
`138e2c6d8`. Run from the repository root.

The at_auth symbols `npt_flutter` names (17 real ones; `type` is a false
positive of the declaration scan):

```bash
python3 - <<'PY'
import os, re, collections
sdk = 'packages/at_auth/lib'
app = os.path.expanduser('~/dev/atsign/repos/sshnoports/packages/dart/npt_flutter')
syms = set()
for dp, _, fns in os.walk(sdk):
    for fn in fns:
        if fn.endswith('.dart'):
            t = open(os.path.join(dp, fn), encoding='utf-8', errors='replace').read()
            syms |= set(re.findall(r'^(?:\w+\s+)*(?:class|enum|typedef|mixin|extension)\s+(\w+)', t, re.M))
use = collections.Counter()
for dp, dns, fns in os.walk(app):
    dns[:] = [d for d in dns if d not in ('.dart_tool', 'build')]
    for fn in fns:
        if fn.endswith('.dart'):
            t = open(os.path.join(dp, fn), encoding='utf-8', errors='replace').read()
            for s in syms:
                use[s] += len(re.findall(r'\b' + re.escape(s) + r'\b', t))
for s, n in use.most_common(): print(n, s)
PY
```

`AtOnboardingService` members called across the sibling repositories
(receiver-matched, so a `.authenticate(` on some other object is not
counted):

```bash
python3 - <<'PY'
import os, re, collections
root = os.path.expanduser('~/dev/atsign/repos')
members = 'onboard|authenticate|enroll|sendEnrollRequest|awaitApproval|createAtKeysFile|getAtClient|isOnboarded|getAtLookup|close|completeActivation|atClient|atLookUp|atChops|atAuth'
rx = re.compile(r'\b(\w*[oO]nboardingService\w*|onboardingService|svc|service)\s*[!?]?\.\s*(' + members + r')\b')
per = collections.defaultdict(collections.Counter)
for repo in sorted(os.listdir(root)):
    rp = os.path.join(root, repo)
    if not os.path.isdir(rp) or repo.startswith('at_client_sdk') or repo == 'tmp': continue
    for dp, dns, fns in os.walk(rp):
        dns[:] = [d for d in dns if d not in ('.git', '.dart_tool', 'build', 'node_modules', 'untracked')]
        for fn in fns:
            if fn.endswith('.dart') and not fn.endswith('.mocks.dart'):
                t = open(os.path.join(dp, fn), encoding='utf-8', errors='replace').read()
                if 'AtOnboardingService' in t:
                    for m in rx.finditer(t): per[m.group(2)][repo] += 1
for mem, c in per.items(): print(mem, sum(c.values()), dict(c))
PY
```

Pubspecs outside this repository declaring at_auth (12 after excluding the
`tmp/` copy of this repository):

```bash
grep -rl --include=pubspec.yaml -P '^\s{2}at_auth:' ~/dev/atsign/repos \
  | grep -v '/at_client_sdk' | grep -v '/\.dart_tool/' | grep -v '/tmp/'
```

The published examples' use of the chain, from the pub cache (the version is
the one named, never the newest directory):

```bash
grep -rn 'atAuthKeys\|\.atChops\|\.atLookUp' \
  ~/.pub-cache/hosted/pub.dev/at_client_flutter-1.1.4/example*/ --include=*.dart
```

## 10. The communications leg of the platform bundle

A client is built from three platform-supplied things. Two are in place:
the keys store (`AtKeysIo`, leg 1) and the storage bundle (`AtClientStorage`,
leg 2). The third is how the client reaches the atServer. Before this leg
every place that needed a connection called `AtLookUp.withSecureSocket`
itself, so an application could not substitute the transport, the proxy
convention or a test double without reaching into each one. gkc asked on 2026-09-13 for the entry
points to supply an **`AtLookUp` factory function**, used wherever a lookup is
built. The eight decisions at the end were ruled by gkc the same day and are
[ruling 8](decisions.md#8-the-communications-leg-an-atlookup-factory-the-entry-points-supply)
in the ledger; the leg was built the same day on the lifecycle branch, as the
"what changes where" table below describes, with the every-connection pin in
at_client's `test/lifecycle/lookups_test.dart` and the preamble's in
at_lookup's `test/lookup_factory_test.dart`.

### What built a lookup before the leg, measured

Direct `AtLookUp.withSecureSocket` calls in library code before the leg, 10
across four packages (`grep -rn "AtLookUp.withSecureSocket(" packages/*/lib`;
the same grep now finds three, at_lookup's `secureSocketLookUps` and at_auth's
two defaults for a caller that hands it no connection, plus one in a dartdoc
example):

| Site                                                   | For                                                                                  | Varies                                                                      |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| at_client `remote_secondary.dart`                      | the client's own connection, and through it sync's (`remoteSecondaryFor`), the file-stream path and the re-derive after a retrofit | authenticator, `secondaryAddressFinder`, `clientConfig`, the preference's TLS fields |
| at_client `notification_service_impl.dart`             | the monitor's connection                                                             | authenticator from `AtChops`, the preference's TLS fields                   |
| at_client `atsign_lifecycle.dart` (`enroll`)           | the unauthenticated submission                                                       | none: `authenticator: null`                                                 |
| at_client `authenticated_lookup.dart`                  | `open`'s probe and `authenticatesAs`                                                 | authenticator from the keys                                                 |
| at_auth `enrollment_handshake.dart`                    | `waitForApproval`, when the caller passed none                                       | none                                                                        |
| at_auth `at_auth_impl.dart`                            | the deprecated `onboard` path, when the caller passed none                           | none                                                                        |
| at_onboarding_cli `auth_cli.dart` (`status`)           | a public-key lookup                                                                  | none                                                                        |
| at_onboarding_cli `auth_cli.dart` (`_proxyLookUp`)     | a connection through a proxy, with `from:` sent first                                | the proxy convention: `rootDomain` starting `proxy:`                        |
| at_server_status `at_status_impl.dart`                 | the status probe                                                                     | none                                                                        |

Every one passed `secureSocketTransport(SecureSocketConfig())`, the client's
two adding the preference's `decryptPackets`, `pathToCerts` and
`tlsKeysSavePath`. Three sites took an optional `AtLookUp?` and built one
only when handed none; at_client's `open`, `activate`, `enroll`,
`resumeEnrollment`, `authenticatesAs` and `buildAtClient` all carry that
`atLookUp:` parameter still (C3), and 23 test files use it to inject a mock.

What that injection did not reach: when a test handed `open` a mock lookup,
the client's own connection was the mock, but sync's `remoteSecondaryFor` and
the monitor built **real** lookups from the preference, so two of the three
connections a client held escaped the double. The factory reaches all three;
at_client's `test/lifecycle/lookups_test.dart` pins that every connection a
client opens, its own, sync's and the monitor's, came from the one it was
given, with a client built without one as the control.

Not built through `withSecureSocket`, and not this leg: at_lookup's
`CacheableSecondaryAddressFinder` (a raw TLS socket to the atDirectory, the
`SecondaryAddressFinder` interface being the injection point), at_client's
`StreamNotificationHandler` (the legacy file stream, a raw socket), at_auth's
provisioning probe (`socket_probe_io.dart`), and at_lookup's `MonitorClient`
(exported, no caller in this repository). The WASM design's transport section
owns those.

### The shape

```dart
// at_lookup, beside withSecureSocket
typedef AtLookUpFactory = AtLookupMuxable Function({
  required String atSign,
  required AtRootDomain rootDomain,
  required AtAuthenticator? authenticator,
  SecondaryAddressFinder? secondaryAddressFinder,
  Map<String, dynamic> clientConfig,
});

// at_lookup_io.dart: the default, and the only place that names the TLS
// transport. onConnect runs once on each new connection, before anything else
// is sent on it: the proxy's `from:` goes there.
AtLookUpFactory secureSocketLookUps({
  SecureSocketConfig? config,
  Future<void> Function(AtCommandExecutor connection)? onConnect,
}) {
  final transport = secureSocketTransport(config ?? SecureSocketConfig());
  return ({required atSign, required rootDomain, required authenticator,
      secondaryAddressFinder, clientConfig = const {}}) =>
        AtLookUp.withSecureSocket(
            atSign: atSign, rootDomain: rootDomain, authenticator: authenticator,
            transport: transport, secondaryAddressFinder: secondaryAddressFinder,
            clientConfig: clientConfig, onConnect: onConnect);
}
```

The factory captures **how bytes travel** (the transport and its settings, or
a wholly different `AtLookUp` implementation); each call names **what the
connection is for** (which atSign, how it authenticates, which address finder,
what it announces about itself). The root domain stays a per-call argument,
from the preference or the verb, so where the atDirectory is does not move.

The application supplies it where it supplies the other two legs:

```dart
final client = await Atsign('@alice').open(
    keys: keys, storage: storage, preference: preference,
    lookUps: secureSocketLookUps(config: SecureSocketConfig()..pathToCerts = certs));
```

and the client holds it: `buildRemoteSecondary`, sync's `remoteSecondaryFor`,
the file-stream path and the re-derive after a retrofit all call
`client.lookUps(...)` instead of `AtLookUp.withSecureSocket(...)`, and the
monitor's connection comes through `NotificationServiceImpl.create(lookUps:)`,
the way that service takes `connection`: it holds the client as its
interface, so the caller that built the client hands it the factory. The
verbs build the lookups they need with it and hand **instances** to at_auth
(`AtEnrollment.submit(request, lookUp)`, `waitForApproval(atLookup:)`,
`activateAtSign(atLookUp:, awaitProvisioning: true)`, the flag because a
lookup at_client built has not reached the atServer yet), so at_auth never
learns the type. The Flutter dialogs and `AtsignFlows`, `CLIBase` and the
`at_activate` commands take `lookUps:` and pass it through; a program that
supplies none gets `defaultLookUps(preference)`, TLS with the preference's
three TLS fields, which is what every site built before. That function, in
`lifecycle/lookups.dart`, is the one at_client file that imports
`at_lookup_io.dart`; everything else takes the factory it is handed, so the
package's reach into the TLS transport is one seam, beside the Hive default
the storage leg left in `at_client_factory.dart`.

Two things fell out. The CLI's `_proxyLookUp` became `proxyLookUps()`, a
factory that sends `from:` first through `onConnect`, a hook
`withSecureSocket` gained for it: the factory is synchronous and the preamble
is not, so the preamble is a step on the connection, run once by
`createConnection` after it has released its mutex and before anything else
is sent, writing to the socket directly. `AtOnboardingPreference.lookUps`
supplies that factory when the root domain names a proxy, so the convention
stopped being a string prefix each site had to know. And a test's factory
reaches all three of a client's connections, because sync and the monitor
ask the same one.

### What changed where

| Package             | Change                                                                                                                                                                                                                              |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| at_lookup           | `AtLookUpFactory` beside `withSecureSocket`; `secureSocketLookUps` in `at_lookup_io.dart`; `withSecureSocket(onConnect:)`. A minor: nothing existing changes.                                                                        |
| at_client           | `buildAtClient(lookUps:)`, `AtClientImpl.lookUps`, `AtServiceFactory.atClient(lookUps:)`; the five construction sites call it; `open`, `activate`, `enroll`, `resumeEnrollment`, `authenticatesAs` take `lookUps:`; the preference's three TLS fields deprecated in favour of the factory's config. |
| at_client_flutter   | `AtsignFlows` and the three lifecycle dialogs take `lookUps:`; the README points at at_client's factory example.                                                                                                                  |
| at_cli_commons      | `CLIBase.fromCommandLineArgs(lookUps:)`, the preference's with none; the README's "Choosing the transport" section.                                                                                                                 |
| at_onboarding_cli   | `AtOnboardingPreference.lookUps`; the commands, `createAtClient` and the onboarding service pass it to every verb; `proxyLookUps()` replaces `_proxyLookUp`; `status`'s public-key lookup uses it.                                    |
| at_server_status    | `AtStatusImpl(lookUps:)`.                                                                                                                                                                                                           |
| at_auth             | keeps taking instances; `activateAtSign(awaitProvisioning:)`, so a lookup at_client built still gets the provisioning wait.                                                                                                         |
| tests               | `test/lifecycle/lookups_test.dart`: every connection a client opens (its own, sync's, the monitor's) came from the factory, with a client built without one as the control, plus `open`'s probe and `enroll`'s submission; at_lookup's `test/lookup_factory_test.dart`: the preamble runs once per connection, before anything else. The 23 files injecting `atLookUp:` keep working; the three `Mock implements AtClientImpl` doubles carry a concrete `lookUps`, as they carry `connection`. |

### Decisions

All ruled 2026-09-13, each as recommended.

| Id | Question                                                                                                          | Recommendation                                                                                                                                                                     |
| -- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C1 | A bare function type, or a small object (`AtConnections`) carrying the factory, the root domain and the address finder, like the storage bundle? | The function, as asked: the other two legs are objects because they carry state, and a factory captures what it needs. The root domain stays where it is. |
| C2 | Where the application hands it over: a parameter on the verbs (as `storage:` is), or a field on `AtClientPreference` (which the services already read)? | The verbs, held on the client, as leg 2 is; the preference stays serialisable configuration. The default is built from the preference's TLS fields.            |
| C3 | The existing `atLookUp:` instance parameters on the verbs, `buildAtClient` and `AtServiceFactory`: keep, or replace with the factory? | Keep for this change: 23 test files and "a caller that already holds one" use them. A factory returning the held instance covers the case later; deprecate then.  |
| C4 | Deprecate `AtClientPreference.decryptPackets`, `pathToCerts` and `tlsKeysSavePath`?                               | Yes: they configure the transport, which is now the factory's. The default factory keeps reading them while deprecated.                                                           |
| C5 | Does at_auth gain the type?                                                                                       | No: at_client builds the lookups and passes instances, as it does now.                                                                                                             |
| C6 | Who owns the type and the default?                                                                                | at_lookup, beside `withSecureSocket`; the default in `at_lookup_io.dart`, the one file that names the TLS transport.                                                              |
| C7 | The CLI's proxy: a factory from `AtOnboardingPreference` when `rootDomain` names a proxy?                          | Yes; it is the first non-default implementation and retires a string convention from the call sites.                                                                              |
| C8 | Do this in this PR or the next?                                                                                   | This PR: it changes the verbs' signatures, which have not published, and the packs already build every client through `open`.                                                     |
