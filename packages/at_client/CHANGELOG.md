## 3.12.0

Several significant enhancements to the API to make it much easier to use.

**Pre-stable readiness sweep** (2026-04-29) — `AtCollection<T>` is
no longer `@experimental`. The pre-stable plan tightened class
modifiers, removed record-typed return values, and pre-allocated
evolution slack so the next minor releases stay non-breaking. See
`AtCollection_API_Assessment.md` §11.5 for the full list of
findings closed and post-stable work deferred.

- feat(AtCollection)!: drop `@experimental` annotation from every
  collection-related public type (`AtCollection`, `CItem`,
  `Query`, `SubSpec`, `TreeNode`, `WithChildren`, `PathField`,
  `Predicate` and subclasses, `PredicateOp`, all `CEvent`
  subclasses, all `OpResult` subclasses,
  `CollectionOpException`). The library is committed to
  non-breaking minor changes from this release forward.

- feat(AtCollection)!: tighten class modifiers for stable release.
  `OpResult` is now `abstract base class` (was `sealed`); user
  exhaustive switches no longer break when a new variant lands.
  `AtCollection<T>` is now `interface class` — `extends`
  forbidden, `implements` still works for mocking. `OpSuccess`,
  `OpFailure`, `CollectionOpException`, and every `CEvent`
  subclass marked `final class`.
- feat(AtCollection)!: replace anonymous records with named
  classes. `CAncestor` typedef → `final class CAncestor` with
  named-only ctor. `Query.watchWithSub` returns
  `Stream<List<WithChildren<P, C>>>` — a new `final class` —
  instead of an anonymous record type.
- refactor(AtCollection)!: drop the `sharedWith:` named-optional
  on `update`. Use `updateSharedWith` to change recipients only,
  or mutate `item.sharedWith` directly before calling
  `update(item)` to bundle a value change with a recipient
  change.
- feat(AtCollection): pre-allocate `PredicateOp` values `like`,
  `inSet`, `between`, `contains`, `startsWith`. Their
  implementations throw `UnimplementedError` until landed; adding
  the impl later is non-breaking. Apps that exhaustively switch
  on `PredicateOp` should always include a `default:` branch.
- feat(AtCollection): `exists(id, owner)` — presence check that
  doesn't materialise the value.
- feat(AtCollection): `Query<T>.distinct(keyFn)` — first-seen-
  per-key dedupe terminal.
- feat(AtCollection)!: rename `Query.fetch` → `Query.get`.
  `fetch()` retained as a `@Deprecated` shim for one minor.
- chore(AtCollection): privatise `logger`; move `prettyString` to
  a `CItem` extension (reads as `item.prettyString`).
- chore(AtCollection)!: relocate every `@visibleForTesting` member
  to a `part of` test-hooks file. The instance-method names
  (`handleNotification`,
  `subCollectionWithInjectedNotifications`, etc.) and the static
  helpers (`clearFactoriesForTest` etc.) no longer hang off
  `AtCollection<T>` — they're top-level helpers with a `ForTest`
  suffix in `collections_test_hooks.dart`. Tests call e.g.
  `collectionWithInjectedNotifications<T>(...)` instead of
  `AtCollection<T>.withInjectedNotifications(...)`.

- feat: New feature - Collections - a clean API for storing, sharing, 
  unsharing and deleting objects in named collections, with sub-collections, 
  event streams, built-in support for read receipts, and more
- feat(AtCollection): `typeTag` is required wherever a factory is
  registered — `AtCollection.registerFactory<U>(...)`, the
  `fromJson:` shortcut on `AtCollection.new` /
  `AtCollection.withInjectedNotifications` / `AtClient.collection<T>`
  / `AtCollection.subCollection<U>`, and
  `Query<T>.watchWithSub<U>(subFromJson: ...)`. Pinning the
  wire-format identifier explicitly stops Dart's minifier /
  tree-shaker (AOT obfuscated builds) silently renaming the
  on-wire type tag when class names move.
  Pass `typeTag: 'YourType'` next to every `fromJson:` /
  `registerFactory` call.
