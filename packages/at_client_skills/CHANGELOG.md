# Changelog — at_client_skills

## 1.4.0

- Teach at_client 4.0 — one platform package per app (`at_client_cli` or
  `at_client_flutter`), and the storage, transport and atDirectory finder every
  client is opened with.
- List what at_client 4.0 removed, with what replaces each — the `notify*` and
  `startMonitor` methods, `send(namespace:)`, `NotificationParams.forText`, the
  `AtClientManager` service getters, `sync(onDone:)` / `onError:`, `setOnDone`,
  `AtServiceFactory.atClient`, `Query.fetch()` and the unused
  `AtClientPreference` fields.
- Point `hiveStoragePath` users to a storage object; `commitLogPath` is gone.
- A new app names `PqPosture.pqActive`, as every snippet now does, and an app
  built on 3.x moves to it through `pqReady` in two releases, with a table of
  what each posture writes, reads and needs.
- A client never runs below its posture floor, set by its keyfile's keys.
- Under `pqActive`, a collection's namespace ends with `.` and
  `preference.namespace`, or its first write throws
  `NamespaceKeyUnavailableException`.
- Under `pqActive`, a write right after the client opens waits up to 30
  seconds for start-up to publish the namespace key.
- Offline under `pqActive`, a device's first write in a namespace, and a share
  with no current copy of the recipient's key, need the atServer; later writes
  go on offline, across restarts.
- A program serving a mixed fleet writes post-quantum with
  `pqActive.copyWith(disallowLegacyEncryption: false)` and
  `allowLegacyCryptoFallback`, requiring each peer's namespace.
- A share goes to the most specific namespace key the recipient advertises;
  `sealToNamespace` requires one namespace, and `canSealTo` asks first. A
  `pqReady` program sends with `sealToNamespace` alone.
- Follow at_client_flutter 2.0 in the auth flows — dialogs hand back the
  `AtClient`, the app owns it, and nothing imports `at_auth`.
- A Flutter app with its own UI calls the verbs through `AtsignFlows`, and a
  pending enrollment's client takes its store from `storageOrDefault`.
- Storage backends come from their own imports, `package:at_client/hive.dart`
  and `package:at_client/memory.dart`; a Flutter app passing no storage gets
  Hive in the app's support directory.
- Keys live in a store that outlives the process.
- Document the AtClient lifecycle — the `Atsign` verbs, the platform bundle a
  client is built from, connection state, and `AtClientManager.use`.
- A `refused` connection lists `enrollmentDenied` among its causes.
- An `AtLookUpFactory` takes no `clientConfig`, and builds no file-stream
  connection, since atServers no longer support the stream verb.
- A CLI program takes its `lookUps:` from at_client_cli's
  `lookUpsFor(rootDomain)`, which routes through a proxy when the root domain
  names one. `createAtClient` is at_client_cli's, unchanged.
- Document stopping a client — what `stop()` ends, that it does not drain, and
  the re-push a stop can leave behind.
- Keys a denial, a cancel or an expiry left with no credential are refused by
  `open` with `AtNoCredentialException`.
- A second process on a Hive store another holds is refused with
  `AtStorageInUseException`.
- Document headless enrolment — where the passcode comes from, who may approve,
  and least-privilege namespaces.
- Show what a pending enrolment carries beyond its id — the app, the device and
  the access being requested — so an approval screen can say what it is
  approving. An agent approves only the enrollment it expects and denies the
  rest.
- A screen that only closes calls `pending.stop()`, which keeps the request for
  `resumeEnrollment`; `cancel()` abandons it, throws
  `AtEnrollmentCancelledException` from the wait, and removes the pending keys.
- Once `pending.stop()` or `cancel()` returns, an app whose approval landed
  first opens the atSign at once.
- `resumeEnrollment` refusing several matching requests is in the error table,
  with what picks one.
