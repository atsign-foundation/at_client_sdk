// Typed, shareable, reactive collections layered on AtClient.
// Entry point: [AtCollection]. See its class-level doc comment for
// the feature tour (CRUD, sub-collections, read receipts, events).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// at_commons re-exports a `StringBuffer` class that would otherwise shadow
// `dart:core`'s. Hide it so this file (and any consumer of the collections
// API) can use `StringBuffer` with its standard Dart semantics.
import 'package:at_client/at_client.dart' hide StringBuffer;
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData, AtMetaData;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';

part 'collections_test_hooks.dart';

// -----------------------------------------------------------------------------
// AtCollection<T>

/// A typed collection of [CItem<T>] records scoped to a
/// fully-qualified namespace (e.g. `'todos.my_app'`). Entry point
/// for all CRUD, sub-collection, event-stream, and read-receipt
/// operations on that namespace.
///
/// **Status:** stable. The API surface is committed to non-breaking
/// minor changes — `interface class` modifier, `final` event
/// subclasses, named-class return types, and pre-allocated enum
/// slack are in place so additive evolution stays compatible.
/// Behavioural improvements continue to land in minor releases.
///
/// **Obtain one via [AtClient.collection]**, never directly:
///
/// ```dart
/// final todos = await atClient.collection<Todo>(
///   'todos.my_app',
///   const Duration(days: 7),
///   fromJson: Todo.fromJson,
///   cleanupOrphansOnCreation: true,  // optional startup sweep
/// );
/// ```
///
/// `AtClient.collection` caches one instance per namespace, so
/// subsequent calls with the same namespace return the same object.
///
/// ---
///
/// ## Three primary features
///
/// ### 1. CRUD on typed records
///
/// A [CItem<T>] is a single typed record owned by one atSign and
/// optionally shared (distributed) to others. [create] / [update] /
/// [delete] / [get] / [getItems] are the verbs.
///
/// ```dart
/// final item = await todos.create(
///   obj: Todo('write readme'),
///   sharedWith: {'@bob'.toAtsign()},
/// );
///
/// item.obj.done = true;
/// await todos.update(item);
///
/// for (final t in await todos.getItems()) {
///   print('${t.owner}: ${t.obj.title}');
/// }
///
/// await todos.delete(item);
/// ```
///
/// ### 1a. Composable queries
///
/// [query] returns a [Query<T>] you can chain and terminate with
/// either [Query.get] (one-shot `Future<List<CItem<T>>>`) or
/// [Query.watch] (live reactive `Stream<List<CItem<T>>>`). Queries
/// are immutable values — build once, pass around, reuse. Execution
/// is always on-device against the local synced store.
///
/// ```dart
/// final overdue = todos.query()
///     .where((t) => !t.obj.done)
///     .where((t) => t.obj.due.isBefore(DateTime.now()))
///     .orderBy((t) => t.obj.due)
///     .limit(20);
///
/// final list = await overdue.get();
/// final live = overdue.watch();  // re-emits on update/delete
/// ```
///
/// For ad-hoc stream pipelines outside the builder's vocabulary, the
/// raw `getItemsAsStream().where(...).toList()` path still works —
/// [Query] is the ergonomic complement, not a replacement.
///
/// ### 2. Sub-collections to arbitrary depth
///
/// A [CItem] can be a parent of its own [AtCollection<U>]; that
/// sub-collection's items can themselves be parents; and so on.
/// Nesting is bounded only by the Atsign Protocol's 255-char key
/// limit. The absolute worst-case wire shape is the cached-copy
/// form `cached:<other-atsign>:<itemId>.<composedNs>@<self-atsign>`
/// where each atSign can be up to 55 chars. That fixes the wrapper
/// overhead at `cached:` (7) + `<other>` (55) + `:` (1) + `@<self>`
/// (55) = **118 chars**, leaving **137 chars** for everything
/// inside (item id + every level of composed namespace).
///
/// In practice that's plenty. With a 15-char application namespace
/// and a strategy of single-character collection / sub-collection
/// names, each tree level costs 11 chars (`.<sub>.<parent.id>`),
/// so the theoretical depth ceiling is **11 levels (root + 10
/// nested sub-collections)** — far deeper than any realistic
/// hierarchical model needs. Each [subCollection] call enforces
/// the budget and throws [ArgumentError] before any I/O if the
/// composed namespace would overflow.
///
/// ```dart
/// // Level 1: comments on a post.
/// final comments = posts.subCollection<Comment>(
///   parent: post,
///   subName: 'comments',
///   defaultExpiration: const Duration(days: 30),
///   fromJson: Comment.fromJson,
/// );
/// final comment = await comments.create(
///   obj: Comment('nice one'),
///   sharedWith: post.sharedWith,
/// );
///
/// // Level 2: replies on that comment.
/// final replies = comments.subCollection<Reply>(
///   parent: comment,
///   subName: 'replies',
///   defaultExpiration: const Duration(days: 30),
///   fromJson: Reply.fromJson,
/// );
/// await replies.create(obj: Reply('thanks'), sharedWith: {post.owner});
///
/// // Cascade a parent delete down the tree.
/// await posts.delete(post, cascade: true);
/// ```
///
/// ### 3. Built-in read-receipt framework
///
/// Every item has an implicit reserved `__rr` sub-collection
/// holding receipts written by readers. Receipts populate
/// [CItem.readBy] lazily and stay current via an event subscription
/// — no bookkeeping at the app layer.
///
/// ```dart
/// // Reader side: mark an incoming item as read. Idempotent.
/// await incomingItem.markReadByMe();
///
/// // Owner side: who has read my item?
/// final readers = await myItem.readBy;   // Future<Set<Atsign>>
/// print('Read by: $readers');
///
/// // Sync UI render after an async prime:
/// await myItem.readBy;                   // prime cache
/// render(myItem.readBySnapshot);         // sync read of same cache
///
/// // React to receipts in real time:
/// todos.readReceipts.listen((e) {
///   print('${e.from} read item ${e.id} at ${e.readAt}');
/// });
/// ```
///
/// ---
///
/// ## Event streams
///
/// See [CEvent] and its subclasses for wire shapes.
///
/// ```dart
/// collection.watch()          // Stream<CEvent> — everything below
/// collection.updates          // Stream<CItemUpdated>
/// collection.deletes          // Stream<CItemDeleted>
/// collection.readReceipts     // Stream<CReadReceipt>
/// collection.subUpdates       // Stream<CSubItemUpdated>  — descendants
/// collection.subDeletes       // Stream<CSubItemDeleted>  — descendants
/// ```
///
/// ### Event surfaces — getter vs method
///
/// Event surfaces that take no parameters are exposed as
/// **parameterless getters** ([updates], [deletes], [readReceipts],
/// [subUpdates], [subDeletes], [availableEvents]). Surfaces that
/// take parameters are **methods** ([watch], [expiringSoonEvents]).
///
/// [availableEvents] lazy-starts a single per-collection scheduler
/// the first time it's read; [expiringSoonEvents(leadTime:)] takes
/// per-call parameters so it stays a method and starts an
/// independent scheduler per call.
///
/// ---
///
/// Per-key decode failures on the read path are yielded into the
/// stream as errors — not logged and swallowed. Every higher-level
/// read method is a thin wrapper over [getItemsAsStream], so
/// `await collection.getItems()` will throw on the first bad key;
/// `await for` without an `onError` handler will throw on the first
/// bad key. Apps that want the old silent-skip posture should chain
/// `.handleError(...)` before consuming the stream.
interface class AtCollection<T> {
  static const String _rr = '__rr';

  // Random-id alphabet and RNG (for auto-generated item ids).
  static const String _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _rng = Random.secure();

  // Factory registry (process-global, NOT per-collection):
  //   - _factoriesByType: lookup by [Type] when drafting (obfuscation-safe)
  //   - _factoriesByTag:  lookup by wire-format type-tag when rehydrating
  //
  // A single global registry simplifies apps that use the same domain
  // type across multiple collection instances (tests, polymorphic
  // parent/child, cross-namespace). Re-registering the same
  // `(Type, typeTag)` pair is idempotent — the factory body is
  // replaced, last write wins. Re-registering a Type under a
  // *different* tag, or a tag against a *different* Type, throws
  // [StateError] — the wire-format tag is part of the cross-atSign
  // contract and must not silently change underneath callers.
  static final Map<Type, _FactoryEntry> _factoriesByType = {};
  static final Map<String, Function> _factoriesByTag = {};

  // Tags we've already warned about during rehydrate. Per-tag, not
  // per-collection or per-message — one SHOUT per unrecognised tag
  // is enough to alert the developer; further occurrences are
  // expected duplicates from the same registry drift.
  static final Set<String> _warnedMissingFactoryTags = {};

  // Per-item cache of read-receipt sub-collections. Keyed by
  // (owner.toString(), id) so it survives CItem rehydrate cycles.
  final Map<String, AtCollection<Map<String, dynamic>>> _rrCache = {};

  // Item ids whose self-key this process has successfully written
  // (and not subsequently deleted). Lets [_selfKeyExists] short-
  // circuit without a round-trip when the caller's about to update
  // an item we just persisted — the common bulk-edit path. Cleared
  // on successful self-delete; left alone on failures so a retry
  // path still probes. Cross-process visibility: self-keys are
  // owner-scoped and only this client writes them, so a local
  // "I just wrote it" entry is authoritative for the
  // does-it-exist question.
  final Set<String> _seenSelfIds = <String>{};

  // Lazy-init scheduler that fires CItemAvailable into [_events] when
  // each tracked item's `availableAt` passes. Started on first access
  // to [availableEvents] and runs for the lifetime of this
  // collection — see the [CItemAvailable] dartdoc for the rationale.
  _CItemTimerScheduler<CItemAvailable, T>? _availableScheduler;

  // Immutable wiring (set by the private constructor).
  final AtClient atClient;

  /// Fully-qualified namespace — must include the application namespace.
  /// E.g. `'todos.my_apps'`.
  final String namespace;

  final Duration defaultExpiration;

  late final AtSignLogger _logger;

  // Internal event controller and derived streams.
  final StreamController<CEvent> _events = StreamController.broadcast();

  // Notification regex patterns, built in the constructor from [namespace].
  // Matches any key at any depth (L0 or any sub-collection) whose tail
  // is `.<namespace>@<anyone>`. Dispatch by depth is done in
  // `handleNotification` based on `_getPartsFromNotifKey`'s ancestry
  // length — not by separate per-depth regexes.
  late final RegExp _regexObjAny;
  late final String _regexAllStr;

  late final StreamSubscription<AtNotification> _notificationSubscription;

  // The notification stream used for this collection's dispatch. Stored
  // so sub-collections built via [readReceiptsFor] can reuse an
  // injected (test) stream rather than hit the NotificationService.
  Stream<AtNotification>? _injectedNotifications;

  // Sub-collection bookkeeping. On instances returned by [subCollection],
  // these point at the parent item and the parent collection; they're null
  // on standalone / root collections.
  CItem<dynamic>? _parentItem;
  AtCollection<dynamic>? _parentCollection;
  StreamSubscription<CItemDeleted>? _parentDeleteSub;

  // ---------------------------------------------------------------------------
  // Construction

  /// Creates a new [AtCollection] against [namespace] (which must be fully
  /// qualified — see [AtClient.collection]). When supplied, [fromJson]
  /// auto-registers the factory for type `T` — equivalent to calling
  /// `registerFactory<T>(fromJson, typeTag: typeTag)` after construction.
  ///
  /// [fromJson] and [typeTag] travel together: supplying one without the
  /// other throws [ArgumentError]. See [registerFactory] for why
  /// [typeTag] is required.
  factory AtCollection(
    AtClient atClient,
    String namespace,
    Duration defaultExpiration, {
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
  }) =>
      AtCollection._(
        atClient,
        namespace,
        defaultExpiration,
        fromJson: fromJson,
        typeTag: typeTag,
      );

  /// Test-only factory that bypasses `atClient.notificationService.subscribe`
  /// and drives notification dispatch from [notifications] instead. Keeps
  /// the production constructor's surface clean. Reachable only through
  /// `collectionWithInjectedNotifications` in `collections_test_hooks.dart`.
  factory AtCollection._withInjectedNotifications(
    AtClient atClient,
    String namespace,
    Duration defaultExpiration, {
    required Stream<AtNotification> notifications,
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
  }) =>
      AtCollection._(
        atClient,
        namespace,
        defaultExpiration,
        fromJson: fromJson,
        typeTag: typeTag,
        notifications: notifications,
      );

  AtCollection._(
    this.atClient,
    this.namespace,
    this.defaultExpiration, {
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    Stream<AtNotification>? notifications,
  }) {
    if (!namespace.contains('.')) {
      throw ArgumentError('namespace must be fully qualified');
    }
    if (fromJson != null && typeTag == null) {
      throw ArgumentError(
        'typeTag is required when fromJson is supplied. '
        "Pass typeTag: '$T' alongside fromJson, or call "
        "AtCollection.registerFactory<$T>(fromJson, typeTag: '$T') "
        'separately. The typeTag pins the wire-format identifier so it '
        'survives Dart minifier / tree-shaker renames in release builds.',
      );
    }
    if (fromJson == null && typeTag != null) {
      throw ArgumentError(
        'typeTag was supplied without fromJson. Pass fromJson alongside '
        'it, or omit both and register the factory separately via '
        'AtCollection.registerFactory.',
      );
    }
    if (fromJson != null) {
      registerFactory<T>(fromJson, typeTag: typeTag!);
    }

    _logger = AtSignLogger(' AtCollection<$T> $namespace ');

    // TODO: namespace may contain periods - the regular expression should
    // escape those periods
    _regexAllStr = '.*\\.$namespace@';
    // Matches the direct-item shape `<id>.<ns>@` AND any deeper
    // sub-item shape `<id>.<subName>.<parentId>.…<ns>@`. We use this
    // as a cheap filter to reject notifications that don't belong to
    // this collection at all; depth-dispatch happens via the parsed
    // ancestry length, not by regex.
    _regexObjAny = RegExp('(^|:)[^.]+(\\.[^.]+)*\\.$namespace@');

    _injectedNotifications = notifications;
    final notifStream = notifications ??
        atClient.notificationService.subscribe(
          regex: _regexAllStr,
          shouldDecrypt: true,
        );
    _notificationSubscription = notifStream.listen(_handleNotificationImpl);
  }

  // ---------------------------------------------------------------------------
  // Basic getters

  /// The atSign this collection's underlying [atClient] is acting as.
  /// See [self] for a more readable alias in ownership-centric code.
  Atsign get atSign => atClient.atSign;

  /// Convenience alias for [atSign] — reads naturally when contrasting
  /// "self" with "other" atSigns in ownership / sharing logic.
  /// `item.owner == collection.self` is the ownership test the
  /// library uses internally.
  Atsign get self => atClient.atSign;

  /// True iff this collection was constructed via [subCollection] on a
  /// parent collection.
  bool get isSubCollection => _parentItem != null;

  // ---------------------------------------------------------------------------
  // Factory registry

  /// Registers a factory for type [U] so objects of that type can be
  /// drafted and rehydrated by any [AtCollection] in this process.
  ///
  /// [typeTag] is the **wire-format identifier** for [U] — it is
  /// written into every record's envelope and used to look the
  /// factory up on rehydrate. It is required because deriving the
  /// tag from `U.toString()` is unsafe under Dart's minifier /
  /// tree-shaker (release-mode Flutter web, AOT obfuscated builds);
  /// a renamed class name silently changes the on-wire tag and
  /// rehydrate falls back to the raw map. Pinning [typeTag]
  /// explicitly is the only way to guarantee the wire format is
  /// stable across builds and across atSigns.
  ///
  /// Static by design: factories are process-global, shared across
  /// every [AtCollection] instance. Callers that supply `fromJson:`
  /// to [AtCollection.new] / [AtClient.collection] / [subCollection]
  /// must also supply the matching `typeTag:` — those entry points
  /// just forward into this method.
  ///
  /// Use for polymorphic collections where `T` is an abstract
  /// supertype:
  ///
  ///     AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');
  ///     AtCollection.registerFactory<Cat>(Cat.fromJson, typeTag: 'Cat');
  ///     final pets = await atClient.collection<Pet>(ns, defaultExpiration);
  ///
  /// **Re-registration rules.** Re-registering the same `(U, typeTag)`
  /// pair replaces the factory body (last write wins; useful for
  /// tests). Re-registering [U] under a *different* tag, or [typeTag]
  /// against a different type, throws [StateError] — the tag is part
  /// of the cross-atSign wire-format contract and must not silently
  /// drift. To rotate a wire format, choose a new tag, deploy
  /// readers that accept both old and new, then retire the old.
  ///
  /// **Process-global scope.** The registry is a single static map per
  /// Dart isolate, shared across every [AtCollection] / [AtClient] in
  /// that isolate. There is intentionally no per-AtClient registry —
  /// the same wire format must round-trip identically regardless of
  /// which atSign happens to be active when a record is read or
  /// written. Apps that load multiple atSigns sequentially register
  /// each `(T, typeTag)` once at startup and reuse the registry across
  /// switches.
  static void registerFactory<U>(
    U Function(Map<String, dynamic>) fromJson, {
    required String typeTag,
  }) {
    if (typeTag.trim().isEmpty) {
      throw ArgumentError(
        'typeTag must be non-empty / non-whitespace; got "$typeTag" for $U.',
      );
    }
    final existing = _factoriesByType[U];
    if (existing != null && existing.tag != typeTag) {
      throw StateError(
        'Type $U is already registered with typeTag "${existing.tag}"; '
        'cannot re-register it under "$typeTag". The wire-format tag '
        'for a given type is part of the cross-atSign contract — pick '
        'one and keep it. To replace the factory body for the same '
        'type, pass the same typeTag.',
      );
    }
    for (final e in _factoriesByType.entries) {
      if (e.key != U && e.value.tag == typeTag) {
        throw StateError(
          'typeTag "$typeTag" is already registered for type ${e.key}; '
          'cannot register it for $U as well. typeTag is the wire-format '
          'identifier and must be unique across all registered types.',
        );
      }
    }
    _factoriesByType[U] = _FactoryEntry(typeTag, fromJson);
    _factoriesByTag[typeTag] = fromJson;
  }

  /// Test-only escape hatch that drops every registered factory.
  /// Useful at the start of a test that wants a clean global registry
  /// (process-global static state otherwise carries between tests).
  /// Not for production use — the registry is meant to be append-only
  /// from app code.
  static void _clearFactoriesForTestImpl() {
    _factoriesByType.clear();
    _factoriesByTag.clear();
  }

  // ---------------------------------------------------------------------------
  // Drafting / persisting

  /// Builds a new (not-yet-persisted) [CItem] owned by this atSign. No
  /// I/O — use [create] to persist a new item, or [update] to save
  /// changes to an existing one.
  ///
  /// If [id] is omitted a random 8-character `[a-z0-9]` id is assigned;
  /// **note** that [draft] performs no uniqueness check — if you want to
  /// guarantee a collision-free id, use [create] (which retries on
  /// collision) rather than calling [draft] followed by a manual write.
  ///
  /// [expiresAt] defaults to `now + defaultExpiration`. Supply an
  /// explicit value to override for this item alone.
  ///
  /// [availableAt] defaults to `null` (visible immediately). Supply a
  /// future `DateTime` to delay visibility of recipient copies
  /// (time-to-birth). A past timestamp is treated the same as `null` by
  /// the write path, so setting one is harmless but has no effect.
  CItem<T> draft({
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
    DateTime? expiresAt,
    DateTime? availableAt,
  }) {
    final now = DateTime.now().toUtc();
    id ??= _newItemId();
    return CItem._(
      owner: atSign,
      id: id,
      type: _resolveType(obj),
      obj: obj,
      sharedWith: sharedWith ?? {},
      createdAt: now,
      expiresAt: expiresAt ?? now.add(defaultExpiration),
      availableAt: availableAt,
      collection: this,
      parentOwners: _expectedAncestorOwners(),
    );
  }

