## 3.7.0-rc1

- fix: a connection built before anything reads `notifications` now
  reconnects when it drops. The stream getter installs the routing seam for
  the case where a verb opened the connection first, but not the disconnect
  seam — so a client that authenticated or ran a verb before calling
  `startNotifications` had a socket whose loss reached nothing: no `false` on
  `notificationConnectionUp`, no reconnect, and a listener silent for the rest
  of the process while still reporting itself up.
- fix: a watermark read that throws no longer leaves the client permanently
  deaf. `getLastNotificationTime` is caller code running inside the reconnect
  loop, and an exception aborted the attempt AFTER it had opened and
  authenticated a connection — which then stayed valid, so every later attempt
  skipped the connect, re-ran only the throwing call, and backed off forever
  with `monitor:` never sent. The only symptom was an `up` that never arrived.
  The read is now guarded: the failure is logged at `warning` and the
  connection starts without a watermark, which costs a replayed window rather
  than every future notification.
- fix: a reconnect no longer re-requests the backlog from where notifications
  first started. `startNotifications`'s `lastNotificationTime` is now
  `getLastNotificationTime`, a function the muxable calls on every connect
  rather than a value it remembers — restoring what the caller-owned monitor
  loop did before the muxable took over reconnection.
- fix: `stopNotifications` retires any reconnect loop still sleeping on a
  backoff, and clears the `_reconnecting` flag it used to leave set. A stop
  followed by a start inside that window let the orphaned loop wake, see
  notifications running again, and act on the connection the restart had just
  made — a second `monitor:` on a live socket, its heartbeat reset, and an
  `up` with no preceding down — while the stale flag disarmed the disconnect
  handler for up to 34 seconds. `isReconnectingNotifications` also no longer
  reads true after a stop.
- fix: a subscriber applying back-pressure no longer loses its connection to
  the heartbeat. Pausing the `notifications` stream stops the socket being
  read, which is the documented point of it, but it also means nothing can
  answer the `noop:0` probe — so the probe timed out and destroyed a healthy
  connection. A pause longer than `heartbeatResponseTimeout` (10s by default)
  was enough, which one slow `await` in an `await for` body will do. The
  heartbeat now skips while delivery is paused, before and after the probe
  goes out.
- deprecated: `AtLookUp.executeVerb`'s `sync` parameter, removal in 4.0. It
  has never been read: the verb always executes on the remote atServer, and
  there is no sync behaviour for the parameter to control.
- fix(deps): raised the `at_chops` constraint to `^3.6.0`. The old `^3.3.0`
  floor was never exercised — the only build evidence for this package is
  against at_chops 3.5.0 and later, so a consumer resolving 3.3.0 or 3.4.x
  was relying on a combination nothing had tested. Workspace resolution hides
  that gap locally, because it always supplies the in-tree at_chops. 3.6.0 is
  what this release is built and tested against.
- fix(deps): raised the `at_commons` constraint to `^5.16.0`. This package now
  reads `AtNetworkTimeouts.defaultResponseBudget`, which does not exist in
  at_commons 5.15.0 or earlier — under the old `^5.13.0` a consumer could
  resolve an at_commons that this package does not compile against.

- fix: a request in flight when its connection closes now fails immediately
  instead of waiting out its response budget. `AtLookupImpl` holds
  `requestResponseMutex` across that wait, so a connection that had already gone
  stalled the **next** request on the same instance for the whole transient
  budget - 30 seconds by default. Stopping an atSign's client while its startup
  work was still in flight was enough to trigger it, and the request that
  followed read as a hang rather than as a closed connection. Every close now
  routes through one place that fails the pending read first, and the caller
  gets a `ConnectionInvalidException` naming what happened rather than an
  `AtTimeoutException` pointing at the atServer. A response already parsed and
  queued before the connection went away is still returned.

