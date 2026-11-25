import 'dart:async';

import 'package:at_client/at_client.dart';

import '../exceptions.dart';
import '../log_text.dart';
import 'item_locks.dart';

/// An item address: the item's id and the Atsign that owns it.
typedef JsItemAddress = ({String id, Atsign owner});

/// One `where` clause: a dotted path into the item's data, an operator and
/// a value.
typedef JsWhereClause = ({String path, String op, Object? value});

/// An item as plain values: `id`, `owner`, `type`, `data`, `sharedWith`
/// (a list of atSigns), and `createdAt`, `expiresAt` and `availableAt` in
/// milliseconds since the epoch (`availableAt` may be null).
typedef JsItem = Map<String, Object?>;

/// A record this device cannot read: its id, its owner and the reason, a
/// [CollectionFailure.unreadable] or [CollectionFailure.tooDeep].
typedef JsUnreadable = ({String id, Atsign owner, CollectionFailure kind});

/// What [JsCollectionsAdapter.list] and [JsCollectionsAdapter.query]
/// resolve with: the readable items in upstream order, and one entry per
/// record that could not be read.
typedef JsListing = ({List<JsItem> items, List<JsUnreadable> unreadable});

/// An event as plain values: `type`, `id`, `owner` and the fields of that
/// event type. See [JsCollectionsAdapter.watch].
typedef JsEvent = Map<String, Object?>;

/// The deepest nesting of item data that reaches JS, counted in containers
/// (maps and lists) with the data object itself the first level. The bridge
/// refuses a `data` argument nested deeper, and no read returns data nested
/// deeper.
const maxItemDataDepth = 64;

/// Whether [value] nests containers deeper than [maxItemDataDepth] levels.
/// Iterative, so data of any depth is measured without recursing.
bool exceedsMaxDepth(Object? value) {
  final pending = <(Object?, int)>[(value, 1)];
  while (pending.isNotEmpty) {
    final (current, level) = pending.removeLast();
    final children = switch (current) {
      Map<Object?, Object?>(:final values) => values,
      Iterable<Object?>() => current,
      _ => null,
    };
    if (children == null) continue;
    if (level > maxItemDataDepth) return true;
    for (final child in children) {
      pending.add((child, level + 1));
    }
  }
  return false;
}

/// The error for an item whose data nests deeper than [maxItemDataDepth].
JsCollectionsError itemTooDeep({String? id, String? owner}) =>
    JsCollectionsError(CollectionFailure.tooDeep, id: id, owner: owner);

/// The eight collection operations on plain values, as the JS bridge uses
/// them. [JsCollectionsAdapter] is the implementation; tests of the bridge
/// supply another.
abstract interface class ItemCollection {
  Future<JsItem> create(Map<String, dynamic> data,
      {String? id, List<String> sharedWith});
  Future<JsItem?> get(JsItemAddress address);
  Future<JsListing> list();
  Future<JsListing> query(List<JsWhereClause> clauses);
  Future<JsItem> update(JsItemAddress address, Map<String, dynamic> data);
  Future<JsItem> share(JsItemAddress address, List<String> atSigns);
  Future<void> remove(JsItemAddress address, {bool cascade = false});
  Future<void> Function() watch(
    void Function(JsEvent event) onEvent, {
    required void Function(JsCollectionsError error) onError,
  });
}

/// Translates plain values into [AtCollection] calls, and results, events
/// and errors back into plain values, for the JS facade.
///
/// It adds no behaviour: no namespace qualification, defaults, sorting,
/// caching or type filtering. Every item is addressed by id and owner. A
/// write re-reads the item right before writing and never removes a
/// recipient it did not read, so a recipient another device added is kept.
/// Every operation returns a Future that rejects with a
/// [JsCollectionsError], except that a [StoppedException] from at_client
/// (a call in flight when the client stops) is rethrown as it is.
final class JsCollectionsAdapter implements ItemCollection {
  /// [locks] is the session's lock map, shared by every adapter it builds,
  /// and [namespace] the folded namespace this collection is keyed under in
  /// it. A lone adapter gets a map of its own.
  JsCollectionsAdapter(this._collection,
      {ItemLocks? locks, this.namespace = ''})
      : _locks = locks ?? ItemLocks();

  final AtCollection<Map<String, dynamic>> _collection;
  final ItemLocks _locks;
  final String namespace;

  final _logger = AtSignLogger('JsCollectionsAdapter');

