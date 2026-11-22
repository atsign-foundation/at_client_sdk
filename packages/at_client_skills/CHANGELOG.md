# Changelog — at_client_skills

## 1.4.0 — 2026-09-13

- `Atsign.enroll` now throws `AtKeysUnusableException`, as `open` does, for
  keys it cannot read or that record another Atsign, and refuses a keyfile it
  cannot create, before anything is sent; a request it sent but could not
  file throws `AtEnrollmentException` naming it (`references/15`).
- An approval whose keys cannot be collected throws whatever collecting them
  threw, mostly not an `AtEnrollmentException`, so a final `catch` waits
  again rather than cancelling (`references/15`).
- A denial or expiry whose pending keys the AtKeys store cannot remove still
  throws the decision, its message saying the keys stay (`SKILL.md`;
  `references/14`, `15`).
- `at_activate cancel` gives up the pending request a keyfile holds, and a
  `CLIBase` program waiting on one names it (`SKILL.md`; `references/14`,
  `15`).
- Keys `open` cannot use throw `AtKeysUnusableException` before it connects,
  `AtNoCredentialException` and `AtEnrollmentPendingException` among them
  (`SKILL.md`; `references/05`, `15`).
- `enroll` refuses an AtKeys store that already holds live keys or a pending
  request (`references/15`).
- `resumeEnrollment` throws `AtKeysUnusableException`, as `open` does, for
  keys it cannot read or that record another Atsign (`references/15`).
- `PkamDialog` waits on a pending request in a store it can write and offers
  Cancel, and says what it shows for keys it cannot use (`references/05`).
- The package map says the browser platform package, `at_client_web`, is
  still being built and is not published (`references/06`).
- An `AtCollection` item id is folded to lower case, and one holding `.`, `:`,
  `@`, whitespace or a control character is refused; a new item's id is 1 to
  64 characters of `a-z`, `0-9`, `-` and `_`, starting with a letter or digit;
  `upsert` applies that rule only when neither local storage nor the atServer
  holds an item with the id (a `remoteOnly` client asks the atServer alone),
  judges that from the item's metadata without decrypting it, and keeps the
  refusal when its atServer lookup fails for any reason but the item's absence
  or the client being stopped; a `subName` is folded too and must hold only
  characters a key's name can hold; no event or listed item carries a refused
  id, and event ids arrive folded (`SKILL.md`; `references/02`, `07`).
- `getMeta` reads a key's metadata without decrypting its value, and takes
  `getRequestOptions` as `get` does (`references/12`).
- On a `remoteOnly` client, request options that leave `useRemoteAtServer`
  unset follow the preference; only an explicit value overrides it, and a
  `local:` key never leaves the device (`references/12`).
- A `CLIBase` program whose keyfile holds only an enrollment request waits
  for its approval rather than throwing (`SKILL.md`; `references/14`).
- A screen that only closes calls `pending.stop()`, which keeps the request
  for `resumeEnrollment`; `cancel()` is for a Cancel the user confirms
  (`references/15`).
- Once `pending.stop()` or `cancel()` returns, an app whose approval landed
  first opens the atSign at once (`references/15`).
- `sync()` calls made while a round runs share one more round once it ends
  (`references/15`).
- A cancelled wait throws once the pending keys are gone, and so does a wait
  whose request another wait cancelled before its approval was filed
  (`references/15`).
- `resumeEnrollment` is called without an app or device, which are
  deprecated and ignored: it resumes the one pending enrollment an AtKeys
  store holds (`SKILL.md`; `references/15`).
- A collection write whose own copy fails writes no recipient's copy
  (`references/02`).
- A write waits up to 30 seconds in all for start-up to ask for its namespace
  key's private and for the answer (`SKILL.md`).
- A client never runs below its posture floor, set by its keyfile's keys
  (`SKILL.md`).
- Sync's fallback is a 30-second timer; `AtClientPreference.syncIntervalMins`,
  which set nothing, is listed as removed in 4.0 (`SKILL.md`; `references/11`,
  `15`).
- A notification a subscription drops, one it cannot decrypt included, is
  logged at warning and emitted on `droppedEvents` (`SKILL.md` §13).
- A `create` whose share fails after its own copy is retried with
  `updateSharedWith(e.item!, ...)`, catching `CollectionOpException<T>`
  (`references/02`).
- Keys a denial, a cancel or an expiry left with no credential are refused
  by `open` with `AtNoCredentialException` (`SKILL.md`; `references/15`).
- A second process on a Hive store another holds is refused with
  `AtStorageInUseException` (`references/14`, `15`).
- An item a collection cannot read yet is a `CItemReadException`, which
  `.handleError` can test for (`references/02`, `references/07`).
- A program serving a mixed fleet writes post-quantum with
  `PqPosture.pqActive.copyWith(disallowLegacyEncryption: false)` and
  `allowLegacyCryptoFallback`, requiring each peer's namespace (`SKILL.md`
  §11).
