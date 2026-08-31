## 5.17.0

- feat: `enroll:infons:<namespace>` — "info about a namespace". A read verb
  alongside `enroll:listns`, taking the same authorisation, returning a JSON
  **map** of facts about the namespace rather than a list of its members. Its
  first member is `lastRevokedAt`: the latest moment a revocation touched an
  enrollment granted that namespace, or null.
  A map because the fact is about the NAMESPACE and not about any member: on a
  roster of approved enrollments the same value would have had to be repeated on
  every row under a name apologising for where it lived. `enroll:listns` is
  unchanged, which matters — a client resolves conveyance recipients through it,
  and its returning approved enrollments only is what keeps a revoked enrollment
  off every roster.

## 5.16.0

- feat: add `AtNetworkTimeouts.defaultResponseBudget` (90s) — the overall budget
  for one complete response, as distinct from `defaultTimeout`, which bounds the
  wait for the *next* bytes and restarts every time a chunk arrives. A large
  response is many such waits in a row, and only this budget bounds their sum, so
  a peer that trickles bytes indefinitely is caught by this and by nothing else.
  Deliberately not passed through `cap`: it bounds an aggregate rather than a
  single operation, and its own default already exceeds the 60s ceiling. Nothing
  reads it yet.

- docs: `signingAlgo` says plainly that it names the APKAM **authentication**
  key's algorithm — the key that signs the `from:` challenge — and not the
  algorithm an enrollment signs documents with. The name invites the second
  reading and the two are deliberately different algorithms from rollout 1
  onward. Stated on `EnrollParams`, `EnrollVerbBuilder` and `PkamVerbBuilder`,
  which all declare the field and previously said this in two forms and none.

- feat: add `EnrollVerbBuilder.apkamPublicKeySignature`, threading the existing
  `EnrollParams.apkamPublicKeySignature` through to the built command. The field
  had no route to the wire, so an `enroll:update` could not carry the proof of
  possession the atServer requires before it installs a new `apkamPublicKey` —
  which made the rotation the field exists for unsendable.
- feat: add `Metadata.copy()` — a field-for-field copy, so callers handing
  metadata from one object to another stop hand-rolling the field list. A
  hand-rolled copier silently drops any field added to `Metadata` later: the
  value still round-trips and only the missing field is absent at the far end,
  which is how `immutable` and `appMetadata` went astray on several paths in
  `at_client`. A caller that must not carry a field clears it after copying, so
  the exception is written where it applies rather than being the default.

## 5.15.0

- feat: add `EnrollVerbBuilder.apsk`, threading the existing
  `EnrollParams.apsk` through to the built command. The field had no route to
  the wire, so nothing could send the value the atServer publishes verbatim.
- feat: add `EnrollParams.apskLegacy` and the matching `EnrollVerbBuilder`
  field, carrying the **bare** RSA `_apsk` string an enrollment publishes
  verbatim. Every deployed `_apsk` consumer base64-decodes the value as an RSA
  key, so a plain-legacy enrollment must be able to publish that shape through
  the same verb every other enrollment uses. A separate field rather than
  widening `apsk` to two types, which would have been source-breaking on a
  published field. The atServer writes it as-is — **not** JSON-encoded, since a
  quoted string is not what a bare-RSA parser reads — and refuses a request
  carrying both fields, which would disagree about one record with no basis for
  choosing between them.
- fix: `EnrollParams.apsk`'s entry `status` is `active` or **`retired`**, not
  `verifyOnly` as 5.14.0 documented, and the entry carries a `kid` like every
  other key entry in the protocol. `retired` is use-neutral — "retained, not
  for new operations" — because `use` already names the operation a key serves:
  a retired signing key still verifies old envelopes, and a retired
  encapsulation key still opens records already sealed to it. Documentation
  only; the atServer stores the value verbatim, so no record carries either
  spelling.

## 5.14.0