  /// Creates a brand-new [CItem] and persists it. Throws [StateError] if
  /// [id] is supplied and the self-key `<id>.<namespace>@<self>` already
  /// exists — use [update] to modify an existing item. When [id] is
  /// omitted, a random 8-character id is generated with an existence
  /// check; we retry on collision (odds are astronomically low) and give
  /// up after 10 attempts with a [StateError].
  ///
  /// [expiresAt] and [availableAt] are forwarded to [draft]. See that
  /// method's doc comment for the defaults and the null semantics.
  ///
  /// Returns the persisted item. Throws [CollectionOpException] on any
  /// key-level failure.
  Future<CItem<T>> create({
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
    DateTime? expiresAt,
    DateTime? availableAt,
  }) async {
    final String useId;
    if (id != null) {
      if (await _selfKeyExists(id)) {
        throw StateError(
          'Cannot create item with id "$id": already exists in $namespace. '
          'Use update() to modify an existing item.',
        );
      }
      useId = id;
    } else {
      useId = await _uniqueItemId();
    }
    final item = draft(
      obj: obj,
      id: useId,
      sharedWith: sharedWith,
      expiresAt: expiresAt,
      availableAt: availableAt,
    );
    final results = await _put(item);
    if (results.any((r) => r is OpFailure)) {
      throw CollectionOpException(results);
    }
    return item;
  }