- A share goes to the most specific namespace key the recipient advertises;
  `sealToNamespace` requires one namespace, and `canSealTo` asks first
  (`SKILL.md`).
- A `pqReady` program sends with `sealToNamespace` alone, which selects the
  namespace-key provider (`SKILL.md`).
- A new app names `PqPosture.pqActive`, as every snippet now does, and an
  app built on 3.x moves to it through `pqReady` in two releases; a table
  says what each posture writes, reads and needs (`SKILL.md` §11; the
  references).
- Offline under `pqActive`: a device's first write in a namespace, and a
  share with no current copy of the recipient's key, need the atServer;
  later writes go on offline, across restarts (`SKILL.md` §11;
  `references/05`).
- Under `pqActive`, a write right after the client opens waits up to 30
  seconds for its start-up to publish the namespace key (`SKILL.md` §11).
- A registrar API key is the app's own, created via the registrar at
  my.atsign.com (`references/05`); `at_register`, and `at_activate onboard`
  without `-c`, send `AT_REGISTRAR_API_KEY` when it is set, and otherwise a
  built-in key (`references/06`).
- A new agent's atSign is onboarded with `--posture pqActive`, and instances
  sharing a keyfile retrofit it one at a time (`references/14`).
- A notification is sent with `idAndNamespace:`, and `subscribe` hands back
  values still encrypted unless `shouldDecrypt` is true (`SKILL.md` §13;
  `references/10`, `15`).
- Keys live in a store that outlives the process (`SKILL.md` §11).
- `AtClient.notify`, `notifyChange`, `notifyAll` and `startMonitor`,
  `NotificationParams.forText` and `send(namespace:)` are listed as removed in
  4.0, with what replaces each (`SKILL.md` §18; `references/01`).
- `AtClientManager`'s `syncService` and `notificationService`,
  `sync(onDone:)`, `sync(onError:)`, `setOnDone`, `AtServiceFactory.atClient`
  and `syncStrategy` are listed as removed in 4.0 (`SKILL.md` §18;
  `references/01`, `11`, `15`).
- `AtClientPreference`'s `isLocalStoreRequired`, `privateKey`, `useAtChops`,
  `signingAlgoType` and `hashingAlgoType`, `RemoteSecondary`'s
  `signingAlgoType` and `PutRequestOptions.storeSharedKeyEncryptedMetadata`
  are listed as removed in 4.0 (`SKILL.md` §18; `references/01`).
- Teaches at_client 4.0: one platform package per app (`at_client_cli` or
  `at_client_flutter`), the storage, transport and atDirectory finder every
  client is opened with, and what 4.0 removed, named as removed.
- A CLI program takes its `lookUps:` from at_client_cli's
  `lookUpsFor(rootDomain)`, which routes through a proxy when the root domain
  names one (`SKILL.md`; `references/06`, `14`, `15`).
- `Query.fetch()` is listed as removed in 4.0 (`references/03`).
- `createAtClient` is at_client_cli's, unchanged, not a removed API
  (`SKILL.md`; `references/01`, `06`).
- A Flutter app with its own UI calls the verbs through at_client_flutter's
  `AtsignFlows`, and a pending enrollment's client takes its store from
  `storageOrDefault` (`SKILL.md`; `references/01`).
- A `refused` connection lists `enrollmentDenied` among its causes.
- The canonical todos examples, CLI and Flutter, run at `PqPosture.pqActive`
  (`SKILL.md` §19).
- `pending.cancel()` abandons an enrollment: it ends the wait, which throws
  `AtEnrollmentCancelledException`, and removes the pending keys
  (`references/15`).
- An `AtLookUpFactory` takes no `clientConfig`: a factory of your own drops
  that parameter (`references/15`).
- Multiple instances of one agent take their lock with
  `tryAcquireServerMutex`.
- Storage: each backend comes from its own import, `HiveAtClientStorage` from
  `package:at_client/hive.dart` and `InMemoryAtClientStorage` from
  `package:at_client/memory.dart`, and a Flutter app passing no storage gets
  at_client_flutter's default, Hive in the app's support directory
  (`SKILL.md`; `references/01`, `05`, `14`, `15`).
- Stopping a client: `stop()` ends the client's timers and waits and closes
  every connection, work it cuts short fails with `StoppedException`, and a
  push the atServer accepted just before the stop is pushed again by the next
  client (`references/15-client-lifecycle.md` §7; `SKILL.md`).
- The auth flows follow at_client_flutter 2.0: every dialog hands back the
  `AtClient` it opened, the app owns it, and nothing imports `at_auth`.
  `AtAuthRequest`, `AuthResponse`, `_setupAtClient` and
  `AtClientManager.setCurrentAtSign` are gone from the skill (rewritten
  `references/05-flutter-auth.md`; `SKILL.md` §10).