- feat: `AtLookupMuxable.notificationConnectionUp` — `true` when `monitor:` is
  accepted on a live connection, `false` when it is lost or stopped. The
  muxable owns reconnection, so it is the only thing that knows; at_client's
  `Monitor` re-broadcasts it as a listener state, which noports' daemon
  subscribes to for its whole life. Broadcast, unlike `notifications`, because
  it is a state signal whose latest value supersedes the last — a dropped
  notification is gone, a dropped state event is re-derivable.

- feat: `AtLookupMuxable` gains the members callers were reaching for through
  a cast to the concrete class: `authenticator`, `isConnectionAvailable` and
  `readResponse`, plus `scan(auth:)`, `scan(showHiddenKeys:)` and
  `lookup(metadata:)`. Those last three are a defect this surfaced -
  `AtLookupImpl` accepted **more** than `AtLookUp` declared, so a caller
  moving to the interface silently lost parameters. Dart permits an
  implementer to add optional named parameters, so nothing goes red when the
  restatement is incomplete: `showHiddenKeys` was missed on the first pass and
  this entry named only two parameters until it was found. They
  are restated on the muxable rather than added to `AtLookUp`, which is frozen:
  adding a parameter there forces every `implements AtLookUp` to redeclare it.

- feat: `AtLookUp.withSecureSocket(...)` — the entry point, returning an
  `AtLookupMuxable`. Static, so it adds nothing to the `implements` contract
  and breaks none of the classes that mock `AtLookUp`. It takes an
  `AtRootDomain` rather than a `String, int` pair, and requires both
  `authenticator` (nullable, because "this connection never authenticates" is
  a real mode that ought to be stated) and `transport`. No socket settings
  appear in its signature: they belong to the transport.
- feat: `AtLookupTransport` bundles the three connection factories
  `AtLookupImpl` has always accepted into one value, so a caller holding only
  the `AtLookupMuxable` interface can still say how connections are made. It
  bundles rather than abstracts on purpose: the web-port plan records that
  these factories are already injectable and that the blocker is their
  **return type**, so a second abstraction here would be one more seam for that
  work to reconcile. It also carries the `SecureSocketConfig`, because how a
  transport reaches an atServer is a property of the transport — TLS
  certificates and a keylog path mean nothing to one that is not TLS over TCP.
  It is not yet sufficient for a non-socket transport, and does not claim to
  be — `AtConnection.getSocket()` still returns a `Socket`.
- feat: the socket transport is `secureSocketTransport(...)` in a new
  `package:at_lookup/at_lookup_io.dart`, and `transport` has no default.
  A default naming an implementation pulls that implementation's imports in
  whatever the caller injects, which is how a transport swap fails silently
  instead of failing to compile; naming the transport is therefore also what
  selects the library carrying it. Callers import the `_io` barrel, which
  re-exports everything in `at_lookup.dart`. This does not make a web build
  possible on its own — `AtConnection.getSocket()` still has to go, which is a
  major — but it means that change will not also have to remove a default.
- feat: `AtLookupImpl`'s constructor is `@Deprecated` in favour of the factory.
  The class itself is **not** deprecated and does not move: it is exported from
  the barrel, so renaming it or making it private would remove a public class,
  which this release is not. The warnings at each construction site are the
  deliverable — 45 of them, `info`, so nothing breaks while they are worked
  through.
- feat: `MonitorClient` is `@Deprecated` with no replacement. A tree-wide
  search finds its own declaration and nothing else, and it predates the
  connect timeouts — it builds its socket directly rather than through
  `SecureSocketUtil`, so it never got them. Use `withSecureSocket` and
  `AtLookupMuxable.notifications`.

- feat: the muxable owns reconnect, reauth and heartbeat, because it owns the
  socket. Losing the notification connection re-establishes it on the
  `[1,2,3,5,8,13,21,34]`-second backoff, re-runs the authenticator, and
  re-issues `monitor:` with the same regex — one that dropped it would start
  delivering everything. The **watermark is asked for again**, not replayed
  from the start value: `startNotifications` takes a
  `getLastNotificationTime` function and the muxable calls it on every
  connect, so a reconnect resumes from where the caller has actually got to.
  This is the behaviour at_client's `Monitor` had when it owned reconnection
  and re-read the watermark on each start; holding the number instead would
  re-request the whole retained backlog on every reconnect. A quiet connection is probed with `noop:0`, because a
  connection that only ever reads cannot tell a quiet atServer from a dead
  socket. at_client's `Monitor` carries an identical delay list; both cannot
  own reconnection.