- feat: add `EnrollParams.apsk` — the value a client composes for its own
  `public:_apsk.<enrollmentId>.a.__e@<atSign>` signing key, carried on
  `enroll:request` and stored verbatim on the enrollment record. A
  `Map<String, dynamic>` like `metadata`, opaque to the atServer, capped there
  at 20KB encoded.

  It exists so the atServer can stop composing that value from
  `(apkamPublicKey, signingAlgo)`. PKAM verification is record-authoritative
  and reads the enrollment record, so `_apsk` is a client-side artefact the
  server has no use for and no business knowing the format of — it was
  publishing one only because the record's rightful writer, the enrollee, does
  not exist yet at approval. Sending the value moves the format back to the
  side that owns it, and a new signing-key shape stops needing a server
  release. Absent means no `_apsk` is published at all.

  The form the client composes is a versioned array of signing keys —
  `{"v":1,"keys":[{"use","alg","pub","status"}]}` — spelled as `KeyPackage`'s
  keys are, so one vocabulary covers every "list of keys with algorithms" in
  the protocol. An entry whose `status` is `verifyOnly` has stopped signing but
  is retained: envelopes are stored durably and re-verified later, so removing
  a key would retroactively unverify everything ever signed with it.

- feat: add `EnrollOperationEnum.update` and the matching `enroll:update`
  alternation in the `enroll` grammar — an approved enrollment amending its own
  record's `apkamPublicKey`, `signingAlgo`, `apsk` and `metadata`. Self-only:
  the connection's enrollment id must equal the target's. It never reaches
  `namespaces` or the approval state, because an operation an enrollment can
  invoke on itself must not be able to widen its own grant.

  This is what lets an enrollment replace its APKAM authentication keypair
  while keeping its id, rather than the replacement being a new enrollment.

- feat: add `EnrollParams.apkamPublicKeySignature` — base64 of a signature by
  the **new** APKAM private key over
  `<enrollmentId>|<apkamPublicKey>|<signingAlgo>`, required on an
  `enroll:update` that changes `apkamPublicKey`.

  The connection proves possession of the enrollment's *current* key and
  nothing else proves possession of the new one, so without this a
  compromised-but-authenticated client can install a public key whose private
  half is held by someone else — locking out the legitimate holder while the
  record still looks valid.

## 5.13.0