- New: AtClient lifecycle — the `Atsign` verbs (`open`, `activate`, `enroll`,
  `resumeEnrollment`), the platform bundle a client is built from (`keys:`,
  `storage:` and `lookUps:`, the `AtLookUpFactory` that builds every
  connection the client opens), the connection state (`client.connection`:
  online / offline / refused, the causes, `awaitOnline`), the sync and
  notification services' start and stop, `AtClientManager.use`, and what
  `stop()` does and does not do (new `references/15-client-lifecycle.md`;
  `SKILL.md` §11; later sections renumbered).
- The package map, the headless-agent and sync references and the
  deprecation guide drop `at_auth` and `setCurrentAtSign`, and point from
  `hiveStoragePath` to a storage object.
- Evals: the two auth evals follow the new flows; two new evals cover
  logout / switching and the connection state.
- The connections an `AtLookUpFactory` builds no longer include a file
  stream's: atServers no longer support the stream verb (`references/15`).
- Under `pqActive`, a collection's namespace ends with `.` and
  `preference.namespace`, or its first write throws
  `NamespaceKeyUnavailableException` (`SKILL.md` §3, §11).
- An agent approves only the enrollment it expects and denies the rest, a
  subscriber keeps only the sender it trusts, and the receive sample matches
  what the send sample sends (`SKILL.md` §13; `references/05`, `10`, `14`).
- A connect attempt the atServer answers with a server error such as
  AT0011, or with no challenge, reads as offline (`unreachable`), not
  refused, and `CLIBase` reports it as an outage when it opens (`SKILL.md`;
  `references/01`, `05`, `14`, `15`).
- A denied enrollment request throws `AtEnrollmentDeniedException` and an
  expired one `AtEnrollmentExpiredException` (both at_client 4.1.0), and one
  the atServer keeps answering without a decision, or one approved whose
  keys cannot be collected, stays pending for `resumeEnrollment` (`SKILL.md`;
  `references/14`, `15`).
- An `error:` reply to a connection's `from:`, `pkam:` or `cram:` is an
  `AtAuthErrorReplyException` (at_client 4.1.0) carrying the reply's code as
  `errorCode`, and a refusal code gives the refused cause (`SKILL.md`;
  `references/15`).

## 1.3.0 — 2026-07-31

- Document RPC between atsigns — `AtRpc` / `AtRpcClient` request/response
  (new `references/13-rpc.md`).
- Document headless agents and multi-instance coordination — `CLIBase` auth,
  per-process storage paths, the immutable-mutex pattern, and stateless
  scaling with `ServiceFactoryWithNoOpSyncService`
  (new `references/14-multi-agent.md`).
- Document remote vs local atServer operations — client-wide
  `remoteLocalPref`, per-operation `useRemoteAtServer`, and `bypassCache`
  (new `references/12-remote-atserver.md`).
- Document the rule to never pin `at_client` / `at_client_flutter` versions —
  install with `dart pub add` instead.
- Clarify the macOS `network.server` entitlement is only needed when the app
  opens a listening socket (e.g. NoPorts tunnels).
- Add `noports_core` and `at_stream` (pre-release) to the package map.
- Document that `at_onboarding_flutter` is discontinued — use `at_client_flutter`.
- Add evals covering the new content, and tighten the owner-writes-only and
  activation evals.
- Document the `skills` CLI prerequisite and the full install steps in the
  README.

## 1.2.0 — 2026-07-07

- Document sync scoping (`syncRegex`) and the sync lifecycle
  (new `references/11-sync.md`).
- Document the rule to hold `watch()` streams in `State`, never in `build()`,
  and fix the `StreamBuilder` snippets.
- Document the owner-writes-only collaboration/ownership model.
- Document the atSign activation / atDirectory prerequisite.

## 1.1.0 — 2026-06-23

- Add `user-invocable: true` so the skill registers as a slash command.
- Document the required macOS entitlements in `references/05-flutter-auth.md`:
  `network.client` (connect to the atServer) and
  `files.user-selected.read-only` (the `.atKeys` file picker).
- Fix the test-hooks import: the helpers come from `at_client.dart`, not the
  `src/collections/...` `part of` file (`SKILL.md`, `references/09`).
- Add an eval covering the macOS entitlement fix.

## 1.0.0 — 2026-06-08

Initial release.

- `AtCollection<T>` — full CRUD, `CItem<T>`, `Query<T>`, sub-collections,
  read receipts, event streams
- `wherePath` / `PathField<T>` typed predicates
- `watchWithTree` / `watchWithSub` for deep multi-level hierarchies
- `at_client_flutter` auth — all 4 dialog flows (CRAM, atKeys file,
  device keychain, APKAM)
- `AtClientManager` post-auth setup
- Package selection guide (`at_client`, `at_client_flutter`, `at_auth`,
  `at_chops`, `at_cli_commons`)
- Domain-object patterns (`toJson`/`fromJson`, `registerFactory`, `typeTag`)
- Unit testing without a live atServer (`collections_test_hooks.dart`)
- Architecture decision guide: `AtCollection<T>` vs Notifications + SQLite
- 10 common pitfalls with fixes
- Deprecation guide: `AtCollectionModel`, `at_common_flutter`,
  `at_backupkey_flutter`
