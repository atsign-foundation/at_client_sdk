// =============================================================================
// AtCollection<T> — a typed collection of items on the Atsign Protocol.
//
// MENTAL MODEL (read this first):
//
// A [CItem] is a single typed record owned by exactly one atSign. The owner
// can mutate and delete it; everyone else can only read their own cached
// copy. `item.owner == self` ⇔ you may call [create], [update] or [delete]
// on it.
//
// [CItem.sharedWith] is a set of atSigns who each receive a *copy* of the
// item. It is a distribution list, not a permission grant — you cannot
// "un-share" retroactively except by deleting their copy.
//
// Read receipts: every [CItem] has an implicit reserved sub-collection
// `__rr` whose items are the receipts written by readers. Query via
// [CItem.readers] / [CItem.wasMarkedReadByMe] on the item itself, or
// via [AtCollection.wasMarkedReadByMe] from the reader's side. Incoming
// receipts fire as [CReadReceipt] events on the parent collection.
//
// PERSISTENCE VERBS:
// - [draft] builds a local [CItem] with no I/O. Use when you need to stage
//   changes (adjusting `expiresAt`, `availableAt`, etc.) before committing.
// - [create] persists a brand-new item. Throws [StateError] if the self-key
//   already exists. If no id is supplied, a random 8-character id is
//   generated and checked for collision before use (retries up to 10 times).
// - [update] persists changes to an existing item. Throws [StateError] if
//   the self-key does not exist. With the default `unshareWithOthers: true`
//   any existing recipient copy whose atSign is NO LONGER in
//   `item.sharedWith` is deleted; retained recipients are overwritten in
//   place — never delete-then-write.
// - [delete] removes the item and its recipient copies. Throws
//   [CollectionOpException] on any key-level failure and [StateError] if
//   `cascade: false` (the default) and self-owned descendants exist.
//
// FACTORY REGISTRY (process-global, via static [AtCollection.registerFactory]).
// Registering a `fromJson` lets AtCollection rehydrate typed objects. The
// simple shape is:
//
//     atClient.collection<Todo>('todos.myapp', ttl, fromJson: Todo.fromJson);
//
// which calls [AtCollection.registerFactory<Todo>] internally, binding
// `Todo.fromJson` to the type-tag `'Todo'` (from `Todo.toString()`) and
// keying it on `Todo` (the [Type]) for lookup when drafting. For
// polymorphic collections (e.g. `AtCollection<Pet>` holding both `Dog`
// and `Cat`), register each concrete type explicitly:
//
//     AtCollection.registerFactory<Dog>(Dog.fromJson);
//     AtCollection.registerFactory<Cat>(Cat.fromJson);
//
// Under obfuscated builds where class names may be renamed, pass an
// explicit `typeTag:` to pin the wire-format type-tag and keep
// interoperability across build variants:
//
//     AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');
//
// READING:
// - [get] throws [AtKeyNotFoundException] if the item is missing.
// - [getMaybe] returns `null` when the item is missing.
// - [getItems] fetches every item in the collection (optionally filtered by
//   id/owner) as a `List<CItem<T>>`. Throws [CollectionGetException] if any
//   per-key decode failed — the exception carries the partial list plus the
//   errors list.
// - [getItemsAsStream] yields a `Stream<CItem<T>>`, ideal for filter-style
//   queries: `collection.getItemsAsStream().where(...).toList()`.
//
// EVENT STREAMS:
//
//     collection.watch()          // Stream<CEvent> — all of the below
//     collection.updates          // Stream<CItemUpdated>
//     collection.deletes          // Stream<CItemDeleted>
//     collection.readReceipts     // Stream<CReadReceipt>
//     collection.subUpdates       // Stream<CSubItemUpdated>  — descendants
//     collection.subDeletes       // Stream<CSubItemDeleted>  — descendants
//
// =============================================================================

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
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';

