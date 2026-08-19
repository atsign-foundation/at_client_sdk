# One listener, two framings

Status: design settled. **Step 1 of nine has landed**
(`AtNetworkTimeouts.defaultResponseBudget` in at_commons, read by nothing yet),
**and step 2's harness half** — `FakeAtServerSocket` plus the delivery and
back-pressure tests. **Next is the rest of step 2**, the listener redesign, in
[section 5](#5-order-of-work). This line is the only statement of progress;
`git log` is the record of what landed. Owner: gkc.
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
    final keys = await io.read(atSign);          // re-read EVERY auth

    if (keys == null) {                          // not onboarded yet
      return _cram(executor, atSign, cramSecret!);
    }

    final algo = keys.authenticationAlgorithmFor(enrollmentId);
    final challenge = validatedFromChallenge(
        await executor.sendSync('from:$atSign\n'), atSign);
    // … sign with `algo`, send pkam:, return success …
  };
```

## 5. Order of work

Each step is a commit boundary. The auth seam lands additively, callers migrate,
then the old path is deleted — so no package is uncompilable between commits.

| #   | Step                                                                                                                                                                                                                                | Package        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| 1   | Add `defaultResponseBudget` beside `defaultOnboardingTimeout`, documented as uncapped-by-design and why. Nothing reads it yet.                                                                                                       | at_commons     |
| 2   | **Lands as two commits.** First `FakeAtServerSocket` over a real `StreamController` alone, proven against current behaviour so it is not judging code written beside it. Then the completer, the resettable idle timer, timeouts from `AtNetworkTimeouts`, the `onNotification` seam, and the `_stripPrompt` `-1` guard. Signature unchanged. | at_lookup      |
| 3   | Declare `AtAuthenticator` and `AtCommandExecutor`; accept and prefer an injected authenticator **alongside** the existing ladder. Nothing breaks yet.                                                                                | at_lookup      |
| 4   | Supply the authenticators **from at_auth**, built over `AtKeysIo` — at_lookup still names none of it, and gains no dependency. at_auth, at_client and at_onboarding_cli switch to passing one. **at_tools' `at_cli` is the external case** — it sets `preference.privateKey` with no AtChops at all. | at_auth        |
| 5   | Delete both copies of the `atChops → privateKey → cramSecret` ladder, the credential fields, `signingAlgoType` at `:744`, and **`at_chops` from the pubspec**.                                                                       | at_lookup      |
| 6   | Add `AtLookupMuxable`, `AtLookupImpl implements AtLookupMuxable`, the single-subscription notification controller with pause wired to the socket, and reconnect / reauth / heartbeat ownership.                                       | at_lookup      |
| 7   | `withSecureSocket` in, constructor deprecated. Deprecate `MonitorClient` in the same commit — exported, zero consumers tree-wide, and its `_createNewConnection` bypasses `SecureSocketUtil` so it never got the connect timeouts.    | at_lookup      |
| 8   | Migrate the 64 sites, compiler-enumerated. **Run `dart analyze` in `tests/at_functional_test` and `tests/at_end2end_test` separately** — 29 of the 64 live there, invisible to at_lookup's own analyze.                               | 9 packages     |
| 9   | Monitor takes an `AtLookupMuxable` and loses its connection factory, PKAM auth, buffer, framing constants, overflow check, prompt stripping, `sendCommand`, backoff and heartbeat. **Wiring passes a fresh instance.**                | at_client      |

Sequencing constraint: at_lookup goes **3.7.0 → 3.8.0** and at_client already
pins `^3.7.0`, so at_lookup publishes first. at_commons moves too, putting step 1
at the front of the release order as well as the commit order. at_auth's
constraint on at_lookup rises in step 4, in the same commit as the first use.

## 6. Filed, not scheduled

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