  /// Updates an existing [item]. Throws [StateError] if the self-key does
  /// not exist (use [create] for new items). Throws [ArgumentError] if
  /// [item.owner] is not this atSign.
  ///
  /// With the default `unshareWithOthers: true`, any recipient copy
  /// whose atSign is NO LONGER in `item.sharedWith` is deleted;
  /// recipients present in both the existing set and `item.sharedWith`
  /// are overwritten in place. Pass `false` to leave any current
  /// recipient copies alone (useful when adding recipients without
  /// risking removal of existing ones during a concurrent read).
  ///
  /// To change the value AND the recipient set in one call, mutate
  /// `item.sharedWith` directly before calling [update] — e.g.
  /// `item.sharedWith..clear()..addAll(newSet); update(item)`.
  ///
  /// If you only need to change recipients (no value change on the
  /// item itself), prefer [updateSharedWith] — it skips the self-key
  /// rewrite entirely and just diffs the recipient copies.
  ///
  /// Typical usage: fetch an item via [get] / [getItems], mutate its
  /// fields, then call [update].
  Future<void> update(
    CItem<T> item, {
    bool unshareWithOthers = true,
  }) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not update items owned by other atSigns');
    }
    if (!await _selfKeyExists(item.id)) {
      throw StateError(
        'Cannot update item "${item.id}": no such item exists in $namespace. '
        'Use create() to add a new item.',
      );
    }
    final results = await _put(item, unshareWithOthers: unshareWithOthers);
    if (results.any((r) => r is OpFailure)) {
      throw CollectionOpException(results);
    }
  }

  /// Updates only the recipient set on an existing [item] — does NOT
  /// rewrite the self copy. Useful when you want to add or remove
  /// recipients without bumping the item's commit-id or pushing a
  /// fresh CItemUpdated to every existing recipient.
  ///
  /// Computes the delta against `item.sharedWith`:
  ///
  /// - With the default `unshareWithOthers: true`, any atSign in
  ///   `item.sharedWith` but not in [sharedWith] has its recipient
  ///   copy deleted.
  /// - Any atSign in [sharedWith] but not in `item.sharedWith` gets
  ///   a fresh recipient copy written (with the item's current value
  ///   and metadata).
  /// - Recipients present in BOTH sets are left untouched — their
  ///   existing copies stay at the commit-id they already have.
  ///
  /// On success, `item.sharedWith` is mutated in place to match
  /// [sharedWith]. If [sharedWith] equals `item.sharedWith`, the
  /// method is a no-op (no I/O) but `item.sharedWith` is still
  /// updated (handles the case where the caller passed a fresh `Set`
  /// instance).
  ///
  /// Does NOT emit a local [CItemUpdated] / [CItemDeleted] on this
  /// collection's events — the self-item's state hasn't changed from
  /// this atSign's perspective. New recipients see their own
  /// [CItemUpdated] via the round-trip notification path; removed
  /// recipients see their own [CItemDeleted] the same way.
  ///
  /// Throws [ArgumentError] if `item.owner != self`. Throws
  /// [StateError] if the item's self-key doesn't exist (use [create]
  /// to add new items). Throws [CollectionOpException] on any
  /// key-level put / delete failure.
  Future<void> updateSharedWith(
    CItem<T> item,
    Set<Atsign> sharedWith, {
    bool unshareWithOthers = true,
  }) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not update items owned by other atSigns');
    }
    if (!await _selfKeyExists(item.id)) {
      throw StateError(
        'Cannot update sharedWith for item "${item.id}": no such item '
        'exists in $namespace. Use create() to add it first.',
      );
    }
    final toUnshare = unshareWithOthers
        ? item.sharedWith.difference(sharedWith)
        : const <Atsign>{};
    final toShare = sharedWith.difference(item.sharedWith);
    if (toUnshare.isEmpty && toShare.isEmpty) {
      // No recipient-set delta. Still align the item's own Set with
      // the caller's argument in case they passed a fresh instance.
      item.sharedWith
        ..clear()
        ..addAll(sharedWith);
      return;
    }
    final now = DateTime.now();
    if (toShare.isNotEmpty &&
        item.expiresAt.millisecondsSinceEpoch < now.millisecondsSinceEpoch) {
      throw ArgumentError(
        'item.expiresAt must be in the future to add new recipients',
      );
    }
    final md = toShare.isEmpty ? null : _buildMetadata(item, now);
    final results = <OpResult>[];
    for (final r in toUnshare) {
      final k = AtKey.fromString('$r:${item.id}.$namespace$atSign');
      try {
        await atClient.delete(k);
        results.add(OpSuccess(k, CollectionOp.delete));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.delete, e));
      }
    }
    for (final r in toShare) {
      final k = AtKey.fromString('$r:${item.id}.$namespace$atSign');
      try {
        k.metadata = md!;
        await atClient.put(k, jsonEncode(item.toJson()));
        results.add(OpSuccess(k, CollectionOp.put));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.put, e));
      }
    }
    if (results.any((r) => r is OpFailure)) {
      throw CollectionOpException(results);
    }
    item.sharedWith
      ..clear()
      ..addAll(sharedWith);
  }

  /// Deletes [item] and every one of its recipient copies. Only the owner
  /// may call this. Throws [CollectionOpException] on any key-level
  /// failure.
  ///
  /// If [cascade] is false (the default) and [item] has self-owned
  /// descendants in any sub-collection, throws [StateError] and does not
  /// write anything — the caller must either delete descendants
  /// explicitly or pass `cascade: true`.
  ///
  /// If [cascade] is true, every self-owned descendant (at any depth) is
  /// deleted before [item] itself.
  Future<void> delete(CItem<T> item, {bool cascade = false}) async {
    final results = await _delete(item, cascade: cascade);
    if (results.any((r) => r is OpFailure)) {
      throw CollectionOpException(results);
    }
  }

  // ---------------------------------------------------------------------------
  // Reads

  /// Internal regex-keyed scan used by every higher-level read in
  /// the SDK (the [getItemsAsStream] decode loop, the
  /// cleanup-orphans root scan, the recipient diff in [_put], the
  /// self-and-recipients sweep in [_delete]). Composes a regex from
  /// optional [id] / [owner] filters, calls [AtClient.getAtKeys],
  /// and returns the matching keys sorted by `fullKeyAndOwner` so
  /// per-(owner, id) copies (self + recipients) are contiguous in
  /// the output.
  ///
  /// Private by design: `AtKey` is an Atsign Protocol primitive the
  /// rest of the AtCollection surface deliberately hides. Exposing
  /// raw keys to app code would re-introduce the ceremony the
  /// library exists to remove. Production callers reach for
  /// [getItems] / [getItemsAsStream] (typed) or the [Query<T>]
  /// builder instead.
  Future<List<AtKey>> _getKeysInternal({String? id, Atsign? owner}) async {
    // want a regex like (^|:)[^.]+\.collection\.name\.space@
    // e.g. (^|:)[^.]+\.notes\.todos\.demos@
    id ??= '[^.]+';
    final ownerFragment = owner ?? '@';
    final regex = '(^|:)$id\\.$namespace$ownerFragment';
    return (await atClient.getAtKeys(regex: regex))
      ..sort((a, b) => a.fullKeyAndOwner.compareTo(b.fullKeyAndOwner));
  }

  /// True iff an item with the given [id] owned by [owner] exists in
  /// this collection — without fetching or decoding its value. Cheap
  /// presence-check: use this in preference to `getOrNull(id, owner) != null`
  /// when you only care whether the item is there.
  ///
  /// For self-owned items the call hits the seen-id cache populated
  /// by every successful read/write in this process; for items owned
  /// by other atSigns it does a key-listing scan and returns true if
  /// any cached copy exists locally.
  Future<bool> exists(String id, Atsign owner) async {
    if (owner == atSign) {
      return _selfKeyExists(id);
    }
    final keys = await _getKeysInternal(id: id, owner: owner);
    return keys.isNotEmpty;
  }

  /// Fetches a single item. Throws [AtKeyNotFoundException] if no item
  /// with this [id] owned by this [owner] exists. For a null-returning
  /// variant, see [getOrNull].
  ///
  /// A per-key decode failure encountered before any item is yielded
  /// propagates as that failure (via [getItemsAsStream]'s stream-error
  /// mechanism). Once a matching item is yielded the stream is
  /// cancelled, so later-in-the-scan errors never surface here.
  Future<CItem<T>> get(String id, Atsign owner) async {
    final item = await getOrNull(id, owner);
    if (item == null) {
      throw AtKeyNotFoundException(
        'No item found with id $id owned by $owner',
      );
    }
    return item;
  }

  /// Same as [get] but returns `null` when no item exists, instead of
  /// throwing [AtKeyNotFoundException]. Same error-propagation
  /// semantics as [get] for per-key decode failures that precede the
  /// first matching item.
  Future<CItem<T>?> getOrNull(String id, Atsign owner) async {
    await for (final item in getItemsAsStream(id: id, owner: owner)) {
      return item; // first match; stream unsubscribed here.
    }
    return null;
  }

  /// Fetches every item in the collection as a `List<CItem<T>>`,
  /// optionally filtered by [id] / [owner]. Items with the same
  /// `owner+id` across self and shared copies are deduplicated and their
  /// `sharedWith` sets are unioned.
  ///
  /// Thin wrapper around [getItemsAsStream]: a per-key decode failure
  /// aborts the list with that error (via `.toList()` propagating the
  /// stream error). If you need to continue past decode failures, use
  /// [getItemsAsStream] directly and chain `.handleError(...)` or
  /// collect errors yourself.
  Future<List<CItem<T>>> getItems({String? id, Atsign? owner}) =>
      getItemsAsStream(id: id, owner: owner).toList();

  /// Fundamental read path. Yields each item as it is fetched, deduping
  /// on `owner+id`. Ideal for filter-style queries:
  ///
  ///     final done = await collection.getItemsAsStream()
  ///         .where((item) => item.obj.done)
  ///         .toList();
  ///
  /// Per-key decode failures are yielded into the stream as **errors**
  /// (via `yield* Stream<CItem<T>>.error(...)`), not swallowed. Good
  /// data items keep flowing before and after each error. Callers
  /// choose the policy:
  ///
  ///   - `.toList()` / `await for` without `onError` → first error
  ///     aborts with the error thrown.
  ///   - `.listen(onData, onError: ...)` → handle per-key errors
  ///     without stopping.
  ///   - `.handleError(...)` chained before consumption → restore a
  ///     silent-skip posture.
  ///
  /// All higher-level read methods ([get], [getOrNull], [getItems]) are
  /// thin wrappers over this stream.
  Stream<CItem<T>> getItemsAsStream({String? id, Atsign? owner}) async* {
    // [_getKeysInternal] returns keys sorted by `fullKeyAndOwner`, so
    // all copies of the same item (self + per-recipient) are
    // contiguous. We buffer each item, absorb its recipient siblings'
    // `sharedWith` additions, and yield once per unique (owner, id).
    final keys = await _getKeysInternal(id: id, owner: owner);
    CItem<T>? pending;
    String? pendingKey;
    for (final k in keys) {
      try {
        if (k.fullKeyAndOwner != pendingKey) {
          if (pending != null) yield pending;
          final v = await atClient.get(k);
          final decoded = _decodeEnvelope(v.value!, k);
          // Parent-owner ancestry filter (see §3 of the post-
          // implementation tidy-up plan). Legacy items whose envelope
          // lacks `parents` are accepted lenient-ly as matching this
          // sub-collection's expected chain.
          final parsedParents = _decodeParentOwners(decoded);
          if (parsedParents != null && !_ancestryMatches(parsedParents)) {
            // Item belongs to a different parent-owner chain at the
            // same key shape — skip.
            continue;
          }
          pending = CItem._(
            owner: k.sharedBy!.toAtsign(),
            id: k.key.split('.').first,
            type: decoded['type'] as String,
            obj: _rehydrate<T>(decoded['obj']!, decoded['type'] as String),
            sharedWith: {},
            createdAt: v.metadata!.createdAt!,
            expiresAt: v.metadata!.expiresAt ??
                DateTime.now().toUtc().add(defaultExpiration),
            availableAt: _liveAvailableAt(v.metadata!.availableAt),
            collection: this,
            parentOwners: parsedParents ?? _expectedAncestorOwners(),
          );
          pendingKey = k.fullKeyAndOwner;
        }
        if (k.sharedWith != null) {
          pending!.sharedWith.add(k.sharedWith!.toAtsign());
        }
      } catch (e, st) {
        // Per-key decode failures are yielded as stream errors rather
        // than logged-and-skipped. The stream continues after an error
        // — subsequent iterations of this for-loop produce further
        // data or error events. Callers choose the policy:
        //
        //   - `.toList()` / `await for` (no onError): first error
        //     aborts with the error thrown. This is what [getItems]
        //     does.
        //   - `.listen(onData, onError: ...)`: handle per-key errors
        //     without stopping the stream.
        //   - `.handleError(...)` before consuming: restore the
        //     silent-skip posture with explicit in-library tolerance
        //     (see [CItem.readBy] for an example — it does this to
        //     tolerate legacy `__rr` items written in the pre-
        //     refactor wire format).
        yield* Stream<CItem<T>>.error(
          'getItemsAsStream decode failure on ${k.key}: $e\n$st',
        );
      }
    }
    if (pending != null) yield pending;
  }

  /// Builds a new [Query] scoped to this collection's direct items.
  /// Chain [Query.where] / [Query.orderBy] / [Query.thenBy] /
  /// [Query.limit] / [Query.skip] and terminate with [Query.get]
  /// (one-shot) or [Query.watch] (live reactive).
  ///
  /// ```dart
  /// final overdue = await todos.query()
  ///     .where((t) => !t.obj.done)
  ///     .where((t) => t.obj.due.isBefore(DateTime.now()))
  ///     .orderBy((t) => t.obj.due)
  ///     .limit(20)
  ///     .get();
  /// ```
  ///
  /// For genuinely ad-hoc pipelines you can still use
  /// [getItemsAsStream] directly with any `Stream` transformer —
  /// [Query] is the value-typed ergonomic path, not a replacement.
  Query<T> query() => Query<T>._(this, _QuerySpec<T>());

  // ---------------------------------------------------------------------------
  // Read receipts

  /// True if the current atSign has already sent a read receipt for
  /// [item]. Delegates to [CItem.wasMarkedReadByMe], which returns
  /// true for self-owned items without any I/O.
  Future<bool> wasMarkedReadByMe(CItem<T> item) => item.wasMarkedReadByMe();

  /// Sends a read receipt to the owner of [item]. Idempotent — if a
  /// receipt already exists for this atSign, the call is a no-op.
  /// No-op on self-owned items.
  Future<void> markReadByMe(CItem<T> item) => item.markReadByMe();

  /// Returns (creating and caching if necessary) the reserved `__rr`
  /// sub-collection that holds read receipts for [item].
  ///
  /// This is the public entry point for querying receipts directly —
  /// e.g. a live "how many readers?" badge is just
  /// `todos.readReceiptsFor(item).query().watch().map((l) => l.length)`,
  /// and a one-shot check is `.query().count()`. Callers generally
  /// shouldn't *write* through this handle — use
  /// [CItem.markReadByMe] / [AtCollection.markReadByMe] — but
  /// reading is fully supported and idiomatic.
  ///
  /// Each receipt sub-item's `owner` is the atSign that marked the
  /// parent item as read; the sub-item's body is a small JSON map
  /// carrying the `readAt` timestamp.
  ///
  /// The returned [AtCollection] is memoised per `(item.owner, item.id)`
  /// so repeated calls for the same item return the same instance,
  /// keeping its notification subscription and live-event machinery
  /// alive across UI rebuilds.
  AtCollection<Map<String, dynamic>> readReceiptsFor(CItem<T> item) {
    final cacheKey = '${item.owner}:${item.id}';
    final cached = _rrCache[cacheKey];
    if (cached != null) return cached;
    final sub = _buildSubCollection<Map<String, dynamic>>(
      parent: item,
      subName: _rr,
      defaultExpiration: const Duration(days: 365),
      notifications: _injectedNotifications,
    );
    _rrCache[cacheKey] = sub;
    return sub;
  }

  // ---------------------------------------------------------------------------
  // Sub-collections

  /// Returns an [AtCollection] of [CItem]s scoped to [parent] — e.g. the
  /// comments on a specific blog post, or the replies on a specific
  /// comment.
  ///
  /// ```dart
  /// final comments = posts.subCollection<Comment>(
  ///   parent: post,
  ///   subName: 'comments',
  ///   defaultExpiration: const Duration(days: 30),
  ///   fromJson: Comment.fromJson,
  /// );
  /// await comments.create(obj: Comment('great post'));
  /// ```
  ///
  /// The returned collection is a plain `AtCollection<U>`; it supports
  /// every method of the parent class, including further nesting:
  ///
  /// ```dart
  /// final replies = comments.subCollection<Reply>(
  ///   parent: aComment,
  ///   subName: 'replies',
  ///   defaultExpiration: const Duration(days: 30),
  ///   fromJson: Reply.fromJson,
  /// );
  /// ```
  ///
  /// **Nesting depth is bounded by the Atsign Protocol's 255-char
  /// key limit.** The composed namespace this call produces is
  /// `<subName>.<parent.id>.<this.namespace>`. The absolute
  /// worst-case on-wire key for any descendant is the cached-copy
  /// shape `cached:<other-atsign>:<itemId>.<composedNs>@<self-atsign>`;
  /// at 55 chars per atSign that's a fixed wrapper overhead of
  /// 118 chars (`cached:` 7 + `<other>` 55 + `:` 1 + `@<self>` 55),
  /// leaving 137 chars for `<itemId>.<composedNs>`. Reserving 8
  /// chars for the SDK's auto-generated item id and 1 for the
  /// separator, **`composedNs` is capped at 128 chars** — applied
  /// independently of the actual self-atSign length so the same
  /// SDK builds round-trip-safe keys regardless of which atSign
  /// owns this client. [subCollection] enforces this budget at
  /// construction time and throws [ArgumentError] before any I/O
  /// if the composed namespace would overflow — errors never reach
  /// the wire.
  ///
  /// The reserved sub-collection name `__rr` is rejected (it's used
  /// internally for read receipts); pick any other string.
  ///
  /// **Parent-delete behaviour.** When [parent] is deleted — locally,
  /// or via a remote-delete notification — the sub-collection
  /// automatically deletes this atSign's own items scoped to it. See
  /// [cleanupOrphans] for the cold-start / offline recovery equivalent.
  AtCollection<U> subCollection<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    U Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
  }) =>
      _subCollectionInternal<U>(
        parent: parent,
        subName: subName,
        defaultExpiration: defaultExpiration,
        fromJson: fromJson,
        typeTag: typeTag,
      );

  /// Test-only variant of [subCollection] that injects [notifications]
  /// instead of subscribing through the live `NotificationService`.
  /// Same surface as [subCollection] otherwise — same reserved-name
  /// guard, same key-length budget check.
  ///
  /// Hidden behind a separate entry point (rather than an extra
  /// optional parameter on [subCollection]) so production callers see
  /// only the verbs they need; the test hook never appears in
  /// IDE auto-complete on the public surface.
  AtCollection<U> _subCollectionWithInjectedNotifications<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    required Stream<AtNotification> notifications,
    U Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
  }) =>
      _subCollectionInternal<U>(
        parent: parent,
        subName: subName,
        defaultExpiration: defaultExpiration,
        fromJson: fromJson,
        typeTag: typeTag,
        notifications: notifications,
      );

  AtCollection<U> _subCollectionInternal<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    U Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    Stream<AtNotification>? notifications,
  }) {
    if (subName == _rr) {
      throw ArgumentError(
        'subName "$_rr" is reserved for the built-in read-receipt '
        'sub-collection. Use item.readers() / item.wasMarkedReadByMe() '
        '/ item.markReadByMe() — or AtCollection.markReadByMe / '
        'wasMarkedReadByMe — instead of constructing it directly.',
      );
    }
    return _buildSubCollection<U>(
      parent: parent,
      subName: subName,
      defaultExpiration: defaultExpiration,
      fromJson: fromJson,
      typeTag: typeTag,
      notifications: notifications,
    );
  }

  /// Internal sub-collection constructor without the reserved-name
  /// guard. Used by [readReceiptsFor] to build the `__rr` sub-collection.
  AtCollection<U> _buildSubCollection<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    U Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    Stream<AtNotification>? notifications,
  }) {
    if (subName.isEmpty || subName.contains('.')) {
      throw ArgumentError('subName must be non-empty and dot-free: "$subName"');
    }
    if (parent.id.contains('.')) {
      throw ArgumentError('parent.id must not contain dots: "${parent.id}"');
    }
    final composedNs = '$subName.${parent.id}.$namespace';
    // Worst-case key shape (cached-shared-with form):
    //   cached:<other>:<itemId>.<composedNs>@<self>
    // The Atsign Protocol caps every atSign at 55 chars (including
    // the leading '@'). At absolute worst case BOTH atSigns are at
    // that max, fixing the wrapper overhead at:
    //   cached: (7) + <other> (55) + : (1) + @<self> (55) = 118
    // which leaves 255 - 118 = 137 chars for <itemId>.<composedNs>.
    // The SDK's auto-generated item ids are 8 chars; reserving 8 +
    // 1 for the separator '.' gives a hard cap of 128 chars on
    // composedNs.
    //
    // The bound is INDEPENDENT of the actual self-atSign length —
    // we want the same SDK to produce round-trip-safe keys
    // regardless of which atSign owns this client. Custom item ids
    // longer than 8 chars will still encounter a tighter limit at
    // write time (atServer rejects keys > 255), but those callers
    // will know they've stepped outside the SDK's documented
    // contract.
    const int maxComposedNsLength = 128;
    if (composedNs.length > maxComposedNsLength) {
      throw ArgumentError(
        'Composed sub-collection namespace "$composedNs" is '
        '${composedNs.length} chars, exceeds the absolute-worst-case '
        'max of $maxComposedNsLength chars (255-char key limit minus 118 chars '
        'of wrapper overhead for two 55-char atSigns + cached: prefix, and 9 '
        'chars reserved for an 8-char item id + separator). Use a shorter '
        'subName or a shallower nesting depth.',
      );
    }
    // Constructing the sub-collection directly (not via `atClient.collection`)
    // so that `notifications` can be threaded straight through to its
    // constructor for test wiring.
    final sub = notifications != null
        ? AtCollection<U>._withInjectedNotifications(
            atClient,
            composedNs,
            defaultExpiration,
            notifications: notifications,
            fromJson: fromJson,
            typeTag: typeTag,
          )
        : AtCollection<U>(
            atClient,
            composedNs,
            defaultExpiration,
            fromJson: fromJson,
            typeTag: typeTag,
          );
    sub._parentItem = parent;
    sub._parentCollection = this;
    sub._parentDeleteSub?.cancel();
    sub._parentDeleteSub = deletes.listen((e) {
      if (e.id == parent.id && e.owner == parent.owner) {
        unawaited(sub._cascadeFromParentDelete());
      }
    });
    return sub;
  }

  Future<void> _cascadeFromParentDelete() async {
    try {
      // Deep scan — we must pick up not just direct sub-items
      // (`<id>.<ns>@<self>`) but also nested descendants
      // (`<subId>.<subName>.<id>.<ns>@<self>`, and deeper). Using
      // `_getKeysInternal(owner: self)` alone would miss every level
      // deeper than 1.
      final keys = await atClient.getAtKeys(
        regex: '(^|:).+\\.$namespace$self',
      );
      // Ancestry filter: we only delete descendants whose persisted
      // `parents` chain starts with this sub-collection's expected
      // chain. A descendant of a DIFFERENT-owner chain that happens
      // to live under the same composed namespace (id collision
      // case) must be spared.
      final expectedPrefix = _expectedAncestorOwners();
      await Future.wait(keys.map((k) async {
        try {
          final v = await atClient.get(k);
          final decoded = _decodeEnvelope(v.value!, k);
          final persisted = _decodeParentOwners(decoded);
          if (persisted != null && !_startsWith(persisted, expectedPrefix)) {
            return; // not our chain — leave it alone
          }
          await atClient.delete(k);
        } catch (e) {
          _logger.shout('_cascadeFromParentDelete: $e');
        }
      }));
    } catch (e) {
      _logger.shout('_cascadeFromParentDelete scan: $e');
    }
  }

  /// Removes self-owned items whose parent chain has been broken.
  /// Call this at startup to reclaim storage from orphaned sub-items
  /// after an offline period during which a parent may have been
  /// deleted on another atSign.
  ///
  /// Behaviour depends on the collection instance:
  ///
  /// - **Sub-collection** (instance returned by [subCollection]): if
  ///   its bound parent no longer exists locally, delete every
  ///   self-owned item that matches this sub-collection's ancestor-
  ///   owner chain. Cross-owner same-id chains are spared.
  ///
  /// - **Root / standalone collection**: scan every self-owned
  ///   descendant (any sub-collection, any depth) under this
  ///   collection's namespace; for each, walk the full ancestor chain
  ///   (ids from the key + owners from the envelope `parents` field)
  ///   and delete if any level is missing locally. Legacy items with
  ///   no `parents` envelope fall back to a root-ancestor-only check.
  ///
  /// The cleanest place to invoke this is implicitly via
  /// [AtClient.collection]'s `cleanupOrphansOnCreation: true` flag —
  /// the library then runs one sweep before the returned Future
  /// completes. Direct invocation is also supported for apps that
  /// want to sweep at other moments.
  ///
  /// Returns per-key [OpResult]s for every deletion attempted; on a
  /// sub-collection whose parent still exists, returns an empty list
  /// (no-op).
  Future<List<OpResult>> cleanupOrphans() async {
    return isSubCollection
        ? _cleanupOrphansFromSub()
        : _cleanupOrphansFromRoot();
  }

  Future<List<OpResult>> _cleanupOrphansFromSub() async {
    final parent = _parentItem!;
    final parentColl = _parentCollection!;
    final stillAlive = await parentColl.getOrNull(parent.id, parent.owner);
    if (stillAlive != null) return const <OpResult>[];
    // Parent is gone — delete every self-owned item in this sub-
    // collection AND its nested descendants, but only those whose
    // persisted `parents` chain starts with this sub-collection's
    // expected ancestor chain (ancestry filter — see §3 of the post-
    // implementation tidy-up plan).
    final expectedPrefix = _expectedAncestorOwners();
    final results = <OpResult>[];
    final deep = await atClient.getAtKeys(
      regex: '(^|:).+\\.$namespace$atSign',
    );
    for (final k in deep) {
      try {
        final v = await atClient.get(k);
        final decoded = _decodeEnvelope(v.value!, k);
        final persisted = _decodeParentOwners(decoded);
        if (persisted != null && !_startsWith(persisted, expectedPrefix)) {
          continue; // different-owner chain; leave alone
        }
        await atClient.delete(k);
        results.add(OpSuccess(k, CollectionOp.delete));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.delete, e));
      }
    }
    return results;
  }

  Future<List<OpResult>> _cleanupOrphansFromRoot() async {
    // Chain-walking orphan sweep. For each self-owned descendant in
    // this collection's subtree:
    //   1. Parse its ancestor ids and subNames from the key.
    //   2. Read its envelope's `parents` for ancestor owners.
    //   3. For each ancestor level (root-first), construct
    //      `<id_i>.<composedNs_i>@<owner_i>` and check local presence.
    //   4. If any ancestor is absent → orphaned → delete.
    //
    // Legacy items (no `parents`) cannot have their ancestor-owner
    // chain verified, so we preserve the old behaviour: check only
    // the ROOT ancestor's id against direct items locally (any owner).
    final nsSegments = namespace.split('.').length;

    // Legacy-fallback: set of root-ancestor ids that exist locally as
    // direct items (any owner).
    final aliveRootIds = <String>{};
    for (final k in await _getKeysInternal()) {
      final parts = k.key.split('.');
      if (parts.length == nsSegments) {
        aliveRootIds.add(parts.first);
      }
    }

    // Per-sweep cache of alive ids at non-root composed namespaces,
    // populated lazily by the legacy-fallback chain-walker. Keyed by
    // composed namespace string. One getAtKeys probe per distinct
    // level encountered across all legacy descendants in this sweep.
    final legacyAliveCache = <String, Set<String>>{};

    final descendantKeys = await atClient.getAtKeys(
      regex: '(^|:).+\\.$namespace$atSign',
    );
    final results = <OpResult>[];
    for (final k in descendantKeys) {
      final parts = k.key.split('.');
      if (parts.length <= nsSegments) continue; // direct items are alive
      // Parse ancestor ids and subNames from the key.
      //
      // k.key layout for a depth-D descendant (D >= 1):
      //   [itemId, subName_D, id_D, subName_{D-1}, id_{D-1}, ...,
      //    subName_1, id_1, ns_seg_0, ns_seg_1, ..., ns_seg_{nsSegments-2}]
      //
      // The last `nsSegments - 1` parts are the root namespace tail
      // (AtKey.namespace captures the final namespace segment, not
      // the whole thing). The root ancestor's id lives at index
      // `parts.length - nsSegments` (= `rootIndex`). Iterating down
      // by 2 from there walks root → direct parent.
      final rootIndex = parts.length - nsSegments;
      final ancestorIds = <String>[];
      final ancestorSubNames = <String>[];
      for (int i = rootIndex; i >= 2; i -= 2) {
        ancestorIds.add(parts[i]); // root first, then deeper
        ancestorSubNames.add(parts[i - 1]);
      }

      // Determine ancestor owners — from envelope if present, legacy
      // fallback otherwise.
      List<Atsign>? ancestorOwners;
      try {
        final v = await atClient.get(k);
        final decoded = _decodeEnvelope(v.value!, k);
        ancestorOwners = _decodeParentOwners(decoded);
      } catch (_) {
        // Unreadable envelope — fall through to legacy path.
      }

      if (ancestorOwners == null) {
        // Legacy fallback (no envelope `parents`). We can't recover
        // ancestor owners from the key alone, so verify each level
        // by id-presence regardless of owner — chain-walk against
        // the local store. Depth-1 legacy items round-trip cleanly
        // against [aliveRootIds]; depth-2+ items use lazily-cached
        // per-composed-namespace alive sets via [_aliveIdsAt]. Since
        // the local store may legitimately hold a same-id item under
        // a different owner without it being our parent, this path
        // is intentionally lenient — false negatives (preserving
        // an item that's actually orphaned) are preferable to false
        // positives (deleting a live one) under uncertainty.
        bool orphaned = false;
        String composed = namespace;
        for (int i = 0; i < ancestorIds.length; i++) {
          final aliveAtLevel = composed == namespace
              ? aliveRootIds
              : await _aliveIdsAt(composed, legacyAliveCache);
          if (!aliveAtLevel.contains(ancestorIds[i])) {
            orphaned = true;
            break;
          }
          // Descend to the next-level namespace for the next iteration.
          composed = '${ancestorSubNames[i]}.${ancestorIds[i]}.$composed';
        }
        if (!orphaned) continue;
        try {
          await atClient.delete(k);
          results.add(OpSuccess(k, CollectionOp.delete));
        } catch (e) {
          results.add(OpFailure(k, CollectionOp.delete, e));
        }
        continue;
      }

      // Chain-walk: for each ancestor level, build the composed
      // namespace at that level and look up `<id_i>.<ns_i>@<owner_i>`.
      bool orphaned = false;
      String composed = namespace;
      for (int i = 0; i < ancestorIds.length; i++) {
        final ancId = ancestorIds[i];
        final ancOwner = i < ancestorOwners.length
            ? ancestorOwners[i]
            : self; // lenient: short chain ⇒ treat missing as self
        final ancKey = AtKey.fromString('$ancId.$composed$ancOwner');
        try {
          await atClient.get(ancKey);
        } catch (_) {
          orphaned = true;
          break;
        }
        // Descend composed namespace for the next level.
        composed = '${ancestorSubNames[i]}.$ancId.$composed';
      }

      if (!orphaned) continue;
      try {
        await atClient.delete(k);
        results.add(OpSuccess(k, CollectionOp.delete));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.delete, e));
      }
    }
    return results;
  }

  /// Returns the set of ids that exist as direct items at the given
  /// [composedNs] locally, across any owner. Used by the legacy
  /// (`parents`-less) chain-walker in [_cleanupOrphansFromRoot] to
  /// verify each ancestor level on items that pre-date the
  /// envelope-`parents` convention. Cached in [cache] so repeated
  /// probes against the same composed namespace cost one round-trip
  /// per sweep regardless of how many descendants fan out from it.
  Future<Set<String>> _aliveIdsAt(
    String composedNs,
    Map<String, Set<String>> cache,
  ) async {
    final cached = cache[composedNs];
    if (cached != null) return cached;
    final escaped = composedNs.replaceAll('.', '\\.');
    final keys = await atClient.getAtKeys(regex: '(^|:)[^.]+\\.$escaped@');
    final levelSegments = composedNs.split('.').length;
    final alive = <String>{};
    for (final key in keys) {
      final parts = key.key.split('.');
      // AtKey strips the last namespace segment into AtKey.namespace,
      // so a direct item at this composed level has exactly
      // levelSegments dot-separated parts in `key.key` (1 id + the
      // stripped-namespace tail = levelSegments). Deeper descendants
      // have more.
      if (parts.length == levelSegments) {
        alive.add(parts.first);
      }
    }
    cache[composedNs] = alive;
    return alive;
  }

  // ---------------------------------------------------------------------------
  // Notification dispatch

  /// Top-level notification dispatcher. Pauses its own subscription for
  /// the duration of handling so re-entrant notifications don't cause
  /// overlapping work. Dispatch is depth-agnostic: L0 items go to
  /// [_handleObjNotificationImpl]; any sub-item at any nesting depth
  /// goes to [_handleSubObjNotificationImpl].
  Future<void> _handleNotificationImpl(AtNotification n) async {
    _notificationSubscription.pause();
    try {
      if (!_regexObjAny.hasMatch(n.key)) {
        _logger.shout('handleNotification: No handler for ${n.key}');
        return;
      }
      final parts = _getPartsFromNotifKey(n);

      // Until fsync is done, notifications will race ahead of sync events
      // We need to keep the local keystore current
      switch (n.operation) {
        case 'update':
          await _updateLocal(n);
          break;
        case 'delete':
          await _deleteLocal(n);
          break;
      }

      if (parts.ancestry.isEmpty) {
        await _handleObjNotificationImpl(n);
      } else {
        await _handleSubObjNotificationImpl(n);
      }
    } catch (e, st) {
      _logger.shout('handleNotification: $e\nStackTrace:\n$st');
    } finally {
      _notificationSubscription.resume();
    }
  }

  Future<void> _updateLocal(AtNotification n) async {
    if (n.metadata == null || n.from == self) {
      return;
    }
    final keyStore = atClient.getLocalSecondary()?.keyStore;
    if (keyStore == null) return;

    var atData = AtData();
    atData.data = n.value;
    atData.metaData = AtMetaData.fromCommonsMetadata(n.metadata!, n.from);
    atData.metaData!.expiresAt = n.metadata!.expiresAt;
    atData.metaData!.availableAt = n.metadata!.availableAt;
    atData.metaData!.isEncrypted = false;
    _logger.info('Updating cached:${n.key}');
    await keyStore.put(
      'cached:${n.key}',
      atData,
      skipCommit: true,
    );
  }

  Future<void> _deleteLocal(AtNotification n) async {
    if (n.from == self) {
      return;
    }
    final keyStore = atClient.getLocalSecondary()?.keyStore;
    if (keyStore == null) return;
    _logger.info('Deleting cached:${n.key}');
    await keyStore.remove('cached:${n.key}', skipCommit: true);
  }

  /// Handles direct-item notifications (a key with exactly the collection
  /// namespace as its suffix) and emits [CItemUpdated] / [CItemDeleted].
  Future<void> _handleObjNotificationImpl(AtNotification n) async {
    final parts = _getPartsFromNotifKey(n);
    switch (n.operation) {
      case 'update':
        _events.add(CItemUpdated(owner: parts.from, id: parts.id));
      case 'delete':
        _events.add(CItemDeleted(owner: parts.from, id: parts.id));
      default:
        _logger.shout(
          'handleObjNotification: No handler for operation ${n.operation}',
        );
    }
  }

  /// Handles notifications for items in a sub-collection at any depth.
  /// The key has the shape
  /// `<id>.<subName_k>.<ancestorId_k>…<subName_1>.<ancestorId_1>.<namespace>@<owner>`
  /// and we emit [CSubItemUpdated] / [CSubItemDeleted] carrying the
  /// full root-to-direct-parent ancestry, so listeners can filter by
  /// any ancestor (id + owner, to disambiguate across atSigns that
  /// may have picked the same id) or by the innermost sub-collection's
  /// `subName`.
  ///
  /// Ancestor ids come from the key; ancestor owners come from the
  /// sub-item's envelope `parents` field. For update events we fetch
  /// the sub-item to read that envelope. For delete events the
  /// sub-item is gone and owners stay null — see
  /// [CSubItemDeleted.ancestry] for the documented behaviour.
  ///
  /// When the innermost sub-collection's subName is the reserved
  /// `__rr` name, we also emit a [CReadReceipt] on top of the
  /// [CSubItemUpdated] so application code can subscribe to read
  /// receipts directly via [readReceipts]. The receipt's `id` is the
  /// direct parent's id (i.e. `ancestry.last.id` — the item being
  /// read).
  Future<void> _handleSubObjNotificationImpl(AtNotification n) async {
    final parts = _getPartsFromNotifKey(n);
    if (parts.ancestry.isEmpty) {
      _logger.info('handleSubObjNotification: empty ancestry ${n.key}');
      return;
    }
    final directParent = parts.ancestry.last;
    switch (n.operation) {
      case 'update':
        // Fetch the sub-item envelope to recover ancestor owners. The
        // get is typically local-cache hot (we were just notified
        // about this key). A malformed / legacy envelope yields a null
        // owner chain which is tolerated lenient-ly.
        List<Atsign>? parentOwners;
        try {
          final k = AtKey.fromString(
            n.key.replaceAll('${n.to}:', ''),
          );
          final v = await atClient.get(k);
          parentOwners = _decodeParentOwners(_decodeEnvelope(v.value!, k));
        } catch (e) {
          _logger.warning(
            'handleSubObjNotification: envelope fetch for ${n.key} '
            'failed: $e — emitting with null ancestor owners',
          );
        }
        _events.add(CSubItemUpdated(
          owner: parts.from,
          id: parts.id,
          ancestry: _zipAncestryOwners(parts.ancestry, parentOwners),
        ));
        if (directParent.subName == _rr) {
          // A __rr sub-item is always shared WITH the parent's owner
          // (that's how receipts reach them). The notification's `to`
          // field therefore identifies the parent's owner — which is
          // what `CReadReceipt.owner` carries, so events can be
          // filtered unambiguously against a specific CItem even when
          // item ids collide across atSigns.
          _events.add(CReadReceipt(
            owner: n.to.toAtsign(),
            id: directParent.id,
            from: parts.from,
            readAt: DateTime.now(),
          ));
        }
      case 'delete':
        _events.add(CSubItemDeleted(
          owner: parts.from,
          id: parts.id,
          ancestry: parts.ancestry,
        ));
      default:
        _logger.shout(
          'handleSubObjNotification: No handler for operation ${n.operation}',
        );
    }
  }

  /// Pairs [ancestry] (ids + subNames from the key) with [ownersFromEnvelope]
  /// (owners from the sub-item's `parents` envelope field) to produce an
  /// owner-enriched ancestry for [CSubItemUpdated]. If [ownersFromEnvelope]
  /// is null (legacy item / failed fetch) or shorter than the ancestry,
  /// missing entries keep `owner: null`.
  List<CAncestor> _zipAncestryOwners(
    List<CAncestor> ancestry,
    List<Atsign>? ownersFromEnvelope,
  ) {
    if (ownersFromEnvelope == null) return ancestry;
    return [
      for (int i = 0; i < ancestry.length; i++)
        CAncestor(
          id: ancestry[i].id,
          subName: ancestry[i].subName,
          owner: i < ownersFromEnvelope.length ? ownersFromEnvelope[i] : null,
        ),
    ];
  }

  /// Walks ancestor collections and emits [CSubItemUpdated] on each
  /// ancestor's `_events` for a sub-item just written locally on this
  /// collection. No-op when this collection is not a sub-collection
  /// (root writes have no ancestors to notify).
  ///
  /// The ancestry slice emitted on each ancestor matches what the
  /// notification path produces when the round-trip arrives — each
  /// ancestor sees only the chain from its own perspective down to
  /// the leaf's direct parent. See [handleSubObjNotification] for the
  /// round-trip equivalent.
  ///
  /// Note: read receipts (`__rr` sub-items) intentionally do NOT
  /// trigger a local [CReadReceipt] emit. CReadReceipt's semantic
  /// meaning is "someone read MY item"; that event fires on the
  /// owner's side via the round-trip. Locally on the reader's side,
  /// the receipt write surfaces only as a [CSubItemUpdated] on the
  /// reader's view (and the recipient round-trip on the owner's side
  /// is what produces the CReadReceipt for the owner).
  void _emitAncestorSubUpdated(CItem<T> item) {
    if (_parentItem == null) return;
    // links built innermost-first; we reverse on emit so each
    // ancestor sees root-first ancestry (matching the notification
    // path).
    final links = <CAncestor>[
      CAncestor(
        id: _parentItem!.id,
        subName: namespace.split('.').first,
        owner: _parentItem!.owner,
      ),
    ];
    AtCollection<dynamic>? cursor = _parentCollection;
    while (cursor != null) {
      cursor._events.add(CSubItemUpdated(
        owner: item.owner,
        id: item.id,
        ancestry: links.reversed.toList(),
      ));
      if (cursor._parentItem == null) break;
      links.add(CAncestor(
        id: cursor._parentItem!.id,
        subName: cursor.namespace.split('.').first,
        owner: cursor._parentItem!.owner,
      ));
      cursor = cursor._parentCollection;
    }
  }

  /// Same shape as [_emitAncestorSubUpdated] but emits
  /// [CSubItemDeleted]. **Better than the round-trip equivalent on
  /// one axis:** the round-trip always carries `null` owners in
  /// `ancestry` because the sub-item's envelope is gone by the time
  /// the notification fires. Locally we still hold every ancestor's
  /// (id, owner) pair on the in-process [CItem] graph, so the local
  /// CSubItemDeleted has fully-populated ancestor owners. Apps that
  /// hand-listen to deletes can take advantage; apps that
  /// match-on-id-only continue to work unchanged.
  void _emitAncestorSubDeleted(CItem<T> item) {
    if (_parentItem == null) return;
    final links = <CAncestor>[
      CAncestor(
        id: _parentItem!.id,
        subName: namespace.split('.').first,
        owner: _parentItem!.owner,
      ),
    ];
    AtCollection<dynamic>? cursor = _parentCollection;
    while (cursor != null) {
      cursor._events.add(CSubItemDeleted(
        owner: item.owner,
        id: item.id,
        ancestry: links.reversed.toList(),
      ));
      if (cursor._parentItem == null) break;
      links.add(CAncestor(
        id: cursor._parentItem!.id,
        subName: cursor.namespace.split('.').first,
        owner: cursor._parentItem!.owner,
      ));
      cursor = cursor._parentCollection;
    }
  }

  _CParts _getPartsFromNotifKey(AtNotification n) {
    String keyName = n.key.replaceAll('${n.to}:', '').replaceAll(n.from, '');
    final ix = keyName.lastIndexOf('.$namespace');
    if (ix >= 0) {
      keyName = keyName.substring(0, ix);
    }
    final parts = keyName.split('.');
    // parts layout by depth (natural order):
    //   L0 root  : [id]                               (length 1)
    //   L1 sub   : [id, subName, parentId]            (length 3)
    //   L2 sub2  : [id, subName, pId, gSubName, gId]  (length 5)
    // General: length = 2*depth + 1. Ancestors are built from the
    // outermost id inward (so the first entry is the root ancestor).
    final ancestry = <CAncestor>[];
    for (int i = parts.length - 1; i >= 2; i -= 2) {
      // parts[i] is an ancestor's id; parts[i-1] is the subName of
      // the sub-collection that contains this ancestor's children
      // (i.e. the child-step toward the current item). Owners are
      // not recoverable from a key — the dispatcher fetches the
      // sub-item's envelope to fill them in for update events.
      ancestry.add(CAncestor(id: parts[i], subName: parts[i - 1]));
    }
    return (
      from: n.from.toAtsign(),
      id: parts.first,
      ancestry: ancestry,
    );
  }

  // ---------------------------------------------------------------------------
  // Event streams

  /// All events from this collection as a single broadcast stream.
  /// For type-filtered access, prefer the typed getters below
  /// ([updates] / [deletes] / [readReceipts] / [subUpdates] /
  /// [subDeletes]) — they avoid an `is`-check in every listener.
  ///
  /// The stream is live and broadcast; multiple listeners are
  /// supported. Unless app code includes an exhaustive `switch` (not
  /// recommended — see [CEvent] doc comment), it should include a
  /// `default: break` branch to stay forward-compatible with future
  /// event types.
  Stream<CEvent> watch() => _events.stream;

  /// Fires when a direct item (at this collection's namespace, depth
  /// 0) is created or updated by any atSign the caller observes —
  /// including this atSign's own writes after they round-trip.
  /// Payload: see [CItemUpdated].
  Stream<CItemUpdated> get updates =>
      watch().where((e) => e is CItemUpdated).cast<CItemUpdated>();

  /// Fires when a direct item is deleted (by its owner or via
  /// cascade-from-parent). Payload: see [CItemDeleted].
  Stream<CItemDeleted> get deletes =>
      watch().where((e) => e is CItemDeleted).cast<CItemDeleted>();

  /// Fires when another atSign posts a read receipt for an item the
  /// caller owns. Reader identity is in [CReadReceipt.from]; the
  /// item being read is identified by `(owner, id)` on the event
  /// itself (same pair as the corresponding [CItem]). Read-receipt
  /// events on your OWN writes aren't fired — you can't receipt your
  /// own items ([CItem.markReadByMe] is a no-op on self-owned items).
  Stream<CReadReceipt> get readReceipts =>
      watch().where((e) => e is CReadReceipt).cast<CReadReceipt>();

  /// Fires for any descendant (sub-collection) item that was created
  /// or updated — at any nesting depth. Use [CSubItemUpdated.ancestry]
  /// to inspect the full root-to-direct-parent chain (each level
  /// carries `id + subName + owner`), or [CSubItemUpdated.subName]
  /// for just the innermost sub-collection name.
  ///
  /// This is the best place to filter with a combined
  /// `(id, owner, subName)` predicate — e.g.
  /// `e.ancestry.last.id == myTodo.id && e.ancestry.last.owner ==
  /// myTodo.owner && e.subName == 'notes'` — because ids alone are
  /// not globally unique across atSigns.
  Stream<CSubItemUpdated> get subUpdates =>
      watch().where((e) => e is CSubItemUpdated).cast<CSubItemUpdated>();

  /// Fires for any descendant (sub-collection) item that was deleted.
  /// On deletes, [CSubItemDeleted.ancestry] has every `owner` set to
  /// `null` — the sub-item is gone so there's no envelope to recover
  /// owner info from. Match on ids alone, or cache the last seen
  /// [CSubItemUpdated] for correlation.
  Stream<CSubItemDeleted> get subDeletes =>
      watch().where((e) => e is CSubItemDeleted).cast<CSubItemDeleted>();

  /// Fires when a scheduled item's `availableAt` time passes —
  /// e.g. an item written with `availableAt: tomorrow` triggers a
  /// [CItemAvailable] tomorrow at that moment. Items with no
  /// `availableAt` (immediately visible) are not tracked.
  ///
  /// On first access to this getter the SDK lazy-starts a scheduler:
  /// scans the current collection, registers every item with a
  /// future `availableAt`, and arms a single shared `Timer` to the
  /// soonest. Subsequent updates / deletes on this collection
  /// reschedule (or unregister) accordingly. The scheduler runs for
  /// the lifetime of the [AtCollection]; cancelling all subscribers
  /// does not stop it.
  ///
  /// Also flows through [watch] alongside the other [CEvent]
  /// subclasses, so a single `switch (event)` listener can handle
  /// it without needing a separate subscription.
  Stream<CItemAvailable> get availableEvents {
    _availableScheduler ??= _CItemTimerScheduler<CItemAvailable, T>(
      collection: this,
      fireAtOf: (item) => item.availableAt,
      makeEvent: (item) => CItemAvailable(
        owner: item.owner,
        id: item.id,
        availableAt: item.availableAt!,
      ),
      emit: _events.add,
      label: 'availableAt',
    )..start();
    return watch().where((e) => e is CItemAvailable).cast<CItemAvailable>();
  }

  /// Returns a stream that fires [CItemExpiringSoon] [leadTime] before
  /// each tracked item's `expiresAt`. Items whose
  /// `expiresAt - leadTime` is already in the past at subscription
  /// time fire on the next event-loop turn so the listener doesn't
  /// silently miss them.
  ///
  /// Single-subscription stream — each call to this method spins up
  /// its own scheduler so different lead times can coexist. Stream
  /// cancellation tears the scheduler down. Wrap with
  /// [Stream.asBroadcastStream] for multi-listener UIs.
  ///
  /// Does **not** flow through [watch] — the lead time is per-
  /// subscription, so emitting it on the master stream would force a
  /// single canonical lead time which is not useful.
  Stream<CItemExpiringSoon> expiringSoonEvents({
    required Duration leadTime,
  }) {
    if (leadTime.isNegative) {
      throw ArgumentError.value(
        leadTime,
        'leadTime',
        'leadTime must be non-negative',
      );
    }
    late final StreamController<CItemExpiringSoon> ctrl;
    late final _CItemTimerScheduler<CItemExpiringSoon, T> scheduler;
    ctrl = StreamController<CItemExpiringSoon>(
      onListen: () {
        scheduler = _CItemTimerScheduler<CItemExpiringSoon, T>(
          collection: this,
          fireAtOf: (item) => item.expiresAt.subtract(leadTime),
          makeEvent: (item) => CItemExpiringSoon(
            owner: item.owner,
            id: item.id,
            expiresAt: item.expiresAt,
            leadTime: leadTime,
          ),
          emit: ctrl.add,
          label: 'expiresAt-$leadTime',
        )..start();
      },
      onCancel: () async {
        await scheduler.dispose();
      },
    );
    return ctrl.stream;
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  /// Parses the `parents` field from a decoded envelope, returning
  /// `null` if the field is absent (legacy data). The result is the
  /// root-first chain of ancestor owners persisted at write time.
  List<Atsign>? _decodeParentOwners(Map<String, dynamic> decoded) {
    final raw = decoded['parents'];
    if (raw == null) return null;
    if (raw is! List) return null;
    return [
      for (final e in raw) (e['owner'] as String).toAtsign(),
    ];
  }

  /// True iff [persisted] (from an envelope's `parents` field) is a
  /// valid match for this collection's expected ancestor-owner chain.
  /// A shorter-than-expected persisted list is a legacy-straggler
  /// mismatch → false.
  bool _ancestryMatches(List<Atsign> persisted) {
    final expected = _expectedAncestorOwners();
    if (persisted.length != expected.length) return false;
    for (int i = 0; i < expected.length; i++) {
      if (persisted[i] != expected[i]) return false;
    }
    return true;
  }

  /// Walks up this collection's parent chain (if it's a sub-collection)
  /// and returns the root-to-direct-parent owner chain. Empty for root
  /// collections. Used by [_put] to emit the `parents` envelope field
  /// and by `_loadItems` to filter sub-collection reads by ancestor
  /// ownership.
  List<Atsign> _expectedAncestorOwners() {
    final owners = <Atsign>[];
    AtCollection<dynamic>? cursor = this;
    while (cursor != null && cursor._parentItem != null) {
      owners.insert(0, cursor._parentItem!.owner);
      cursor = cursor._parentCollection;
    }
    return owners;
  }

  /// Parses ancestor ids out of this collection's composed namespace.
  /// For a root collection, returns `[]`. For a sub-collection whose
  /// composed namespace is `<subName>.<pId>.<rootNs>`, returns
  /// `[pId]`. For a sub-sub-collection `<sub2>.<pId2>.<sub1>.<pId1>.<rootNs>`,
  /// returns `[pId1, pId2]` (root-first, matching [_expectedAncestorOwners]).
  List<String> _ancestorIdsFromNamespace() {
    if (_parentItem == null) return const <String>[];
    // Find the root namespace by walking to the root collection.
    AtCollection<dynamic> cursor = this;
    while (cursor._parentCollection != null) {
      cursor = cursor._parentCollection!;
    }
    final rootNs = cursor.namespace;
    // `namespace` of this (sub-)collection is something like
    // `<subN>.<idN>.<subN-1>.<idN-1>...<sub1>.<id1>.<rootNs>`. Strip
    // the rootNs suffix; the remainder alternates subName / id, with
    // subName first (closest to this level).
    final tail = namespace.substring(0, namespace.length - rootNs.length - 1);
    final parts = tail.split('.');
    // parts layout: [subN, idN, subN-1, idN-1, ..., sub1, id1].
    // Ancestor ids in root-first order: id1, id2, ..., idN.
    final ids = <String>[];
    for (int i = parts.length - 1; i >= 0; i -= 2) {
      ids.add(parts[i]);
    }
    return ids;
  }

  String _newItemId() {
    final buf = StringBuffer();
    for (int i = 0; i < 8; i++) {
      buf.write(_idAlphabet[_rng.nextInt(_idAlphabet.length)]);
    }
    return buf.toString();
  }

  Future<String> _uniqueItemId({int maxAttempts = 10}) async {
    for (int i = 0; i < maxAttempts; i++) {
      final candidate = _newItemId();
      if (!await _selfKeyExists(candidate)) return candidate;
    }
    throw StateError(
      'Could not generate a unique item id in $maxAttempts attempts — '
      'is this collection catastrophically full?',
    );
  }

  Future<bool> _selfKeyExists(String id) async {
    if (_seenSelfIds.contains(id)) return true;
    try {
      await atClient.get(AtKey.fromString('$id.$namespace$atSign'));
      // Populate the cache opportunistically so subsequent calls in
      // this process skip the round-trip too.
      _seenSelfIds.add(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _resolveType(Object? obj) {
    if (obj is Uint8List) return 'binary';
    final entry = _factoriesByType[obj.runtimeType];
    if (entry != null) return entry.tag;
    return 'n/a';
  }

  // Drops a past [availableAt] so rehydrated CItems don't carry a stale
  // schedule. The Atsign Protocol metadata wire format is additive — a past
  // `availableAt` on the server has no mechanism to be cleared by an
  // update, so it may linger indefinitely. Presenting it as null here
  // keeps the app's view consistent with the item's actual state
  // (already available) and prevents the write path from reapplying it.
  static DateTime? _liveAvailableAt(DateTime? v) {
    if (v == null) return null;
    return v.isAfter(DateTime.now()) ? v : null;
  }

  /// Builds the Atsign Protocol [Metadata] for a write derived from
  /// [item]'s `expiresAt` and `availableAt`. Shared between the
  /// self-key and per-recipient writes in [_put] and the
  /// recipient-only writes in [updateSharedWith] so both paths produce
  /// bit-identical metadata.
  ///
  /// Skips `availableAt`/`ttb` when the scheduled time has already
  /// passed — atServer rejects negative `ttb` values, and an item
  /// whose `availableAt` is in the past is already available by
  /// definition. A schedule set by an earlier write therefore persists
  /// harmlessly once it has fired: subsequent writes don't try to
  /// re-schedule it.
  Metadata _buildMetadata(CItem<T> item, DateTime now) {
    final md = Metadata()
      ..ttr = -1
      ..ccd = true
      ..expiresAt = item.expiresAt
      ..ttl = item.expiresAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch
      ..namespaceAware = false;
    if (item.availableAt != null && item.availableAt!.isAfter(now)) {
      md.availableAt = item.availableAt;
      md.ttb =
          item.availableAt!.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    }
    return md;
  }

  /// Decodes a stored value into the CItem JSON envelope, with a
  /// diagnostic [FormatException] if the payload isn't a JSON object
  /// (e.g. legacy pre-refactor `__rr` keys stored a bare numeric
  /// receiptId; `jsonDecode` returns an `int`, and the subsequent
  /// `as Map` cast blows up with a bare `_TypeError`). A typed
  /// [FormatException] is collected cleanly by `_loadItems` as a
  /// per-key error instead of crashing the whole read.
  Map<String, dynamic> _decodeEnvelope(String value, AtKey k) {
    final raw = jsonDecode(value);
    if (raw is! Map<String, dynamic>) {
      throw FormatException(
        'Expected JSON object envelope at ${k.fullKeyAndOwner}, got '
        '${raw.runtimeType}',
      );
    }
    return raw;
  }

  V _rehydrate<V>(Object obj, String type) {
    if (type == 'binary') {
      return Base2e15.decode(obj.toString()) as V;
    }
    final f = _factoriesByTag[type];
    if (f == null) {
      // Tag `n/a` is the synthetic marker for primitives + unregistered
      // objects written by this side; round-tripping a primitive
      // through `obj as V` is the intended path. A non-`n/a` tag with
      // no registered factory means the *writing* side declared a
      // type contract that this reader doesn't share — registry drift,
      // version skew, or a Dart minifier rename if a peer is on a
      // pre-3.13 build that didn't pin `typeTag` explicitly. Surface
      // it once per tag so the developer can register the missing
      // factory; thereafter the silent cast still applies (dynamic /
      // Map<String, dynamic> consumers continue to work).
      if (type != 'n/a' && _warnedMissingFactoryTags.add(type)) {
        _logger.warning(
          'No factory registered for envelope type tag "$type" while '
          'rehydrating into $V. Falling back to a raw cast — typed '
          'access will fail. Register the factory with '
          'AtCollection.registerFactory<YourType>(YourType.fromJson, '
          'typeTag: \'$type\') to close the gap. (Logged once per '
          'unknown tag.)',
        );
      }
      return obj as V;
    }
    return f.call(obj) as V;
  }

  /// Test-only: drops the per-tag dedup set so re-runs of the same
  /// "unknown tag" path emit a fresh warning. The registry itself
  /// is cleared by [_clearFactoriesForTestImpl].
  static void _clearMissingFactoryWarningsForTestImpl() {
    _warnedMissingFactoryTags.clear();
  }

  /// Writes [item] (self + recipient copies) and optionally diff-deletes
  /// recipients that are no longer in `item.sharedWith`. Never throws on
  /// key-level failure — callers that want throwing semantics (like
  /// [create] and [update]) inspect the returned results and raise
  /// [CollectionOpException].
  // TODO(post-stable): expose createBatch / deleteBatch returning
  // List<OpResult> — best-effort batched per-atSign writes built on
  // the same _put primitive. See AtCollection_API_Assessment §11.5.
  Future<List<OpResult>> _put(
    CItem<T> item, {
    bool unshareWithOthers = true,
  }) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not update items owned by other atSigns');
    }
    final now = DateTime.now();
    if (item.expiresAt.millisecondsSinceEpoch < now.millisecondsSinceEpoch) {
      throw ArgumentError('item.expiresAt must be in the future');
    }

    final results = <OpResult>[];
    final selfKey = AtKey.fromString('${item.id}.$namespace$atSign');
    final md = _buildMetadata(item, now);

    // 1. Self copy.
    try {
      selfKey.metadata = md;
      await atClient.put(selfKey, jsonEncode(item.toJson()));
      results.add(OpSuccess(selfKey, CollectionOp.put));
      // Mark this id as "we just wrote it" so a subsequent update()
      // can elide its existence probe. See [_seenSelfIds] doc.
      _seenSelfIds.add(item.id);
      // Local CEvent emission so apps using Query.watch / hand-
      // listened streams see the update synchronously after the
      // local put rather than waiting 1–3 s for the round-trip.
      // The round-trip notification will re-emit the same event
      // when it arrives — Query.watch's delta path is idempotent
      // so UIs redraw once. Hand-listened streams see two
      // callbacks; consumers that care can dedupe by (op, owner,
      // id) over a small window.
      _events.add(CItemUpdated(owner: item.owner, id: item.id));
      _emitAncestorSubUpdated(item);
    } catch (e) {
      results.add(OpFailure(selfKey, CollectionOp.put, e));
    }

    // 2. Diff: delete recipient copies whose atSign is no longer in
    //    item.sharedWith. Retained recipients are overwritten in step 3.
    if (unshareWithOthers) {
      for (final k in await _getKeysInternal(id: item.id, owner: atSign)) {
        final sw = k.sharedWith;
        if (sw == null || sw == atSign) continue;
        if (item.sharedWith.any((a) => a == sw)) continue;
        try {
          await atClient.delete(k);
          results.add(OpSuccess(k, CollectionOp.delete));
        } catch (e) {
          results.add(OpFailure(k, CollectionOp.delete, e));
        }
      }
    }

    // 3. Recipient copies (create or overwrite).
    for (final otherAtSign in item.sharedWith) {
      final k = AtKey.fromString(
        '$otherAtSign:${item.id}.$namespace$atSign',
      );
      try {
        k.metadata = md;
        await atClient.put(k, jsonEncode(item.toJson()));
        results.add(OpSuccess(k, CollectionOp.put));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.put, e));
      }
    }
    return results;
  }

  /// Trimmed [_put] variant: writes only recipient copies, skipping
  /// the self-key write and the unshare-others diff. Used by
  /// [CItem.markReadByMe] — read receipts are pure outbound
  /// notifications, so a self copy at the writer would be storage
  /// waste (the writer never queries their own receipt back).
  ///
  /// Still emits the same local [CItemUpdated] on this collection's
  /// stream and [CSubItemUpdated] on ancestors as [_put] does, so
  /// `Query.watch()` consumers on the writer's side see the recipient
  /// copy land immediately rather than waiting for the round-trip
  /// notification (which never arrives for self-written records).
  ///
  /// Does NOT touch [_seenSelfIds] — no self key was written, so the
  /// "we just wrote this id" cache must not claim otherwise.
  Future<List<OpResult>> _putRecipientsOnly(CItem<T> item) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not send items owned by other atSigns');
    }
    final now = DateTime.now();
    if (item.expiresAt.millisecondsSinceEpoch < now.millisecondsSinceEpoch) {
      throw ArgumentError('item.expiresAt must be in the future');
    }
    final results = <OpResult>[];
    final md = _buildMetadata(item, now);
    for (final otherAtSign in item.sharedWith) {
      final k = AtKey.fromString(
        '$otherAtSign:${item.id}.$namespace$atSign',
      );
      try {
        k.metadata = md;
        await atClient.put(k, jsonEncode(item.toJson()));
        results.add(OpSuccess(k, CollectionOp.put));
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.put, e));
      }
    }
    if (results.any((r) => r is OpSuccess)) {
      _events.add(CItemUpdated(owner: item.owner, id: item.id));
      _emitAncestorSubUpdated(item);
    }
    return results;
  }

  /// Deletes [item] and its recipient copies; if [cascade] is true also
  /// deletes self-owned descendants. Never throws on key-level failure —
  /// [delete] wraps this and raises [CollectionOpException] if any op
  /// failed.
  Future<List<OpResult>> _delete(
    CItem<T> item, {
    bool cascade = false,
  }) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not delete items owned by other atSigns');
    }

    // Expected chain for valid descendants of [item] at this collection
    // level: (this collection's ancestors) + [self]. Id-collision safety:
    // descendants whose key happens to match the regex but whose
    // envelope declares a different ancestor chain (e.g. self's
    // sub-items on a DIFFERENT-owner's same-id parent) are rejected.
    final expectedChainPrefix = <Atsign>[..._expectedAncestorOwners(), self];
    final descendants = await _selfOwnedDescendantKeysFiltered(
      item.id,
      expectedChainPrefix,
    );
    if (descendants.isNotEmpty && !cascade) {
      throw StateError(
        'Cannot delete item ${item.id}: ${descendants.length} self-owned '
        'descendant(s) still exist. Call delete(item, cascade: true) to '
        'also remove them, or delete them explicitly first.',
      );
    }

    final results = <OpResult>[];
    if (cascade) {
      for (final k in descendants) {
        try {
          await atClient.delete(k);
          results.add(OpSuccess(k, CollectionOp.delete));
        } catch (e) {
          results.add(OpFailure(k, CollectionOp.delete, e));
        }
      }
    }
    for (final k in await _getKeysInternal(id: item.id, owner: atSign)) {
      try {
        await atClient.delete(k);
        results.add(OpSuccess(k, CollectionOp.delete));
        // The self-key (no `:`-prefixed recipient atSign in its
        // string form) is the one that gates [_seenSelfIds]. When it
        // goes, drop the cached "exists" mark so a future
        // create()/update() probes correctly. Same gate fires the
        // local CEvent emission — see [_put] for the rationale.
        if (k.sharedWith == null) {
          _seenSelfIds.remove(item.id);
          _events.add(CItemDeleted(owner: item.owner, id: item.id));
          _emitAncestorSubDeleted(item);
        }
      } catch (e) {
        results.add(OpFailure(k, CollectionOp.delete, e));
      }
    }
    return results;
  }

  Future<List<AtKey>> _selfOwnedDescendantKeys(String parentId) async {
    final regex = '(^|:).+\\.$parentId\\.$namespace$atSign';
    return atClient.getAtKeys(regex: regex);
  }

  /// Variant of [_selfOwnedDescendantKeys] that also filters each
  /// candidate by its envelope's `parents` chain. Only descendants
  /// whose `parents` **begins with** [expectedChainPrefix] are kept.
  /// Legacy items lacking the `parents` field pass the filter (lenient
  /// tolerance per the post-implementation tidy-up plan).
  Future<List<AtKey>> _selfOwnedDescendantKeysFiltered(
    String parentId,
    List<Atsign> expectedChainPrefix,
  ) async {
    final raw = await _selfOwnedDescendantKeys(parentId);
    // Fast path: at root-level cascade with no id collision, filter is
    // unnecessary. But we don't know up-front whether a collision
    // exists, so always do the per-key envelope decode. One extra
    // round-trip per candidate; fine at typical scales.
    final keep = <AtKey>[];
    for (final k in raw) {
      try {
        final v = await atClient.get(k);
        final decoded = _decodeEnvelope(v.value!, k);
        final persisted = _decodeParentOwners(decoded);
        if (persisted == null) {
          // Legacy: accept.
          keep.add(k);
          continue;
        }
        if (_startsWith(persisted, expectedChainPrefix)) {
          keep.add(k);
        }
      } catch (e) {
        // Bad envelope / unreadable — err on the side of keeping the
        // candidate (so `prevent` fires rather than silently stranding
        // a malformed descendant). Cascade will try to delete it.
        _logger.warning('descendant envelope decode failed on ${k.key}: $e');
        keep.add(k);
      }
    }
    return keep;
  }

  /// True iff [list] begins with [prefix] (element-wise equality).
  static bool _startsWith<X>(List<X> list, List<X> prefix) {
    if (list.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (list[i] != prefix[i]) return false;
    }
    return true;
  }
}

