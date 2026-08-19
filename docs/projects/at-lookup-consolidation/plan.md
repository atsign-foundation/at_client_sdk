# One listener, two framings

Status: design settled. **Steps 1 and 2 have landed** — the response budget in
at_commons, `FakeAtServerSocket`, the `_stripPrompt` guard the harness found on
its first use, the event-driven `read()`, and the `onNotification` seam.
**Step 3 has landed too** — `AtAuthenticator`, `AtCommandExecutor`, and
`AtLookupImpl` preferring an injected authenticator over the ladder.
**Step 4 is part done**: `authenticatorFor` exists and at_auth's three sites
use it. Measured against a live atServer with both routes logging at `shout`:
**57 authentications through the injected route, 201 still through the
ladder**. ⚠️ An earlier measurement said "4 ladder" - it was read at `finer`,
which the functional harness suppresses. ⚠️ **"Ladder = 0" is the wrong finish line**, though this row said so. About
ten files in `tests/at_functional_test` construct an `AtLookupImpl` and set
`atChops` on it directly - they are testing at_lookup and at_auth, so they
legitimately use the ladder, and they can only change when step 5 deletes the
fields. The count therefore has a floor that production migration cannot
reach. Step 4 is finished when **no `lib/` site sets credentials on a lookup**;
the residual count is then entirely test code, and step 5 clears it. ⚠️ **The at_client install does NOT belong in `AtClientImpl`'s `atChops`
setter.** Putting it there was measured to change nothing: 57 injected / 201
ladder before and after, while at_client's 1480 tests and the functional 177
all passed either way. `remote_secondary.dart:72` sets `atLookUp.atChops` in
the **constructor**, so the chops that matters never passes through that
setter. The install has to happen where `RemoteSecondary` is built - which
also needs an `AtKeysIo` threaded to it, since `RemoteSecondary` holds a
preference and a lookup but no keystore. Reverted rather than shipped: a no-op
that reads as a completed migration is worse than an absent one.

