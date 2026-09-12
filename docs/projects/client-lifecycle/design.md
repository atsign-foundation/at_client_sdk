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

In progress: steps 1, 2, 4 and 5 of [section 7](#7-what-is-owed-in-order)
are done, except the durable copy of the atServer address, and step 3 is
next. at_onboarding_cli's and at_client_flutter's own consumers of at_auth's
DTOs are gone with steps 4 and 5, so the removal in step 3 no longer has
either package in its way; their CHANGELOGs, READMEs and example trees from
step 6 went with them, and so did at_client's README. The functional and
e2e packs build their clients through `open` (their fixtures, and every
test that authenticated or onboarded through at_auth), which is what
`open` refusing a second client per **principal** rather than per atSign
was needed for: an owner client and an enrolled client of one atSign in
one process. `Atsign.authenticatesAs` is the client-less check ruling 2
allowed for, added because six pack tests assert exactly that. `AtClientManager.setCurrentAtSign` and `fromAuthSession` are not yet
deprecated: that waits until the live packs' fixtures are on `open`, so the
annotation never lands ahead of the callers it would flag. The work is a
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
One rule, not two.

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
`getAtClient()`/`atClient` stay with their present meaning, implemented over
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
new verbs. `setCurrentAtSign(atChops:)` stays deprecated until 4.0, as the
deprecation plan already records.

### at_client_flutter (2.0.0)

Deletes `AuthService` and `FlutterEnrollmentService` (their orchestration is
what moved; their only external consumer is `npt_flutter`, which is being
reworked). Keeps `KeychainStorage`, `KeychainAtKeysIo` and the dialogs under
their current names, rewritten over at_client's verbs (Private_Messaging_Armis
and kryzapp use the dialogs and the keychain, nothing else). Re-exports what
at_client re-exports, so one import covers an app.

### at_onboarding_cli (2.0.0)

Keeps `at_activate`, `at_register` and the `auth_cli` sub-commands, thin over
at_client and at_auth's registrar; keeps the three-member
`AtOnboardingService` adapter (ruling 6); drops `EnrollmentCheckpoint`
(ruling 5) and the eleven other service members.

### at_cli_commons

`CLIBase` builds on `open` and awaits the connection state with a budget
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