- feat: `OutboundMessageListener.onDisconnect`. The listener knows the socket
  died before anything else does and used to keep it to itself, so a
  subscriber just stopped hearing anything, with no event separating "the
  atServer is quiet" from "the socket is gone".
- fix: `stopNotifications` no longer awaits the notification controller's
  `close()`. On a single-subscription controller that future completes only
  once a subscriber has received the done event, so starting notifications and
  stopping them without ever listening — a legal sequence — hung forever.

- feat: `AtLookupMuxable`, an `AtLookUp` that also carries the atServer's
  asynchronous notification stream, so one class knows both of the atServer's
  framings instead of the framing code existing twice. `AtLookupImpl`
  implements it: `notifications` is a **single-subscription** stream whose
  pause reaches the socket, `startNotifications` sends `monitor:` under the
  request-response mutex, and `stopNotifications` closes both. A broadcast
  stream was rejected — it does not buffer, ignores pause and drops anything
  arriving before a listener attaches, and each of those is a lost
  notification, which is indistinguishable from one the atServer never sent.
- feat: `OutboundMessageListener` keeps the subscription `listen()` used to
  discard, and exposes `pauseDelivery`/`resumeDelivery`. That is what makes
  back-pressure real: pausing stops reading the socket, so TCP closes the
  window on the atServer rather than this process buffering without bound.
  Note that `StreamSubscription` **counts** pauses — two need two resumes.
- fix: ⚠️ `MonitorVerbBuilder.multiplexed` does not do what it says, and
  nothing in at_lookup sets it. Its dartdoc claims the atServer "will only send
  notifications once there is no request currently in progress". No atServer
  implements it: zero occurrences in `at_server` `origin/trunk`, against a
  probe proven positive on `selfNotifications` (16). The monitor verb's syntax
  — shared by both sides — does capture `multiplexed`, so the atServer parses
  the flag and ignores it rather than refusing it. Until an atServer
  implements the interlock, give the notification stream a connection of its
  own.

- feat: the six credential members are `@Deprecated` — `atChops`,
  `signingAlgoType`, `hashingAlgoType` and `enrollmentId` on both `AtLookUp`
  and `AtLookupImpl`, plus `privateKey` and `cramSecret` on the impl.
  Authentication runs through an injected `AtAuthenticator`, which at_auth
  builds from whichever credential shape a caller holds, so at_lookup no
  longer needs key material of its own. The fallback ladder still reads these
  fields and nothing breaks; the fields and the ladder are removed together in
  the next major. `signingAlgoType` and `hashingAlgoType` are one setting —
  they are read on the same lines when the PKAM signature is built — so
  deprecating either without the other would say the survivor lives on into
  the major, which is not true.
- fix: `privateKey`'s deprecation message claimed "privateKey reference is no
  longer used". That was false: the ladder in `_process` reads the field and
  signs with it, and before the authenticator seam landed it was the leg most
  of the traffic took. The message now names the replacement instead.

- fix: `pkamAuthenticate` prefers an injected authenticator too, not only
  `executeCommand`. at_auth reaches that method directly rather than through a
  verb, so a seam wired into the verb path alone would have looked connected
  while doing nothing on the one call that matters most. The enrollment id is
  now threaded to the recording, because a caller of `pkamAuthenticate` names
  it in the call while a verb has only the field.

- feat: `validatedFromChallenge` is public API rather than
  `@visibleForTesting`. Authentication is moving to at_auth, where the key
  material is, and the side that signs a challenge is the side that must refuse
  a malformed one. The alternative was a second copy of a security control,
  and two copies drift.