// -----------------------------------------------------------------------------
// Recursive multi-level sub-collection terminal — [SubSpec] + [TreeNode]
// + [Query.watchWithTree].

/// Immutable description of one level in a sub-collection tree. Used
/// with [Query.watchWithTree] to declare a parent → children → ...
/// shape that the library will live-orchestrate.
///
/// Each [SubSpec] declares the [subName] under which this level lives,
/// the [subDefaultExpiration] for items written through it, and an
/// optional `subFromJson` + `subTypeTag` pair (required together if
/// either is supplied, same rule as [AtCollection.subCollection]).
/// Nested [children] describe further levels deeper in the tree.
///
/// ```dart
/// SubSpec<Comment>(
///   subName: 'comments',
///   subDefaultExpiration: const Duration(days: 30),
///   subFromJson: Comment.fromJson,
///   subTypeTag: 'Comment',
///   children: [
///     SubSpec<Reply>(
///       subName: 'replies',
///       subDefaultExpiration: const Duration(days: 30),
///       subFromJson: Reply.fromJson,
///       subTypeTag: 'Reply',
///     ),
///   ],
/// );
/// ```
final class SubSpec<U> {
  final String subName;
  final Duration subDefaultExpiration;
  final U Function(Map<String, dynamic>)? subFromJson;
  final String? subTypeTag;
  final List<SubSpec<dynamic>> children;

