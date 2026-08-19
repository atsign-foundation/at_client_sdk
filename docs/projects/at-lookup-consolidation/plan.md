# One listener, two framings

Status: design settled. **Steps 1-4 have landed.** The response budget in
at_commons; `FakeAtServerSocket` and the `_stripPrompt` bug it found on first
use; the event-driven `read()` and the second framing; `AtAuthenticator` and
`AtCommandExecutor`; and authenticators supplied from at_auth for all three
credential shapes a caller can hold.

**Step 4's production migration is complete, and measured rather than
asserted.** With all four authentication entry points instrumented at `shout`,
a functional pass counts **250 of 257 authentications through the injected
seam**. `_process` never falls through to the ladder. The remaining **7** are
test files constructing an `AtLookupImpl` directly, and can only change when
step 5 removes the fields. Re-derive with the recipe in
[section 7](#7-corrections).

Six `lib/` sites still *write* `atChops` onto a lookup, deliberately: the
authenticator is installed **beside** that field, not instead of it, because
`EnrollmentApprover` and others still read it for work that is not
authentication.

**Step 5 was blocked on a ruling and the ruling has been made: the credential
members are `@Deprecated` in 3.x, not deleted** (gkc, 2026-08-19). Deleting
them breaks `AtLookUp`, which is a public interface, and this project ships as
an additive minor. So step 5 annotates and documents; the deletion becomes a
scheduled later major, and the prerequisites below survive as its preconditions
rather than this step's. **Landed as the annotation pass**: six members, on
both the interface and the impl override, because most callers hold the
concrete type and an interface-only annotation would fire for almost nobody.

That pass is measured, not asserted. `dart analyze --fatal-warnings` over all
16 workspace members: **16 of 16 exit 0 before and after**, findings 1201 →
1286, every one of them `info`. Nothing breaks and no reader has to move
first, because `deprecated_member_use` is `info` here and `--fatal-warnings`
does not promote it.

⚠️ **The annotation therefore signals almost nothing on its own.** 1151 of the
1201 baseline findings were *already* `deprecated_member_use`, nearly all from
at_chops' in-flight compatibility deprecation, so 90 more land invisibly in
that pile. The signal a consumer actually reads is the doc comment, the
CHANGELOG and this plan — not the analyzer. Do not treat "we deprecated it" as
having told anyone.

## The acceptance gate for the whole sequence

**Zero uses of `AtLookupImpl` in lib code and READMEs** (gkc, 2026-08-19).
Mechanical, re-runnable, and it prints its own positive control:

```bash
bash docs/projects/at-lookup-consolidation/count_atlookupimpl.sh
```

Reading at `3e4919d22` + step 6a/6b: **47 uses across 24 files**, against a
control finding 169 `AtLookUp`. A further 111 sit in tests, examples, docs and
CHANGELOGs; those are reported by the script and deliberately **not** gated,
because a CHANGELOG entry describing what `AtLookupImpl` did in a released
version is a true statement about that version.

⚠️ **47 is not the plan's "64 construction sites" with a different name.** 64
counts constructions; 47 counts every use in scope — constructions, type
annotations, `is` checks and imports. Quoting one for the other is the mistake
[section 7](#7-corrections) already records twice.

**Next is the deletion's preconditions**, marked **BLOCKS THE MAJOR** in
[section 6](#6-filed-not-scheduled).

This line is the only statement of progress. `git log` records what landed;
[section 7](#7-corrections) holds the readings that were superseded and why.
Owner: gkc.
Written against `gkc-pq-d1-spike` at `9f5da2ad0` and `origin/trunk` at
`401e14d98`, 2026-08-19.

Goal: fold the connection-consolidation work into `gkc-pq-d1-spike` as an
additive **minor** release, by deleting duplicated machinery rather than
replacing it. Every public contract survives; the connection count does not
change; `at_lookup` stops holding key material.

Three local branches feed in and none lands as written:

- `gkc-fewer-connections` — a 4.0.0 rewrite deleting `AtLookupImpl`, renaming
  the public interface and collapsing two sockets into one. **Local-only: no
  upstream, on no remote ref.** Used here as a design reference, not merged.
- `gkc-increase-message-listener-timeout-defaults` — adds two process-wide
  mutable statics to `OutboundMessageListener`.
- `gkc-pq-d1-spike` — the branch this lands on. Its at_lookup 3.7.0 commit
  `4e2507012` is the evidence that started this work.

Contents:

1. [The frame](#1-the-frame)
2. [What Monitor duplicates](#2-what-monitor-duplicates)
3. [Decisions](#3-decisions)
4. [The factory](#4-the-factory)
5. [Order of work](#5-order-of-work)
6. [Filed, not scheduled](#6-filed-not-scheduled)
7. [Corrections](#7-corrections)

## 1. The frame

`monitor.dart:439-442` records `authenticatedAsEnrollmentId` and
`authenticatedAt` on its own connection metadata, with a comment explaining that
Monitor authenticates independently of `AtLookupImpl`. That is commit
`4e2507012` — the at_lookup 3.7.0 change, the only at_lookup commit on this
branch — **written a second time because Monitor has its own PKAM.** The
duplication tax is being paid in current work, not historical work.

The collapse from two connections to one is *not* part of this work. It becomes
a wiring choice: hand Monitor a fresh `AtLookupMuxable` and the count is
unchanged; hand it `RemoteSecondary`'s and it is one. That switch requires no
further at_lookup change once this lands.

## 2. What Monitor duplicates

Measured at `gkc-pq-d1-spike`: `monitor.dart` (582 lines) against
`outbound_message_listener.dart` and `at_lookup_impl.dart`.

| Piece                                    | Verdict                                                                                                                                                  |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_checkBufferOverFlow`                   | Near-identical — differs only by `dynamic` vs `List<int>` and a redundant `as int`.                                                                       |
| `_stripPrompt`                           | **The duplicate carries a fix the original lacks.** Monitor guards `if (colonIndex == -1) return result;`; the listener would `substring(0, -1)` without it. |
| Framing constants, byte buffer           | Declared in both.                                                                                                                                        |
| PKAM auth                                | Fully duplicated from `AtLookupImpl.pkamAuthenticate`, including the new enrollment recording.                                                            |
| Reconnect backoff                        | **The same list in both** — `[1, 2, 3, 5, 8, 13, 21, 34]` seconds. Plus a heartbeat each.                                                                 |
| `sendCommandMutex` + `requestCompleter`  | **Only in the duplicate.** The original still polls every 10 ms.                                                                                         |
| `messageHandler`                         | **Genuinely different, not duplication.** Monitor frames on a bare `\n`; the listener frames on `\n@`.                                                    |

That last row is the shape of the job. The two parsers are not redundant copies
— they read two different framings, and the consolidation is one listener that
knows both.

## 3. Decisions

Numbering is dependency order: each unblocked the next.

**1 — Freeze `AtLookUp`; new surface goes on a sub-interface.** `AtLookUp` keeps
exactly today's members; `AtLookupMuxable implements AtLookUp` carries the new
ones. The break was never in the impl: **18 `Mock`/`Fake implements` sites**
exist — at_auth 12, at_client_flutter 3, at_client 2, at_onboarding_cli 1 — and
widening the interface would leave them satisfying the new members through
`noSuchMethod`, returning null into non-nullable types **at runtime only**, with
`dart analyze` clean.

⚠️ The freeze protects **5** of those 18 — the ones that mock `AtLookUp`. The
other **13 mock `AtLookupImpl`**, the concrete class, which *does* gain the
muxable members in step 6, so they are exposed exactly as before. Sweep them in
that step; the compiler will not.

```bash
git grep -nP 'class \w+ extends (Mock|Fake) implements AtLook\w*'
```

**2 — Monitor consumes a notification stream, not a socket.** It keeps its own
concerns — regex, last-notification time, surfacing state — and loses connection
creation, PKAM auth, buffer, framing, overflow check, prompt stripping and
`sendCommand`. After `monitor:` a plain socket stops carrying request-response,
so a Monitor that *takes over* its AtLookUp's socket could only ever be handed a
dedicated one; only a both-framings listener keeps the shared-connection option
reachable.

**3 — `read()` becomes a completer plus a resettable idle timer.** The 10 ms poll
loop goes. `Monitor.sendCommand`, the pattern being ported, has **one** timeout;
`read()` has two. `maxWaitMilliSeconds` is total wall-clock, while
`transientWaitTimeMillis` means *no bytes at all for N ms* and is reset by
`messageHandler` on every chunk. A bare completer cannot express the second, so
porting verbatim would silently drop server-went-quiet detection.

**4 — One listener, evolved in place.** `OutboundMessageListener` gains the
completer, the idle timer and an optional `onNotification` callback. No
`MultiplexedOutboundMessageListener` class. Two listeners would recreate inside
at_lookup exactly the duplication being deleted from Monitor. Safe in place: the
file is **not in at_lookup's barrel**, and its one external consumer,
`at_client_impl.dart:1772`, calls `.read(maxWaitMilliSeconds: …)` — a signature
decision 3 preserves.

**5 — Deprecate the constructor; add a factory; keep the class.**
`AtLookupImpl` leaves the public barrel at the next major. **The 64
`deprecated_member_use` warnings are the deliverable**, not a cost — they are the
mechanical list of where construction must change. A static factory is additive,
because statics are not part of the `implements` contract, so it does not disturb
decision 1's freeze.

**6 — Single-subscription controller, pause wired to the socket.**
`notifications` is a normal `StreamController`, not a broadcast one, with
`onPause`/`onResume` wired to the socket subscription. Today `monitor.dart:508`
pauses the socket subscription, awaits full handling and resumes in a `finally`
at `:542` — real end-to-end back-pressure. A broadcast controller does not
buffer, does not honour pause, and drops anything arriving before a listener
attaches; a dropped event nothing retries is data loss.

**7 — Timeouts live in `AtNetworkTimeouts`, split by kind.** Transient reads
`AtNetworkTimeouts.effectiveDefault`; the total becomes a new
`defaultResponseBudget`, documented as uncapped-by-design. at_commons already
declares itself the single place for this and its dartdoc covers "waiting for a
response". Its `defaultTimeout` is **30 s** — the exact value the timeouts branch
independently picked. It already distinguishes the kinds: `maxAllowed` (60 s)
caps operations, `defaultOnboardingTimeout` is exempt because it bounds a loop.
The total must follow the second, since at_client passes
`outboundConnectionTimeout` — **600 000 ms** — for stream reads.

**8 — A fake socket over a real `StreamController`, plus mechanism counters.**
The waiting path itself **is** covered, contrary to what this decision first
claimed: printing inside the poll loop and running
`outbound_message_listener_test.dart` counts **38 iterations across 7 tests** —
the whole `AtTimeOutException` group. Those 7 are the regression detector to
protect when the poll loop becomes a completer, not a gap to fill.

What nothing covers is **delivery**. There is **no `StreamController` anywhere
in at_lookup's tests**: every test feeds bytes by calling `messageHandler`
directly, so no test has ever driven data in through a socket, and
`createMockAtServerSocket` stubs `listen` to return a `MockStreamSubscription`
that delivers nothing and cannot show that pausing stops delivery. Without the
harness, decision 6's two properties ship with nothing able to detect their
absence. Every new case gets a break-it mutation whose failure quotes its own
reason string.

**9 — The signing algorithm is derived, not passed.** *Superseded in part by
decision 10*: the principle stands, but at_lookup stops signing altogether, so
the algorithm now comes from `AtKeys.authenticationAlgorithmFor(enrollmentId)`
inside the authenticator. It was a derived fact stored in parallel —
`at_lookup_impl.dart:744` held `SigningAlgoType signingAlgoType =
SigningAlgoType.rsa2048`, going into the signature *and* onto the wire, while
at_auth's own source comments the workaround: at_lookup "would otherwise sign an
ML-DSA key with the RSA routine". **The originally-planned at_chops change is no
longer required for this work** — see [section 6](#6-filed-not-scheduled).

**10 — at_lookup holds no key material; it takes one authenticator.** at_lookup
declares `AtAuthenticator` and `AtCommandExecutor` and knows nothing about keys;
**`at_chops` leaves its pubspec.** Forced by the dependency graph, not
preference: `AtKeys` and `AtKeysIo` live in **at_auth, which depends on
at_lookup**, and `CryptoProvider`/`CryptoRuntime` live in at_client, so at_lookup
structurally cannot name any of them. at_lookup's whole AtChops surface is 11
lines in 2 files. Building the authenticator over the **IO** rather than a
snapshot means a mid-session retrofit propagates by construction.

**11 — The muxable owns reconnect, reauth and heartbeat.** It holds the socket,
so it re-establishes it, re-runs the authenticator and re-issues `monitor:` under
`requestResponseMutex`. Monitor's `connectDelays`, `delayIx` and heartbeat are
deleted. Both classes implement the **same** `[1, 2, 3, 5, 8, 13, 21, 34]`-second
backoff, so one had to lose it; on the later shared wiring the connection also
carries verb traffic, so a Monitor-owned reconnect would be healing a socket it
does not own for a subsystem that is not it.

**12 — One held closure, branching on what the keystore says.** A single
authenticator lives for the instance's lifetime and asks `AtKeysIo` on every
invocation: usable APKAM material present means PKAM, absent means CRAM. Nothing
is swapped and no phase flag exists. A muxable really does span both credentials
— `onboard()` CRAMs at `at_auth_impl.dart:216` and PKAMs at `:293` on **one**
instance — and branching on the keystore reuses the predicate at_auth already
treats as authoritative: `onboard()` opens by reading `atKeysIo` and throws
"already onboarded" on a non-null result. One source of truth, read fresh, so
once activation files the keys the one-shot CRAM secret becomes unreachable with
nothing to remember to replace.

### What still has to happen at the CRAM→PKAM transition

The teardown stays. `at_auth_impl.dart:285` closes the connection between the
CRAM and the PKAM, and it is still required: both `pkamAuthenticate` and
`cramAuthenticate` wrap their bodies in `if (!isAuthenticated)`, so a live
CRAM-authenticated socket will not re-authenticate in place. `createConnection()`
then builds a fresh connection whose metadata allows the PKAM through.

## 4. The factory

Named for its transport, so a differently-transported factory can join it later.
Six parameters, none of them key material.

```dart
// packages/at_lookup/lib/src/at_lookup.dart — static, so additive
typedef AtAuthenticator = Future<bool> Function(AtCommandExecutor);

abstract interface class AtLookUp {
  // … existing members, frozen …

  static AtLookupMuxable withSecureSocket({
    required String             atSign,
    required AtRootDomain       rootDomain,
    required SecureSocketConfig secureSocketConfig,
    required AtAuthenticator?   authenticator,
    Map<String, dynamic>        clientConfig = const {},
    SecondaryAddressFinder?     secondaryAddressFinder,
  });
}
```

Gone, and with them `at_chops` from at_lookup's pubspec: `atChops`,
`enrollmentId`, `privateKey`, `cramSecret`, `signingAlgoType`,
`hashingAlgoType`.

| Parameter                | Kind                | Why                                                                                                                                                                                                                                                        |
| ------------------------ | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `atSign`                 | required            | No possible default. It is what `validatedFromChallenge` checks the server's challenge against.                                                                                                                                                             |
| `rootDomain`             | required            | Replaces the `String, int` pair with at_commons' `AtRootDomain`, which validates the port and knows `isProxyAddress`. Three sites unpack one into the pair today; a fourth reassembles it immediately after.                                                  |
| `secureSocketConfig`     | required            | The parameter the factory is named for, so non-nullable: a caller wanting defaults writes `SecureSocketConfig()` and thereby states it. A production site omits what its neighbour sets — `enrollment_service.dart:65` passes none where `RemoteSecondary` builds one from three preference fields. |
| `authenticator`          | required, nullable  | The whole of auth in one value. `null` means this connection never authenticates — a real mode: `at_status_impl.dart:99` holds no key material at all, and an OTP enroll request routes through `auth: false`.                                              |
| `clientConfig`           | optional            | at_lookup cannot build one — `AtClientConfig` lives above it. One producer exists, so every hand-built lookup sends a bare `from:@atsign` and the atServer records no client particulars.                                                                    |
| `secondaryAddressFinder` | optional            | Nominally duplicative with `rootDomain`, but it is the only carrier of the shared atDirectory cache.                                                                                                                                                        |

The other side of the seam, in at_auth, where the key material, the enrollment
and the algorithm all already live:

```dart
// One closure for the instance's life; it asks the keystore which
// credential applies, every time it is invoked.
AtAuthenticator authenticatorFor(AtKeysIo io, String atSign,
                                 {String? cramSecret, String? enrollmentId}) =>
  (executor) async {
    final AtKeys keys;
    try {
      keys = await io.read(atSign);              // re-read EVERY auth
    } on AtKeysSourceAbsentException {           // not onboarded yet
      return _cram(executor, atSign, cramSecret!);
    }

    final algo = keys.authenticationAlgorithmFor(enrollmentId)
        ?? SigningAlgoType.rsa2048;
    final challenge = validatedFromChallenge(
        await executor.sendSync('from:$atSign\n'), atSign);
    // … sign with `algo`, send pkam:, return success …
  };
```

Three corrections to that sketch, each measured against the types rather than
assumed:

- **`AtKeysIo.read` returns `FutureOr<AtKeys>`, never null**, so this sketch's
  original `if (keys == null)` was dead code the analyzer would have rejected.
  The "not onboarded yet" signal is the typed
  `AtKeysSourceAbsentException`, which `FileAtKeysIo.read` throws for a missing
  keyfile and which exists precisely so a caller can tell that apart from a
  keyfile it cannot read.
- **`authenticationAlgorithmFor` returns null whenever `enrollmentId` is
  null** — it is `enrollmentId == null ? null : …`. A legacy, non-APKAM
  authentication therefore resolves to nothing and needs the same
  `?? SigningAlgoType.rsa2048` default, and for the same reason,
  that `at_client_impl.dart` already documents at its own call site: at_lookup
  signs with rsa2048 by default, so a legacy enrollment compares as rsa2048.
- ⚠️ **PKAM validates the challenge and CRAM does not.**
  `pkamAuthenticate` passes the `from:` response through
  `validatedFromChallenge`; `cramAuthenticate` digests it raw. Port both
  exactly as they are and change neither silently — then decide whether the
  asymmetry is intended, on its own evidence. It is filed in
  [section 6](#6-filed-not-scheduled), not fixed here.

## 5. Order of work

Each step is a commit boundary. The auth seam lands additively, callers migrate,
then the old path is deleted — so no package is uncompilable between commits.

| #   | Step                                                                                                                                                                                                                                | Package        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| 1   | Add `defaultResponseBudget` beside `defaultOnboardingTimeout`, documented as uncapped-by-design and why. Nothing reads it yet.                                                                                                       | at_commons     |
| 2   | **Lands as two commits.** First `FakeAtServerSocket` over a real `StreamController` alone, proven against current behaviour so it is not judging code written beside it. Then the completer, the deadline recomputed from `_lastReceivedTime` on every wake, timeouts from `AtNetworkTimeouts`, the `onNotification` seam, and the `_stripPrompt` `-1` guard. **`read`'s two params become nullable** - source-compatible for every caller, but not literally unchanged as this row first said, and breaking for an implementer that overrides `read` with `int` params. There are none in tree; the mocks go through `noSuchMethod`. | at_lookup      |
| 3   | Declare `AtAuthenticator` and `AtCommandExecutor`; accept and prefer an injected authenticator **alongside** the existing ladder. Nothing breaks yet.                                                                                | at_lookup      |
| 4   | Supply the authenticators **from at_auth**, built over `AtKeysIo` — at_lookup still names none of it, and gains no dependency. at_auth, at_client and at_onboarding_cli switch to passing one. **at_tools' `at_cli` is the external case** — it sets `preference.privateKey` with no AtChops at all. | at_auth        |
| 5   | **DONE, and reshaped by a ruling: annotate, do not delete** (gkc, 2026-08-19). The six credential members carry `@Deprecated` on both the interface and the impl override; the ladder still reads them, so nothing breaks. Everything below this sentence describes **the later major that does the deletion**, and is kept here because it is what that major must do. ⛔ Do not read the rest of this row as owed at step 5. — Delete both copies of the `atChops → privateKey → cramSecret` ladder, the credential fields, `signingAlgoType` at `:744`, and **`at_chops` from the pubspec**. ⚠️ **Widen `AtAuthenticator`'s return in this same step** (ruled 2026-08-19). It returns `bool` today and that works only because `_authenticateWith` reads at_lookup's own `enrollmentId` field to record `AtConnectionMetaData.authenticatedAsEnrollmentId`. Deleting the field leaves nothing able to supply it - the authenticator is the side that knows the enrollment, and `bool` cannot carry it - so a caller could no longer tell which enrollment a live socket holds. Return a small result carrying success and the enrollment id, and let at_lookup record it. Widening the executor with `recordAuthentication` was the rejected alternative: it makes the id a side effect rather than data, and keeps `AtCommandExecutor` wider than it needs to be. ⚠️ **`atChops` is not only an auth credential, and deleting it breaks a non-auth reader.** `enrollment_approver.dart` reads `atLookUp.atChops` six times to do enrollment crypto - it takes the encryption private key out of it at `:41`, decrypts the wrapped payload at `:52` and `:63`, and at `:47` **mutates** it (`atLookUp.atChops?.atChopsKeys.apkamSymmetricKey = …`). The lookup is being used as a shared mutable crypto context between at_auth components, which is why the field is on `AtLookUp` at all. The approver is at_auth code and has the keys, so it should be handed its own crypto rather than reaching through a network object for it - but that is a change to the approver, and it has to land before or with the deletion. | at_lookup      |
| 6   | Add `AtLookupMuxable`, `AtLookupImpl implements AtLookupMuxable`, the single-subscription notification controller with pause wired to the socket, and reconnect / reauth / heartbeat ownership. ⚠️ **Do not port `MultiplexedOutboundMessageListener` as written** - it truncates multi-line values (see [section 7](#7-corrections)). The framing that works is two passes: the notification check byte by byte, the `\n@` check only from the last newline on, as landed in step 2. | at_lookup      |
| 7   | `withSecureSocket` in, constructor deprecated. Deprecate `MonitorClient` in the same commit — exported, zero consumers tree-wide, and its `_createNewConnection` bypasses `SecureSocketUtil` so it never got the connect timeouts.    | at_lookup      |
| 8   | Migrate the 64 sites, compiler-enumerated. **Run `dart analyze` in `tests/at_functional_test` and `tests/at_end2end_test` separately** — 29 of the 64 live there, invisible to at_lookup's own analyze.                               | 9 packages     |
| 9   | Monitor takes an `AtLookupMuxable` and loses its connection factory, PKAM auth, buffer, framing constants, overflow check, prompt stripping, `sendCommand`, backoff and heartbeat. **Wiring passes a fresh instance.**                | at_client      |

Sequencing constraint: at_lookup publishes first, at_commons moves with it
putting step 1 at the front of the release order as well as the commit order,
and at_auth's constraint on at_lookup rises in step 4, in the same commit as
the first use.

⚠️ **This paragraph used to say "at_lookup goes 3.7.0 → 3.8.0". There is no
3.8.0.** pub.dev's latest at_lookup is **3.6.1**; the in-tree `3.7.0` was
bumped by `4e2507012` and has never been published, so it is the in-progress
heading and the whole consolidation folds into it. Checked against pub.dev's
API and `git log -L3,3:packages/at_lookup/pubspec.yaml`, not against in-tree
precedent — which is the trap this repo has already hit once, at `66ec12a38`
("fold 3.7.0 entries back into unpublished 3.6.0").

## 6. Filed, not scheduled

⚠️ **The heading is no longer the whole truth, and the anchor is kept only
because other sections link to it.** Four of what follows are not filed-and-
unscheduled at all — they are **required before the credential fields can be
deleted**, and burying required work under a heading that says otherwise is how
it gets skipped. They are marked **BLOCKS THE MAJOR**. The genuinely filed
items are at the end, under [Actually filed](#actually-filed).

⚠️ **These used to be marked `BLOCKS STEP 5`, and the rename is not
cosmetic.** Step 5 no longer deletes anything — it annotates (see the Status
block). What these four block is the *later major* that does the deletion. Left
saying "step 5", they would read as blocking work that has already shipped, and
a fresh session would go looking for a gate that is not there.

### BLOCKS THE MAJOR — deletion does not remove the ladder, it makes a keystore mandatory

Measured, by tagging both routes and attributing the ladder authentications in
a functional pass (107 of them at the point of sampling):

| where | count | why |
| ----- | ----- | --- |
| `enrollment_test.dart` | 35 | constructs `AtLookupImpl` directly - test code exercising at_lookup itself |
| `at_client_lifecycle_functional_test.dart` | 19 | `AtClient` built with **no `atKeysIo`** |
| `atclient_notify_test.dart` | 12 | same - it creates clients nine times and passes no keystore |
| `atclient_sync_callback_test.dart` | 8 | same |
| the rest | ~33 | spread thin |

By atSign: 90 `@alice🛠`, 11 `@bob🛠`, 4 `@sachin`, 2 `@srie`.

The second group is the finding. An `AtClient` constructed without an
`AtKeysIo` gets no authenticator - correctly, since nothing can authenticate
from a keystore it was not given - and falls through to the ladder on
`preference.privateKey` / `atChops`. So the ladder's remaining traffic is not
un-migrated code; it is **callers who supply no keystore**.

Step 5 therefore is not the mechanical deletion the row implies. Deleting the
ladder makes an `AtKeysIo` **required** to authenticate, which is a breaking
change for every consumer that builds a client from a preference alone - and
at_tools' `at_cli` is already named in the corrections table as exactly such a
consumer, outside this tree.

**There is a bridge, and the ladder itself shows the way.** Its legacy leg
signs with `AtPkamKeyPair.create('', privateKey)` - an **empty public half**,
because RSA signing needs only the private key. at_auth already builds a
signer of that shape for a different reason:
`enrollment_handshake._apkamChopsAwaitingSymmetricKey` constructs an AtChops
with an empty encryption private key, for an enrollment whose keys are
deliberately incomplete.

So a caller holding nothing but `preference.privateKey` can still be given an
authenticator, and needs no keystore at all:

```dart
/// The legacy credential: a PKAM private key and nothing else. Reads no
/// keystore, because there is none - which is exactly the caller this exists
/// for.
AtAuthenticator authenticatorForPrivateKey(String atSign, String privateKey,
    {Map<String, dynamic> clientConfig = const {}});
```

With that, step 5 deletes the ladder without making a keystore mandatory and
without a major: at_client hands keystore-less callers this authenticator
instead. The credential decision still leaves at_lookup, which is the point -
it just lands in at_client rather than in a keyfile. Worth building **before**
step 5, so the deletion has somewhere for those callers to go.

### BLOCKS THE MAJOR (partly) — at_onboarding_cli had no local functional harness

`tests/at_onboarding_cli_functional_tests` has **no `runLocal.sh`**, and its
`docker-compose.yaml` defaults to `atsigncompany/virtualenv:vip` - the
published image, not the local PQ-capable build the rest of this work is
verified against. So there is no local path to functionally verify anything
in at_onboarding_cli, and `tests/at_functional_test` does not exercise the CLI.

The consequence for this project: the CLI's authenticator install is
**unit-green only** (54 tests), and its six remaining construction sites
(`at_onboarding_service_impl` `:215 :445 :460 :488 :721`, `auth_cli.dart:413`)
should be migrated with that in mind - they are not uniform, either. Some
authenticate, `:721` only checks `isOnboarded`, and two send a bare `from:`
through a proxy. Installing an authenticator on all of them is harmless where
unused, because it only runs when authentication is required, but the absence
of a live check means the change wants a runner first. Writing one - a
`runLocal.sh` matching at_functional_test's, defaulting to
`at_virtual_env:local` - is the cheaper thing to do before the migration, not
after it.

### BLOCKS THE MAJOR — `atLookUp.enrollmentId` has 51 uses, not the 7 first recorded

⚠️ **This section used to say "seven at_client modules", and that was a
hand-built list.** The annotation pass replaced it with an enumeration from
`dart analyze`, which resolves the receiver type and so cannot miss a caller
the way a grep can. The seven were all real and all still here — what the list
omitted is below.

The full figure is **51 uses across 34 files**, workspace-wide, reads and
writes together. Two denominators are in play and they are not the same
question: "how many modules ask the lookup which enrollment they are" (the
original 7) and "how many uses break when the member goes" (51). Neither is
wrong; quoting one for the other is.

In at_client `lib/`, **eight readers**, not seven:

| file | line | in the original 7? |
| ---- | ---- | ------------------ |
| `crypto/nskey/nskey_rotation.dart` | 254 | yes |
| `crypto/nskey/nskey_seeding.dart` | 67 | yes |
| `crypto/nskey/pq_signing_root.dart` | 904 | yes |
| `mixins/apkam_signing.dart` | 67 | yes |
| `service/enrollment_privilege_resolver.dart` | 36 | yes |
| `service/envelope_enrollment_conveyance.dart` | 253 | yes |
| `signing/signing_key_minting.dart` | 296, 314 | `:314` only |
| `secret_sharing/key_package_minting.dart` | 124 | **no — missed** |

`key_package_minting.dart:124` reads `atLookUp?.enrollmentId` into a local
spelled **`enrolment`**, single *l*, and every downstream use names that local.
So a grep anchored on the usage sites never connects them back to the member —
which is exactly why the analyzer, not a grep, is the instrument for this list.

Plus `remote_secondary.dart` at `:78`, `:95`, `:108` and `:148` — the write
site and the authenticator-precedence branches that read the field to *build*
its replacement.

And **at_onboarding_cli has four more** the at_client-scoped count never
covered: `at_onboarding_service_impl.dart` at `:146`, `:166`, `:185`, `:515`.

All of them are asking "which enrollment am I operating as" — a fact about the
client, read off a network object because that is where somebody parked it.
They need the answer from the client instead, and the field goes with the
ladder once they have it.

Two things to be careful of when moving them. `AtLookUp.enrollmentId` is what
the *next* authentication will use, which is deliberately not
`AtConnectionMetaData.authenticatedAsEnrollmentId` - what a live socket
actually holds; that distinction is documented on the metadata field and must
survive the move. And `apkam_signing.dart:67` reads
`... ?? 'primary'`, a manufactured sentinel: anything downstream comparing
against `'primary'` is comparing against "we did not know", not against an
enrollment.

### BLOCKS THE MAJOR — the approver's crypto (DONE additively, 2026-08-19)

`EnrollmentApprover.approve` reaches through `atLookUp.atChops` for three
things, none of them authentication: the atSign's **encryption** private key
(`:41`), the self-encryption key (`:63`), and a scratch slot for the APKAM
symmetric key it derives (`:47`).

That last one looked like a shared side effect and is not. `:47` is the **only**
writer of `apkamSymmetricKey` onto a lookup's chops anywhere in the tree, and
nothing reads it back: the two `encryptString(keyName: 'apkamSymmetricKey')`
calls a few lines below resolve it through at_chops' own key lookup, in the
same method. `enrollment_handshake.dart:112` sets it on its own local chops,
not the lookup's. So the approver can be handed its own signer and mutate that.

The change is additive, and the shape this project uses everywhere else - the
tolerant reader ships first, the deletion follows:

```dart
// at_auth: AtEnrollment, and AtEnrollmentImpl, and the approver
Future<AtEnrollmentResponse> approve(
    EnrollmentRequestDecision decision,
    AtLookUp atLookUp, {
    AtChops? approverChops,   // step 5 makes this the only source
});
```

The approver resolves `approverChops ?? atLookUp.atChops`, refuses when both
are null, and uses that one object throughout. at_client's
`enrollment_service_impl` passes `approverChops: atClient.atChops`. Step 5 then
deletes the fallback and the field together, and no behaviour moves on the day
it does.

⚠️ **It does not leave the mocks alone, even though the parameter is
optional.** This paragraph first claimed it would. Dart requires an override to
declare every named parameter of the member it overrides - probed:
`void f(int a)` is not a valid override of `void f(int a, {String? extra})`,
`invalid_override`. Nine classes mock `AtEnrollment` and **four override
`approve` with a concrete body and no named parameters**
(`enrollment_conveyance_guard_test`, `enrollment_conveyance_seam_test`,
`enrollment_service_test`, `nskey_convey_at_approval_test`, all in at_client).
Those four move in the same commit. The mercy is that this one is a compile
error rather than the usual silent `noSuchMethod` null - `dart analyze` names
every site.


### ⚠️ `monitor:multiplexed` is a flag no atServer implements

Found while building step 6, and it decides how the muxable may be wired.

`MonitorVerbBuilder.multiplexed` in at_commons documents itself as telling the
atServer that a connection carries both notification and request-response
traffic, so that "the server will only send notifications once there is no
request currently in progress". That interlock is exactly what would make one
shared socket safe.

**It does not exist.** Measured against `at_server` `origin/trunk` (head
`cfb64a65`), not against the local checkout — which sits on
`gkc-fix-2747-notify-crosses-test-boundary`, a different branch:

| probe | result |
| ----- | ------ |
| `git grep -ci 'multiplexed' origin/trunk` (all files) | **0** |
| positive control: `git grep -ci 'selfNotifications' origin/trunk -- '*.dart'` | **16**, lines printed |

The control matters: a broken probe and a true absence print the same nothing.

Worse than unimplemented, it is **not refused**. `VerbSyntax.monitor` — in
at_commons, shared by client and server — carries
`(:(?<multiplexed>multiplexed))?`, so the atServer parses the flag, captures
it, never reads it, and answers normally. A client setting it gets success and
no interlock.

And the hazard it was meant to prevent is live: `monitor_verb_handler.dart`
subscribes to the notification manager's stream and writes each notification to
the connection as it arrives, with nothing gating that write on a request being
in flight. A notification landing mid-response is appended to a buffer whose
prefix is already `data:`, so the framing check — which tests that prefix —
does not route it and it is absorbed into the verb response. Corruption, under
concurrency only.

**Consequences.** `startNotifications` deliberately does not set the flag, and
says so at the call site. The muxable needs a connection of its own, which is
what the plan already assumed — [section 1](#1-the-frame) says the connection
count does not change and collapsing two sockets into one is a later wiring
choice. This is the measurement behind that being right. Owed elsewhere: an
atServer-side implementation, or the flag's removal from at_commons.

### Actually filed

- **Twenty `lib/` doc comments cite a planning-doc path, which the project's
  own rule bans** ("never a phase/step/option number or a planning-doc
  filename" — a rule flagged more than once). Found by
  `git grep -n 'docs/projects' -- '*/lib/*.dart'`: 21 hits, of which the one in
  `at_auth/lib/src/auth/at_authenticator.dart` was written by this work and has
  been rewritten to state the technical reason instead. The other **20** are
  the PQ work's established convention — `at_enrollment_request.dart:242`,
  `file_io.dart:61`, `file_lock.dart:5`, `pq_hpke.dart:16` and `:262`,
  `pq_client_bootstrap.dart:33`, `mint_lock.dart:43`, `nskey_records.dart:10`
  and `:118`, `pq_signing_chain.dart:86`, `published_nskey_key_ring.dart:101`
  and `:288`, `privilege_resolver.dart:32`, `apkam_signing.dart:40`,
  `envelope_signature.dart:666`, `signing_key_minting.dart:263`, plus four in
  `tests/pq_matrix/*/lib/`. Not touched here: they predate this project and
  most cite a numbered *decision*, which is arguably a durable reference rather
  than a planning trail. **That distinction is gkc's call, not this plan's** —
  the rule as written admits neither. Re-derive the list with the grep above
  rather than trusting this one.
- **`AtLookupImpl.authenticate()` carries a deprecation somebody backed out
  of, and the reason they gave no longer holds.** `at_lookup_impl.dart:560` is
  a commented-out annotation: `/// @Deprecated('Use method pkamAuthenticate')
  Commenting deprecation since it causes issue in dart analyze in the caller`.
  It is the legacy PKAM leg, impl-only (not on `AtLookUp`), and it is what the
  ladder calls with the now-deprecated `privateKey`. The annotation pass
  measured what "issue in dart analyze" actually means here: `info`, which
  `--fatal-warnings` does not promote, with all 16 workspace packages exiting
  0. So the stated blocker is gone. **Not annotated here** — it is a seventh
  member beyond the six ruled on, and widening a deprecation set is gkc's call.
- **at_onboarding_cli still constructs six lookups without an authenticator** —
  `at_onboarding_service_impl` `:215 :445 :460 :488 :721` and
  `auth_cli.dart:413`. They are not uniform: some authenticate, `:721` only
  checks `isOnboarded`, and two send a bare `from:` through a proxy. Installing
  one everywhere is harmless where unused, since it runs only when
  authentication is required. Verify with
  `tests/at_onboarding_cli_functional_tests/runLocal.sh`, which now exists.
- **`at_onboarding_service_impl.onboard` builds its `FileAtKeysIo` without the
  passphrase**, where the read path requires one. That asymmetry is deliberate
  as of this work — onboarding *writes* — but nobody has established whether a
  passphrase belongs there too. It was left alone rather than changed as a side
  effect of sharing a helper; the read path's omission was a real bug and is
  fixed.
- **`check_test_env.dart` in `tests/at_onboarding_cli_functional_tests` is dead
  code.** It polls `lookup:publickey@sitaram` until it answers — state only
  pkamLoad creates — so in a suite that deliberately runs without pkamLoad it
  can never pass, and hangs for its five-minute timeout. CI does not call it.
  Either delete it or give it a check that suits this suite.
- **REJECTED, do not "fix":** `at_client_flutter/enrollment_service.dart:65`
  builds a lookup with no authenticator, and that is correct. It submits an
  OTP-based enrollment, which routes through `auth: false` and never
  authenticates — the case the factory's nullable `authenticator` exists for.
  `at_server_status/at_status_impl.dart:100` is the same shape and holds no key
  material at all.
- **Seven ladder authentications survive in the functional pack**, all in test
  files that construct an `AtLookupImpl` directly: `nskey_rotation_live_test`
  (3), and one each in `apsk_server_side_test`, `copied_keyfile_test`,
  `enrollment_namespace_gate_test`, `enrollment_pq_key_exchange_live_test`.
  Nothing in `lib/` reaches the ladder. These change when step 5 removes the
  fields, not before.
- **CRAM does not validate the `from:` challenge; PKAM does.**
  `at_lookup_impl.cramAuthenticate` digests the raw response, while
  `pkamAuthenticate` passes it through `validatedFromChallenge` first. The
  control exists so a server cannot get a client to sign a challenge naming a
  different atSign. Whether it matters for CRAM — where the secret is already
  shared with that server — is a question with an answer, and nobody has
  written it down. Not changed by this work; step 4 ports both verbatim.

**`enrollment_submitter.dart:290` advertises `rsa2048` unconditionally.** It
ignores `AtEnrollmentRequest.signingAlgo` while `:215` mints an RSA keypair.
Under a PQ posture that is the wrong advertisement. Adjacent to decisions 9 and
10 but fixed by neither — those settle the *signing* side; this is the
*advertising* side.

**Algorithm identity on the at_chops key hierarchy.** No longer required, since
at_lookup stops signing — but `RsaKeyPair`, `MlDsa65KeyPair` and friends still
name their algorithm only by type, while `AtChopsImpl._getSigningAlgorithm` reads
it from `AtSigningInput`. Worth doing for at_chops' other callers.

**Two fixes that are wrong on trunk today.**

- The plookup fix: cherry-pick `07372d58b` from `gkc-fewer-connections`; its
  parent blob is byte-identical to trunk's, so it applies clean. It fixes a
  functional test that times out, because `LookupVerbBuilder.buildCommand()`
  ignores `auth: false` and the atServer resolves the lookup as a shared-key one,
  returning AT0015.
- The `test/samples` deletion: 34 files. One,
  `samples/monitor/connectivity_test.dart`, matches `*_test.dart` and at_client
  has no `dart_test.yaml`, so CI collects it — and it declares a `main()` with a
  live stream subscription and no `test()` at all. `samples/lookup.dart:10` is
  also one of the 64 sites, so deleting first shrinks step 8 by one.

## 7. Corrections

### How to re-derive step 4's progress

Instrument **all four** authentication entry points in
`at_lookup_impl.dart` with `logger.shout`, then run
`tests/at_functional_test/runLocal.sh` and count:

| probe at | counts |
| --- | --- |
| top of `_authenticateWith` | the injected seam |
| beside `logger.finer('calling pkam using atchops')` | `_process` falling through |
| after `pkamAuthenticate`'s authenticator early-return | that method's own fallback |
| first line of `authenticate(String? privateKey)` | the legacy leg |

⚠️ **`shout`, not the existing levels.** The ladder's own log is `finer` and
the harness sets the root level, so reading it unmodified under-reports by
roughly fiftyfold — that produced a "4 ladder" figure when the truth was 201.

⚠️ **Assert the anchor count before replacing.** The prologue shared by the
direct legs appears **three** times, and the third is `_authenticateWith` —
the injected path itself. Tagging that as ladder use would report the fix as
the problem.

### How to re-derive who still uses the deprecated members

Not by grep. `enrollmentId`, `privateKey` and `cramSecret` are field names on
many unrelated types here — at_auth's own `AtAuthKeys.enrollmentId` is
*separately* deprecated and contributes 33 findings of its own — so a text
search cannot tell the receiver types apart. `dart analyze` can, because it
resolves them.

Analyze every workspace member and filter on the tail these six annotations
share:

```bash
MARK='Removed with the credential ladder in the next major release'
# in each of the 16 workspace packages:
dart analyze --fatal-warnings > /tmp/$pkg.log 2>&1
# then, over the collected logs:
grep -h "$MARK" /tmp/*.log | sed -E "s/.*- '([^']+)' is deprecated.*/\1/" \
  | sort | uniq -c | sort -rn                       # by member
grep -h "$MARK" /tmp/*.log | grep ' lib/'           # production sites only
```

Reading at `768d08119` + the annotation commit: **90 findings** — `enrollmentId`
51, `atChops` 25, `signingAlgoType` 12, `hashingAlgoType` 2.

⚠️ **Prove the filter both ways before believing a number from it.** The tail
must match a real line in the annotated run (print it) and return **0** against
the pre-annotation baseline. Both were checked; without the second, this filter
would silently also collect at_chops' 1151 unrelated deprecations.

⚠️ **`privateKey` and `cramSecret` return zero, and that is a finding, not a
broken probe.** Neither has a single consumer anywhere in the 16 packages —
`privateKey` was already annotated in the baseline, so its uses would have
shown up there too, and they do not. Those two can be deleted at the major with
far less ceremony than the other four.

### Readings that were superseded

- **"4 ladder authentications"** → **201**. Read at `finer` under a harness
  that filters it, while the injected route was counted at `shout`: two
  instruments, reported as one comparison.
- **"Ladder = 0 is the finish line"** → wrong. Test files constructing an
  `AtLookupImpl` directly put a floor under it that no production change can
  reach. The finish line is **no `lib/` site reaching the ladder**.
- **"8 production sites write `atChops`"** → **6**. Three of the original
  eight cascade onto response and preference objects rather than lookups, and
  a seventh (`at_client_impl.dart:105`) writes to `RemoteSecondary`'s setter,
  which reaches a lookup only through `remote_secondary.dart:39` — already
  counted.
- **The at_client install in `AtClientImpl`'s `atChops` setter** → reverted.
  Measured to change nothing (57/201 before and after) because
  `RemoteSecondary` sets `atLookUp.atChops` in its **constructor**. Every suite
  passed either way. A no-op that reads as a completed migration is worse than
  an absent one.


Figures and claims that changed under measurement, kept so nobody rebuilds on the
first version.

| Claimed                                                | Measured               | Mechanism                                                                                                                                             |
| ------------------------------------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 83 construction sites                                  | **64**                 | `AtLookupImpl\(` matches as a substring inside `MockAtLookupImpl(` — 15 mocktail lines — plus the declaration and 3 dartdoc lines. Confirmed two ways.  |
| 42 overlapping files (branch vs trunk)                 | **47**                 | Counted by path equality, missing 5 files trunk renamed that the branch also modifies.                                                                |
| 34 dead sample scripts                                 | **33 + 1 collected**   | One matches the collection glob and CI runs unscoped.                                                                                                 |
| `privateKey` is obsolete                               | **Live**               | Named holder outside the tree: at_tools `at_cli` on `origin/trunk`, no AtChops anywhere in it.                                                         |
| `signingAlgoType` should be a required parameter       | **Not a parameter**    | Three production sites cannot supply a correct value; decision 10 then removed the need entirely.                                                      |
| Monitor keeps retry/backoff                            | **Muxable owns it**    | Corrected in decision 11. Both had the identical delay list.                                                                                          |
| `_reconnectLoop` skips the mutex                       | **It takes it**        | Suspected by symmetry with a comment; the code acquires `requestResponseMutex` exactly as `startNotifications` does.                                   |
| The auth short-circuit is a branch regression          | **Present on both**    | The branch spells it as an early `return true`; this branch as `if (!isAuthenticated) { … }` around the whole body. Onboarding is built on it.         |
| Install the authenticator on `authenticate()`          | **Held closure**       | Install stores the phase a second time, so it can disagree with at_auth's state — the derived-vs-stored hazard decision 9 invoked and 10 avoids.       |
| Rebase drops at_lookup work silently                   | **Conflicts**          | Git reports `CONFLICT (modify/delete)`. The hazard is that it reads as "keep the file or not" and `git rm` discards 87 lines without showing a hunk.   |
| Listener tests never enter the waiting path            | **7 do, 38 times**     | Measured by printing in the poll loop and running the suite: the whole `AtTimeOutException` group waits. The real gap is delivery — zero `StreamController` in at_lookup's tests, so nothing drives bytes through a socket. |
| `gkc-fewer-connections`' listener is adoptable         | **Truncates values**   | Its byte loop starts at 0, so an internal `\n@` inside a `data:` value reads as the terminator. Measured by running that exact file over `data:the_key_is\n@bob:phone@alice\n@alice@`: it returns `data:the_key_is`. at_lookup's own `data contains new line character and @` test (`outbound_message_listener_test.dart:95`) would have caught it, so it never ran against this suite. |
| Seven at_client modules read `atLookUp.enrollmentId`   | **8 readers, 51 uses** | The seven were real; the list was hand-built and missed `key_package_minting.dart:124`, which stores the value in a local spelled `enrolment` (single *l*) so no usage-site grep leads back to it. Re-derived from `dart analyze`, which resolves receiver types. at_onboarding_cli holds four more the at_client-scoped count never covered. |
| `privateKey reference is no longer used` (its own `@Deprecated` message) | **False; it is live** | `_process`'s ladder reads the field and calls `authenticate(privateKey)` with it, and before the authenticator seam it was the leg most ladder traffic took. Shipped in at_lookup's source as an annotation a consumer would read as "inert". Replaced with a message naming the replacement. |
| at_lookup goes 3.7.0 → 3.8.0                           | **There is no 3.8.0**  | pub.dev's latest is **3.6.1**. In-tree `3.7.0` was bumped by `4e2507012` and never published, so it is the in-progress heading and everything folds into it. The claim came from in-tree precedent, which this repo has already been burned by once — `66ec12a38`. |
| Deprecating the fields will force the readers to move  | **It forces nothing**  | `deprecated_member_use` is severity `info` here and `--fatal-warnings` does not promote it: all 16 workspace packages exit 0 before and after. Worse for the signal, 1151 of the 1201 baseline findings were *already* that same lint, so 90 more are invisible. A prediction of mine, wrong; the analyzer settled it. |
| Annotating only adds findings                          | **It removes 5 too**   | Dart suppresses `deprecated_member_use` *inside* a declaration that is itself deprecated, so annotating the five declarations naming the (also deprecated) `AtChops` type hid at_chops' own signal on those lines. at_lookup went 33 → 28. Explained rather than rounded: 90 new − 5 suppressed = the +85 workspace delta exactly. |