- feat: `AtCommandExecutor.sendSync` accepts the same two timeout budgets as
  `OutboundMessageListener.read`. Authentication does not want one answer: the
  CRAM leg of onboarding waits far less than a verb response does, and moving
  that code out of at_lookup must not change its timing.

- feat: `AtLookupImpl` accepts an injected authenticator. Two new types,
  `AtAuthenticator` and `AtCommandExecutor`, let a caller hand over the whole
  of authentication as one closure instead of handing at_lookup a credential
  to store. at_lookup cannot name `AtKeys` or `AtKeysIo` - they live in
  at_auth, which depends on at_lookup - so the keystore, the enrollment and
  the signing algorithm stay on the caller's side of the seam. When set, the
  authenticator is preferred over the existing
  atChops/privateKey/cramSecret ladder; when absent, nothing changes. Both
  routes work, and the ladder goes once every caller supplies one.

- feat: `OutboundMessageListener` can route asynchronous notifications, via a
  new `onNotification` callback. The atServer frames the two kinds of message
  differently - a verb response ends with a newline and the ready prompt
  `@<atSign>@`, while a notification is a reply to nothing, so no prompt
  follows it and it ends at a bare newline. One listener now knows both. While
  `onNotification` is null the second framing is not applied at all and parsing
  is byte-for-byte what it was, because routing notifications to a callback
  nobody installed would drop them.

- feat: `OutboundMessageListener.read` waits on an event instead of polling.
  It slept 10ms at a time and re-checked a queue, so every response carried up
  to a polling interval of latency for no reason. It now sleeps until a
  response is queued or until the nearer of its two deadlines, whichever comes
  first.
- feat: `read`'s two timeouts come from `AtNetworkTimeouts` and are now
  nullable. The whole-response budget defaults to
  `AtNetworkTimeouts.defaultResponseBudget` (90s, unchanged in value) and the
  between-chunks budget to `AtNetworkTimeouts.effectiveDefault`, which moves
  that default from **10s to 30s**. Ten seconds of silence is not evidence a
  busy atServer has gone away, and the two budgets measure different things:
  one bounds the whole response, the other restarts on every chunk. The
  defaulting is **per parameter**: a budget you pass is used as you passed it,
  but passing only one of the two leaves the other on the new default — so a
  caller that set only `maxWaitMilliSeconds` moves from a 10s silence budget
  to 30s. A process that sets `AtNetworkTimeouts.defaultTimeout` at startup
  now moves this too, which puts the response read under the same
  process-wide setting that already governs connect, atDirectory and auth.

- fix: a response carrying no colon no longer destroys the connection.
  `OutboundMessageListener._stripPrompt` ran `substring(0, -1)` when
  `indexOf(':')` found nothing, and the bare `@<atSign>@` that completes the
  handshake is exactly such a response - one `_isValidResponse` accepts. The
  RangeError was raised inside the socket's data handler, so `runZonedGuarded`
  reported it as a socket error and closed a healthy connection, leaving the
  caller with an `AtTimeoutException` naming the wrong cause. Guarded, as the
  copy of this method in at_client's `Monitor` already was.

- feat: a connection records the identity it authenticated as.
  `AtConnectionMetaData` gains `authenticatedAsEnrollmentId` and
  `authenticatedAt` beside `isAuthenticated`, set by every path in
  `AtLookupImpl` that authenticates. `AtLookUp.enrollmentId` is what the *next*
  PKAM will send, so it cannot answer which enrollment a socket that is already
  up holds; this can.

## 3.6.1

- fix: strengthen the from challenge. A client now checks that a `from:`
  challenge has the shape an atServer issues — `_<uuid><atSign>:<uuid>`, and
  that the atSign it names is the one this client asked for — before signing
  it. Defensive in anticipation of broader use of the APKAM keypair in future.

## 3.6.0