// -----------------------------------------------------------------------------
// CItem

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
      _readReceiptSub = _collection.readReceipts
          .where((e) => e.id == id)
          .listen((e) => readers.add(e.from));
      _subFinalizer.attach(this, _readReceiptSub!, detach: this);
      // Use `getItemsAsStream` (tolerant of per-key decode errors —
      // it logs and skips). Legacy pre-refactor `__rr` records with
      // bare-numeric values are silently ignored here rather than
      // blowing up the whole load.
      final rr = _collection._readReceiptsFor(this);
      await for (final receipt in rr.getItemsAsStream()) {
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
  /// receipt for this item, does nothing. Otherwise creates a receipt
  /// sub-item shared with [owner]. No-op on self-owned items.
  Future<void> markReadByMe() async {
    if (owner == self) return;
    if (await wasMarkedReadByMe()) return;
    final rr = _collection._readReceiptsFor(this);
    await rr.create(
      obj: {'readAt': DateTime.now().toUtc().toIso8601String()},
      sharedWith: {owner},
    );
  }
}

// -----------------------------------------------------------------------------
// Operation results & exceptions

enum CollectionOp { put, delete }

sealed class OpResult {
  final AtKey atKey;
  final CollectionOp op;
  OpResult(this.atKey, this.op);
}

class OpSuccess extends OpResult {
  OpSuccess(super.atKey, super.op);
  @override
  String toString() => '$atKey:${op.name}:Success';
}

class OpFailure extends OpResult {
  final Object reason;
  OpFailure(super.atKey, super.op, this.reason);
  @override
  String toString() => '$atKey:${op.name}:Failure:$reason';
}

/// Thrown by [AtCollection.create] / [AtCollection.update] /
/// [AtCollection.delete] when any key-level op failed. Inspect [results]
/// for the per-key breakdown, or [failures] / [firstFailure] for the
/// subset that went wrong.
class CollectionOpException implements Exception {
  final List<OpResult> results;
  CollectionOpException(this.results);

  List<OpFailure> get failures => results.whereType<OpFailure>().toList();

  OpFailure? get firstFailure => failures.isEmpty ? null : failures.first;

  @override
  String toString() =>
      'CollectionOpException with ${failures.length} failure(s):\n'
      '  ${failures.join('\n  ')}';
}

/// Thrown by [AtCollection.getItems] when any per-key decode failed.
/// Carries the [partialItems] that did decode plus the [errors] that
/// didn't.
class CollectionGetException implements Exception {
  final List<CItem<dynamic>> partialItems;
  final List<Object> errors;
  CollectionGetException(this.partialItems, this.errors);

  @override
  String toString() =>
      'CollectionGetException: ${errors.length} per-key error(s); '
      '${partialItems.length} item(s) decoded.\n'
      '  ${errors.join('\n  ')}';
}

// -----------------------------------------------------------------------------
// Events

sealed class CEvent {
  final Atsign owner;
  final String id;
  CEvent({required this.owner, required this.id});
}

class CReadReceipt extends CEvent {
  final Atsign from;
  final DateTime readAt;
  CReadReceipt({
    required super.owner,
    required super.id,
    required this.from,
    required this.readAt,
  });
}

class CItemUpdated extends CEvent {
  CItemUpdated({required super.owner, required super.id});
}

class CItemDeleted extends CEvent {
  CItemDeleted({required super.owner, required super.id});
}

/// A single link in a sub-item's parent chain. [id] is the ancestor's
/// own id; [subName] is the name of the sub-collection that contains
/// this ancestor's next-level-down children.
///
/// Example — for the key `T.replies.S.comments.R.posts.app@owner`
/// (a "reply" on a "comment" on a "post"), the ancestry from root is:
///   - `(id: R, subName: 'comments')` — R's children live in `comments`
///   - `(id: S, subName: 'replies')`  — S's children live in `replies`
///
/// For a depth-1 sub-item, the ancestry has exactly one entry.
typedef CAncestor = ({String id, String subName});

