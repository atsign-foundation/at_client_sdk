# decisions.md, the client-lifecycle ledger

One ruling per section, numbered permanently, each carrying its status. The
reasoning sits with the ruling here rather than in a separate detail file,
since there are 7 of them; the design that applies them is
[`design.md`](design.md). A ruling that changes is corrected in place and its
status says so; nothing is appended as history.

| Status              | Means                                                                              |
| ------------------- | ---------------------------------------------------------------------------------- |
| `LIVE`              | Stands as ruled.                                                                   |
| `AMENDED`           | Stands, but part was changed later, on the date given.                             |
| `PARTLY SUPERSEDED` | Part was replaced and the rest holds. The body says which part went.               |
| `SUPERSEDED`        | Replaced outright. Title struck.                                                   |
| `REJECTED`          | Considered and not adopted. Title struck; the body stays so it isn't re-proposed.  |

All 7 were made by gkc on 2026-09-12, in one conversation, each after the
measurement it cites.

## 1. at_client owns the client lifecycle; at_auth is the protocol layer under it

`LIVE`. Onboarding, login and enrollment (both the requesting side and the
approving side) get one home, at_client, which at_client_flutter and
at_onboarding_cli use rather than orchestrating at_auth themselves. at_auth
stays a package and shrinks to the responsibilities gkc named: the registrar
API, activation, enrollment submission with `waitForApproval`, and approve as
the issuance of the verb on an authenticated connection plus the legacy keys
it conveys. Neither a new intermediate package nor absorbing at_auth into
at_client.

Why: at_client_flutter 1.1.4's published examples use deprecation families B
and D as one 40-line chain and declare `at_auth: ^3.0.0` themselves to name
the types; `npt_flutter` names 17 at_auth symbols and issues approvals
through at_auth directly, which conveys no post-quantum material; and the one
operation that already forced the better shape, `approve`, already delegates
to `atClient.enrollmentService` with a NOTE saying why. The alternatives
considered: at_client owning only the authenticated half (leaves the app
writing at_auth's types and at_auth's surface frozen); a new package between
at_client and the app-facing two (a ninth package to version for
orchestration that belongs beside the conveyance it needs); absorbing at_auth
(moves the `.atKeys` format's owner and every non-SDK consumer at once).

## 2. Login is client creation

`LIVE`. `AtAuth.authenticate` leaves at_auth's public surface together with
its six DTOs (`AuthRequest`, `AtAuthRequest`, `AtOnboardingRequest`,
`AuthResponse`, `AtAuthResponse`, `AtOnboardingResponse`). at_auth keeps the
`authenticatorFor` primitive. An app opens its client from an `AtKeysIo` and
the client PKAMs, as `AtClientManager.fromAuthSession` and
`setCurrentAtSign(atKeysIo:)` already do. A client-less "do these keys still
work" check, if wanted later, is a small at_client function over the same
primitive rather than an at_auth flow.

Why: authenticating and then building a client is two steps for one intent,
and every app in the sibling repositories performs them back to back. The
alternatives, a client-less `authenticate(atSign, AtKeysIo)` returning a
session, or the present shape with only the live objects stripped, each keep
a hand-off type the app has to carry across.

## 3. Clients are owned; the manager adopts

`LIVE`. `open`, `activate` and `enroll` return an `AtClient` the caller owns
and stops. `AtClientManager.getInstance().use(client)` is the only way a
client becomes current; the manager stops building clients and keeps the
current one plus the switch listeners.

Why: `buildAtClient` (owned) and `setCurrentAtSign` (current) both exist,
and `AuthService.createClient`'s dartdoc documents the muddle between them:
an owned client is filed in `AtClientImpl.atClientInstanceMap`, so a later
`setCurrentAtSign` adopts it, replaces its services without stopping the old
ones, and stops it on the next switch. NoPorts' bulk activation never wants a
client at all and closes at_auth's connection itself for want of an owner.
gkc took the recommendation and added ruling 4 in the same breath.

## 4. Open works offline; the outcome is online, offline or refused

`LIVE`. An `AtClient` is obtainable with no network, functional for
everything the local `AtClientStorage` serves. `open` reports which of three
outcomes it reached, as a current value and a stream on the client: online
(connected and PKAM accepted), offline (no atServer reached), refused (the
atServer rejected the credentials, with the reason: revoked, unauthenticated,
invalid enrollment). On refusal, the first open of a principal on a device
must be online: with no local store yet for that (atSign, enrollment) the
refusal throws a typed exception and nothing is handed back; with a store
present the client comes back in `refused(reason)` and the app decides. The
stream emits the same `refused` when revocation lands mid-life.

Why, in gkc's words: *"an app should still be able to get a functional
AtClient albeit functional only for everything which can use the local
AtClientStorage ... we just need to be able to distinguish, upon 'open my
AtClient', between (1) I've made a remote connection and am fully functional
and (2) I've not made a remote connection but am fully functional for offline
behaviour."* The third outcome was added because AT0027 ("Apkam Access
Revoked") maps to no exception type today, so `npt_flutter` matches the error
text for it, and because revocation is a state the client must surface
whenever it arrives. The first-open rule was preferred over "refusal always
throws" (which gives a revoked device nothing, and still needs a mid-life
state) and over "refusal always yields an offline client" (which hands a
mistyped keyfile a working-looking client with an empty store).