- A `CLIBase` program whose keyfile holds only an enrollment request waits for
  its approval rather than throwing.
- A new agent's atSign is onboarded with `--posture pqActive`, and instances
  sharing a keyfile retrofit it one at a time.
- A registrar API key is the app's own, created via the registrar at
  my.atsign.com; the CLI tools send `AT_REGISTRAR_API_KEY` when it is set.
- Say that a root domain is a type, not a string, and how to build one without
  going through a selection dialog.
- Use `send(idAndNamespace:)` and say what the value is — an id and a namespace
  joined by a dot, split at the first one. `subscribe` hands back values still
  encrypted unless `shouldDecrypt` is true.
- Document notification delivery confirmation — `getStatus` / `fetch`, the
  two-value status enum, and the expiration window.
- Document at-least-once notification delivery — replay on a stop, and
  handlers that must tolerate running twice.
- A notification a subscription drops, one it cannot decrypt included, is
  logged at warning and emitted on `droppedEvents`. A subscriber keeps only the
  sender it trusts.
- Document waiting for sync to settle — `waitUntilCaughtUp`, its snapshot
  semantics, and the mandatory `timeout`.
- Document a stopped sync service — `SyncProgress.stopped`, and
  `waitUntilCaughtUp` ending with `StoppedException` too.
- Sync's fallback is a 30-second timer, and `sync()` calls made while a round
  runs share one more round once it ends.
- Document the `CItem<T>` fields — which are mutable, that the payload cannot
  be reassigned, and that the shared-with set is never null.
- Say that sharing does not cascade the way deleting does, so adding a
  collaborator leaves existing children invisible to them.
- A collection write whose own copy fails writes no recipient's copy; a
  `create` whose share fails after its own copy is retried with
  `updateSharedWith`, catching `CollectionOpException<T>`.
- An item a collection cannot read yet is a `CItemReadException`, which
  `.handleError` can test for.
- Document public keys — `AtKey.public`, signed-not-encrypted values, and the
  always-remote `plookup` read path.
- Document error handling — the exception families, `getTraceMessage()` over
  `toString()`, and `CollectionOpException` partial failures.
- Document `StoppedException` — why it is not an `AtException`, and catch
  order.
- Document `AtRpcCallbacks` — the route for a peer that both answers and makes
  requests, and that `sendRequest` widens the allow list.
- Warn that an RPC `call()` has no timeout of its own and waits forever on a
  peer that never answers, and bound every call in the samples.
- Multiple instances of one agent take their lock with `tryAcquireServerMutex`.
- Note that NoPorts carries its own access control, with a pointer to
  `noports_core` rather than a description of its internals.
- The canonical todos examples, CLI and Flutter, run at `PqPosture.pqActive`.
- Fix the install instructions: a fresh project needs `skills get --ide`,
  since auto-detection only finds an agent directory that already exists.
- Bring the skill within the Agent Skills spec — the `description` was over the
  1024-character limit, and sync setup moves out of Flutter Auth to where it
  applies to any client.
- Extend the evals to cover the new material.

## 1.3.0

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

## 1.2.0

- Document sync scoping (`syncRegex`) and the sync lifecycle
  (new `references/11-sync.md`).
- Document the rule to hold `watch()` streams in `State`, never in `build()`,
  and fix the `StreamBuilder` snippets.
- Document the owner-writes-only collaboration/ownership model.
- Document the atSign activation / atDirectory prerequisite.

## 1.1.0

- Add `user-invocable: true` so the skill registers as a slash command.
- Document the required macOS entitlements in `references/05-flutter-auth.md`:
  `network.client` (connect to the atServer) and
  `files.user-selected.read-only` (the `.atKeys` file picker).
- Fix the test-hooks import: the helpers come from `at_client.dart`, not the
  `src/collections/...` `part of` file (`SKILL.md`, `references/09`).
- Add an eval covering the macOS entitlement fix.

## 1.0.0

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