class CSubItemUpdated extends CEvent {
  /// Root-to-direct-parent chain. Length equals the sub-item's
  /// nesting depth (1 for a direct sub-item, 2 for a sub-sub, …).
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

class CSubItemDeleted extends CEvent {
  /// Root-to-direct-parent chain. Length equals the sub-item's
  /// nesting depth.
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

// -----------------------------------------------------------------------------
// AtCollection<T>

class AtCollection<T> {
  static const String readReceiptNamespacePart = '__rr';
  static const String _rr = readReceiptNamespacePart;

  // Random-id alphabet and RNG (for auto-generated item ids).
  static const String _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _rng = Random.secure();

  // Factory registry (process-global, NOT per-collection):
  //   - _factoriesByType: lookup by [Type] when drafting (obfuscation-safe)
  //   - _factoriesByTag:  lookup by wire-format type-tag when rehydrating
  //
  // A single global registry simplifies apps that use the same domain
  // type across multiple collection instances (tests, polymorphic
  // parent/child, cross-namespace). Registrations are idempotent —
  // last write wins — so if two parts of your app register different
  // factories for the same type / tag, the later one takes effect.
  static final Map<Type, _FactoryEntry> _factoriesByType = {};
  static final Map<String, Function> _factoriesByTag = {};

  // Per-item cache of read-receipt sub-collections. Keyed by
  // (owner.toString(), id) so it survives CItem rehydrate cycles.
  final Map<String, AtCollection<Map<String, dynamic>>> _rrCache = {};

  // Immutable wiring (set by the private constructor).
  final AtClient atClient;

  /// Fully-qualified namespace — must include the application namespace.
  /// E.g. `'todos.my_apps'`.
  final String namespace;

  final Duration defaultExpiration;

  late final AtSignLogger logger;

  // Internal event controller and derived streams.
  final StreamController<CEvent> _events = StreamController.broadcast();

  // Notification regex patterns, built in the constructor from [namespace].
  // Matches any key at any depth (L0 or any sub-collection) whose tail
  // is `.<namespace>@<anyone>`. Dispatch by depth is done in
  // `handleNotification` based on `_getPartsFromNotifKey`'s ancestry
  // length — not by separate per-depth regexes.
  late final RegExp _regexObjAny;
  late final String _regexAllStr;

  late final StreamSubscription<AtNotification> _rrSub;

  // The notification stream used for this collection's dispatch. Stored
  // so sub-collections built via [_readReceiptsFor] can reuse an
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
  /// `registerFactory<T>(fromJson)` after construction.
  factory AtCollection(
    AtClient atClient,
    String namespace,
    Duration defaultExpiration, {
    T Function(Map<String, dynamic>)? fromJson,
  }) =>
      AtCollection._(
        atClient,
        namespace,
        defaultExpiration,
        fromJson: fromJson,
      );

  /// Test-only factory that bypasses `atClient.notificationService.subscribe`
  /// and drives notification dispatch from [notifications] instead. Keeps
  /// the production constructor's surface clean.
  @visibleForTesting
  factory AtCollection.withInjectedNotifications(
    AtClient atClient,
    String namespace,
    Duration defaultExpiration, {
    required Stream<AtNotification> notifications,
    T Function(Map<String, dynamic>)? fromJson,
  }) =>
      AtCollection._(
        atClient,
        namespace,
        defaultExpiration,
        fromJson: fromJson,
        notifications: notifications,
      );

  AtCollection._(
    this.atClient,
    this.namespace,
    this.defaultExpiration, {
    T Function(Map<String, dynamic>)? fromJson,
    Stream<AtNotification>? notifications,
  }) {
    if (!namespace.contains('.')) {
      throw ArgumentError('namespace must be fully qualified');
    }
    if (fromJson != null) {
      registerFactory<T>(fromJson);
    }

    logger = AtSignLogger(' AtCollection<$T> $namespace ');

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
    _rrSub = notifStream.listen(handleNotification);
  }

  // ---------------------------------------------------------------------------
  // Basic getters

  Atsign get atSign => atClient.atSign;