  static const _eventSources = {
    'data': EventSource.data,
    'notifs': EventSource.notifs,
    'both': EventSource.both,
  };

  /// Serializes writes to the same `(namespace, id, owner)` across every
  /// adapter of the session, so concurrent `update`, `share`, `remove`, and
  /// explicit-id `create` calls run sequentially without overwriting one
  /// another.
  Future<R> _queueWrite<R>(
          String id, Atsign owner, Future<R> Function() body) =>
      _locks.run(namespace, id, owner, body);

  /// Opens [namespace] through [AtClient.collection], unchanged, writing
  /// [type] as the wire type tag. [eventSource] is `'data'`, `'notifs'` or
  /// `'both'`; when omitted, AtClient's default applies. A blank [type] or a
  /// non-positive [expirationMs] rejects with
  /// [CollectionFailure.invalidArgument] before anything opens.
  static Future<JsCollectionsAdapter> open(
    AtClient client, {
    required String namespace,
    required String type,
    required int expirationMs,
    String? eventSource,
    ItemLocks? locks,
  }) =>
      _mapFailures(() async {
        if (expirationMs <= 0) {
          throw JsCollectionsError(CollectionFailure.invalidArgument,
              refusal: CollectionRefusal.expiration);
        }
        if (type.trim().isEmpty) {
          throw JsCollectionsError(CollectionFailure.invalidArgument,
              refusal: CollectionRefusal.type);
        }
        final expiration = Duration(milliseconds: expirationMs);
        final AtCollection<Map<String, dynamic>> collection;
        if (eventSource == null) {
          collection = await client.collection<Map<String, dynamic>>(
              namespace, expiration,
              writeTypeTag: type);
        } else {
          final source = _eventSources[eventSource];
          if (source == null) {
            throw JsCollectionsError(CollectionFailure.invalidArgument,
                refusal: CollectionRefusal.eventSource, subject: eventSource);
          }
          collection = await client.collection<Map<String, dynamic>>(
              namespace, expiration,
              eventSource: source, writeTypeTag: type);
        }
        return JsCollectionsAdapter(collection,
            locks: locks, namespace: namespace);
      });

  /// Creates an item owned by this atSign. Rejects with [CollectionFailure.alreadyExists]
  /// when [id] exists.
  @override
  Future<JsItem> create(
    Map<String, dynamic> data, {
    String? id,
    List<String> sharedWith = const [],
  }) =>
      _mapFailures(
        () {
          Future<JsItem> run() async => _item(await _collection.create(
                obj: data,
                id: id,
                sharedWith: {for (final a in sharedWith) a.toAtsign()},
              ));
          return id == null ? run() : _queueWrite(id, _collection.atSign, run);
        },
        id: id,
        owner: _collection.atSign,
        stateError: id == null ? null : CollectionFailure.alreadyExists,
      );

  /// The item at [address], or null when there is none.
  @override
  Future<JsItem?> get(JsItemAddress address) => _mapFailures(
        () async {
          final item = await _collection.getOrNull(address.id, address.owner);
          return item == null ? null : _item(item);
        },
        id: address.id,
        owner: address.owner,
      );

  /// Every readable item, in the order AtCollection returns them, and the
  /// records that could not be read. An unreadable record does not fail the
  /// listing; one whose key names no Atsign is left out, with a warning.
  @override
  Future<JsListing> list() => _mapFailures(() => _read(const []));

  /// The readable items matching every clause, in the order AtCollection
  /// returns them, and the records that could not be read. Operators: `==`,
  /// `!=`, `<`, `<=`, `>`, `>=`, `isNull`, `isNotNull`.
  @override
  Future<JsListing> query(List<JsWhereClause> clauses) => _mapFailures(
      () => _read([for (final clause in clauses) _predicate(clause)]));

  /// Replaces the data of the item at [address], keeping its recipients,
  /// expiresAt, availableAt and createdAt as just re-read. Rejects with
  /// [CollectionFailure.wrongType] when the item carries another type tag; an untagged
  /// (`n/a`) item takes this collection's tag. [share] and [remove] work on
  /// an item of any type.
  @override
  Future<JsItem> update(JsItemAddress address, Map<String, dynamic> data) =>
      _ownedWrite(address, (current) async {
        final next = _collection.draft(
          obj: data,
          id: current.id,
          sharedWith: current.sharedWith,
          expiresAt: current.expiresAt,
          availableAt: current.availableAt,
        );
        // An untagged item is adopted; another type's item is refused before
        // any write.
        if (current.type != 'n/a' && current.type != next.type) {
          throw JsCollectionsError(CollectionFailure.wrongType,
              id: current.id,
              owner: current.owner.toString(),
              foundType: current.type,
              expectedType: next.type);
        }
        await _collection.update(next, unshareWithOthers: false);
        // The stored creation time, not the draft's.
        next.createdAt = current.createdAt;
        return _item(next);
      });

