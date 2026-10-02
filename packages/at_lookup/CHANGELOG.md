## 3.7.0-rc3

- feat: while notifications are on, each heartbeat the atServer answers logs
  `Heartbeat OK: lastReceipt <time of the last notification>` at info, as
  at_client's Monitor used to.

## 3.7.0-rc2

- fix: a notification arriving after an unexpected line from the atServer (an
  error, a banner, part of a reply) is no longer lost, so a client can no
  longer go deaf while its connection stays up. A notification and a reply
  arriving together are both delivered.
- fix: a TLS connect is bounded through the end of the handshake, so a peer
  that never finishes it no longer hangs the connect or keeps the process
  alive.
- fix: two authentications racing on one lookup no longer leave its verbs
  refused as unauthenticated.
- fix: stopping notifications while they start leaves them stopped, and a
  heartbeat or reconnect that a stop cuts short ends quietly.
- fix: a request in flight when this client closes the connection fails with a
  `ConnectionInvalidException` that says so, logged once at info rather than
  also twice at severe.
- feat: `AtLookUp.close()` ends the lookup: work in flight fails with
  `StoppedException`, its sockets close, notifications stop, and every later
  call throws `StoppedException`. A caller that closed a lookup and kept using
  it calls `AtLookupMuxable.dropConnection()` instead.
- feat: `checkAtSignServer(lookUp, atSign)` reports whether an atSign is
  registered, whether its atServer answers and whether it is activated, with
  the cause of any failure.
- feat: `AtLookUpFactory`, with `secureSocketLookUps` in `at_lookup_io.dart`
  as the TLS default, lets an application choose how every connection a client
  opens travels. `AtLookUp.withSecureSocket` takes `onConnect`, run first on
  each new connection, for a proxy.
- feat: `AtLookupImpl.notificationReconnectDelays` is settable, for tests.
- chore: opening and closing a connection, and sending `monitor:`, log at
  finer rather than info.
- build: requires `at_commons` ^5.18.0.

## 3.7.0-rc1

- feat: `AtLookupMuxable`, an `AtLookUp` that also carries the atServer's
  notifications. `notifications` is a single-subscription stream whose pause
  reaches the socket, `startNotifications` and `stopNotifications` control it,
  and `notificationConnectionUp` says when it is up or lost. **NB** this lets
  at_client use one connection rather than creating and authenticating
  several; making that easy for SDK users to choose comes in a 4.x minor
  release after the post-quantum work.
- feat: `AtLookUp.withSecureSocket(...)` creates one from an `AtRootDomain`, an
  `authenticator` and a `transport`; `AtLookupImpl`'s constructor is
  deprecated in its favour.
- feat: `AtLookupTransport` says how connections are made, with
  `secureSocketTransport(...)` in the new `package:at_lookup/at_lookup_io.dart`,
  which re-exports `at_lookup.dart`. `transport` has no default.
- feat: `AtAuthenticator` and `AtCommandExecutor` let a caller inject
  authentication. The credential members `atChops`, `signingAlgoType`,
  `hashingAlgoType` and `enrollmentId`, and `AtLookupImpl`'s `privateKey` and
  `cramSecret`, are deprecated, for removal in 4.0.
- feat: `AtLookupMuxable` declares `authenticator`, `isConnectionAvailable`,
  `readResponse`, `scan(auth:, showHiddenKeys:)` and `lookup(metadata:)`, so
  callers no longer cast to `AtLookupImpl`.
- feat: `AtConnectionMetaData` records `authenticatedAsEnrollmentId` and
  `authenticatedAt`.
- feat: `OutboundMessageListener` gains `onNotification`, `onDisconnect` and
  `pauseDelivery`/`resumeDelivery`.
- perf: a response is read as soon as it arrives, rather than up to 10ms later.
- fix: a request in flight when its connection closes fails at once, instead of
  waiting for the response timeout.
- deprecated: `AtLookUp.executeVerb`'s `sync` parameter, which was never read;
  removal in 4.0.
- build: requires `at_chops` ^3.6.0 and `at_commons` ^5.16.0.

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