- feat: add `AtNetworkTimeouts` — the process-wide network-timeout policy:
  `defaultTimeout` (30s, the per-attempt default), `maxAllowed` (60s hard cap on
  any single network operation), `defaultOnboardingTimeout` (5 min — the poll
  budget for waiting on a newly-registered atSign to be provisioned, deliberately
  longer than the per-op cap), and `cap()`. The single place to set the SDK's
  network timeouts (#1909).
- feat: add `SecureSocketConfig.connectTimeout` so a connect deadline can be
  threaded through to `SecureSocket.connect`.

## 5.12.0

- feat: add the `enroll:listns:<listNamespace>` operation to the enroll verb
  grammar (the gated per-namespace enrollment-discovery verb), ordered before
  `list` in the operation alternation so it is not prefix-shadowed.
- feat: add `EnrollParams.metadata` (opaque `Map<String, dynamic>`, stored
  verbatim on the enrollment record and returned from discovery) and
  `EnrollParams.signingAlgo` (`rsa2048` | `mldsa65`), with the matching
  `EnrollVerbBuilder` fields; an empty `metadata` map is dropped from the
  built command.
- feat: widen the `pkam` verb `signingAlgo` literal to accept `mldsa65`
  (post-quantum ML-DSA APKAM authentication).

## 5.11.0

- feat: add `Metadata.appMetadata` (`AppMetadata{providerId, additional}`),
  emitted on the wire as `:appMetadata:` (base64-encoded JSON) on the
  `update`, `update:meta` and `notify` verbs and parsed back by the verb
  builders. `providerId` routes pluggable-crypto decryption; `additional`
  is provider-owned opaque metadata. `providerId` must be a non-empty
  string (a `FormatException` is thrown otherwise).

## 5.10.0

- feat: add `:cl` flag to the `scan` verb syntax, plus
  `ScanVerbBuilder.commitLog`
- feat: add `:nc` (no-commit) flag to the `update`, `update:meta`, `update:json`
  and `delete` verb syntaxes, plus `UpdateVerbBuilder.noCommit` and
  `DeleteVerbBuilder.noCommit`
- feat: add `:dAt` (deletedAt) timestamp to the `delete` verb syntax, plus
  `DeleteVerbBuilder.deletedAt`
- feat: emit `Metadata.createdAt` / `updatedAt` / `expiresAt` / `availableAt` on
  the wire as `:cAt:` / `:uAt:` / `:eAt:` / `:aAt:` (used by `update`,
  `update:meta` and `notify`)
- feat: timestamp wire format is ISO 8601 UTC with 6 fractional-second digits,
  e.g. `2026-05-05T11:59:44.123456Z`; helper at `VerbUtil.formatIso8601Micros`

## 5.9.0

- feat: add `AtKey.fullKey` getter — key name including its namespace
- feat: add `AtKey.fullKeyAndOwner` getter — `fullKey` combined with the owning atSign
- feat: add equals method for `AtBytes`

## 5.8.0

- feat: add `AtBytes` supporting hardware acceleration in `at_chops`

## 5.7.0

- feat: extend syntax of `info` verb, adding `info:mtls` and `info:mtlsbrief`

## 5.6.2

- chore: remove `@experimental` annotation from `EnrollVerbBuilder.otp`

## 5.6.1

- chore: fix lint from the new `strict_top_level_inference` rule

## 5.6.0

- feat: add `AtRootDomain` with basic parsing including proxy.

## 5.5.0

- chore(deps): bump uuid to "^4.0.0"

## 5.4.1
- fix: `NotifyVerbBuilder.buildCommand()` uses `AtKey.toString()` instead of 
  doing its own thing.

## 5.4.0
- feat: add `EnrollmentConstants`. Contains various patterns and regular 
  expressions for enrollment-related data
## 5.3.0
- feat: add `immutable` flag to `Metadata` and `force` flag to the 
  DeleteVerbBuilder. Immutable records may not be updated once the immutable 
  flag has been set, and may not be deleted unless the `force` flag has been 
  set in the delete command.
## 5.2.0
- feat: add Atsign string extensions
- feat: add AtServerEvent interface and AtSignPKChangedEvent class
## 5.1.2
- fix: remove isPaginated check in SyncVerbBuilder and always set from: and limit: since sync:from verb
  expects these params to be set.
## 5.1.1
- fix: Introduce IV params for apkam enrollment flow
## 5.1.0
- feat: Introduce skipDeletesUntil for sync:from verb
## 5.0.2
- fix: Add "publicKeyHash" and "hashingAlgo" type to metadata.
- build[deps]: Upgraded the following package:
  - json_annotation to v4.9.0
  - meta to v1.16.0
  - build_runner to v2.4.13
  - json_serializable to v6.9.0
  - lints to v5.0.0
  - test to v1.25.8
  - test_process to v2.1.0
## 5.0.1
- fix: export regex utils class
## 5.0.0
- [Breaking Change]feat: Emit the isEncrypted value in the metadata if it is false
- fix: update pkam regex to accept sha512 as hashing algo
## 4.1.2
- feat: Add "expiry" enroll params to support apkam keys to auto expiry after specified time duration
## 4.1.1
- feat: Add "delete" operation to the enroll verb to allow deletion of denied enrollments
## 4.1.0
- feat: Add "unrevoke" operation to the enroll verb to restore revoked APKAM keys
- fix: Add isEncrypted flag to notify command for both true and false
## 4.0.11
- chore: deprecate MessageTypeEnum.text
- fix: remove deprecated annotation from Metadata.pubKeyCS
## 4.0.10
- fix: Add a "force" variable to enroll_verb_builder to propagate enroll:revoke:force value
- fix: Deprecate apkam in PkamAuthMode enum
## 4.0.9
- feat: enroll verb syntax change for enroll:revoke:force and added new exception AtEnrollmentRevokeException
## 4.0.8
- fix: Add shared_key.atsign@atsign to reservedKey regex
## 4.0.7
- fix: Add fetch operation to enroll verb to get the enrollment details
## 4.0.6
- fix: max key length validation changes
- fix: PublicKey toString method should return 'cached:' when isCached is set in metadata
## 4.0.5
- feat: Enhance enroll:list to enable filtering based on enrollment status
## 4.0.3
- fix: "toJson()" invoked on "pubKeyHash" leads to NullPointerException.
## 4.0.2
- feat: changes to replace md5 checksum - deprecated pubKeyCS in AtKey and introduced new class PublicKeyHash
## 4.0.1
- fix: Add "InvalidPinException" which is thrown when an invalid Semi Permanent Passcode is submitted.
## 4.0.0
- [Breaking Change] fix: Updated regex for Reserved keys (Internal keys used by the server)
- fix: Add "put" operation to OTP verb to store semi-permanent pass codes
- Remove attributes related to AtKey and metadata in verb builders. Instead, use AtKey instance. 
## 3.0.58
- fix: Deprecate encryptedDefaultEncryptedPrivateKey in EnrollParams and introduce encryptedDefaultEncryptedPrivateKey for readability
- fix: Replace encryptedDefaultEncryptedPrivateKey with encryptedDefaultEncryptionPrivateKey in EnrollVerbBuilder
## 3.0.57
- feat: Introduced TTL(Time to Live) for OTP verb to configure OTP expiry
## 3.0.56
- feat: Introduce "AtInvalidEnrollmentException" which is thrown when an enrollment is expired or invalid
- feat: Introduce error code 'AT0030' for Invalid Enrollment Status
- chore: Deprecated all variables in `src/at_constants.dart`, use `AtConstants.<variable-name>` instead
## 3.0.55
- feat: Introduce "AtThrottleLimitExceeded" exception which is thrown when enrollment request exceeds the limit
- feat: Introduce new error codes for apkam enrollments
## 3.0.54
- fix: Modify "totp" verb regex to include alphanumeric characters
- feat: Introduce "EnrollResponse" class which represents the enrollment response.
## 3.0.53
- feat: Modify "enroll" verb regex.
- feat: Introduce "EnrollParams" class to encapsulate enrollment attributes.
## 3.0.52
- fix: Add revoke and list operations to "enroll" verb
- fix: Modify "keys" verb regex and verb builder
## 3.0.51
- feat: added exception class for enrollment exception
## 3.0.50
- feat: add self notification flag in monitor syntax for APKAM feature
## 3.0.49
- feat: added syntax and verb builder for keys verb
- feat: introduced verb builder for enroll and pkam verbs
- chore: Moved this package to a new repo & updated repository URL
## 3.0.48
- feat: totp support in enroll verb
## 3.0.47
- fix: Enhance stats verb to allow regex for stats:15
- feat: Add syntax and verb builder for APKAM enroll verb
## 3.0.46
- fix: Modify emoji list to allow variation selector Unicode
## 3.0.45
- fix: Add constants for AtClientParticulars
## 3.0.44
- feat: introduce enum for pkam authentication mode
## 3.0.43
- feat: Enhanced the monitor verb syntax
  1. added `strict` flag to allow client to request that only regex-matching notifications are sent -
     e.g. do not send other 'control' type notifications like the 'statsNotifications'
  2. added `multiplexed` flag to allow client to indicate that
     this socket is also being used for request-response interactions
## 3.0.42
- fix: Tightened the validation of 'public' key names. Keys like this: `public:@bob:foo.bar@alice` will now correctly be identified as not being valid.
## 3.0.41
- fix: Add 'configkey' to list of reserved keys for key validation purposes
## 3.0.40
- fix: Add notification expiry to the notify verb builder.
## 3.0.39
- feat: add new exceptions for at_chops operations.
## 3.0.38
- fix: add hashing algorithm to pkam syntax.
## 3.0.37
- fix: change signing algo in pkam syntax from rsa256 to sha256.
- fix: pub score issues.
## 3.0.36
- feat: change is pkam syntax to support different signing algorithms.
- fix: pub score issues.
## 3.0.35
- feat: enforce lowercase on AtKey(all key types included)
- fix: incorrect behaviour of cached:public keys in AtKey.fromString()
- feat: Added new fields to Metadata
- feat: Added new encryption metadata to the syntax for notify, update and update:meta verbs
## 3.0.34
- feat: New server-side exception ServerIsPausedException, error code AT0024
## 3.0.33
- fix: Deprecate AtCompactionConfig class
## 3.0.32
- fix: Enable deletion of a local key
## 3.0.31
- feat: Added AtTelemetryService. Marked @experimental while the feature is in early stages.
## 3.0.30
* fix: Add key validations to Update and llookup verb builders
## 3.0.29
* fix: AtKey.fromString() sets incorrect value in sharedWith attribute for public keys.
## 3.0.28
* feat: Introduce the local key type
## 3.0.27
* feat: Implement the `==` and `hashCode` methods for AtKey, AtValue and Metadata classes
## 3.0.26
* feat: Introduce notifyFetch verb
* fix: bug in at_exception_stack.dart
## 3.0.25
* fix: update regex to correctly parse negative values in ttl and ttb
* feat: add clientConfig to from verb syntax
## 3.0.24
* fix:  add error code for InvalidAtKeyException
## 3.0.23
* fix: bug fixes to AtKey.fromString static method and various toString instance methods
* feat: When validating AtKeys, allow _namespace_ to be optional, for legacy app code which depends on keys without namespaces
* feat: Added _getKeyType_ to AtKey

## 3.0.22
- Add ENCODING to update verb regex, update verb builder and Metadata to support encoding of new line character
- Add AtKeyNotFoundException for non-existent keys in secondary
- Add documentation around the Metadata fields
## 3.0.21
- Add constant for stats notification id
## 3.0.20
- Enhance notify verb to include the isEncrypted field
- Add intent and exception scenario to AtException subclasses
- Introducing class SecureSocketConfig to store config params to create security context for secure sockets.
## 3.0.19
- Rename byPassCache to bypassCache in lookup, plookup verb builders and at_constants
## 3.0.18
- Add 'showHidden' to scan regex to display hidden keys when set to true
## 3.0.17
- Introduce exception hierarchy and new AtException subclasses
## 3.0.16
- Hide at_client_exceptions.dart to prevent at_client_exception being referred from at_commons
## 3.0.15
- FEAT: support to bypass cache in lookup and plookup verbs
## 3.0.14
- Remove unnecessary print statements
## 3.0.13
- Generate default notification id
## 3.0.12
- Added optional parameter to info verb. Valid syntax is now either 'info' or 'info:brief'
## 3.0.11
- Rename 'NotifyDelete' to 'NotifyRemove' since 'notify:delete' is already in use.
## 3.0.10
- Added syntax regex for 'notifyDelete' verb
## 3.0.9
- Bug fix in notify verb syntax
## 3.0.8
- Support for encryption shared key and public key in notify verb
## 3.0.7
- Added encryption shared key and public key checksum to metadata
## 3.0.6
- Added syntax regexes for new verbs 'info' and 'noop'
## 3.0.5
- Rename TimeoutException to AtTimeoutException to prevent confusion with Dart async's TimeoutException
## 3.0.4
- Add TimeoutException
## 3.0.3
- Add static factor methods for AtKey creation
## 3.0.2
- added constants for compaction and notification expiry
## 3.0.1
- Add AtKey validations
## 3.0.0
- sync pagination changes
## 2.0.5
- version 2.0.4 update issue
## 2.0.4
- Shared key status in metadata
- Add last notification time to Monitor
## 2.0.3
- Syntax change in stream verb to support resume
## 2.0.2
- Fix regex issue in Notify verb
## 2.0.1
- Remove trailing space in StatsVerbBuilder
## 2.0.0
- Null safety upgrade
## 1.0.1+8
- Refactor code with dart lint rules
## 1.0.1+7
- Third party package dependency upgrade
## 1.0.1+6
- Replace ByteBuffer with ByteBuilder
## 1.0.1+5
- Notification sub system changes
## 1.0.1+4
- added createdAt and updatedAt to metadata
  Introduced batch verb for sync
## 1.0.1+3
- Notify verb builder and update verb syntax changes
## 1.0.1+2
- Update verb builder changes
## 1.0.1+1
- Stream verb syntax changes
## 1.0.1
- Initial version, created by Stagehand