  const SubSpec({
    required this.subName,
    required this.subDefaultExpiration,
    this.subFromJson,
    this.subTypeTag,
    this.children = const [],
  });

  /// Opens this sub-collection on [parent] using the parent collection
  /// [parentColl]'s context. Generic over the parent type [T] but
  /// preserves this spec's own [U] — required when callers iterate a
  /// `List<SubSpec<dynamic>>` and Dart would otherwise erase the
  /// per-element generic, causing the factory auto-register at the
  /// constructor to register `(dynamic, typeTag)` and collide with any
  /// previously-registered `(U, typeTag)` pair.
  ///
  /// Threads [parentColl]'s injected notification stream through so
  /// nested `watchWithTree` recursion sees events from the same test
  /// harness.
  AtCollection<U> _openOnForTest<T>(
    AtCollection<T> parentColl,
    CItem<T> parent,
  ) =>
      parentColl._subCollectionInternal<U>(
        parent: parent,
        subName: subName,
        defaultExpiration: subDefaultExpiration,
        fromJson: subFromJson,
        typeTag: subTypeTag,
        notifications: parentColl._injectedNotifications,
      );
}

/// One node in the snapshot returned by [Query.watchWithTree]. Carries
/// the [parent] [CItem<T>] and the per-sub-collection [branches] —
/// each branch keyed by its [SubSpec.subName] and holding the current
/// list of children at that level (which are themselves [TreeNode]s,
/// recursing all the way down).
///
/// Children are [TreeNode<dynamic>] because Dart's type system can't
/// thread the per-level generic parameter through a heterogeneous
/// recursive structure without codegen. App code that knows the
/// topology can `branches['comments']!.cast<TreeNode<Comment>>()`.
final class TreeNode<T> {
  final CItem<T> parent;
  final Map<String, List<TreeNode<dynamic>>> branches;

  const TreeNode({required this.parent, required this.branches});
}

/// One row in the snapshot returned by [Query.watchWithSub] — a
/// parent [CItem<P>] alongside the current list of its children
/// [CItem<C>] from a single named sub-collection.
///
/// Equivalent to a `(parent, children)` record but a named class so
/// the SDK can add fields in future minor versions without breaking
/// destructuring code at consumer sites.
final class WithChildren<P, C> {
  final CItem<P> parent;
  final List<CItem<C>> children;

  const WithChildren({required this.parent, required this.children});
}

// -----------------------------------------------------------------------------
// Query<T> — fluent, composable, value-typed query over AtCollection<T>.
//
// Complements [AtCollection.getItemsAsStream] with a builder-style API
// you can store, pass around, and terminate with either [Query.get]
// (one-shot List) or [Query.watch] (live reactive Stream). Executes
// on-device over the local synced store — end-to-end encryption means
// the atServer can't filter plaintext on your behalf, so on-device is
// the only correct execution model (see the [AtCollection] class doc).
//
// The spec is captured as a small immutable data object so a future
// indexed executor (SQLite + JSON-field indexes, once that migration
// lands) can introspect individual modifiers and push eligible ones
// down to secondary indexes without changing the caller's code.

/// A composable, value-typed query over an [AtCollection<T>]. Build up
/// a query with [where] / [orderBy] / [thenBy] / [limit] / [skip], then
/// terminate with [get] (one-shot) or [watch] (live reactive).
///
/// ```dart
/// final overdue = todos.query()
///     .where((t) => !t.obj.done)
///     .where((t) => t.obj.due.isBefore(DateTime.now()))
///     .orderBy((t) => t.obj.due)
///     .limit(20);
///
/// final list = await overdue.get();
/// final live = overdue.watch();
/// ```
///
/// Queries are **immutable**: each modifier returns a new [Query].
/// Reuse a built query anywhere; there's no shared mutable state.
///
/// Execution is **on-device**, over the local synced store. Under
/// end-to-end encryption the atServer cannot decrypt the records it
/// holds on your behalf, so on-device is the only correct model —
/// not a performance compromise. See the [AtCollection] class doc for
/// the platform-context details.
///
/// For ad-hoc stream pipelines outside this builder's vocabulary, use
/// [AtCollection.getItemsAsStream] directly with Dart's stream
/// transformers. [Query] complements that path; it does not replace it.
final class Query<T> {
  final AtCollection<T> _collection;
  final _QuerySpec<T> _spec;

  Query._(this._collection, this._spec);

  /// Adds a predicate. Multiple [where] calls AND together —
  /// `q.where(a).where(b)` yields items where both [a] and [b] hold.
  Query<T> where(bool Function(CItem<T> item) predicate) =>
      Query<T>._(_collection, _spec._withPredicate(predicate));

  /// Adds a typed [Predicate] from the [PathField]-based AST. Equivalent
  /// in semantics to [where] (AND'd with any other predicates),
  /// but introspectable: a future indexed executor can walk the tree
  /// and push eligible clauses to a secondary index, while [where]'s
  /// closures stay opaque.
  ///
  /// ```dart
  /// final overdue = await todos.query()
  ///     .wherePath($Todo.done.eq(false))
  ///     .wherePath($Todo.due.lt(DateTime.now()))
  ///     .get();
  ///
  /// // Or compose with .and / .or:
  /// final urgent = await todos.query()
  ///     .wherePath($Todo.done.eq(false).and($Todo.due.lt(soon)))
  ///     .get();
  /// ```
  ///
  /// Co-exists with [where]: both lists are evaluated, AND'd together.
  /// Use [where] for ad-hoc closures; reach for [wherePath] when you'd
  /// like the library to be able to optimise the predicate later.
  Query<T> wherePath(Predicate predicate) =>
      Query<T>._(_collection, _spec._withTypedPredicate(predicate));

  /// Sorts by [keyFn]. A subsequent [orderBy] **replaces** any
  /// previous orderings (matches LINQ / Drift / Isar idiom — call
  /// [thenBy] to add tiebreakers without resetting).
  ///
  /// The key type must implement `compareTo`; [Comparable] is passed
  /// as a raw type so `int`, `double`, `DateTime`, `String`, and any
  /// `Comparable<X>` are all accepted at the call site.
  Query<T> orderBy(
    Comparable<dynamic> Function(CItem<T> item) keyFn, {
    bool descending = false,
  }) =>
      Query<T>._(
        _collection,
        _spec._withOrderBys([_OrderBy<T>(keyFn, descending: descending)]),
      );

  /// Adds a secondary (tiebreaker) sort key. Multiple [thenBy] calls
  /// accumulate, so:
  ///
  /// ```dart
  /// q.orderBy((t) => t.obj.dueDate)
  ///  .thenBy((t) => t.obj.title, descending: true)
  ///  .thenBy((t) => t.createdAt);
  /// ```
  ///
  /// orders by `dueDate`, then within ties by `title` descending,
  /// then within still-ties by `createdAt`. Each level has its own
  /// independent [descending].
  ///
  /// Throws [StateError] when called without a prior [orderBy] —
  /// `thenBy` is a tiebreaker by definition, so it has nothing to
  /// tiebreak against on its own.
  Query<T> thenBy(
    Comparable<dynamic> Function(CItem<T> item) keyFn, {
    bool descending = false,
  }) {
    if (_spec.orderBys.isEmpty) {
      throw StateError(
        'thenBy() requires a prior orderBy(). Call .orderBy(...) first '
        'to establish the primary sort, then chain .thenBy(...) for '
        'tiebreakers.',
      );
    }
    return Query<T>._(
      _collection,
      _spec._withOrderBys([
        ..._spec.orderBys,
        _OrderBy<T>(keyFn, descending: descending),
      ]),
    );
  }