  /// Convenience alias for [atSign] — reads naturally when contrasting
  /// "self" with "other" atSigns in ownership / sharing logic.
  Atsign get self => atClient.atSign;

  /// True iff this collection was constructed via [subCollection] on a
  /// parent collection.
  bool get isSubCollection => _parentItem != null;

  // ---------------------------------------------------------------------------
  // Factory registry

  /// Registers a factory for type [U] so objects of that type can be
  /// drafted and rehydrated by any [AtCollection] in this process.
  /// The wire-format tag is [typeTag] if supplied, otherwise
  /// `U.toString()`.
  ///
  /// Static by design: factories are process-global, shared across
  /// every [AtCollection] instance. Callers that need to register a
  /// factory implicitly by passing `fromJson:` to [AtClient.collection]
  /// are just calling into this same registry.
  ///
  /// Use for polymorphic collections where `T` is an abstract supertype:
  ///
  ///     AtCollection.registerFactory<Dog>(Dog.fromJson);
  ///     AtCollection.registerFactory<Cat>(Cat.fromJson);
  ///     final pets = await atClient.collection<Pet>(ns, ttl);
  ///
  /// If you build with Dart's minifier / tree-shaker (e.g. release-mode
  /// Flutter web) and class names may be renamed, pin the tag explicitly:
  ///
  ///     AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');
  static void registerFactory<U>(
    U Function(Map<String, dynamic>) fromJson, {
    String? typeTag,
  }) {
    final tag = typeTag ?? U.toString();
    _factoriesByType[U] = _FactoryEntry(tag, fromJson);
    _factoriesByTag[tag] = fromJson;
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
  CItem<T> draft({
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
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
      expiresAt: now.add(defaultExpiration),
      availableAt: null,
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
  /// Returns the persisted item. Throws [CollectionOpException] on any
  /// key-level failure.
  Future<CItem<T>> create({
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
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
    final item = draft(obj: obj, id: useId, sharedWith: sharedWith);
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

  /// Raw [AtKey]s in this collection, optionally filtered by [id] / [owner].
  /// Prefer [getItems] / [getItemsAsStream] for application code; this
  /// hatch is kept for debugging and advanced cases.
  Future<List<AtKey>> getKeys({String? id, Atsign? owner}) async {
    // want a regex like (^|:)[^.]+\.collection\.name\.space@
    // e.g. (^|:)[^.]+\.notes\.todos\.demos@
    id ??= '[^.]+';
    final ownerFragment = owner ?? '@';
    final regex = '(^|:)$id\\.$namespace$ownerFragment';
    return (await atClient.getAtKeys(regex: regex))
      ..sort((a, b) => a.fullKeyAndOwner.compareTo(b.fullKeyAndOwner));
  }

  /// Fetches a single item. Throws [AtKeyNotFoundException] if no item
  /// with this [id] owned by this [owner] exists. For a null-returning
  /// variant, see [getMaybe].
  Future<CItem<T>> get(String id, Atsign owner) async {
    final (items, errors) = await _loadItems(id: id, owner: owner);
    if (errors.isNotEmpty) {
      throw CollectionGetException(items, errors);
    }
    if (items.isEmpty) {
      throw AtKeyNotFoundException(
        'No item found with id $id owned by $owner',
      );
    }
    return items.first;
  }

  /// Same as [get] but returns `null` when no item exists, instead of
  /// throwing [AtKeyNotFoundException]. Still throws
  /// [CollectionGetException] on decode errors.
  Future<CItem<T>?> getMaybe(String id, Atsign owner) async {
    final (items, errors) = await _loadItems(id: id, owner: owner);
    if (errors.isNotEmpty) {
      throw CollectionGetException(items, errors);
    }
    return items.isEmpty ? null : items.first;
  }

  /// Fetches every item in the collection as a `List<CItem<T>>`,
  /// optionally filtered by [id] / [owner]. Items with the same
  /// `owner+id` across self and shared copies are deduplicated and their
  /// `sharedWith` sets are unioned.
  ///
  /// Throws [CollectionGetException] if any per-key decode failed — the
  /// exception carries both the partial-list and the errors so callers
  /// that want "best effort" reads can inspect it rather than propagate.
  Future<List<CItem<T>>> getItems({String? id, Atsign? owner}) async {
    final (items, errors) = await _loadItems(id: id, owner: owner);
    if (errors.isNotEmpty) {
      throw CollectionGetException(items, errors);
    }
    return items;
  }

  /// Yields each item as it is fetched, deduping on `owner+id`. Ideal for
  /// filter-style queries:
  ///
  ///     final done = await collection.getItemsAsStream()
  ///         .where((item) => item.obj.done)
  ///         .toList();
  ///
  /// Decode failures are logged and skipped rather than surfaced —
  /// callers who need failure detail should use [getItems] and catch
  /// [CollectionGetException].
  Stream<CItem<T>> getItemsAsStream({String? id, Atsign? owner}) async* {
    // [getKeys] returns keys sorted by `fullKeyAndOwner`, so all copies of
    // the same item (self + per-recipient) are contiguous. We buffer each
    // item, absorb its recipient siblings' `sharedWith` additions, and
    // yield once per unique (owner, id).
    final keys = await getKeys(id: id, owner: owner);
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
            expiresAt: v.metadata!.expiresAt!,
            availableAt: _liveAvailableAt(v.metadata!.availableAt),
            collection: this,
            parentOwners: parsedParents ?? _expectedAncestorOwners(),
          );
          pendingKey = k.fullKeyAndOwner;
        }
        if (k.sharedWith != null) {
          pending!.sharedWith.add(k.sharedWith!.toAtsign());
        }
      } catch (e) {
        logger.warning('getItemsAsStream decode failure on ${k.key}: $e');
      }
    }
    if (pending != null) yield pending;
  }

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
  /// sub-collection for [item]. Apps should not call this directly —
  /// use [CItem.readers] / [CItem.wasMarkedReadByMe] /
  /// [CItem.markReadByMe] or the [markReadByMe] /
  /// [wasMarkedReadByMe] shims above.
  AtCollection<Map<String, dynamic>> _readReceiptsFor(CItem<T> item) {
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
  /// comments on a specific blog post. The returned collection is a
  /// plain `AtCollection<U>`; it supports every method of the parent
  /// class, including further nesting via [subCollection].
  ///
  /// The composed namespace is `<subName>.<parent.id>.<this.namespace>`,
  /// which must fit within atProtocol's 255-char key limit given the
  /// current atSign length. A violation throws [ArgumentError] at
  /// construction, before any I/O.
  ///
  /// When [parent] is deleted (locally or via a remote notification), the
  /// returned sub-collection auto-deletes this atSign's own items scoped
  /// to it. See [cleanupOrphans] for the offline-recovery counterpart.
  AtCollection<U> subCollection<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    U Function(Map<String, dynamic>)? fromJson,
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
      notifications: notifications,
    );
  }