## 5. The key destination is the resume store

`LIVE`. `enroll(keys:)` files the minted keypair under the new enrollment id
as `pending` typed material in the destination the caller named, with app,
device and namespaces on the slot. Resume finds the pending slot for (app,
device) in the same store; approval flushes the completed keys and moves the
material to `active`; denial or expiry removes it. at_onboarding_cli's
`EnrollmentCheckpoint` file and at_client_flutter's keychain `EnrollmentData`
go. `CryptographicMaterialStatus` gains `pending`.

Why: both packages already persist an in-flight enrollment, differently, and
both look it up by the same things the keyfile's enrollment slot already
records (`AtKeysEnrollment` has `enrollmentId`, `namespaces`, `appName`,
`deviceName`, stamped by the submitter). The status vocabulary was made an
open, forward-ranked `String` on 2026-08-14 so that adding a token would stop
being a breaking at-rest change; an older build treats an unknown token as
not active and refuses transitions on it, which is the right reading of a
pending keypair. The protection a pending private key gets is the store's own
(passphrase envelope, OS keychain, or the chmod-600 plaintext the CLI
checkpoint uses today). Alternatives: a `PendingEnrollment` record beside the
store, persisted per platform (the present situation, tidied); in-memory only
(gives up a recovery both packages built on purpose).

## 6. at_onboarding_cli keeps a three-member `AtOnboardingService`

`LIVE`. `AtOnboardingServiceImpl(atSign, preference)`, `authenticate()` and
`getAtClient()`/`atClient` stay with their present meaning, implemented over
at_client's `open` (a `FileAtKeysIo` from `atKeysFilePath` and `passPhrase`)
and the manager's adopt; `authenticate()` answers true only for the online
outcome. The other ten members and the live-object getters go. `CLIBase` in
at_cli_commons builds on `open` directly.

Why: across the 7 sibling repositories that name the class (at_demos,
sshnoports, at_nautel_snmp, mwc_demo, google-travelers-workshops, kryzapp,
at_talk, at_tools and noports-tools name it; 7 call its members), the
receiver-matched call sites are `.authenticate()` 19, `.getAtClient()` 9,
`.atClient` 5, `.onboard()` 3 and `.enroll()` 3, the last two in sshnoports
only. Nothing outside this repository calls `sendEnrollRequest`,
`awaitApproval`, `createAtKeysFile`, `isOnboarded`, `getAtLookup`, `close`,
`completeActivation`, `.atLookUp`, `.atChops` or `.atAuth`. An adapter that
size migrates 7 repositories by dependency bump; deleting the class would
change 33 call sites including teaching material; keeping all fourteen
members would preserve a second, unused vocabulary for enrollment.

## 7. A new project, a P0 row, and a branch cut from the speed-up branch

`AMENDED` 2026-09-12, the same day. The design lives in
`docs/projects/client-lifecycle/`; the PQ table carries it as a **P0** row
(it gates at_auth 4.0 final, at_client_flutter 2.0, at_onboarding_cli 2.0
and the `npt_flutter` port, so it is on D1's critical path); the deprecation
plan's families B, C and D are marked superseded by it and the rest of that
plan continues as P1. The implementation is built on `gkc-client-lifecycle`,
which gkc directed be cut from `gkc-test-pack-speedup` once that branch's
work was committed and pushed, rather than from trunk after it merges; the
branch holds the session plumbing this builds on either way. That branch
merged to trunk as PR #2229 on 2026-09-12, and `gkc-client-lifecycle` was
rebased onto trunk the same day. Acceptance is
`npt_flutter` compiling with no `package:at_auth` import and no `at_auth:` in
its pubspec, the published-example rig reporting only the breaks the 2.0
CHANGELOGs name, and the four live packs green.

Why: a client-lifecycle design filed inside the PQ design (1,000 lines of
cryptography) or as step 9 of a clean-up plan would be read by nobody looking
for the client's public API. The ruling as first made preferred a branch from
trunk so as not to carry the speed-up branch's 82 commits through every
rebase; gkc chose to start at once on top of them instead, accepting that
this PR stacks on #2229 until that merges.