  /// Keeps at most [n] items after filter + sort + skip.
  Query<T> limit(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'limit must be non-negative');
    return Query<T>._(_collection, _spec._withLimit(n));
  }

  /// Skips the first [n] items after filter + sort, before [limit].
  // TODO(post-stable): add Query.startAfter(CItem) cursor pagination
  // for stable scrolling on dynamic data. See
  // AtCollection_API_Assessment §11.5.
  Query<T> skip(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'skip must be non-negative');
    return Query<T>._(_collection, _spec._withSkip(n));
  }

  /// One-shot fetch. Reads the local store once, applies the spec,
  /// returns a list. For a live reactive variant, see [watch].
  ///
  /// Propagates any error from the underlying [AtCollection.getItems]
  /// (e.g. a per-key decode failure). Use [watch] if you need errors
  /// on a live channel instead of a single throw.
  Future<List<CItem<T>>> get() async {
    final all = await _collection.getItems();
    return _spec._apply(all);
  }

  /// Deprecated alias for [get] — keeps existing call-sites compiling
  /// while they migrate. Will be removed in the next minor release.
  @Deprecated('use get() instead — fetch() will be removed in the next minor')
  Future<List<CItem<T>>> fetch() => get();

  /// One-shot fetch with duplicates removed by [keyFn]. The first
  /// matching item per key is kept; subsequent items mapping to the
  /// same key are dropped. Order is the same first-seen order as
  /// [get] — apply [orderBy] / [thenBy] before [distinct] to control
  /// which item wins each key bucket.
  ///
  /// Cheap convenience for "give me one of each X" queries —
  /// equivalent to calling [groupBy] and taking each bucket's first
  /// element, but without materialising the buckets.
  Future<List<CItem<T>>> distinct<K>(K Function(CItem<T> item) keyFn) async {
    final items = await get();
    final seen = <K>{};
    final result = <CItem<T>>[];
    for (final item in items) {
      if (seen.add(keyFn(item))) result.add(item);
    }
    return result;
  }

  /// Number of items matching the full spec (predicates + sort + skip
  /// + limit). Equivalent to `(await get()).length` but makes the
  /// intent explicit at the call site.
  Future<int> count() async => (await get()).length;

  /// True iff at least one item matches the predicates. Short-circuits
  /// on the first match — does **not** apply [orderBy], [skip], or
  /// [limit], because "does anything match?" is independent of
  /// pagination and sort order.
  ///
  /// An optional [predicate] is ANDed with any accumulated [where]
  /// clauses for the check — `q.any((t) => t.obj.done)` reads more
  /// naturally than `q.where((t) => t.obj.done).any()`.
  Future<bool> any([bool Function(CItem<T> item)? predicate]) async {
    await for (final item in _collection.getItemsAsStream()) {
      if (!_spec.predicates.every((p) => p(item))) continue;
      if (!_spec.typedPredicates.every((p) => p.evaluate(item))) continue;
      if (predicate != null && !predicate(item)) continue;
      return true;
    }
    return false;
  }

  /// First item matching the full spec. Throws [StateError] when
  /// nothing matches; see [firstOrNull] for a null-returning variant.
  Future<CItem<T>> first() async {
    final item = await firstOrNull();
    if (item == null) {
      throw StateError('Query.first(): no items match this query');
    }
    return item;
  }

  /// First item matching the full spec, or `null` when nothing
  /// matches.
  ///
  /// If [orderBy] is set on the spec, a full sort is required before
  /// "first" is meaningful — the whole matching set is fetched, sorted
  /// and skipped through before the first item is returned.
  ///
  /// If [orderBy] is unset, "first" means "first-encountered" and the
  /// implementation short-circuits on the stream as soon as a
  /// match is yielded. In that case [limit] is effectively clamped to
  /// 1 for the purposes of this call; [skip] is respected.
  Future<CItem<T>?> firstOrNull() async {
    if (_spec.limitN != null && _spec.limitN! == 0) return null;
    if (_spec.orderBys.isNotEmpty) {
      final list = await get();
      return list.isEmpty ? null : list.first;
    }
    var toSkip = _spec.skipN ?? 0;
    await for (final item in _collection.getItemsAsStream()) {
      if (!_spec.predicates.every((p) => p(item))) continue;
      if (!_spec.typedPredicates.every((p) => p.evaluate(item))) continue;
      if (toSkip > 0) {
        toSkip--;
        continue;
      }
      return item;
    }
    return null;
  }

  /// Groups the matching items by a key derived from each. Runs the
  /// full spec (predicates + sort + skip + limit) before grouping, so
  /// within each bucket items are in the same order [get] would
  /// return.
  ///
  /// ```dart
  /// final byOwner = await todos.query()
  ///     .where((t) => !t.obj.done)
  ///     .groupBy((t) => t.owner);
  /// // byOwner: Map<Atsign, List<CItem<Todo>>>
  /// ```
  Future<Map<K, List<CItem<T>>>> groupBy<K>(
    K Function(CItem<T> item) keyFn,
  ) async {
    final items = await get();
    final out = <K, List<CItem<T>>>{};
    for (final item in items) {
      out.putIfAbsent(keyFn(item), () => <CItem<T>>[]).add(item);
    }
    return out;
  }

  /// Live reactive terminal that joins each parent item matching this
  /// query with its children from a named sub-collection.
  ///
  /// ```dart
  /// final stream = todos.query().where((t) => !t.obj.done)
  ///     .watchWithSub<TodoNote>(
  ///       subName: 'notes',
  ///       subDefaultExpiration: const Duration(days: 365),
  ///       subFromJson: TodoNote.fromJson,
  ///       subTypeTag: 'TodoNote',
  ///     );
  /// // stream: Stream<List<WithChildren<Todo, TodoNote>>>
  /// ```
  ///
  /// Re-emits on any parent update/delete that could affect the
  /// result set, and on any child update/delete within any of the
  /// current parents' `subName` sub-collections. The previous
  /// hand-rolled `Map<parentId, List<child>>` dance in consumer apps
  /// collapses to a single stream subscription with this.
  ///
  /// The returned stream is single-subscription. Each parent held by
  /// the stream owns an internal `.watch()` on its sub-collection;
  /// those child subscriptions are cancelled automatically when the
  /// parent leaves the result set (via filter change or delete) and
  /// when the outer stream is cancelled.
  ///
  /// This is a first-class terminal — implemented in ~80 LOC here
  /// rather than re-invented by every consumer. Phase 2 may add a
  /// child-query parameter so callers can filter / sort the children
  /// too; today the children are the sub-collection's full default
  /// view.
  Stream<List<WithChildren<T, U>>> watchWithSub<U>({
    required String subName,
    required Duration subDefaultExpiration,
    U Function(Map<String, dynamic>)? subFromJson,
    String? subTypeTag,
  }) {
    // Per-parent state. Key is `<owner>:<id>` — the (owner, id) pair
    // under which a CItem is globally unique.
    final childLatest = <String, List<CItem<U>>>{};
    final childSubs = <String, StreamSubscription<List<CItem<U>>>>{};
    List<CItem<T>> latestParents = const [];
    late final StreamController<List<WithChildren<T, U>>> ctrl;
    StreamSubscription<List<CItem<T>>>? parentSub;

    String keyOf(CItem<T> p) => '${p.owner}:${p.id}';

    void emit() {
      if (ctrl.isClosed) return;
      ctrl.add([
        for (final p in latestParents)
          WithChildren<T, U>(
            parent: p,
            children: List<CItem<U>>.from(childLatest[keyOf(p)] ?? const []),
          ),
      ]);
    }

    Future<void> onParents(List<CItem<T>> parents) async {
      latestParents = parents;
      final currentKeys = parents.map(keyOf).toSet();
      // Cancel subs for parents that left the result set.
      final leavers =
          childSubs.keys.where((k) => !currentKeys.contains(k)).toList();
      for (final k in leavers) {
        await childSubs.remove(k)?.cancel();
        childLatest.remove(k);
      }
      // Track whether we opened any new child sub. If we did, skip
      // the explicit emit below — each new sub's initial-fetch
      // emission already calls emit() through its listener, and
      // emitting from both paths produced duplicate snapshots
      // (consumers that did per-snapshot work, e.g. a TUI sending a
      // read-receipt on every new todo, were doing it twice).
      bool openedNewSub = false;
      for (final p in parents) {
        final k = keyOf(p);
        if (childSubs.containsKey(k)) continue;
        // Use the private internal entry point so we can thread the
        // parent collection's injected notification stream (if any)
        // through to the child sub-collection — required for tests
        // that drive both parent and child events from a single
        // controller. Production callers see only the public
        // [subCollection] verb, which has no notifications: param.
        final sub = _collection._subCollectionInternal<U>(
          parent: p,
          subName: subName,
          defaultExpiration: subDefaultExpiration,
          fromJson: subFromJson,
          typeTag: subTypeTag,
          notifications: _collection._injectedNotifications,
        );
        childSubs[k] = sub.query().watch().listen(
          (children) {
            childLatest[k] = children;
            emit();
          },
          onError: (Object e, StackTrace st) {
            if (!ctrl.isClosed) ctrl.addError(e, st);
          },
        );
        openedNewSub = true;
      }
      // No new subs opened (either only leavers, or the parent set
      // is unchanged) — emit now, otherwise no event is delivered
      // for the leaver removal / parent-set churn.
      if (!openedNewSub) {
        emit();
      }
    }

    ctrl = StreamController<List<WithChildren<T, U>>>(
      onListen: () {
        parentSub = watch().listen(
          (parents) => unawaited(onParents(parents)),
          onError: (Object e, StackTrace st) {
            if (!ctrl.isClosed) ctrl.addError(e, st);
          },
        );
      },
      onCancel: () async {
        await parentSub?.cancel();
        for (final s in childSubs.values) {
          await s.cancel();
        }
        childSubs.clear();
        childLatest.clear();
      },
    );
    return ctrl.stream;
  }

  /// Live reactive terminal that joins each parent matching this query
  /// with **multiple levels** of sub-collections, each level described
  /// by a [SubSpec]. Generalises [watchWithSub] to arbitrary depth.
  ///
  /// ```dart
  /// final stream = posts.query()
  ///     .watchWithTree([
  ///       SubSpec<Comment>(
  ///         subName: 'comments',
  ///         subDefaultExpiration: const Duration(days: 30),
  ///         subFromJson: Comment.fromJson,
  ///         subTypeTag: 'Comment',
  ///         children: [
  ///           SubSpec<Reply>(
  ///             subName: 'replies',
  ///             subDefaultExpiration: const Duration(days: 30),
  ///             subFromJson: Reply.fromJson,
  ///             subTypeTag: 'Reply',
  ///           ),
  ///         ],
  ///       ),
  ///     ]);
  /// // stream: Stream<List<TreeNode<Post>>>
  /// // tree[i].parent              → CItem<Post>
  /// // tree[i].branches['comments'] → List<TreeNode<dynamic>> (one per comment)
  /// // tree[i].branches['comments'][j].branches['replies']
  /// //                              → List<TreeNode<dynamic>> (one per reply)
  /// ```
  ///
  /// Re-emits on any change at any level: parent updates/deletes that
  /// affect the result set, plus child / grand-child / ... events
  /// within any open sub-tree. When a parent leaves the result set, the
  /// library cascade-cancels every descendant subscription rooted at
  /// that parent — including transitively. Same on outer-stream
  /// cancellation.
  ///
  /// The returned stream is single-subscription. Wrap with
  /// [Stream.asBroadcastStream] for multi-listener UIs.
  Stream<List<TreeNode<T>>> watchWithTree(List<SubSpec<dynamic>> subSpecs) {
    // Per-parent state, keyed by `<owner>:<id>`:
    //   childSubs[parentKey][subName] = stream subscription on that
    //     sub-collection's recursive watchWithTree (one entry per spec).
    //   childLatest[parentKey][subName] = latest emitted children list.
    final childSubs = <String, Map<String,
        StreamSubscription<List<TreeNode<dynamic>>>>>{};
    final childLatest = <String, Map<String, List<TreeNode<dynamic>>>>{};
    List<CItem<T>> latestParents = const [];
    late final StreamController<List<TreeNode<T>>> ctrl;
    StreamSubscription<List<CItem<T>>>? parentSub;

    String keyOf(CItem<dynamic> p) => '${p.owner}:${p.id}';

    void emit() {
      if (ctrl.isClosed) return;
      ctrl.add([
        for (final p in latestParents)
          TreeNode<T>(
            parent: p,
            branches: Map<String, List<TreeNode<dynamic>>>.from(
              childLatest[keyOf(p)] ?? const {},
            ),
          ),
      ]);
    }

    Future<void> onParents(List<CItem<T>> parents) async {
      latestParents = parents;
      final currentKeys = parents.map(keyOf).toSet();
      // Cascade-cancel subs for parents that left the result set —
      // their entire sub-tree is gone.
      final leavers =
          childSubs.keys.where((k) => !currentKeys.contains(k)).toList();
      for (final k in leavers) {
        final perParent = childSubs.remove(k);
        if (perParent != null) {
          for (final s in perParent.values) {
            await s.cancel();
          }
        }
        childLatest.remove(k);
      }
      // Open subs for newly-arrived parents — one stream per declared
      // [SubSpec].
      for (final p in parents) {
        final k = keyOf(p);
        if (childSubs.containsKey(k)) continue;
        childSubs[k] = {};
        childLatest[k] = {};
        for (final spec in subSpecs) {
          // Use SubSpec._openOnForTest<T>(...) so this spec's own U
          // survives the loop iteration over List<SubSpec<dynamic>> —
          // without it Dart would erase U to dynamic and the
          // constructor's implicit (Type, typeTag) registration would
          // clash with the already-registered (RealType, typeTag)
          // entry.
          final subColl = spec._openOnForTest(_collection, p);
          // Recurse: each child's own children come from a nested
          // watchWithTree on the sub-collection's query. Empty
          // [spec.children] makes the recursion a single-level scan.
          final stream = subColl.query().watchWithTree(spec.children);
          childSubs[k]![spec.subName] = stream.listen(
            (children) {
              childLatest[k]![spec.subName] = children;
              emit();
            },
            onError: (Object e, StackTrace st) {
              if (!ctrl.isClosed) ctrl.addError(e, st);
            },
          );
        }
      }
      emit();
    }

    ctrl = StreamController<List<TreeNode<T>>>(
      onListen: () {
        parentSub = watch().listen(
          (parents) => unawaited(onParents(parents)),
          onError: (Object e, StackTrace st) {
            if (!ctrl.isClosed) ctrl.addError(e, st);
          },
        );
      },
      onCancel: () async {
        await parentSub?.cancel();
        for (final perParent in childSubs.values) {
          for (final s in perParent.values) {
            await s.cancel();
          }
        }
        childSubs.clear();
        childLatest.clear();
      },
    );
    return ctrl.stream;
  }

  /// Live reactive variant. Emits an initial snapshot on first listen,
  /// then re-emits a fresh snapshot whenever an update or delete on
  /// the source collection could affect the result set.
  ///
  /// **Execution shape.** For queries with no `limit` / `skip`, this
  /// terminal maintains a per-stream cached result list and applies
  /// each event as a single-item delta: fetch one item, evaluate
  /// against predicates, insert / replace / remove, re-emit. That
  /// avoids the full-collection re-scan on every event.
  ///
  /// For queries with `limit` or `skip` set, the next-out-of-window
  /// item isn't cached, so the terminal falls back to a full
  /// `fetch()` on each event — same behaviour as before. (Future
  /// option: keep `limit + lookahead` items cached so deltas can
  /// patch the window without a refetch.)
  ///
  /// Per-stream events are serialised via an internal mutex so two
  /// near-simultaneous events can't race on the cached list.
  ///
  /// Listens to the collection's direct-item events ([AtCollection.updates]
  /// and [AtCollection.deletes]) only. Sub-collection events do not
  /// trigger a refresh — query a sub-collection directly for that.
  ///
  /// The returned stream is single-subscription. Wrap with
  /// [Stream.asBroadcastStream] if multiple listeners are required.
  Stream<List<CItem<T>>> watch() {
    StreamSubscription<CItemUpdated>? updSub;
    StreamSubscription<CItemDeleted>? delSub;
    late final StreamController<List<CItem<T>>> controller;

    // Per-stream result cache. Populated on the initial fetch;
    // mutated in place by [onUpdate] / [onDelete]. `null` means
    // "not yet primed" (initial fetch has not completed) — events
    // arriving in that window queue behind the initial fetch via
    // [serialize].
    List<CItem<T>>? cache;

    // Use the delta path only when there's no pagination — see the
    // dartdoc above for the rationale.
    final usesDeltaPath = _spec.limitN == null && _spec.skipN == null;

    bool matchesPredicates(CItem<T> item) {
      for (final p in _spec.predicates) {
        if (!p(item)) return false;
      }
      for (final p in _spec.typedPredicates) {
        if (!p.evaluate(item)) return false;
      }
      return true;
    }

    void resort() {
      if (_spec.orderBys.isEmpty || cache == null) return;
      cache!.sort((a, b) {
        for (final ob in _spec.orderBys) {
          final cmp = ob.keyFn(a).compareTo(ob.keyFn(b));
          if (cmp != 0) return ob.descending ? -cmp : cmp;
        }
        return 0;
      });
    }

    Future<void> refresh() async {
      if (controller.isClosed) return;
      try {
        final snapshot = await get();
        if (!controller.isClosed) {
          cache = [...snapshot];
          controller.add(snapshot);
        }
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    Future<void> onUpdate(Atsign owner, String id) async {
      if (!usesDeltaPath || cache == null) {
        // Pagination, or pre-initial-fetch event: full refetch is the
        // correct fallback.
        return refresh();
      }
      if (controller.isClosed) return;
      CItem<T>? fresh;
      try {
        fresh = await _collection.getOrNull(id, owner);
      } catch (e, st) {
        // Per-item read error — surface, then realign via a full
        // refetch so we don't drift out of sync with the store.
        if (!controller.isClosed) controller.addError(e, st);
        return refresh();
      }
      if (controller.isClosed) return;
      final idx =
          cache!.indexWhere((c) => c.id == id && c.owner == owner);
      final wasInCache = idx >= 0;
      // `fresh == null` here means the item was deleted between the
      // event and the per-item read — treat as a delete, not a
      // negative match.
      final passes = fresh != null && matchesPredicates(fresh);
      if (passes) {
        if (wasInCache) {
          cache![idx] = fresh;
        } else {
          cache!.add(fresh);
        }
        resort();
      } else if (wasInCache) {
        cache!.removeAt(idx);
      } else {
        // Didn't match before, doesn't now — no emission needed.
        return;
      }
      if (!controller.isClosed) {
        controller.add(List<CItem<T>>.from(cache!));
      }
    }

    Future<void> onDelete(Atsign owner, String id) async {
      if (!usesDeltaPath || cache == null) {
        return refresh();
      }
      if (controller.isClosed) return;
      final idx =
          cache!.indexWhere((c) => c.id == id && c.owner == owner);
      if (idx < 0) return; // not in result set, nothing to emit
      cache!.removeAt(idx);
      if (!controller.isClosed) {
        controller.add(List<CItem<T>>.from(cache!));
      }
    }

    // Per-stream serialiser. Chains tasks so events can't interleave
    // across an in-flight single-item fetch — the cache mutation is
    // atomic from the perspective of the next event.
    Future<void> processing = Future<void>.value();
    void serialize(Future<void> Function() task) {
      processing = processing.then((_) => task()).catchError((
        Object e,
        StackTrace st,
      ) {
        if (!controller.isClosed) controller.addError(e, st);
      });
    }

    controller = StreamController<List<CItem<T>>>(
      onListen: () {
        // Subscribe to events BEFORE the initial fetch so an event
        // arriving during the initial fetch is still applied
        // afterwards (the serialiser holds it behind the fetch).
        updSub = _collection.updates.listen((e) {
          serialize(() => onUpdate(e.owner, e.id));
        });
        delSub = _collection.deletes.listen((e) {
          serialize(() => onDelete(e.owner, e.id));
        });
        serialize(refresh);
      },
      onCancel: () async {
        await updSub?.cancel();
        await delSub?.cancel();
        // Drain in-flight work so we don't tear the controller down
        // mid-cache-mutation.
        await processing;
      },
    );
    return controller.stream;
  }
}

// -----------------------------------------------------------------------------
// Predicate AST — typed, introspectable companion to the closure-based
// [Query.where] path. See the [Query.wherePath] terminal for usage.
//
// The AST is an alternative to passing opaque closures to [Query.where]:
// a closure can be *executed* but not *inspected*, which means the
// library can't see "this predicate tests obj.done == false" — just
// "a function". The AST nodes here let a future indexed executor walk
// the tree, push eligible clauses to a secondary index (e.g. SQLite +
// JSON-field indexes once the local store migrates that way), and
// evaluate the rest in memory. Today the AST evaluates entirely in
// memory, like the closure path; the work that lands here is the
// surface that makes future push-down possible without a caller-code
// change.
//
// Shape: [PathField] is a typed accessor (path + extractor). Operators
// on [PathField] mint [Predicate] nodes ([CmpPredicate]); combinators
// on [Predicate] ([AndPredicate], [OrPredicate], [NotPredicate])
// compose them. Concrete leaves and combinators are `final class`
// rather than `sealed` so new node types can land in minor versions
// without breaking downstream `is` chains.

/// A typed, introspectable accessor for one field on a [CItem<T>].
/// Pair with [Query.wherePath] / [PathField.eq] etc. to build a
/// [Predicate] the library can both evaluate and inspect.
///
/// ```dart
/// // Declare once, reuse anywhere.
/// abstract class $Todo {
///   static final done = PathField<bool>(
///     path: ['obj', 'done'],
///     extract: (item) => (item.obj as Todo).done,
///   );
///   static final due = PathField<DateTime>(
///     path: ['obj', 'due'],
///     extract: (item) => (item.obj as Todo).due,
///   );
/// }
///
/// // Use:
/// final overdue = await todos.query()
///     .wherePath($Todo.done.eq(false))
///     .wherePath($Todo.due.lt(DateTime.now()))
///     .get();
/// ```
///
/// [path] is metadata only — it describes which field this accessor
/// reads, in dotted form (e.g. `['obj', 'done']`). It is not consulted
/// at evaluation time; that's [extract]'s job. A future indexed
/// executor uses [path] to decide whether a predicate over this field
/// can be pushed down to a secondary index.
///
/// [extract] is the live evaluator. It is called once per item per
/// predicate eval; keep it allocation-free where possible.
final class PathField<V> {
  final List<String> path;
  final V Function(CItem<dynamic> item) extract;

  const PathField({required this.path, required this.extract});

  /// `field == value`.
  Predicate eq(V value) =>
      CmpPredicate._(this, PredicateOp.eq, value);

  /// `field != value`.
  Predicate neq(V value) =>
      CmpPredicate._(this, PredicateOp.neq, value);
}

/// `<`, `<=`, `>`, `>=` for fields whose value is [Comparable].
extension ComparablePathField<V extends Comparable<dynamic>>
    on PathField<V> {
  Predicate lt(V value) => CmpPredicate._(this, PredicateOp.lt, value);
  Predicate lte(V value) => CmpPredicate._(this, PredicateOp.lte, value);
  Predicate gt(V value) => CmpPredicate._(this, PredicateOp.gt, value);
  Predicate gte(V value) => CmpPredicate._(this, PredicateOp.gte, value);
}

/// Null checks for fields whose declared value type is nullable.
/// Declare the field as `PathField<Foo?>` to opt in.
extension NullablePathField<V extends Object> on PathField<V?> {
  Predicate get isNull => CmpPredicate._(this, PredicateOp.isNull, null);
  Predicate get isNotNull =>
      CmpPredicate._(this, PredicateOp.isNotNull, null);
}

/// Comparison operator carried by a [CmpPredicate]. Stored as a value
/// (rather than encoded in the subclass) so `switch` over op stays
/// exhaustive at evaluation time and indexed-executor pushdown can
/// pattern-match on it.
///
/// The set is **not** truly closed: members [like], [inSet], [between],
/// [contains], and [startsWith] are pre-allocated names for operators
/// that aren't yet implemented in [CmpPredicate.evaluate]. Calling
/// `evaluate` with one throws [UnimplementedError]. They're declared
/// now so adding their implementations later doesn't expand the enum
/// shape (which would force user `switch` statements to refactor).
/// Apps that pattern-match on [PredicateOp] should always include a
/// `default:` branch.
enum PredicateOp {
  eq,
  neq,
  lt,
  lte,
  gt,
  gte,
  isNull,
  isNotNull,
  like,
  inSet,
  between,
  contains,
  startsWith,
}

/// Root of the typed-predicate AST. Mint with the operator methods on
/// [PathField] (e.g. `field.eq(value)`); compose with [and] / [or] /
/// [not]. Pass to [Query.wherePath] to apply.
///
/// Designed for future introspection: a SQLite-indexed local store
/// (planned, see assessment §1a) will be able to walk the tree and
/// translate eligible leaf nodes into `WHERE` clauses backed by JSON-
/// path indexes. Until that landing, all evaluation is in memory and
/// behaviourally identical to a closure passed to [Query.where].
abstract class Predicate {
  /// Evaluates this predicate against [item]. Implementations should
  /// be allocation-free and side-effect-free.
  bool evaluate(CItem<dynamic> item);

  /// Returns a new [Predicate] that holds when both this and [other]
  /// hold. Flattens chains: `a.and(b).and(c)` produces a single
  /// 3-child [AndPredicate], not a nested tree.
  Predicate and(Predicate other) {
    if (this is AndPredicate) {
      return AndPredicate([...(this as AndPredicate).children, other]);
    }
    return AndPredicate([this, other]);
  }

  /// Returns a new [Predicate] that holds when at least one of this or
  /// [other] holds. Flattens chains the same way [and] does.
  Predicate or(Predicate other) {
    if (this is OrPredicate) {
      return OrPredicate([...(this as OrPredicate).children, other]);
    }
    return OrPredicate([this, other]);
  }

  /// Returns the negation. Double-negation collapses: `p.not.not == p`.
  Predicate get not =>
      this is NotPredicate ? (this as NotPredicate).inner : NotPredicate(this);
}

/// Leaf comparison predicate produced by [PathField] operators.
/// Carries the field, op, and value publicly so a future indexed
/// executor can pattern-match.
final class CmpPredicate extends Predicate {
  final PathField<dynamic> field;
  final PredicateOp op;
  final Object? value;

  CmpPredicate._(this.field, this.op, this.value);

  @override
  bool evaluate(CItem<dynamic> item) {
    final actual = field.extract(item);
    switch (op) {
      case PredicateOp.eq:
        return actual == value;
      case PredicateOp.neq:
        return actual != value;
      case PredicateOp.isNull:
        return actual == null;
      case PredicateOp.isNotNull:
        return actual != null;
      case PredicateOp.lt:
      case PredicateOp.lte:
      case PredicateOp.gt:
      case PredicateOp.gte:
        // Both sides null are not orderable; treat as "false" rather
        // than throw, matching SQL `NULL` comparison semantics.
        if (actual == null || value == null) return false;
        final cmp = (actual as Comparable<dynamic>).compareTo(value);
        switch (op) {
          case PredicateOp.lt:
            return cmp < 0;
          case PredicateOp.lte:
            return cmp <= 0;
          case PredicateOp.gt:
            return cmp > 0;
          case PredicateOp.gte:
            return cmp >= 0;
          default:
            throw StateError('unreachable');
        }
      case PredicateOp.like:
      case PredicateOp.inSet:
      case PredicateOp.between:
      case PredicateOp.contains:
      case PredicateOp.startsWith:
        throw UnimplementedError(
          'PredicateOp.${op.name} is reserved but not yet implemented.',
        );
    }
  }
}

/// Conjunction. All children must hold. Flattens on construction via
/// [Predicate.and] so chains don't build a left-leaning tree.
final class AndPredicate extends Predicate {
  final List<Predicate> children;

  AndPredicate(this.children);

  @override
  bool evaluate(CItem<dynamic> item) =>
      children.every((p) => p.evaluate(item));
}

/// Disjunction. At least one child must hold. Flattens via
/// [Predicate.or].
final class OrPredicate extends Predicate {
  final List<Predicate> children;

  OrPredicate(this.children);

  @override
  bool evaluate(CItem<dynamic> item) =>
      children.any((p) => p.evaluate(item));
}

/// Negation. Double-negation collapses via [Predicate.not].
final class NotPredicate extends Predicate {
  final Predicate inner;

  NotPredicate(this.inner);

  @override
  bool evaluate(CItem<dynamic> item) => !inner.evaluate(item);
}

/// Immutable spec for a [Query<T>]. Kept as data (not just closures)
/// so a future indexed executor can introspect the modifiers — e.g.
/// push eligible predicates to SQLite JSON indexes while evaluating
/// the rest in memory.
final class _QuerySpec<T> {
  final List<bool Function(CItem<T>)> predicates;
  /// Typed-AST predicates (parallel to [predicates]). Both lists are
  /// AND'd together at evaluation time. The library currently
  /// evaluates these in memory; introspection is enabled for a future
  /// indexed executor.
  final List<Predicate> typedPredicates;
  // Ordered list of sort keys, primary first. Empty = no sort. Multi-
  // entry compares are evaluated in registration order, falling
  // through on ties — see [_apply].
  final List<_OrderBy<T>> orderBys;
  final int? skipN;
  final int? limitN;

  const _QuerySpec({
    this.predicates = const [],
    this.typedPredicates = const [],
    this.orderBys = const [],
    this.skipN,
    this.limitN,
  });

  _QuerySpec<T> _withPredicate(bool Function(CItem<T>) p) => _QuerySpec<T>(
        predicates: [...predicates, p],
        typedPredicates: typedPredicates,
        orderBys: orderBys,
        skipN: skipN,
        limitN: limitN,
      );

  _QuerySpec<T> _withTypedPredicate(Predicate p) => _QuerySpec<T>(
        predicates: predicates,
        typedPredicates: [...typedPredicates, p],
        orderBys: orderBys,
        skipN: skipN,
        limitN: limitN,
      );

  _QuerySpec<T> _withOrderBys(List<_OrderBy<T>> os) => _QuerySpec<T>(
        predicates: predicates,
        typedPredicates: typedPredicates,
        orderBys: os,
        skipN: skipN,
        limitN: limitN,
      );

  _QuerySpec<T> _withSkip(int n) => _QuerySpec<T>(
        predicates: predicates,
        typedPredicates: typedPredicates,
        orderBys: orderBys,
        skipN: n,
        limitN: limitN,
      );

  _QuerySpec<T> _withLimit(int n) => _QuerySpec<T>(
        predicates: predicates,
        typedPredicates: typedPredicates,
        orderBys: orderBys,
        skipN: skipN,
        limitN: n,
      );

  List<CItem<T>> _apply(List<CItem<T>> items) {
    var out = items;
    for (final p in predicates) {
      out = out.where(p).toList();
    }
    for (final p in typedPredicates) {
      out = out.where(p.evaluate).toList();
    }
    if (orderBys.isNotEmpty) {
      out = [...out]..sort((a, b) {
          for (final ob in orderBys) {
            final cmp = ob.keyFn(a).compareTo(ob.keyFn(b));
            if (cmp != 0) return ob.descending ? -cmp : cmp;
          }
          return 0;
        });
    }
    if (skipN != null && skipN! > 0) {
      out = out.skip(skipN!).toList();
    }
    if (limitN != null) {
      out = out.take(limitN!).toList();
    }
    return out;
  }
}

final class _OrderBy<T> {
  final Comparable<dynamic> Function(CItem<T>) keyFn;
  final bool descending;

  const _OrderBy(this.keyFn, {required this.descending});
}

// -----------------------------------------------------------------------------
// Timer-driven event scheduler used by [AtCollection.availableEvents]
// and [AtCollection.expiringSoonEvents] (W7). Maintains a sorted list
// of upcoming firings and a single shared `Timer` armed to the
// soonest. Items are registered on the initial `getItems()` scan and
// kept current via the collection's [updates] / [deletes] streams.
//
// The scheduler is generic over the event type [E] and the
// collection's domain type [T], parameterised by:
//   - [fireAtOf]: when the event should fire for an item (returning
//     null skips registration).
//   - [makeEvent]: builds the event payload from the item.
//   - [emit]: receives the built event.
//
// Uses a plain sorted list for the firings — O(N) insert/remove is
// fine at the scales AtCollection targets (low thousands of items
// with a future fire time at any one moment). A heap or
// SplayTreeMap would give O(log N) and is a straightforward swap if
// a real workload ever needs it.

final class _Firing<E> {
  final DateTime fireAt;
  final Atsign owner;
  final String id;
  final E event;

  const _Firing(this.fireAt, this.owner, this.id, this.event);
}

final class _CItemTimerScheduler<E extends CEvent, T> {
  final AtCollection<T> collection;

  /// Returns when the event should fire for [item], or null if the
  /// item shouldn't be tracked (no `availableAt` / already past).
  final DateTime? Function(CItem<T> item) fireAtOf;

  /// Builds the event payload from the item that just fired.
  final E Function(CItem<T> item) makeEvent;

  /// Receives each emitted event. Wired to the master `_events`
  /// controller for `availableEvents`, or to a per-stream controller
  /// for `expiringSoonEvents`.
  final void Function(E event) emit;

  /// Diagnostic label, surfaced in log lines so it's clear which
  /// scheduler (`availableAt` vs `expiresAt-leadTime`) is firing.
  final String label;

  // Sorted ascending by fireAt.
  final List<_Firing<E>> _firings = [];
  Timer? _timer;
  StreamSubscription<CItemUpdated>? _updSub;
  StreamSubscription<CItemDeleted>? _delSub;
  bool _started = false;
  bool _disposed = false;

  _CItemTimerScheduler({
    required this.collection,
    required this.fireAtOf,
    required this.makeEvent,
    required this.emit,
    required this.label,
  });

  /// Begins tracking. Idempotent: a second call is a no-op so the
  /// `availableEvents` getter can call it on every access without
  /// caring whether a previous call already started it.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Listen BEFORE the initial fetch so an event arriving during
    // the scan is still captured and applied afterwards.
    _updSub = collection.updates.listen((e) {
      unawaited(_onUpdate(e.owner, e.id));
    });
    _delSub = collection.deletes.listen((e) {
      _onDelete(e.owner, e.id);
    });
    unawaited(_initialPopulate());
  }

  Future<void> _initialPopulate() async {
    try {
      final items = await collection.getItems();
      if (_disposed) return;
      for (final item in items) {
        _registerForItem(item);
      }
      _scheduleNext();
    } catch (_) {
      // Read errors are surfaced through the collection's existing
      // error channels (e.g. the [CollectionGetException] path).
      // The scheduler itself doesn't need to crash — items written
      // after this point will register normally via the
      // updates/deletes hooks.
    }
  }

  void _registerForItem(CItem<T> item) {
    final fireAt = fireAtOf(item);
    if (fireAt == null) return;
    // Past timestamps fire on the next event-loop turn so the
    // listener doesn't silently miss them.
    final clamped = fireAt.isAfter(DateTime.now())
        ? fireAt
        : DateTime.now();
    final firing = _Firing<E>(clamped, item.owner, item.id, makeEvent(item));
    _insertSorted(firing);
  }

  void _insertSorted(_Firing<E> f) {
    // Linear insert — O(N). At scales of "thousands of pending
    // firings" this is well below per-event Timer overhead.
    int i = 0;
    while (i < _firings.length && !_firings[i].fireAt.isAfter(f.fireAt)) {
      i++;
    }
    _firings.insert(i, f);
  }

  void _removeByOwnerId(Atsign owner, String id) {
    _firings.removeWhere((f) => f.owner == owner && f.id == id);
  }

  /// Arms the [Timer] to the soonest pending firing. Cancels the
  /// previous timer first; safe to call after every mutation.
  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _firings.isEmpty) return;
    final now = DateTime.now();
    final soonest = _firings.first.fireAt;
    final wait = soonest.isAfter(now) ? soonest.difference(now) : Duration.zero;
    _timer = Timer(wait, _onFire);
  }

  void _onFire() {
    if (_disposed) return;
    final now = DateTime.now();
    // Drain every firing whose fireAt has now passed (a single Timer
    // event may cover multiple co-scheduled items).
    while (_firings.isNotEmpty && !_firings.first.fireAt.isAfter(now)) {
      final f = _firings.removeAt(0);
      try {
        emit(f.event);
      } catch (e, st) {
        collection._logger.warning(
          '$label scheduler: emit threw for (${f.owner}, ${f.id}): $e\n$st',
        );
      }
    }
    _scheduleNext();
  }

  Future<void> _onUpdate(Atsign owner, String id) async {
    if (_disposed) return;
    // Drop any pending firing for this (owner, id) — the new item's
    // `availableAt` / `expiresAt` may differ.
    _removeByOwnerId(owner, id);
    try {
      final fresh = await collection.getOrNull(id, owner);
      if (_disposed) return;
      if (fresh != null) {
        _registerForItem(fresh);
      }
    } catch (_) {
      // Read failure on a single id — surface the fact to logs but
      // don't tear the scheduler down. The next event will retry
      // implicitly.
      collection._logger.warning(
        '$label scheduler: getOrNull failed for ($owner, $id); '
        'item will not fire until a subsequent update succeeds',
      );
    }
    _scheduleNext();
  }

  void _onDelete(Atsign owner, String id) {
    if (_disposed) return;
    _removeByOwnerId(owner, id);
    _scheduleNext();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _updSub?.cancel();
    await _delSub?.cancel();
    _firings.clear();
  }
}

