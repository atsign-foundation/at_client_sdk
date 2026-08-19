## 3.7.0

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
  one bounds the whole response, the other restarts on every chunk. Callers
  passing explicit values are unaffected, and a process that sets
  `AtNetworkTimeouts.defaultTimeout` at startup now moves this too.

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