- feat(AtCollection): registry rejects re-registering the same
  type under a different `typeTag`, and rejects binding the same
  `typeTag` to two different types — the wire-format contract no
  longer drifts silently. Same-(type, tag) re-registration is
  idempotent (last fromJson body wins).
- feat(AtCollection): `Query<T>.thenBy(keyFn, {descending})` for
  multi-key sort. Chains tiebreakers after a primary `orderBy`,
  each level with its own independent `descending:`. `orderBy`
  retains replace semantics (LINQ / Drift / Isar idiom);
  `thenBy` without a prior `orderBy` throws `StateError`.
- feat(AtCollection)!: `subCollection<U>` no longer exposes the
  `notifications:` test hook on its public surface. Tests that
  inject a notification stream now call
  `subCollectionWithInjectedNotifications<U>(...)` (a
  `@visibleForTesting` sibling). Internal callers (e.g.
  `Query.watchWithSub`) thread the parent collection's stream
  through a private path, so live behaviour is unchanged.
- feat(AtCollection): unknown envelope `type` tags are now logged
  as a per-collection WARNING (once per tag) on rehydrate
  fallback, naming the missing tag and pointing at
  `registerFactory`. Closes the silent registry-drift footgun
  alongside the W2 required-`typeTag` change.
- perf(AtCollection): `update(item)` now elides the existence
  probe when this process has already successfully written the
  same self-key (per-collection `_seenSelfIds` cache, drained on
  successful self-key delete). Same-process bulk-edit workloads
  pay one fewer round-trip per item.
- fix(AtCollection): `cleanupOrphans` now sweeps depth-2+ legacy
  descendants (items written before the `parents` envelope) when
  any ancestor between root and direct parent is locally absent.
  The legacy fallback chain-walks by id-presence at each composed-
  namespace level (owner-agnostic, intentionally lenient).
- feat(AtCollection): `Query<T>.watchWithTree(List<SubSpec>)` for
  multi-level parent → children → grandchildren joins.
  Generalises `watchWithSub` to arbitrary depth via recursive
  `SubSpec<U>` nodes; emits a `List<TreeNode<T>>` whose
  `branches[subName]` carry nested `TreeNode<dynamic>` lists.
  Cascade-cancels descendant subscriptions when a parent leaves
  the result set or the outer stream is cancelled.
- feat(AtCollection): typed predicate AST. `PathField<V>` is a
  declared accessor (`path` + `extract`) that mints `Predicate`
  nodes via `eq` / `neq` / `lt` / `lte` / `gt` / `gte` / `isNull`
  / `isNotNull`; `Predicate.and` / `.or` / `.not` compose them.
  New `Query<T>.wherePath(Predicate)` modifier coexists with
  closure-based `where` (both lists AND together at evaluation).
  Today the AST evaluates in memory; a future SQLite-indexed
  executor can walk the tree and push eligible clauses to a
  secondary index without changing caller code.
- perf(AtCollection): `Query<T>.watch()` now does incremental
  delta maintenance for non-paginated queries — single-item read
  on update events, zero-read cache mutation on deletes — instead
  of a full collection refetch every event. Pagination queries
  (`limit` / `skip`) keep the original full-refetch path because
  the next-out-of-window item isn't cached.
- feat(AtCollection)!: `getKeys` removed from the public surface.
  The implementation lives behind a private `_getKeysInternal`
  used by the SDK's own read/write/cleanup paths. There were no
  example or production callers; app code should use `getItems`
  / `getItemsAsStream` / `Query<T>` instead. `AtKey` no longer
  appears anywhere in the AtCollection public API.