// -----------------------------------------------------------------------------
// CItem

/// A single typed record in an [AtCollection]. Wraps an application's
/// domain object of type [T] together with Atsign Protocol object metadata:
///
/// - **[owner]** — the atSign that wrote this item. Only the owner can
///   mutate or delete it; other atSigns see read-only cached copies.
///   `item.owner == item.self` is the ownership test the library uses
///   internally.
///
/// - **[id]** — a per-owner unique identifier (not globally unique).
///   Alice and Bob can each have an item with id `abc` — they're
///   distinct records. Combine `(owner, id)` to identify an item
///   globally.
///
/// - **[obj]** — the app-defined payload. For collections whose `T` is
///   registered via [AtCollection.registerFactory], incoming envelopes
///   are rehydrated into typed instances.
///
/// - **[sharedWith]** — the distribution list: atSigns who each receive
///   their own cached copy of this item. Mutable — edit it then call
///   [AtCollection.update] to persist the diff.
///
/// - **[createdAt] / [expiresAt] / [availableAt]** — lifecycle
///   timestamps. [expiresAt] is mutable (the owner can extend or
///   shorten an item's TTL); [availableAt] schedules recipient-copy
///   visibility (time-to-birth).
///
/// - **[readBy]** / **[readBySnapshot]** / **[wasMarkedReadByMe]** /
///   **[markReadByMe]** — the read-receipt surface. See the
///   [AtCollection] class-level doc for the receipt model overview.
///
/// Construction is always via [AtCollection.draft] or
/// [AtCollection.create]; the constructor is private so every CItem
/// is bound to a collection it can delegate to for reads, sub-
/// collection resolution, and event streaming.
///
/// **Mutability.** [sharedWith], [expiresAt], and [availableAt] are
/// intentionally mutable so the natural "fetch, mutate, persist"
/// idiom works without a separate copy step. Mutate them in place,
/// then call [AtCollection.update] to persist. Internally [obj] is
/// also assigned-to during rehydrate; app code should treat the
/// rehydrated value as the canonical state and not mutate the
/// rehydrated [obj] reference itself — model objects implement
/// `toJson` / `fromJson` and the round-trip is the supported path.
final class CItem<T> {
  /// The atSign which created this [CItem]. For example if we are
  /// currently `@alice`, then the owner of a [CItem] which we create is
  /// `@alice`; the owner of a [CItem] shared with us by `@bob` is `@bob`.
  final Atsign owner;

  /// The unique identifier, prepended to the collection's namespace when
  /// persisted. E.g. if the collection namespace is `todos.my_apps` then
  /// the full persisted key prefix is `<id>.todos.my_apps`.
  final String id;

  /// The type-tag that drives rehydration. Set automatically by [draft]
  /// from `obj.runtimeType.toString()` when a factory is registered,
  /// otherwise `'binary'` for [Uint8List] or `'n/a'` for primitives.
  late final String type;