  /// Adds [atSigns] to the recipients of the item at [address]. Never
  /// removes a recipient.
  @override
  Future<JsItem> share(JsItemAddress address, List<String> atSigns) =>
      _ownedWrite(address, (current) async {
        // The result carries the item's data, so an item that cannot be
        // returned is refused before anything is written.
        if (exceedsMaxDepth(current.obj)) {
          throw itemTooDeep(id: current.id, owner: current.owner.toString());
        }
        await _collection.updateSharedWith(
          current,
          {...current.sharedWith, for (final a in atSigns) a.toAtsign()},
          unshareWithOthers: false,
        );
        return _item(current);
      });

  /// Deletes the item at [address]. Rejects with [CollectionFailure.hasSubItems] when it
  /// has sub-items and [cascade] is false.
  @override
  Future<void> remove(JsItemAddress address,
          {bool cascade = false}) =>
      _ownedWrite(
          address, (current) => _collection.delete(current, cascade: cascade),
          stateError: CollectionFailure.hasSubItems);

  /// Calls [onEvent] with each AtCollection event and [onError] with each
  /// error on the event stream, until the returned function is called; its
  /// Future completes once the subscription is cancelled.
  ///
  /// Event types: `updated`; `deleted` (`wasExpired`); `available`
  /// (`availableAt`); `expiringSoon` (`expiresAt`, `leadTimeMs`);
  /// `readReceipt` (`from`, `readAt`); `subItemUpdated` and
  /// `subItemDeleted` (`ancestry`, a list of `{id, subName, owner}`); and
  /// `unknown` for an event type this adapter does not know. Times are
  /// milliseconds since the epoch.
  @override
  Future<void> Function() watch(
    void Function(JsEvent event) onEvent, {
    required void Function(JsCollectionsError error) onError,
  }) {
    final subscription = _collection.watch().listen(
          (event) => onEvent(_event(event)),
          onError: (Object error) => onError(_toJsCollectionsError(error)),
        );
    return subscription.cancel;
  }

  /// Runs [write] on the item at [address] as just re-read, after the owner
  /// check, and returns what it returns. A [write] that returns the item
  /// converts it with [_item] itself, so a `remove` never fails after it
  /// deleted.
  Future<R> _ownedWrite<R>(
    JsItemAddress address,
    Future<R> Function(CItem<Map<String, dynamic>> current) write, {
    CollectionFailure stateError = CollectionFailure.notFound,
  }) =>
      _mapFailures(
        () {
          final owner = address.owner;
          if (owner != _collection.atSign) {
            throw JsCollectionsError(CollectionFailure.notOwner,
                id: address.id,
                owner: owner,
                collectionOwner: _collection.atSign);
          }
          return _queueWrite(address.id, owner, () async {
            final current = await _collection.get(address.id, owner);
            return await write(current);
          });
        },
        id: address.id,
        owner: address.owner,
        stateError: stateError,
      );

  static String _describeAtKey(AtKey key) {
    try {
      return '$key';
    } on Object {
      // AtKey.toString throws InvalidAtKeyException when key.key is empty, and
      // key.key is late on manually constructed keys.
      try {
        final ns = key.namespace == null || key.namespace!.isEmpty
            ? ''
            : '.${key.namespace}';
        final owner = key.sharedBy ?? '';
        return '${key.key}$ns$owner';
      } on Object {
        return '<invalid key>';
      }
    }
  }