  /// Internal sub-collection constructor without the reserved-name
  /// guard. Used by [_readReceiptsFor] to build the `__rr` sub-collection.
  AtCollection<U> _buildSubCollection<U>({
    required CItem<T> parent,
    required String subName,
    required Duration defaultExpiration,
    U Function(Map<String, dynamic>)? fromJson,
    Stream<AtNotification>? notifications,
  }) {
    if (subName.isEmpty || subName.contains('.')) {
      throw ArgumentError('subName must be non-empty and dot-free: "$subName"');
    }
    if (parent.id.contains('.')) {
      throw ArgumentError('parent.id must not contain dots: "${parent.id}"');
    }
    final composedNs = '$subName.${parent.id}.$namespace';
    final maxLen = 174 - atSign.toString().length;
    if (composedNs.length > maxLen) {
      throw ArgumentError(
        'Composed sub-collection namespace "$composedNs" is '
        '${composedNs.length} chars, exceeds the max of $maxLen for atSign '
        '$atSign. Use a shorter subName or a shallower nesting depth.',
      );
    }
    // Constructing the sub-collection directly (not via `atClient.collection`)
    // so that `notifications` can be threaded straight through to its
    // constructor for test wiring.
    final sub = notifications != null
        ? AtCollection<U>.withInjectedNotifications(
            atClient,
            composedNs,
            defaultExpiration,
            notifications: notifications,
            fromJson: fromJson,
          )
        : AtCollection<U>(
            atClient,
            composedNs,
            defaultExpiration,
            fromJson: fromJson,
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
      // `getKeys(owner: self)` alone would miss every level deeper
      // than 1.
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
          logger.shout('_cascadeFromParentDelete: $e');
        }
      }));
    } catch (e) {
      logger.shout('_cascadeFromParentDelete scan: $e');
    }
  }

  /// Removes self-owned items whose parent chain has been broken.
  ///
  /// **On a sub-collection** (one returned by [subCollection] on a parent
  /// item): if the bound parent no longer exists, deletes every self-owned
  /// item in the sub-collection.
  ///
  /// **On a root or standalone collection**: scans every self-owned
  /// descendant (any sub-collection, any depth) under this collection's
  /// namespace and deletes those whose *root ancestor* — the direct item
  /// in this collection — no longer exists. This is the path an app
  /// should call on startup after the user may have been offline while a
  /// parent item was deleted elsewhere, to reclaim storage from orphaned
  /// sub-items of parents that are gone.
  ///
  /// Returns per-key [OpResult]s for every deletion attempted.
  Future<List<OpResult>> cleanupOrphans() async {
    return isSubCollection
        ? _cleanupOrphansFromSub()
        : _cleanupOrphansFromRoot();
  }

  Future<List<OpResult>> _cleanupOrphansFromSub() async {
    final parent = _parentItem!;
    final parentColl = _parentCollection!;
    final stillAlive = await parentColl.getMaybe(parent.id, parent.owner);
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
    for (final k in await getKeys()) {
      final parts = k.key.split('.');
      if (parts.length == nsSegments) {
        aliveRootIds.add(parts.first);
      }
    }

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
        // Legacy fallback: only the root ancestor is checked.
        if (aliveRootIds.contains(ancestorIds.first)) continue;
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

  // ---------------------------------------------------------------------------
  // Notification dispatch

  /// Top-level notification dispatcher. Pauses its own subscription for
  /// the duration of handling so re-entrant notifications don't cause
  /// overlapping work. Dispatch is depth-agnostic: L0 items go to
  /// [handleObjNotification]; any sub-item at any nesting depth goes
  /// to [handleSubObjNotification].
  @visibleForTesting
  Future<void> handleNotification(AtNotification n) async {
    _rrSub.pause();
    try {
      if (!_regexObjAny.hasMatch(n.key)) {
        logger.shout('handleNotification: No handler for ${n.key}');
        return;
      }
      final parts = _getPartsFromNotifKey(n);
      if (parts.ancestry.isEmpty) {
        await handleObjNotification(n);
      } else {
        await handleSubObjNotification(n);
      }
    } catch (e, st) {
      logger.shout('handleNotification: $e\nStackTrace:\n$st');
    } finally {
      _rrSub.resume();
    }
  }

  /// Handles direct-item notifications (a key with exactly the collection
  /// namespace as its suffix) and emits [CItemUpdated] / [CItemDeleted].
  @visibleForTesting
  Future<void> handleObjNotification(AtNotification n) async {
    final parts = _getPartsFromNotifKey(n);
    switch (n.operation) {
      case 'update':
        _events.add(CItemUpdated(owner: parts.from, id: parts.id));
      case 'delete':
        _events.add(CItemDeleted(owner: parts.from, id: parts.id));
      default:
        logger.shout(
          'handleObjNotification: No handler for operation ${n.operation}',
        );
    }
  }

  /// Handles notifications for items in a sub-collection at any depth.
  /// The key has the shape
  /// `<id>.<subName_k>.<ancestorId_k>…<subName_1>.<ancestorId_1>.<namespace>@<owner>`
  /// and we emit [CSubItemUpdated] / [CSubItemDeleted] carrying the
  /// full root-to-direct-parent ancestry, so listeners can filter by
  /// any ancestor id or by the innermost sub-collection's `subName`.
  ///
  /// When the innermost sub-collection's subName is the reserved
  /// `__rr` name, we also emit a [CReadReceipt] on top of the
  /// [CSubItemUpdated] so application code can subscribe to read
  /// receipts directly via [readReceipts]. The receipt's `id` is the
  /// direct parent's id (i.e. `ancestry.last.id` — the item being
  /// read).
  @visibleForTesting
  Future<void> handleSubObjNotification(AtNotification n) async {
    final parts = _getPartsFromNotifKey(n);
    if (parts.ancestry.isEmpty) {
      logger.shout('handleSubObjNotification: empty ancestry ${n.key}');
      return;
    }
    final directParent = parts.ancestry.last;
    switch (n.operation) {
      case 'update':
        _events.add(CSubItemUpdated(
          owner: parts.from,
          id: parts.id,
          ancestry: parts.ancestry,
        ));
        if (directParent.subName == _rr) {
          _events.add(CReadReceipt(
            owner: self,
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
        logger.shout(
          'handleSubObjNotification: No handler for operation ${n.operation}',
        );
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
      // (i.e. the child-step toward the current item).
      ancestry.add((id: parts[i], subName: parts[i - 1]));
    }
    return (
      from: n.from.toAtsign(),
      id: parts.first,
      ancestry: ancestry,
    );
  }

  // ---------------------------------------------------------------------------
  // Event streams

  /// All events from this collection as they fire. For type-filtered
  /// access, prefer [updates] / [deletes] / [readReceipts] /
  /// [subUpdates] / [subDeletes].
  Stream<CEvent> watch() => _events.stream;

  Stream<CItemUpdated> get updates =>
      watch().where((e) => e is CItemUpdated).cast<CItemUpdated>();

  Stream<CItemDeleted> get deletes =>
      watch().where((e) => e is CItemDeleted).cast<CItemDeleted>();

  Stream<CReadReceipt> get readReceipts =>
      watch().where((e) => e is CReadReceipt).cast<CReadReceipt>();

  /// Fires for any descendant (sub-collection) item that was updated —
  /// at any nesting depth. Use [CSubItemUpdated.ancestry] to inspect
  /// the full root-to-direct-parent chain, or [CSubItemUpdated.subName]
  /// for just the innermost sub-collection name.
  Stream<CSubItemUpdated> get subUpdates =>
      watch().where((e) => e is CSubItemUpdated).cast<CSubItemUpdated>();

  /// Fires for any descendant item that was deleted.
  Stream<CSubItemDeleted> get subDeletes =>
      watch().where((e) => e is CSubItemDeleted).cast<CSubItemDeleted>();

  // ---------------------------------------------------------------------------
  // Debug helper

  /// Returns a multi-line human-readable dump of [item] — useful for
  /// example-app logging and debugging.
  String prettyString(CItem<dynamic> item) {
    final base = '${item.id}.$namespace${item.owner}'
        '\n\tsharedWith: ${item.sharedWith}'
        '\n\texpiresAt: ${item.expiresAt}'
        '\n\tavailableAt: ${item.availableAt}'
        '\n\ttype: ${item.type}'
        '\n\truntimeType: ${item.obj.runtimeType}';
    if (item.type == 'binary') {
      return '$base\n\tlength: ${item.obj.length} bytes';
    }
    return '$base\n\tobj: ${item.obj}';
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
    try {
      await atClient.get(AtKey.fromString('$id.$namespace$atSign'));
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
  // schedule. The atProtocol metadata wire format is additive — a past
  // `availableAt` on the server has no mechanism to be cleared by an
  // update, so it may linger indefinitely. Presenting it as null here
  // keeps the app's view consistent with the item's actual state
  // (already available) and prevents the write path from reapplying it.
  static DateTime? _liveAvailableAt(DateTime? v) {
    if (v == null) return null;
    return v.isAfter(DateTime.now()) ? v : null;
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
    if (f == null) return obj as V;
    return f.call(obj) as V;
  }

  /// Loads items, collecting per-key decode errors rather than throwing.
  /// The public [getItems] / [get] / [getMaybe] wrap this to surface the
  /// errors as [CollectionGetException] when needed.
  Future<(List<CItem<T>>, List<Object>)> _loadItems({
    String? id,
    Atsign? owner,
  }) async {
    final map = <String, CItem<T>>{};
    final errors = <Object>[];
    for (final k in await getKeys(id: id, owner: owner)) {
      try {
        CItem<T> item;
        if (map.containsKey(k.fullKeyAndOwner)) {
          item = map[k.fullKeyAndOwner]!;
        } else {
          final v = await atClient.get(k);
          logger.info('Retrieved raw value ${v.value}');
          final decoded = _decodeEnvelope(v.value!, k);
          // Parent-owner ancestry filter (see ancestor-owner
          // disambiguation in the post-implementation tidy-up plan).
          // Legacy items (no `parents` in envelope) pass through.
          final parsedParents = _decodeParentOwners(decoded);
          if (parsedParents != null && !_ancestryMatches(parsedParents)) {
            continue;
          }
          item = CItem._(
            owner: k.sharedBy!.toAtsign(),
            id: k.key.split('.').first,
            type: decoded['type'] as String,
            obj: _rehydrate<T>(decoded['obj']!, decoded['type'] as String),
            sharedWith: {},
            createdAt: v.metadata!.createdAt!,
            expiresAt: v.metadata!.expiresAt!,
            availableAt: _liveAvailableAt(v.metadata!.availableAt),
            collection: this,
            parentOwners: parsedParents ?? _expectedAncestorOwners(),
          );
          map[k.fullKeyAndOwner] = item;
        }
        if (k.sharedWith != null) {
          item.sharedWith.add(k.sharedWith!.toAtsign());
        }
      } catch (e) {
        errors.add(e);
      }
    }
    return (map.values.toList(), errors);
  }

  /// Writes [item] (self + recipient copies) and optionally diff-deletes
  /// recipients that are no longer in `item.sharedWith`. Never throws on
  /// key-level failure — callers that want throwing semantics (like
  /// [create] and [update]) inspect the returned results and raise
  /// [CollectionOpException].
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

    final md = Metadata()
      ..ttr = -1
      ..ccd = true
      ..expiresAt = item.expiresAt
      ..ttl = item.expiresAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch
      ..namespaceAware = false;
    // Skip availableAt/ttb when the scheduled time has already passed —
    // atServer rejects negative ttb values, and an item whose availableAt
    // is in the past is already available by definition. This also means
    // a schedule set by an earlier `update` persists harmlessly once it
    // has fired: subsequent updates don't try to re-schedule it.
    if (item.availableAt != null && item.availableAt!.isAfter(now)) {
      md.availableAt = item.availableAt;
      md.ttb =
          item.availableAt!.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    }

    // 1. Self copy.
    try {
      selfKey.metadata = md;
      await atClient.put(selfKey, jsonEncode(item.toJson()));
      results.add(OpSuccess(selfKey, CollectionOp.put));
    } catch (e) {
      results.add(OpFailure(selfKey, CollectionOp.put, e));
    }

    // 2. Diff: delete recipient copies whose atSign is no longer in
    //    item.sharedWith. Retained recipients are overwritten in step 3.
    if (unshareWithOthers) {
      for (final k in await getKeys(id: item.id, owner: atSign)) {
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
    for (final k in await getKeys(id: item.id, owner: atSign)) {
      try {
        await atClient.delete(k);
        results.add(OpSuccess(k, CollectionOp.delete));
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
        logger.warning('descendant envelope decode failed on ${k.key}: $e');
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