  /// The application's domain object.
  final T obj;

  /// atSigns who receive a copy of this item. Mutable; edit then call
  /// [AtCollection.update] to persist.
  final Set<Atsign> sharedWith;

  /// When this item was first written. Set by [AtCollection.draft] for
  /// new items; read from server metadata on rehydrate.
  DateTime createdAt;

  /// Wall-clock expiry. Mutate before calling [AtCollection.update] to
  /// change the item's lifecycle.
  DateTime expiresAt;

  /// Earliest moment at which recipient copies become visible. `null`
  /// means "visible immediately". Mutate before calling
  /// [AtCollection.update] to schedule.
  DateTime? availableAt;

  /// The collection that minted this item. Used internally to resolve
  /// the item's `__rr` sub-collection for read-receipt queries.
  final AtCollection<T> _collection;

  /// Root-to-direct-parent owner chain persisted in the envelope.
  /// Empty for items in a root collection. Length equals the item's
  /// nesting depth for items in a sub-collection. Owner at index `i`
  /// is the ancestor at nesting level `i` (root-most first).
  ///
  /// Ids of ancestors are not duplicated here — they're recoverable
  /// from the item's key via the sub-collection's composed
  /// namespace. See [ancestors] for the combined (owner, id) view.
  final List<Atsign> parentOwners;

  CItem._({
    required this.owner,
    required this.id,
    required this.type,
    required this.obj,
    required this.sharedWith,
    required this.createdAt,
    required this.expiresAt,
    required this.availableAt,
    required AtCollection<T> collection,
    List<Atsign>? parentOwners,
  })  : _collection = collection,
        parentOwners = parentOwners ?? const <Atsign>[] {
    if (obj is Uint8List && type != 'binary') {
      throw ArgumentError('type for Uint8List must be "binary"');
    }
  }

  Map<String, dynamic> toJson() {
    final base = type == 'binary'
        ? <String, dynamic>{
            'type': type,
            'obj': Base2e15.encode(obj as Uint8List),
          }
        : <String, dynamic>{'type': type, 'obj': obj};
    if (parentOwners.isNotEmpty) {
      base['parents'] = [
        for (final o in parentOwners) {'owner': o.toString()}
      ];
    }
    return base;
  }

  @override
  String toString() => 'CItem{owner: $owner, sharedWith: $sharedWith,'
      ' id: $id, type: $type, obj: ${obj.runtimeType},'
      ' expiresAt: $expiresAt, availableAt: $availableAt}';

  /// The atSign this item's collection is acting as — delegates to
  /// [AtCollection.self]. Useful for ownership checks:
  /// `item.owner == item.self` means "I own this item".
  Atsign get self => _collection.self;

  /// Root-to-direct-parent chain for a sub-collection item. Empty for
  /// items in a root collection. Each entry combines the
  /// envelope-persisted [parentOwners] at the same index with the id
  /// of that ancestor, which is recovered from the sub-collection's
  /// composed namespace.
  ///
  /// If [parentOwners] is empty but the collection's namespace shows
  /// this item lives at depth ≥ 1 (legacy data written before the
  /// `parents` envelope field was added), owners fall back to this
  /// item's own [owner] — same lenient assumption applied throughout
  /// the codebase for backward compatibility.
  List<({Atsign owner, String id})> get ancestors {
    final ids = _collection._ancestorIdsFromNamespace();
    if (ids.isEmpty) return const <({Atsign owner, String id})>[];
    // Pair owners to ids, falling back to [owner] for any missing
    // entries in the envelope (legacy items).
    return [
      for (int i = 0; i < ids.length; i++)
        (
          owner: i < parentOwners.length ? parentOwners[i] : owner,
          id: ids[i],
        ),
    ];
  }

  // Lazy, event-maintained reader cache. `null` until the first load;
  // mutex-protected to serialise concurrent callers; subscribed to the
  // parent collection's `readReceipts` stream so arrivals append in-place.
  Set<Atsign>? _readers;
  final Mutex _readersLoadMutex = Mutex();
  StreamSubscription<CReadReceipt>? _readReceiptSub;

  // Serialises concurrent [markReadByMe] callers on this CItem so two
  // overlapping callers don't both reach _put and issue duplicate
  // wire writes for the same (owner, id) receipt. Cross-CItem-instance
  // racing is still resolved by the deterministic receipt id + the
  // duplicate-id guard in [AtCollection.create] — this mutex just
  // avoids the wasted round-trip on the common single-instance path.
  final Mutex _markReadByMeMutex = Mutex();

  // Cancel per-CItem read-receipt subscriptions when the CItem is GC'd
  // (CItems churn on every refreshTodos-style loop; we'd leak otherwise).
  static final Finalizer<StreamSubscription> _subFinalizer =
      Finalizer<StreamSubscription>((sub) => sub.cancel());

  /// The set of atSigns known to have read this item.
  ///
  /// First access triggers a one-shot load from the reserved `__rr`
  /// sub-collection. After that, incoming `CReadReceipt` events on the
  /// parent collection (targeting this item) append into the cached
  /// set, so subsequent `readBy` calls are O(1) and always current.
  ///
  /// Works regardless of who owns the item — if I own it, receipts
  /// from readers (who shared with me) populate the set; if I'm a
  /// reader of someone else's item, my own receipt populates the set
  /// (since my own `__rr` self-copy is on my atServer).
  ///
  /// For synchronous UI rendering after an `await readBy` prime, see
  /// [readBySnapshot].
  Future<Set<Atsign>> get readBy async {
    await _readersLoadMutex.protect(() async {
      if (_readers != null) return;
      // Subscribe BEFORE the fetch so events arriving during the I/O
      // are not lost. Initialise the set synchronously so the listener
      // has somewhere to append.
      final readers = <Atsign>{};
      _readers = readers;
      // Filter on BOTH id and owner — item ids are unique per-atSign
      // only. If two atSigns each happen to own an item with id 't1',
      // an event for one must not cross-pollinate the other CItem's
      // readers set. See `CReadReceipt.owner` — it carries the parent
      // item's owner, set from the notification's `to` field in
      // `handleSubObjNotification`.
      _readReceiptSub = _collection.readReceipts
          .where((e) => e.id == id && e.owner == owner)
          .listen((e) => readers.add(e.from));
      _subFinalizer.attach(this, _readReceiptSub!, detach: this);
      // Chain `.handleError` on the __rr sub-collection stream so a
      // single malformed receipt (e.g. legacy pre-refactor record
      // with a bare-numeric value) doesn't poison this whole load.
      // `getItemsAsStream` yields decode errors into the stream; we
      // swallow them HERE because `readBy` is a best-effort cache —
      // missing one reader is far preferable to crashing every read
      // path that touches the cache (including ownership checks via
      // `wasMarkedReadByMe`).
      final rr = _collection.readReceiptsFor(this);
      final tolerant = rr.getItemsAsStream().handleError((Object e) {
        _collection._logger.warning('readBy: skipping __rr decode error: $e');
      });
      await for (final receipt in tolerant) {
        readers.add(receipt.owner);
      }
    });
    return UnmodifiableSetView(_readers!);
  }

  /// Synchronous accessor for the cached reader set; useful for UI
  /// draw loops that can't await. Returns an empty set until the first
  /// `await item.readBy` has primed the cache. Event-driven updates
  /// keep this in sync thereafter.
  Set<Atsign> get readBySnapshot =>
      _readers == null ? const <Atsign>{} : UnmodifiableSetView(_readers!);

  /// True iff the current atSign ([self]) has already posted a read
  /// receipt for this item. Returns true for self-owned items (the
  /// owner is trivially "caught up" on their own record).
  Future<bool> wasMarkedReadByMe() async {
    if (owner == self) return true;
    return (await readBy).contains(self);
  }

  /// Idempotent: if the current atSign has already posted a read
  /// receipt for this item, does nothing. Otherwise writes a
  /// recipient-only receipt sub-item shared with [owner]. No-op on
  /// self-owned items.
  ///
  /// Receipts are recipient-only: no self copy is written on the
  /// reader's side. The recipient form alone (cached locally as
  /// `<owner>:r.__rr.<itemId>.<...>@<self>`) is enough to:
  ///   - deliver the receipt to the item's owner via the
  ///     standard sharedWith propagation, and
  ///   - keep [wasMarkedReadByMe] returning true on subsequent
  ///     calls, because [AtCollection.getItemsAsStream]'s key regex
  ///     matches the recipient form too and surfaces the writer
  ///     (this atSign) as a reader.
  ///
  /// Concurrent callers on the same [CItem] instance serialise via
  /// [_markReadByMeMutex]; once one call has written the receipt,
  /// subsequent callers see [_readers] containing [self] and return
  /// without writing. Cross-instance races (two CItem instances for
  /// the same logical record) resolve to the same recipient key so
  /// the second `put` overwrites the first idempotently.
  Future<void> markReadByMe() async {
    if (owner == self) return;
    await _markReadByMeMutex.protect(() async {
      if (await wasMarkedReadByMe()) return;
      final rr = _collection.readReceiptsFor(this);
      // Receipt id is the fixed string 'r'. Single-char is enough
      // because there is only ever one receipt per (reader, item)
      // pair and the owner half of the AtCollection (owner, id)
      // identity already disambiguates per-reader: the same id 'r'
      // from two readers (@alice and @charlie) lands at two distinct
      // recipient-copy keys via their differing self-atSign suffixes
      // (`<itemOwner>:r.__rr.<id>.<ns>@alice` vs `…@charlie`).
      // Picking the shortest legible mnemonic ('r' for "receipt")
      // also returns bytes to the 128-char composed-namespace
      // budget that deeply-nested subCollection chains share.
      final receipt = rr.draft(
        obj: {'readAt': DateTime.now().toUtc().toIso8601String()},
        id: 'r',
        sharedWith: {owner},
      );
      final results = await rr._putRecipientsOnly(receipt);
      if (results.any((r) => r is OpFailure)) {
        throw CollectionOpException(results);
      }
      // Patch the in-process readers cache so a subsequent
      // wasMarkedReadByMe on this CItem instance returns true even
      // if the cache was primed before the receipt was written.
      // Across process restarts the cache re-primes from the local
      // store (which has the recipient copy) and arrives at the
      // same answer.
      _readers?.add(self);
    });
  }

  /// Shortcut for [AtCollection.readReceiptsFor] on this item — the
  /// reserved `__rr` sub-collection holding receipts. Use this when
  /// you want to query receipts directly (e.g. live counts, custom UI
  /// over the receipt timeline):
  ///
  /// ```dart
  /// final unreadCount = item.receipts.query().watch().map((l) => l.length);
  /// final readers = await item.receipts.query().get();
  /// ```
  AtCollection<Map<String, dynamic>> get receipts =>
      _collection.readReceiptsFor(this);
}

// -----------------------------------------------------------------------------
// Operation results & exceptions

enum CollectionOp { put, delete }

abstract base class OpResult {
  final AtKey atKey;
  final CollectionOp op;

  OpResult(this.atKey, this.op);
}

final class OpSuccess extends OpResult {
  OpSuccess(super.atKey, super.op);

  @override
  String toString() => '$atKey:${op.name}:Success';
}

final class OpFailure extends OpResult {
  final Object reason;

  OpFailure(super.atKey, super.op, this.reason);

  @override
  String toString() => '$atKey:${op.name}:Failure:$reason';
}

/// Thrown by [AtCollection.create] / [AtCollection.update] /
/// [AtCollection.delete] when any key-level op failed. Inspect [results]
/// for the per-key breakdown, or [failures] / [firstFailure] for the
/// subset that went wrong.
final class CollectionOpException implements Exception {
  final List<OpResult> results;

  CollectionOpException(this.results);

  List<OpFailure> get failures => results.whereType<OpFailure>().toList();

  OpFailure? get firstFailure => failures.isEmpty ? null : failures.first;

  @override
  String toString() =>
      'CollectionOpException with ${failures.length} failure(s):\n'
      '  ${failures.join('\n  ')}';
}

/// Multi-line human-readable dump of a [CItem] — useful for
/// example-app logging and debugging. Reads at the call site as
/// `item.prettyString`.
extension CItemPrettyString on CItem<dynamic> {
  String get prettyString {
    final base = '$id.${_collection.namespace}$owner'
        '\n\tsharedWith: $sharedWith'
        '\n\texpiresAt: $expiresAt'
        '\n\tavailableAt: $availableAt'
        '\n\ttype: $type'
        '\n\truntimeType: ${obj.runtimeType}';
    if (type == 'binary') {
      return '$base\n\tlength: ${obj.length} bytes';
    }
    return '$base\n\tobj: $obj';
  }
}

// -----------------------------------------------------------------------------
// Events

/// Base class for everything emitted on an [AtCollection]'s event streams.
///
/// **Not `sealed`** — new event subtypes are expected to be added in
/// future minor-version releases (e.g. `CItemAvailable`,
/// `CItemExpiringSoon`). Apps that `switch` on event type should always
/// include a `default:` branch so a new event is a non-event rather
/// than a broken build:
///
/// ```dart
/// collection.watch().listen((event) {
///   switch (event) {
///     case CItemUpdated():    onUpdate(event); break;
///     case CItemDeleted():    onDelete(event); break;
///     case CReadReceipt():    onReceipt(event); break;
///     default:                break; // unknown / future event
///   }
/// });
/// ```
///
/// [owner] + [id] identify the subject of the event — typically a
/// [CItem], matching that item's `owner` + `id`. Individual subclasses
/// may refine what `id` refers to (e.g. for [CSubItemUpdated], `id` is
/// the sub-item's own id and [CSubItemUpdated.ancestry] carries its
/// chain).
abstract class CEvent {
  final Atsign owner;
  final String id;

  CEvent({required this.owner, required this.id});
}

/// Fires when a remote atSign posts a receipt for an item we can
/// observe. [owner] + [id] identify the PARENT item being read (the
/// thing the receipt is about — not the receipt sub-item itself), so
/// they match the `owner` + `id` of the corresponding [CItem].
/// [from] is the reader; [readAt] is the moment the notification was
/// received (not the moment the reader wrote it).
final class CReadReceipt extends CEvent {
  final Atsign from;
  final DateTime readAt;

  CReadReceipt({
    required super.owner,
    required super.id,
    required this.from,
    required this.readAt,
  });
}

final class CItemUpdated extends CEvent {
  CItemUpdated({required super.owner, required super.id});
}

final class CItemDeleted extends CEvent {
  CItemDeleted({required super.owner, required super.id});
}

/// Fires when a scheduled item's `availableAt` time passes — i.e. an
/// item written with `availableAt` in the future has just become
/// visible on the wire. Carries the item's [owner] + [id] so the
/// listener can refetch it via [AtCollection.getOrNull].
///
/// Surfaced via [AtCollection.availableEvents] and [AtCollection.watch].
/// Items written with no `availableAt`, or with an `availableAt` in
/// the past, are not tracked. Cancelling the last subscriber to
/// [AtCollection.availableEvents] does not stop the scheduler — it
/// runs for the lifetime of the [AtCollection], so a re-subscription
/// later still sees the same firings.
final class CItemAvailable extends CEvent {
  /// The scheduled `availableAt` that just passed. Equal to or
  /// fractionally before `DateTime.now()` at emission time.
  final DateTime availableAt;

  CItemAvailable({
    required super.owner,
    required super.id,
    required this.availableAt,
  });
}

/// Fires [leadTime] before an item's `expiresAt`. Useful for
/// reminder / alarm UIs that need to nudge the user before a record
/// disappears (the atServer expires items hard at `expiresAt`, so
/// once that moment arrives the record is already gone).
///
/// Per-stream: returned by [AtCollection.expiringSoonEvents], which
/// takes the [leadTime] as a parameter so different listeners can
/// pick different lead times. Items whose `expiresAt - leadTime` is
/// already in the past at subscription time fire immediately on the
/// next event-loop turn.
final class CItemExpiringSoon extends CEvent {
  /// The item's `expiresAt`. The event fires at
  /// `expiresAt - leadTime`.
  final DateTime expiresAt;

  /// The lead time configured on the [AtCollection.expiringSoonEvents]
  /// call that produced this event. Useful when a single listener
  /// subscribes via multiple lead times and needs to disambiguate.
  final Duration leadTime;

  CItemExpiringSoon({
    required super.owner,
    required super.id,
    required this.expiresAt,
    required this.leadTime,
  });
}

/// A single link in a sub-item's parent chain.
///
/// - [id]: the ancestor's own id.
/// - [subName]: the name of the sub-collection that contains this
///   ancestor's next-level-down children.
/// - [owner]: the ancestor's owner atSign, or `null` when unknown
///   (see below).
///
/// Example — for the key `T.replies.S.comments.R.posts.app@<reply-owner>`
/// (a "reply" on a "comment" on a "post"), the ancestry from root is:
///   - `(id: R, subName: 'comments', owner: <post owner>)`
///   - `(id: S, subName: 'replies', owner: <comment owner>)`
///
/// **Owner availability.** Owners of ancestors are not carried in
/// an Atsign Protocol key; they live only in the sub-item's
/// envelope `parents` field. The event pipeline fetches that
/// envelope to populate [owner] for `CSubItemUpdated` events. On
/// `CSubItemDeleted` events the sub-item itself is gone — there's
/// no envelope to read — so every [owner] is `null`. Legacy
/// sub-items written before the `parents` envelope field was added
/// also yield `null` owners.
///
/// App code that filters event streams by an ancestor must match on
/// **both** `id` AND `owner` to avoid cross-owner collisions when
/// two atSigns independently pick the same id.
final class CAncestor {
  final String id;
  final String subName;
  final Atsign? owner;

  const CAncestor({
    required this.id,
    required this.subName,
    this.owner,
  });

  @override
  bool operator ==(Object other) =>
      other is CAncestor &&
      other.id == id &&
      other.subName == subName &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(id, subName, owner);

  @override
  String toString() => 'CAncestor(id: $id, subName: $subName, owner: $owner)';
}

final class CSubItemUpdated extends CEvent {
  /// Root-to-direct-parent chain. Length equals the sub-item's
  /// nesting depth (1 for a direct sub-item, 2 for a sub-sub, …).
  /// Owners are populated from the sub-item's envelope on arrival;
  /// legacy items or envelopes missing the `parents` field yield
  /// `null` owners.
  final List<CAncestor> ancestry;

  CSubItemUpdated({
    required super.owner,
    required super.id,
    required this.ancestry,
  });

  /// The subName of the innermost sub-collection containing this
  /// item — equivalent to `ancestry.last.subName`.
  String get subName => ancestry.last.subName;
}

final class CSubItemDeleted extends CEvent {
  /// Root-to-direct-parent chain. Length equals the sub-item's
  /// nesting depth. **Owners are always `null` on delete events** —
  /// the sub-item is gone by the time the notification arrives, so
  /// there's no envelope to recover `parents` from. Apps that need
  /// to correlate a delete with the deleted item's ancestry should
  /// cache the last seen `CSubItemUpdated` for that (id, subName)
  /// and look it up here.
  final List<CAncestor> ancestry;

  CSubItemDeleted({
    required super.owner,
    required super.id,
    required this.ancestry,
  });

  /// The subName of the innermost sub-collection containing this
  /// item — equivalent to `ancestry.last.subName`.
  String get subName => ancestry.last.subName;
}

/// Parsed components of a notification key. Private to [AtCollection].
typedef _CParts = ({
  Atsign from,

  /// The item's own id (at any depth).
  String id,

  /// Root-to-direct-parent chain. Empty for a root-level item.
  List<CAncestor> ancestry,
});

/// Internal registry entry for a typed factory. Holds both the wire-format
/// tag and the rehydrator function.
class _FactoryEntry {
  final String tag;
  final Function fromJson;

  _FactoryEntry(this.tag, this.fromJson);
}