- feat: `CacheableSecondaryAddressFinder` takes an optional `cacheDuration` to override the default 1-hour cache TTL.
- fix(deps): updated the `at_chops` constraint to `^3.3.0`, the actual minimum this package compiles against.
- refactor: route PKAM/CRAM signing + hashing through at_chops
  (`PkamSigningAlgo` / `SHA512HashingAlgo`); `crypton` and `crypto` are no
  longer imported anywhere in the package and have been dropped from
  `dependencies`. Byte-identical by construction.
- feat: bound network operations with a timeout so a dead network cannot hang
  the SDK. `SecureSocketUtil.createSecureSocket` now accepts an optional
  `timeout` (and honours `SecureSocketConfig.connectTimeout`), passing it to
  `SecureSocket.connect`. `SecondaryAddressFinder.findSecondary` takes an
  optional `timeout` that bounds the entire atDirectory lookup — the retry loop
  and the previously-fixed 30-second response busy-wait — as a single deadline.
  Both default to `AtNetworkTimeouts.effectiveDefault` (30s) and are capped at
  60s (#1909). Requires `at_commons ^5.13.0`.

## 3.5.0

- chore(deps): at_chops ^3.0.0

## 3.4.1

- fix: revert breaking changes

## 3.4.0

- chore: clean up lint from new `strict_top_level_inference` rule
- feat: AtLookupException non-nullable errorCode and errorMessage

## 3.3.0

- chore(deps): remove unused deps (path)
- chore(deps): at_commons ^5.5.0

## 3.2.0
- feat: add `SecureSocketConfig? config` to `SecondaryUrlFinder` constructor
- fix: make `SecureSocketConfig.tlsKeysSavePath` optional

## 3.1.0
- feat: add `OutboundConnection? connection` to the `AtLookUp` interface

## 3.0.52
- fix: update exception and log messages to use standard terminology 
  ('atServer' instead of 'secondary server', 'atDirectory' instead of 'root 
  server')

## 3.0.51
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 3.0.50
- fix: Flush socket after write and rethrow any exceptions occurred 
## 3.0.49
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.0
  - at_utils to v3.0.19
  - at_chops to v2.0.1
## 3.0.48
- feat: consume EnrollVerbBuilder in AtLookup.executeVerb()
- chore: upgrade at_commons to v4.1.1 and at_utils to v3.0.18
## 3.0.47
- fix: Fixed legacy error handling so error message isn't truncated if it 
  contains a hyphen
## 3.0.46
- fix: Modify "executeCommand" to parse the error response from server and return appropriate exception
## 3.0.45
- build[deps]: Upgraded at_chops to v2.0.0
## 3.0.44
- build[deps]: Upgraded the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_chops to v1.0.7
## 3.0.43
- fix: revert removing private key reference from at_lookup_impl
## 3.0.42
- fix: more informative exception messages
- fix: removed private key reference from at_lookup_impl
## 3.0.41
- feat: introduce methods cramAuthenticate and close into the AtLookup interface
- deprecate: authenticate_cram() from AtLookupImpl. [cramAuthenticate should be used instead]
- build(deps): Upgrade at_commons to v3.0.57 and at_chops to v1.0.5
## 3.0.40
- feat: make `SecondaryUrlFinder` (atServer address lookup) resilient to 
  transient failures to reach an atDirectory
- feat: made `retryDelaysMillis` a public static variable
  in `SecondaryUrlFinder`; this allows clients to control
  - (1) how many retries are done and
  - (2) the delay after each subsequent retry
## 3.0.39
- feat: Changes for apkam
- chore: Upgraded at_commons to 3.0.53 and at_utils to 3.0.15
## 3.0.38
- fix: wrap socket.listen in runZonedGuarded to ensure weird network errors are
  always caught
## 3.0.37
- fix: ensure outbound sockets are cleaned up properly
## 3.0.36
- feat: changes to call at_chops.sign() method which supports different signing algorithms.
- chore: upgrade at_commons to 3.0.43, at_utils to 3.0.12 and at_chops to 1.0.3
## 3.0.35
- fix: fallback code for backward compatibility if at_chops instance is not set
## 3.0.34
- feat: added new method pkamAuthenticate in at_lookup_impl which uses at_chops for pkam signing.
## 3.0.33
- fix: Removed race condition (related to management of outbound connection state after timeouts) which
could in very rare circumstances cause unnecessary long delays
## 3.0.32
- feat: Upgrade at_commons for notifyFetch verb
## 3.0.31
- fix: tls keys are being dumped only by some secure socket connections when decryptPackets is set to true
- feat: tcpNoDelay set to true for all sockets 
- fix: Dart analyzer issues
## 3.0.30
- Introduce clientConfig which can be used to send client configurations to server.
## 3.0.29
- Enhance the executeVerb to handle server responses in JSON format
## 3.0.28
- createConnection() now directly uses CacheableSecondaryAddressFinder which can be passed on as optional param
- Introducing SecureSocketUtil which [optionally] allows creation of secure sockets with security context
- Add mutex to PKAM and CRAM authentication
- AtCommons upgraded to latest version v3.0.20
## 3.0.27
- Improved timeout handling logic in outbound message listener
- Upgraded at_commons version to 3.0.19
## 3.0.26
- Update at_commons version 3.0.18 to display hidden keys in scan
## 3.0.25
- Update at_commons version 3.0.17 for AtException hierarchy
## 3.0.24
- Removed invalid line added to base_connection.dart
## 3.0.23
- Update at_commons version 3.0.16 for bypass cache feature
## 3.0.22
- find secondary bug fix
## 3.0.21
- Added CacheableSecondaryAddressFinder
## 3.0.20
- Update at_commons version
- Remove unnecessary print statement
## 3.0.19
- Export secondary address cache from the package
- Update at_commons and at_utils version
## 3.0.18
- Updated dependencies
## 3.0.17
- Added cache for secondary url lookup from root server
## 3.0.16
- Rename NotifyDelete to NotifyRemove
## 3.0.15
- Update at_commons version for Info and NoOp verb
- Update at_commons version for NotifyDelete verb
## 3.0.14
- Upgrade at_commons version for bug fix in notify verb syntax
## 3.0.13
- Upgrade at_commons version for shared key metadata support in notify
## 3.0.12
- Add encryption shared key and public key checksum of sharedWith atsign in metadata
## 3.0.11
- increase outbound connection timeout
## 3.0.10
- outbound listener bug fix
## 3.0.9
- at_commons version change for AtTimeoutException
- Handle error: responses from server
## 3.0.8
- at_lookup fix race condition when not using await with lookup requests
## 3.0.7
- at_utils version change for fix formatAtSign bug for null value
## 3.0.6
- at_commons and at_utils version change
## 3.0.5
- at_commons and at_utils version change
## 3.0.4
- at_utils and at_commons version change for AtKey validations. 
## 3.0.3
- Reduce wait time on address lookup to root server 
## 3.0.2
- Reduce wait time on server response
## 3.0.1
- connection close replaced with destroy
## 3.0.0
- Sync pagination feature
## 2.0.5
- bug fix for no verb response
## 2.0.4
- at_commons version change
## 2.0.3
- at_utils and at_commons version change for stream resume
## 2.0.2
- at_utils and at_commons version change
## 2.0.1
- at_utils and at_commons version change
## 2.0.0
- Null safety upgrade
## 1.0.0+8
- Refactor code with dart lint rules
- at_utils and at_commons version changes
## 1.0.0+7
- Third party package dependency upgrade
- Call back to auto restart monitor connection
## 1.0.0+6
- at_utils and at_commons version changes
## 1.0.0+5
- atsign validation changes
- at_utils and at_commons version changes
## 1.0.0+4
- at_utils and at_commons version changes
## 1.0.0+3
- public data signing, at_utils and at_commons version changes
## 1.0.0+2
- at_utils and at_commons version changes
## 1.0.0+1
- at_utils version changes
## 1.0.0
- Initial version, created by Stagehand