**Still to migrate** - and it is more than this row first listed. Beyond the
sites already done, `at_onboarding_cli` constructs an `AtLookupImpl` at six
further places (`at_onboarding_service_impl` `:215 :445 :460 :488 :721`,
`auth_cli.dart:413`), and `at_client_flutter/enrollment_service.dart:65` at
one. `at_server_status/at_status_impl.dart:100` needs nothing: it holds no key
material and never authenticates, which is the case the factory's nullable
`authenticator` exists for. Original list: of `atChops` onto a lookup — 2 in
`at_auth_impl`, 1 in `enrollment_handshake`, 3 in at_client
(`at_client_impl:105` reaching `remote_secondary`'s setter at `:32`, plus
`:72`), 1 in `at_onboarding_service_impl` — plus the read guard at
`enrollment_approver.dart:27`, which asks `atLookUp.atChops == null` and will
have nothing to ask once the field goes. See [section 5](#5-order-of-work).

⚠️ Not migration sites, though they match a loose grep for the same names:
`at_auth_impl:131` and `:354` cascade onto the **response** objects, and
`auth_cli.dart:1108` onto an `AtOnboardingPreference`. This row said "eight
production sites" until each was opened. This line
is the only statement of progress; `git log` is the record of what landed. Owner: gkc.
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
| 5   | Delete both copies of the `atChops → privateKey → cramSecret` ladder, the credential fields, `signingAlgoType` at `:744`, and **`at_chops` from the pubspec**. ⚠️ **Widen `AtAuthenticator`'s return in this same step** (ruled 2026-08-19). It returns `bool` today and that works only because `_authenticateWith` reads at_lookup's own `enrollmentId` field to record `AtConnectionMetaData.authenticatedAsEnrollmentId`. Deleting the field leaves nothing able to supply it - the authenticator is the side that knows the enrollment, and `bool` cannot carry it - so a caller could no longer tell which enrollment a live socket holds. Return a small result carrying success and the enrollment id, and let at_lookup record it. Widening the executor with `recordAuthentication` was the rejected alternative: it makes the id a side effect rather than data, and keeps `AtCommandExecutor` wider than it needs to be. ⚠️ **`atChops` is not only an auth credential, and deleting it breaks a non-auth reader.** `enrollment_approver.dart` reads `atLookUp.atChops` six times to do enrollment crypto - it takes the encryption private key out of it at `:41`, decrypts the wrapped payload at `:52` and `:63`, and at `:47` **mutates** it (`atLookUp.atChops?.atChopsKeys.apkamSymmetricKey = …`). The lookup is being used as a shared mutable crypto context between at_auth components, which is why the field is on `AtLookUp` at all. The approver is at_auth code and has the keys, so it should be handed its own crypto rather than reaching through a network object for it - but that is a change to the approver, and it has to land before or with the deletion. | at_lookup      |
| 6   | Add `AtLookupMuxable`, `AtLookupImpl implements AtLookupMuxable`, the single-subscription notification controller with pause wired to the socket, and reconnect / reauth / heartbeat ownership. ⚠️ **Do not port `MultiplexedOutboundMessageListener` as written** - it truncates multi-line values (see [section 7](#7-corrections)). The framing that works is two passes: the notification check byte by byte, the `\n@` check only from the last newline on, as landed in step 2. | at_lookup      |
| 7   | `withSecureSocket` in, constructor deprecated. Deprecate `MonitorClient` in the same commit — exported, zero consumers tree-wide, and its `_createNewConnection` bypasses `SecureSocketUtil` so it never got the connect timeouts.    | at_lookup      |
| 8   | Migrate the 64 sites, compiler-enumerated. **Run `dart analyze` in `tests/at_functional_test` and `tests/at_end2end_test` separately** — 29 of the 64 live there, invisible to at_lookup's own analyze.                               | 9 packages     |
| 9   | Monitor takes an `AtLookupMuxable` and loses its connection factory, PKAM auth, buffer, framing constants, overflow check, prompt stripping, `sendCommand`, backoff and heartbeat. **Wiring passes a fresh instance.**                | at_client      |

Sequencing constraint: at_lookup goes **3.7.0 → 3.8.0** and at_client already
pins `^3.7.0`, so at_lookup publishes first. at_commons moves too, putting step 1
at the front of the release order as well as the commit order. at_auth's
constraint on at_lookup rises in step 4, in the same commit as the first use.

## 6. Filed, not scheduled

⚠️ **The heading is no longer the whole truth, and the anchor is kept only
because other sections link to it.** Four of what follows are not filed-and-
unscheduled at all — they are **required before step 5 can be done**, and
burying required work under a heading that says otherwise is how it gets
skipped. They are marked **BLOCKS STEP 5**. The genuinely filed items are at
the end, under [Actually filed](#actually-filed).

### BLOCKS STEP 5 — it does not delete the ladder, it makes a keystore mandatory

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

### BLOCKS STEP 5 (partly) — at_onboarding_cli had no local functional harness

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

### BLOCKS STEP 5 — seven at_client modules read `atLookUp.enrollmentId`

The same shape as the approver's `atChops`, and larger. One write
(`remote_secondary.dart:98`) and **seven reads**, every one of them
`atClient.getRemoteSecondary()?.atLookUp.enrollmentId`:

`nskey_rotation.dart:254`, `nskey_seeding.dart:67`,
`pq_signing_root.dart:904`, `apkam_signing.dart:67`,
`enrollment_privilege_resolver.dart:36`,
`envelope_enrollment_conveyance.dart:253`, `signing_key_minting.dart:314`.

All seven are asking "which enrollment am I operating as" - a fact about the
client, read off a network object because that is where somebody parked it.
The plan lists `enrollmentId` as Gone at step 5, which would break all seven.
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

### BLOCKS STEP 5 — the approver's crypto (DONE additively, 2026-08-19)

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


### Actually filed

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
