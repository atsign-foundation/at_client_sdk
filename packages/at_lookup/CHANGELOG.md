## 4.0.0

at_lookup owns the wire protocol and makes no cryptographic choice of its own.
Algorithms are supplied at construction, and the only key material it retains is
the PKAM private key — which is what lets it keep re-authenticating a replaced
connection by itself.

- breaking: remove `AtLookUp.atChops`. at_chops 4.0.0 deletes the `AtChops`
  facade, so there is no type left for it to be — and it carried encryption keys
  the handshake never touched. Construct with the algorithms instead:
  `signingAlgo` (an `AtSignatureAlgorithm`, which signs the `from` challenge),
  `hashingAlgo` (the CRAM digest, defaulting to `SHA512HashingAlgo`) and
  `dataAlgo` (data-signature verification, defaulting to `RsaSigningAlgo`)
- breaking: remove `AtLookUp.signingAlgoType` and `hashingAlgoType`. The `pkam`
  verb is now stamped from what `signingAlgo` declares, so it cannot claim one
  algorithm while the signature was produced with another. An algorithm that
  hashes intrinsically (ML-DSA-65) reports a null `hashingAlgoType` and the
  `:hashingAlgo:` token is omitted
- breaking: the PKAM private key is a constructor parameter, `pkamPrivateKey`,
  and is **raw key bytes** — `base64Decode` of the string form an atKeys file
  carries, so PKCS#8 DER for RSA. The deleted `privateKey` field took a PEM
  `String`; the rename is deliberate, since this package deals with several
  private keys. Omit `signingAlgo`/`pkamPrivateKey` for an instance that can only
  `cramAuthenticate`, as activation does before a PKAM key exists;
  `pkamAuthenticate` then throws before contacting the atServer
- feat: `AtLookUp.legacy` and `AtLookUp.pq` construct an instance from just a
  private key — the classical (RSA-2048/SHA-256 PKAM) and post-quantum
  (ML-DSA-65 PKAM) algorithm sets. `AtLookUp.create` names each algorithm
  individually. `pkamAuthenticate({String? enrollmentId})` and
  `cramAuthenticate(String secret)` keep their 3.6.0 signatures
- breaking: `AtLookupImpl` is no longer exported — construct via the factories
  above. `isConnectionAvailable()` moves onto the `AtLookUp` interface, since it
  was previously reachable only by downcasting
- breaking: transparent re-authentication is now PKAM-only. The old
  `cramSecret != null` fallback silently re-CRAMed a dropped connection, which
  only ever made sense during activation. **This is a runtime change that no
  compile error will surface**: a CRAM-only instance that loses its socket now
  throws `UnAuthenticatedException`. The check happens before anything is
  written, so no verb is left half-sent and the exception is safe to retry
- breaking: remove the deprecated `authenticate(privateKey)` and the `privateKey`
  field — use `pkamAuthenticate`
- breaking: remove the deprecated `authenticate_cram(secret)` and the
  `cramSecret` field — use `cramAuthenticate(secret)`
- breaking: remove the deprecated `static AtLookupImpl.findSecondary` — use
  `CacheableSecondaryAddressFinder`, which is still exported and, unlike the
  static, keeps its cache across calls
- breaking: remove `MonitorClient`. It had no callers anywhere, and it was a
  second hard-coded RSA/SHA-256 `from`/`pkam` handshake built on at_chops types
  4.0.0 deletes
- breaking: `secondaryAddressFinder` and `enrollmentId` are constructor
  parameters and lose their setters. A different key is a different authenticated
  identity — construct a new `AtLookUp` rather than swapping one in
- chore: `at_chops` constraint moves to `^4.0.0`.
  `AtLookupSecureSocketFactory` and its two siblings move to
  `src/connection/at_lookup_socket_factories.dart`, still exported

See `docs/auth-key-material.md` for why the design landed here, and
`example/bin/example.dart` for the intended wiring.

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