- feat(AtCollection): timer-driven event streams (W7).
  `availableEvents` (typed sub-stream getter, also flows through
  `watch()`) fires `CItemAvailable` as each tracked item's
  `availableAt` passes — lazy-starts a per-collection scheduler
  on first access. `expiringSoonEvents({required leadTime})`
  returns a fresh `Stream<CItemExpiringSoon>` per call, firing
  `leadTime` before each item's `expiresAt`. Items already
  inside their warning window at subscription time fire on the
  next event-loop turn so listeners don't silently miss them.
  Both backed by a generic `_CItemTimerScheduler` with a single
  shared `Timer` armed to the soonest pending firing; subscribes
  to `updates` / `deletes` to keep its firing list current.
- feat(AtCollection): local CEvent emission for in-process
  writes. `create()` / `update()` / `delete()` now fire the
  corresponding `CItemUpdated` / `CItemDeleted` synchronously on
  the writing collection's `_events` controller, plus
  `CSubItemUpdated` / `CSubItemDeleted` on every ancestor
  collection's controller (with correctly-sliced `ancestry`
  matching the round-trip notification path's shape). UIs that
  use `Query.watch` redraw immediately after a local write
  rather than waiting 1–3 s for the round-trip notification.
  Bonus: locally-emitted `CSubItemDeleted` carries fully-
  populated `ancestry.owner` values — stricter than the round-
  trip path which always sets owners to null on delete events
  (the sub-item's envelope is gone by the time the notification
  fires, so the round-trip can't recover them). Each event
  fires twice per in-process write (once locally, once on
  round-trip); `Query.watch`'s delta path is idempotent so this
  is invisible to typical consumers, while hand-listened streams
  may want to dedupe.
- feat(AtCollection): two new ways to mutate `sharedWith`.
  `update(item, {Set<Atsign>? sharedWith, ...})` accepts a
  nullable `sharedWith` parameter that replaces `item.sharedWith`
  in place before the write — self-documenting at the call
  site, no more "mutate then update" pattern. New
  `updateSharedWith(item, newSharedWith, {unshareWithOthers})`
  applies *only* the recipient delta (un-shares atSigns dropped
  from the new set, shares to atSigns added) without rewriting
  the self copy. Cheap-and-quiet for the common workflow "I
  just want @carol to see this too".
- fix(AtCollection): `subCollection` key-length budget tightened
  to the absolute worst case. Previously assumed 24-char atSigns
  and reserved 174 - len(self) chars for the composed namespace;
  now uses the protocol's 55-char-per-atSign maximum on both
  sides (118-char wrapper overhead) and reserves a flat 128
  chars regardless of self-atSign length, so the same SDK builds
  round-trip-safe keys regardless of which atSign owns the
  AtClient. Class dartdoc and runtime error message updated to
  match. Theoretical depth ceiling (with 1-char collection
  names and a 15-char application namespace) is 11 levels —
  root + 10 nested sub-collections.
- feat: added a new method, `send`, to NotificationService which is much 
  easier to use than the old (still fine to use) `notify` method.
- feat: added `factory AtRpc.server` to make it much simpler to create AtRpc 
  servers. 

Major documentation uplift
- docs: Rewrote the main README
- docs: Added many examples in the [example](example/README.md) directory

And some tech debt cleanup
- feat: explicit AtClient lifecycle control — cleanly stop and resume atClients without
  re-initialising storage or keys
- feat: outgoing AtClient's sync and notification services will now be garbage collected
- chore: deprecated `atClientManager` param in the factories of AtClient, NotificationService, and SyncService
- fix: added null guards to AtClient service getters

## 3.11.0     

- chore(deps): at_auth ^3.0.0
- chore(deps): at_chops ^3.0.0

## 3.10.0

- build(deps): Updated archive dependency to ^4.0.7
- feat: Add RemoteLocalPref enum and AtClientPreference.remoteLocalPref field
  to enable apps to easily default to using the remote atServer
- fix: ensure AtRpcResp and AtRpcReq `.toString()` methods are JSON serialized
  strings
- feat: use responseJson variable so that log is consistent
- fix: fixed rare race condition caused by the handling of legacy shared 
  symmetric keys
- feat: improved resilience of the notifications monitor to weird network 
  conditions

## 3.9.2

- fix: AtRpc - prevent NACK/ACK race when handling request mutex acquisition

## 3.9.1

- chore: removed `@experimental` annotation from AtRpc and AtCollection
- chore: added `// ignore: experimental_member_use` for usages of the 
  still-experimental AtTelemetry

## 3.9.0

- feat: introduce single-responder mode in AtRpc enabling redundancy support in
  request-response services relying on AtRpc. This feature is coupled with
  `enableRequestMutex` flag that controls it.

## 3.8.0

- feat: add optional `useRemoteAtServer` flag to AtClient `getKeys` and
  `getAtKeys` so that apps can ask to fetch directly from atServer rather
  than the local datastore.
- fix: set `isClient` to true and `isServer` to false in AtRpcClient,
  enabling same atSign communication of AtRpc clients and servers.
- fix!: fixed a bug where at_rpc was adding the AtClientPreference's namespace
  to the notifications used by at_rpc
  (https://github.com/atsign-foundation/at_client_sdk/pull/1670).

## 3.7.0

- chore(deps): uuid ^4.0.0
- chore(deps): at_commons ^5.5.0
- chore(deps): at_persistence_secondary_server ^4.2.0
- chore(deps): http ^1.2.1
- chore(deps): remove unused dependencies
- chore(deps): move collection to dev_dependencies

## 3.6.0
- feat: deprecate the (misleadingly named)
  `AtClientPreference.Atsign ProtocolEmitted` and change its default value
  from 1.5.0 to 2.0.0

## 3.5.3
- feat: fetch various atKeys keys from atChops if we have it (which we always 
  do, now) instead of going to the keyStore
- refactor: some deprecations for readability / maintainability

## 3.5.2
- fix: ensure that namespaces in `notify` requests aren't messed up by 
  multipart namespaces in AtClientPreference (e.g. namespace of `foo.bar`)

## 3.5.1
- fix: ensure that namespace is preserved if it happens to be repeated in a 
  notification's key (e.g. `@bob:foo.my_app.my_app@alice` )

## 3.5.0
- feat: add `atLookUp` parameter to AtClientManager.setCurrentAtSign,
  AtClientImpl.create, etc. so we can inject an existing AtLookUp instance if 
  we have one rather than having to create a new one and authenticate again

## 3.4.4
- fix[performance]: when fetching `public:publickey` of another atSign from
  atServer, cache it in local storage instead of depending on sync to take
  care of that (since programs can disable sync)

## 3.4.3
- build[deps]: update dependencies including at_persistence major version 
  changes
- fix: tightened up code for handling `AtKeyNotFoundException`s in 
  `AtCollectionQueryOperationsImpl`
- fix: Enable the same atSign to be used on both sides (client and server) 
  of an AtRpc interaction
- fix: LocalSecondary.isEnrollmentAuthorizedForOperation now checks if the 
  key in question is a `local` key, in which case the answer is always yes.

## 3.4.2
- build[deps]: update dependencies (at_commons, at_lookup, at_auth)

## 3.4.1
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 3.4.0
- feat: Allows clients to skip delete commits until a specific commitID during initial sync
## 3.3.1
- fix: isInSync bug fix for apkam connection
- fix: remove deprecated isPaginated param from SyncVerbBuilder in SyncServiceImpl
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.1.2
- feat: Introduce "publicKeyHash" which uses SHA hashing to verify change in the encryption public key
## 3.3.0
- feat: add the AtClientBindings mixin which was initially added to the 
  noports_core package but has broader applicability.

## 3.2.2
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.0.0
  - at_utils to v3.0.19
  - at_lookup to v3.0.49
  - at_auth to v2.0.7
  - at_persistence_secondary_server to v3.0.64
  - at_chops to v2.0.1
## 3.2.1
- feat: add optional param `encryptValue` to notify method
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v4.1.1
  - at_utils to v3.0.18
  - at_lookup to v3.0.48
  - at_auth to v2.0.5
  - at_persistence_secondary_server to v3.0.63
## 3.2.0
- feat: add `allowAll` flag (defaults to false) to AtRpc
## 3.1.0
- feat: add `useRemoteAtServer` flag to `GetRequestOptions` to allow clients 
  to fetch directly from the atServer rather than the client-side synced 
  cache. This flag was added to `PutRequestOptions` and 
  `DeleteRequestOptions` in version 3.0.60
- fix: Ensure that `NotificationResponseTransformer` does not attempt to 
  decrypt when `atNotification.isEncrypted == false`
## 3.0.78
- chore: publish clean version 3.0.78
## 3.0.77+1
- fix: remove incorrect version 3.0.78 from changelog
## 3.0.77
- fix: Fix the keys expiry job not being triggered
- chore: deprecate NotificationParams.forText()
- feat: Store enrollment details in local key
- fix: Add "sharedKeyEnc" to the metadata
## 3.0.76
- feat: Introduce mechanism to identify and delete expired keys
- feat: Introduce enrollment service to support enrollment operations:
  - Submit enrollment request(s)
  - Approve, Deny and Revoke enrollment request(s)
## 3.0.75
- feat: Introduce feature to fetch enrollment requests from the server
## 3.0.74
- build[deps]: Upgraded dependencies for the following packages:
  - at_chops to v2.0.0
  - at_lookup to v3.0.45
## 3.0.73
- build[deps]: Upgraded dependencies for the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_lookup to v3.0.44
    - at_chops to v1.0.7
    - at_persistence_secondary_server to v3.0.60
- feat: Replace encryption methods from EncryptionUtils with AtChops method 
## 3.0.72
- chore: Minor change to allow us to support dart 
  versions both before and after 3.2.0 specifically for this
  [Dart breaking change](https://github.com/dart-lang/sdk/issues/52801) 
  which was
  [introduced](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md)
  in dart 3.2.0
## 3.0.71
- feat: Replace decryption methods from EncryptionUtil with AtChops methods
## 3.0.70
- build[deps]: Upgraded dependencies for the following packages:
  - asn1lib: `>=1.4.1 <=1.5.0`, crypton: `>=2.1.0 <=2.2.1`, encrypt: `>=5.0.1 <=5.0.3`, crypto: `^3.0.3`
## 3.0.69
- feat: Add AtRpcClient for a much cleaner developer experience for sending AtRpc requests
## 3.0.68
- feat: have AtRpc use ephemeral notifications
## 3.0.67
- feat: Make enrollment available to SyncService/NotificationService for authentication
## 3.0.66
- feat: make namespace NOT mandatory for local keys
- feat: deprecate useAtChops experimental flag and remove fallback code using private key from preferences/EncryptionUtil methods
- updated at_commons to `'3.0.57'`, at_chops to `'1.0.5`, at_persistence_secondary_server to `'3.0.59'` 
## 3.0.65
- feat: apkam changes for at_onboarding_cli
- build: updated at_commons to `'3.0.55'`, at_chops to `'1.0.4`, at_lookup to `'3.0.40'` 
## 3.0.64
- Made ConnectivityListener configurable, and removed some unnecessary network 
  availability checks
- fix: wrap Monitor's call to `socket.listen()` in a runZonedGuarded block
## 3.0.63
- fix: Fixed bug in AtRpc.sendRequest which was causing repeat sends of requests
## 3.0.62
- fix: skip reserved keys during sync conflict checking
- build: updated dependency on http package to `'>=0.13.5 <2.0.0'`
## 3.0.61
- fix: ensure key exchange functions properly when the sync service is not
  being used
- feat: Add AtRpc - A simple rpc request-response API which uses Atsign Protocol
  notifications under the hood.
## 3.0.60
- feat: Add `useRemoteAtServer` to PutRequestOptions. When set, the update
  request will be sent directly to the remote atServer
- feat: Introduce DeleteRequestOptions
  - Add new optional named parameter `deleteRequestOptions` to AtClient.delete
  - Add `useRemoteAtServer` to DeleteRequestOptions. When set, the delete
    request will be sent directly to the remote atServer
- fix: Incorrect commitId gets updated against commit entry when a sync-batch skips an entry
- fix: Sync/Monitor bug while running onboarding_cli with at_chops using pkam from secure element
## 3.0.59
- fix: Sync running into infinite loop when an invalid key is present in the entries to sync into client
- fix: Redundant logs generated for an internal key (lastReceivedNotification)
  while sending notifications
- chore: Reduced log_level of AtKey lower case enforcement message from INFO to FINER
- feat: Introduce clientId, appName, appVersion and platform to distinguish requests from several clients in server logs.
## 3.0.58
- chore: upgrade dependencies. at_commons to 3.0.43, at_utils to 3.0.12, at_lookup to 3.0.36 and at_chops to 1.0.3
## 3.0.57
- feat: Initial support of additional encryption metadata enabling encryption future-proofing
- fix: Expose priority, strategy, notifier, latestN and notificationExpiry in NotificationParams
- fix: Fixed issue where NotificationResponseTransformer would duplicate sharedWith and sharedBy
  when logging `AtKey`s
## 3.0.56
- fix: AtClient.put() throws null-check error when key's namespace is null
## 3.0.55
- fix: Amend Monitor's socket message handler so that it separates multiple 'simultaneous' responses correctly.
- fix: Sync to local fails to delete a cached key
- feat: Introduce CommitOp(CommitOperation) to the KeyInfo to describe key update or delete upon sync
- feat: consume changes in at_commons v3.0.35 that enforce lowercase on AtKey
- build: upgrade dependency at_persistence_secondary_server to v3.0.46
## 3.0.54
- fix: ensure forText notifications are decrypted successfully when using at_commons 3.0.35 or greater
## 3.0.53
- feat: Introduce commit log compaction to keep size of commit log thin
- fix: Fixed a bug where switch atSign event is notified multiple times
- fix: Add AtChops as optional argument to AtServiceFactory.atClient
## 3.0.52
- feat: Introduce AtServiceFactory to make AtClientManager more reusable and more testable
- feat: Make AtChops instance (if any) available everywhere that it can/should be used
## 3.0.51
- feat: Add atSign to AtSignLoggers' names when relevant, so that log messages are clearer
- feat: Made notificationService and syncService available via AtClient to enable cleaner simpler code elsewhere
- fix: Fixed clearing of sync progress listener while switching atsign.
- fix: Remove the inactive listeners from AtClientManager._changeListeners list.
- fix: Reverted back path,async packages to older version
## 3.0.50
- feat: Introduce commit log compaction to keep size of commit log thin
- feat: changes for at_chops uptake
- chore: upgrade at_persistence_spec, at_persistence_secondary_server, at_commons version
## 3.0.49
- fix: Enable AtKey.namespace overrides the namespace in AtClientPreference in AtClient delete method
- fix: Fixed a bug where initial notifications fails to decrypt - invalid pad block issue
## 3.0.48
- feat: Added `lib/src/client/request_options.dart` to provide access to the `RequestOptions` and `GetRequestOptions` classes.
## 3.0.47
- fix: Enable deletion of local keys
## 3.0.46
- fix: Ensure that we handle any and all exceptions related to sending heartbeat request
- feat: Made NotificationServiceImpl's retry delay into a public instance variable, so it can be set by application code
- feat: Changed NotificationServiceImpl's retry delay (from when monitorRetry() is called to when Monitor.start() is called) from 15 seconds to 5 seconds
- fix: Fixed a bug where client could 'miss' notifications while starting up
- fix: Ensure that exceptions related to sending heartbeat request are always caught correctly
- feat: Added experimental telemetry feature
## 3.0.45
- fix: Fix sync running into infinite loop when invalid keys does not sync into local storage
- fix: Upgrade persistence secondary to version 3.0.43 to fix empty batch request being sent to cloud secondary
## 3.0.44
- feat: Introduce fetch method to NotificationService to fetch the notification using id.
- fix: Replace latestNotificationId with local key to store/fetch last received notification
## 3.0.43
- chore: upgrade persistence secondary to version 3.0.42 and persistence spec to 2.0.9
## 3.0.42
- fix: Improved performance of getKeys (and getAtKeys) when sharedBy is specified, by using the existing 
RemoteSecondary connection rather than creating a new one
- fix: Do not try to decrypt empty or null serverEncryptedValue when generating SyncConflict info
- fix: put try-catch around most of the `SyncServiceImpl._checkConflict` method so sync is not impeded if
_checkConflict encounters an exception
- fix: fix null pointer exception in monitorResponse due to delayed server response
- fix: Skip reserved keys from decryption in the notification callback
- fix: Update at_commons to 3.0.29 which fixes AtKey sharedWith attribute has incorrect value for public keys
## 3.0.41
- chore: upgrade persistence secondary to version 3.0.38 which reverts sync of signing keys and statsNotificationKey
## 3.0.40
- chore: upgrade at_commons to 3.0.26
- fix: check isEncrypted flag in sync conflict
- docs: Fixed broken links
## 3.0.39
- chore: upgrade 3rd party dependencies except hive
- chore: upgrade persistence secondary to version 3.0.36
## 3.0.38
- fix: Add client sending config changes to server
- fix: NotificationService.subscribe to return existing listener on same regex
## 3.0.37
- fix: Revert sending client config changes to server
## 3.0.36
- fix: Add metadata validation to put request on client SDK  
- fix: Added unit tests for sync failure
- fix: Export SyncProgressListener to track the SyncProgress. 
- fix: setCurrentAtsign() throws an exception when an invalid atsign is passed.
- feat: Encode new line characters in public-key value
- feat: Send clientConfig to the cloud secondary 
## 3.0.35
* fix: Reverted dependency on 'meta' package to ^1.7.0 as flutter_test package requires 1.7.0 
## 3.0.34
* fix: Ensure _syncFromServer rethrows caught exceptions once it's handled the exception chaining
* feat: Add enforceNamespace (default value true) to AtClientPreference
## 3.0.33
- feat: Upgrade lints version to 2.0.0 
## 3.0.32
- fix: while syncing keys from server to local if there is an issue syncing a key, continue syncing rest of the keys
- fix: do not sync statsNotificationID from client to server
- feat: KeyStreams
- fix: do not create new instance of CacheableSecondaryAddressFinder in at lookup 
- [optional] Users can set SecureSocket's securityContext and store current session TLS keys through AtClientPreferences
## 3.0.31
- Enhance notify text to send text message encrypted
- Upgrade at_persistence_secondary_server to v3.0.30
- Upgrade at_commons version to v3.0.20 for encrypt notify text message
- Upgrade at_lookup version to v3.0.28 for adding mutex to authenticate methods
- feat: Add to NotificationService.notify() signature:
    * added new optional callback parameter, onSentToSecondary
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * and updated code documentation for NotificationService.notify() method
## 3.0.30
- Added bypassCache option in get method
- Added sync conflict info to sync progress callback
- Added security policy
- Fix for skipping reserved keys while checking for sync conflict
- Upgrade at_lookup to v3.0.27 for outbound message listener timeout enhancement  
## 3.0.29
- Added additional attributes in SyncProgress for improved sync observability
## 3.0.28
- Upgrading dependency at_persistence_secondary_server to version 3.0.29 to sync public hidden keys
- Upgrade at_commons to 3.0.18 to enable scan to display hidden keys when showHiddenKeys set to true
## 3.0.27
- Upgraded dependency at_persistence_secondary_server to version 3.0.28
## 3.0.26
- Uptake AtException hierarchy
- Introduce exception chaining
- Fix for Server stuck on old value even though syncing is happening. at_server Issue #721
- Export notification_service.dart file
## 3.0.25
- Fix for regex issue in notification service. Issue #523
- Fix for namespace issue in notify method.Issue #527
- Fix for handling empty sync responses from server. App issue #624
## 3.0.24
- Update the @platform logo
- Default the AtKey.sharedBy to currentAtSign
## 3.0.23
- Fix for at_client issue #508 - getLastNotificationTime bug while trying to decrypt old data
## 3.0.22
- Fix for getKeys in local secondary not returning keys
## 3.0.21
- Cache secondary url returned by root server
## 3.0.20
- Remove print statements
## 3.0.19
- Update at_commons,at_persistence and at_lookup version to remove print statements
## 3.0.18
- Generate Notification id in SDK
## 3.0.17
- Fix self encryption key not found
- Fix for _getLastNotificationTime method returning null
- Added heartbeats to Notifications Monitor to detect and recover from
  dead socket. Heartbeat interval is customizable via AtClientPreference
- Fix for os write permission issue: give app option to pass the path where
  the encrypted file will be saved on disk
## 3.0.16
- Decrypt notification value in SDK
- Support for shared key and public key checksum in notify
- Deprecated methods related to filebin
## 3.0.15
- Fix public key checksum in metadata does not sync to local.
## 3.0.14
- Support for shared key and public key checksum in metadata
- Chunk based encryption/decryption for files up to 1GB
- Change in pubspec to fetch the exact version of atsign packages
## 3.0.13
- Sync deleted cached keys to cloud secondary
- at_lookup version upgrade for increase in outbound connection timeout
## 3.0.12
- Fix automatic sync not working
## 3.0.11
- at_lookup version upgrade for outbound listener bug fix
- added functional test to verify outbound listener bug fix
## 3.0.10
- Uptake at_persistence_secondary_server changes
- Uptake at_lookup changes for AtTimeoutException
- Handle error responses from server
- Refactor put method to use request and response transformers
- Provide callback for sync progress
## 3.0.9
- Uptake at_persistence_secondary_server changes
- Refactor decryption service
- Introduce request response transformers
- Refactor get method to use request response transformers
## 3.0.8
- Updated readme and documentation improvements
## 3.0.7
- Uptake at_persistence_secondary_server changes
- Resolve dart analyzer issues
- Run dart formatter
## 3.0.6
- Uptake AtKey validations
## 3.0.5
- Uptake at_persistence_secondary_server changes
## 3.0.4
- Uptake Hive Lazy Box changes
## 3.0.3
- Sync pagination limit in preference
## 3.0.2
- Expose isSyncInProgress in SyncService
## 3.0.1
- Reduce wait time on monitor connection
- at_lookup version upgrade
## 3.0.0
- Resilient SDK changes and bug fixes
## 2.0.4
- Improve notification service
- Improve monitor
- sync on a dedicated connection
## 2.0.3
- at_commons version upgrade
## 2.0.2
- filebin upload changes
## 2.0.1
- at_commons version upgrade
## 2.0.0
- Null safety upgrade
## 1.0.1+10
- Provision to request for a new outbound connection.
- Minor bug in stream handlers
## 1.0.1+9
- Third party package dependency upgrade
- gitflow changes
- Auto restart monitor connection
- Stream encryption
- Bug fixes
## 1.0.1+8
- Delete cached keys
- Encrypt Stream data
## 1.0.1+7
- Self keys migration issue fix
## 1.0.1+6
- Notification sub system introduced
## 1.0.1+5
- Added automatic refresh of monitor connection
## 1.0.1+4
- Provided multiple atsign support in at client SDK. Introduced batch verb to improve sync performance
## 1.0.1+3
- onboarding changes for server activation and deactivation Backup keys implementation sync improvements
## 1.0.1+2
- sync improvements and at_utils, at_commons, at_lookup version changes
## 1.0.1+1
- Minor changes in at_persistence_spec and at_persistence_secondary_server
## 1.0.1
- pubspec dependencies version changes
## 1.0.0
- Initial version, created by Stagehand