  /// Reads every item through [AtCollection.getItemsAsStream], collecting a
  /// [CItemReadException] per unreadable record instead of stopping at it,
  /// and keeps the items that satisfy every one of [predicates]. An
  /// unreadable record whose key names no Atsign is left out, and a warning
  /// names its key.
  Future<JsListing> _read(List<Predicate> predicates) async {
    final all = <CItem<Map<String, dynamic>>>[];
    final unreadable = <JsUnreadable>[];
    final done = Completer<void>();
    final subscription = _collection.getItemsAsStream().listen(
      all.add,
      onError: (Object error, StackTrace stack) {
        try {
          if (error is CItemReadException) {
            final entry = _unreadable(error);
            if (entry != null) {
              unreadable.add(entry);
            } else {
              _logger.warning('Left out the stored record '
                  '${sanitizeLogText(_describeAtKey(error.key))} from a '
                  'listing: its key names no Atsign');
            }
          } else if (!done.isCompleted) {
            done.completeError(error, stack);
          }
        } catch (e, s) {
          if (!done.isCompleted) done.completeError(e, s);
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future;
    } finally {
      await subscription.cancel();
    }
    // An item nested too deep is reported whatever the predicates say, as an
    // unreadable record is.
    final readable = <CItem<Map<String, dynamic>>>[];
    for (final item in all) {
      if (exceedsMaxDepth(item.obj)) {
        unreadable.add((
          id: item.id,
          owner: item.owner.toAtsign(),
          kind: CollectionFailure.tooDeep,
        ));
      } else {
        readable.add(item);
      }
    }
    final List<CItem<Map<String, dynamic>>> matching;
    try {
      matching = [
        for (final item in readable)
          if (predicates.every((p) => p.evaluate(item))) item
      ];
    } on Error catch (e) {
      // An ordering clause compared values of different types: a
      // TypeError on the VM and dart2wasm, an ArgumentError from
      // compareTo under dart2js.
      if (e is! TypeError && e is! ArgumentError) rethrow;
      throw JsCollectionsError(CollectionFailure.typeMismatch);
    }
    return (
      items: [for (final i in matching) _item(i)],
      unreadable: unreadable
    );
  }

  /// The entry for a record this device cannot read, owned by the Atsign its
  /// key names, or null when the key names no Atsign.
  static JsUnreadable? _unreadable(CItemReadException error) {
    final sharedBy = error.key.sharedBy;
    if (sharedBy == null) return null;
    try {
      return (
        id: _idOf(error.key),
        owner: sharedBy.toAtsign(),
        kind: CollectionFailure.unreadable,
      );
    } on InvalidAtSignException {
      return null;
    }
  }

  /// The item id [key] is stored under.
  static String _idOf(AtKey key) => key.key.split('.').first;

  static Predicate _predicate(JsWhereClause clause) {
    final segments = clause.path.split('.');
    if (segments.any((s) => s.isEmpty)) {
      throw JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.wherePath, subject: clause.path);
    }
    Object? extract(CItem<dynamic> item) {
      Object? at = item.obj;
      for (final segment in segments) {
        at = at is Map ? at[segment] : null;
      }
      return at;
    }

    final path = ['obj', ...segments];
    final field = PathField<Object?>(path: path, extract: extract);
    switch (clause.op) {
      case '==':
        return field.eq(clause.value);
      case '!=':
        return field.neq(clause.value);
      case 'isNull':
        return field.isNull;
      case 'isNotNull':
        return field.isNotNull;
    }
    final ordered = PathField<Comparable<dynamic>>(
        path: path, extract: (item) => extract(item) as Comparable<dynamic>);
    final Predicate Function(Comparable<dynamic> value)? compare =
        switch (clause.op) {
      '<' => ordered.lt,
      '<=' => ordered.lte,
      '>' => ordered.gt,
      '>=' => ordered.gte,
      _ => null,
    };
    if (compare == null) {
      throw JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.whereOperator, subject: clause.op);
    }
    final value = clause.value;
    if (value is! num && value is! String) {
      throw JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.whereValue, subject: clause.op);
    }
    return field.isNotNull.and(compare(value as Comparable<dynamic>));
  }

  static JsItem _item(CItem<Map<String, dynamic>> item) {
    if (exceedsMaxDepth(item.obj)) {
      throw itemTooDeep(id: item.id, owner: item.owner.toString());
    }
    return _itemOf(item);
  }

  static JsItem _itemOf(CItem<Map<String, dynamic>> item) => {
        'id': item.id,
        'owner': item.owner,
        'type': item.type,
        'data': item.obj,
        'sharedWith': item.sharedWith.toList(),
        'createdAt': item.createdAt.millisecondsSinceEpoch,
        'expiresAt': item.expiresAt.millisecondsSinceEpoch,
        'availableAt': item.availableAt?.millisecondsSinceEpoch,
      };

  static JsEvent _event(CEvent event) {
    final head = {'id': event.id, 'owner': event.owner};
    List<Map<String, Object?>> chain(List<CAncestor> ancestry) => [
          for (final a in ancestry)
            {'id': a.id, 'subName': a.subName, 'owner': a.owner}
        ];
    return switch (event) {
      CItemUpdated() => {'type': 'updated', ...head},
      CItemDeleted(:final wasExpired) => {
          'type': 'deleted',
          ...head,
          'wasExpired': wasExpired
        },
      CItemAvailable(:final availableAt) => {
          'type': 'available',
          ...head,
          'availableAt': availableAt.millisecondsSinceEpoch
        },
      CItemExpiringSoon(:final expiresAt, :final leadTime) => {
          'type': 'expiringSoon',
          ...head,
          'expiresAt': expiresAt.millisecondsSinceEpoch,
          'leadTimeMs': leadTime.inMilliseconds
        },
      CReadReceipt(:final from, :final readAt) => {
          'type': 'readReceipt',
          ...head,
          'from': from,
          'readAt': readAt.millisecondsSinceEpoch
        },
      CSubItemUpdated(:final ancestry) => {
          'type': 'subItemUpdated',
          ...head,
          'ancestry': chain(ancestry)
        },
      CSubItemDeleted(:final ancestry) => {
          'type': 'subItemDeleted',
          ...head,
          'ancestry': chain(ancestry)
        },
      _ => {'type': 'unknown', ...head},
    };
  }

  /// Runs [body], turning anything it throws into a [JsCollectionsError].
  /// [stateError] is the code for a StateError from the operation, which
  /// AtCollection uses for a missing, existing or still-parent item.
  static Future<R> _mapFailures<R>(
    Future<R> Function() body, {
    String? id,
    String? owner,
    CollectionFailure? stateError,
  }) async {
    try {
      return await body();
    } on StoppedException {
      rethrow;
    } on StateError {
      throw JsCollectionsError(stateError ?? CollectionFailure.failed,
          id: id, owner: owner, causeType: 'StateError');
    } catch (e) {
      throw _toJsCollectionsError(e, id: id, owner: owner);
    }
  }

  /// A stable name for [error]'s type; the runtime type's name is minified
  /// under dart2js. An error of a type not listed here is `'Unknown'`.
  static String _kindOf(Object error) => switch (error) {
        AtKeyNotFoundException() => 'AtKeyNotFoundException',
        InvalidAtSignException() => 'InvalidAtSignException',
        CItemReadException() => 'CItemReadException',
        AtClientException() => 'AtClientException',
        QueueLimitException() => 'QueueLimitException',
        AtException() => 'AtException',
        StateError() => 'StateError',
        ArgumentError() => 'ArgumentError',
        TimeoutException() => 'TimeoutException',
        FormatException() => 'FormatException',
        _ => 'Unknown',
      };

  static JsCollectionsError _toJsCollectionsError(Object error,
      {String? id, String? owner}) {
    switch (error) {
      case JsCollectionsError():
        return error;
      case CItemReadException():
        // The cause can carry record content; it stays on the Dart side.
        return JsCollectionsError(CollectionFailure.unreadable,
            id: _idOf(error.key),
            owner: _unreadable(error)?.owner.toString(),
            causeType: 'CItemReadException');
      case CollectionOpException(:final failures, :final item):
        // A create without an id learns it here: the item that landed.
        return JsCollectionsError(CollectionFailure.partialFailure,
            id: item?.id ?? id,
            owner: item?.owner.toString() ?? owner,
            causeType: 'CollectionOpException',
            failures: [
              for (final f in failures)
                {
                  'op': f.op.name,
                  'recipient': f.atKey.sharedWith ?? f.atKey.sharedBy ?? '',
                  'kind': _kindOf(f.reason),
                }
            ]);
      case AtKeyNotFoundException():
        return JsCollectionsError(CollectionFailure.notFound,
            id: id, owner: owner, causeType: 'AtKeyNotFoundException');
      case InvalidAtSignException():
        return JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.atSign,
            id: id,
            owner: owner,
            causeType: 'InvalidAtSignException');
      case ArgumentError():
        final (refusal, subject) = switch (error) {
          ArgumentError(name: 'id', message: final String text) => (
              CollectionRefusal.itemId,
              text
            ),
          ArgumentError(name: 'writeTypeTag' || 'typeTag') => (
              CollectionRefusal.typeTag,
              null
            ),
          _ => (null, null),
        };
        return JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: refusal,
            subject: subject,
            id: id,
            owner: owner,
            causeType: 'ArgumentError');
      default:
        return JsCollectionsError(CollectionFailure.failed,
            id: id, owner: owner, causeType: _kindOf(error));
    }
  }
}
