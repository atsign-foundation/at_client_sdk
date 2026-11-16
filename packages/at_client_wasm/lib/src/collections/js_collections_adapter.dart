import 'dart:async';

import 'package:at_client/at_client.dart';

/// An item address: the item's id and the atSign that owns it.
typedef JsItemAddress = ({String id, String owner});

/// One `where` clause: a dotted path into the item's data, an operator and
/// a value.
typedef JsWhereClause = ({String path, String op, Object? value});

/// An item as plain values: `id`, `owner`, `type`, `data`, `sharedWith`
/// (a list of atSigns), and `createdAt`, `expiresAt` and `availableAt` in
/// milliseconds since the epoch (`availableAt` may be null).
typedef JsItem = Map<String, Object?>;

/// A record this device cannot read: its id, its owner and the code
/// [W8.unreadable].
typedef JsUnreadable = ({String id, String owner, String code});

/// What [JsCollectionsAdapter.list] and [JsCollectionsAdapter.query]
/// resolve with: the readable items in upstream order, and one entry per
/// record that could not be read.
typedef JsListing = ({List<JsItem> items, List<JsUnreadable> unreadable});

/// An event as plain values: `type`, `id`, `owner` and the fields of that
/// event type. See [JsCollectionsAdapter.watch].
typedef JsEvent = Map<String, Object?>;

/// The W8 error codes a [JsCollectionsError] carries (js-api.md §6.1).
abstract final class W8 {
  /// A malformed argument: an unknown eventSource or operator, a
  /// non-positive expirationMs, an empty type or path segment, a value an
  /// operator cannot compare, an invalid atSign, or an item id outside
  /// [JsCollectionsAdapter.idPattern].
  static const invalidArgument = 'W8_INVALID_ARGUMENT';

  /// No item with that id and owner.
  static const notFound = 'W8_NOT_FOUND';

  /// A write to an item owned by another atSign.
  static const notOwner = 'W8_NOT_OWNER';

  /// A create with an id that already exists.
  static const alreadyExists = 'W8_ALREADY_EXISTS';

  /// A remove without cascade of an item that has sub-items.
  static const hasSubItems = 'W8_HAS_SUB_ITEMS';

  /// A record this device cannot read, such as one sealed to a key it does
  /// not hold yet.
  static const unreadable = 'W8_UNREADABLE';

  /// An ordering `where` met a value of another type at its path.
  static const typeMismatch = 'W8_TYPE_MISMATCH';

  /// An update of an item another type tag wrote.
  static const wrongType = 'W8_WRONG_TYPE';

  /// Some key-level writes of one operation failed.
  static const partialFailure = 'W8_PARTIAL_FAILURE';

  /// Any other failure; [JsCollectionsError.kind] names it.
  static const failed = 'W8_FAILED';
}

/// The single error shape every adapter operation rejects with.
final class JsCollectionsError extends AtException {
  JsCollectionsError(
    this.code,
    super.message, {
    this.id,
    this.owner,
    this.kind,
    this.failures = const [],
  });

  /// One of the [W8] codes.
  final String code;

  /// The item the failure is about, when known.
  final String? id;
  final String? owner;

  /// The Dart type of the underlying error, for [W8.failed] and each
  /// [failures] entry: a name the adapter knows, or `'Unknown'`.
  final String? kind;

  /// For [W8.partialFailure]: one `{op, recipient, kind}` per failed
  /// key-level write, where recipient is the atSign the copy was for.
  final List<Map<String, String>> failures;

  @override
  String toString() => 'JsCollectionsError($code): $message';
}

/// Translates plain values into [AtCollection] calls, and results, events
/// and errors back into plain values, for the JS facade.
///
/// It adds no behaviour: no namespace qualification, defaults, sorting,
/// caching or type filtering. Every item is addressed by id and owner. A
/// write re-reads the item right before writing and never removes a
/// recipient it did not read, so a recipient another device added is kept.
/// Every operation returns a Future that rejects with a
/// [JsCollectionsError].
final class JsCollectionsAdapter {
  JsCollectionsAdapter(this._collection);

  final AtCollection<Map<String, dynamic>> _collection;

  /// The ids the adapter accepts on every address.
  static final idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  static const _eventSources = {
    'data': EventSource.data,
    'notifs': EventSource.notifs,
    'both': EventSource.both,
  };

  /// Opens [namespace] through [AtClient.collection], unchanged, writing
  /// [type] as the wire type tag. [eventSource] is `'data'`, `'notifs'` or
  /// `'both'`; when omitted, AtClient's default applies.
  static Future<JsCollectionsAdapter> open(
    AtClient client, {
    required String namespace,
    required String type,
    required int expirationMs,
    String? eventSource,
  }) =>
      _guard(() async {
        if (expirationMs <= 0) {
          throw JsCollectionsError(
              W8.invalidArgument, 'expirationMs must be > 0');
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
            throw JsCollectionsError(
                W8.invalidArgument, 'unknown eventSource "$eventSource"');
          }
          collection = await client.collection<Map<String, dynamic>>(
              namespace, expiration,
              eventSource: source, writeTypeTag: type);
        }
        return JsCollectionsAdapter(collection);
      });

  /// Creates an item owned by this atSign. Rejects with [W8.alreadyExists]
  /// when [id] exists.
  Future<JsItem> create(
    Map<String, dynamic> data, {
    String? id,
    List<String> sharedWith = const [],
  }) =>
      _guard(
        () async {
          if (id != null) _checkId(id);
          return _item(await _collection.create(
            obj: data,
            id: id,
            sharedWith: {for (final a in sharedWith) a.toAtsign()},
          ));
        },
        id: id,
        owner: _collection.atSign,
        stateError: id == null ? null : W8.alreadyExists,
      );

  /// The item at [address], or null when there is none.
  Future<JsItem?> get(JsItemAddress address) => _guard(() async {
        _checkId(address.id);
        final item =
            await _collection.getOrNull(address.id, address.owner.toAtsign());
        return item == null ? null : _item(item);
      });

  /// Every readable item, in the order AtCollection returns them, and the
  /// records that could not be read. An unreadable record does not fail the
  /// listing.
  Future<JsListing> list() => _guard(() => _read(const []));

  /// The readable items matching every clause, in the order AtCollection
  /// returns them, and the records that could not be read. Operators: `==`,
  /// `!=`, `<`, `<=`, `>`, `>=`, `isNull`, `isNotNull`.
  Future<JsListing> query(List<JsWhereClause> clauses) =>
      _guard(() => _read([for (final clause in clauses) _predicate(clause)]));

  /// Replaces the data of the item at [address], keeping its recipients,
  /// expiresAt, availableAt and createdAt as just re-read. Rejects with
  /// [W8.wrongType] when the item carries another type tag; an untagged
  /// (`n/a`) item takes this collection's tag. [share] and [remove] work on
  /// an item of any type.
  Future<JsItem> update(JsItemAddress address, Map<String, dynamic> data) =>
      _write(address, (current) async {
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
          throw JsCollectionsError(W8.wrongType,
              'item ${current.id} is a ${current.type}, not a ${next.type}',
              id: current.id, owner: current.owner.toString());
        }
        await _collection.update(next, unshareWithOthers: false);
        // The stored creation time, not the draft's.
        next.createdAt = current.createdAt;
        return next;
      });

  /// Adds [atSigns] to the recipients of the item at [address]. Never
  /// removes a recipient.
  Future<JsItem> share(JsItemAddress address, List<String> atSigns) =>
      _write(address, (current) async {
        await _collection.updateSharedWith(
          current,
          {...current.sharedWith, for (final a in atSigns) a.toAtsign()},
          unshareWithOthers: false,
        );
        return current;
      });

  /// Deletes the item at [address]. Rejects with [W8.hasSubItems] when it
  /// has sub-items and [cascade] is false.
  Future<void> remove(JsItemAddress address, {bool cascade = false}) =>
      _write(address, (current) async {
        await _collection.delete(current, cascade: cascade);
        return current;
      }, stateError: W8.hasSubItems);

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
  Future<void> Function() watch(
    void Function(JsEvent event) onEvent, {
    required void Function(JsCollectionsError error) onError,
  }) {
    final subscription = _collection.watch().listen(
          (event) => onEvent(_event(event)),
          onError: (Object error) => onError(_error(error)),
        );
    return subscription.cancel;
  }

  Future<JsItem> _write(
    JsItemAddress address,
    Future<CItem<Map<String, dynamic>>> Function(
            CItem<Map<String, dynamic>> current)
        write, {
    String stateError = W8.notFound,
  }) =>
      _guard(
        () async {
          _checkId(address.id);
          final owner = address.owner.toAtsign();
          if (owner != _collection.atSign) {
            throw JsCollectionsError(W8.notOwner,
                'item ${address.id} is owned by $owner, not ${_collection.atSign}',
                id: address.id, owner: owner);
          }
          final current = await _collection.get(address.id, owner);
          return _item(await write(current));
        },
        id: address.id,
        owner: address.owner,
        stateError: stateError,
      );

  /// Reads every item through [AtCollection.getItemsAsStream], collecting a
  /// [CItemReadException] per unreadable record instead of stopping at it,
  /// and keeps the items that satisfy every one of [predicates].
  Future<JsListing> _read(List<Predicate> predicates) async {
    final readable = <CItem<Map<String, dynamic>>>[];
    final unreadable = <JsUnreadable>[];
    final done = Completer<void>();
    final subscription = _collection.getItemsAsStream().listen(
      readable.add,
      onError: (Object error, StackTrace stack) {
        if (error is CItemReadException) {
          unreadable.add(_unreadable(error));
        } else if (!done.isCompleted) {
          done.completeError(error, stack);
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
      throw JsCollectionsError(
          W8.typeMismatch, 'a where clause compared values of different types');
    }
    return (
      items: [for (final i in matching) _item(i)],
      unreadable: unreadable
    );
  }

  static JsUnreadable _unreadable(CItemReadException error) => (
        id: error.key.key.split('.').first,
        owner: error.key.sharedBy ?? '',
        code: W8.unreadable,
      );

  static void _checkId(String id) {
    if (!idPattern.hasMatch(id)) {
      throw JsCollectionsError(
          W8.invalidArgument, 'an item id must match ${idPattern.pattern}');
    }
  }

  static Predicate _predicate(JsWhereClause clause) {
    final segments = clause.path.split('.');
    if (segments.any((s) => s.isEmpty)) {
      throw JsCollectionsError(
          W8.invalidArgument, 'empty segment in where path "${clause.path}"');
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
      throw JsCollectionsError(
          W8.invalidArgument, 'unknown where operator "${clause.op}"');
    }
    final value = clause.value;
    if (value is! num && value is! String) {
      throw JsCollectionsError(W8.invalidArgument,
          'where "${clause.op}" needs a number or string value');
    }
    return field.isNotNull.and(compare(value as Comparable<dynamic>));
  }

  static JsItem _item(CItem<Map<String, dynamic>> item) => {
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
  static Future<R> _guard<R>(
    Future<R> Function() body, {
    String? id,
    String? owner,
    String? stateError,
  }) async {
    try {
      return await body();
    } on StateError catch (e) {
      throw JsCollectionsError(stateError ?? W8.failed, e.message,
          id: id, owner: owner, kind: 'StateError');
    } catch (e) {
      throw _error(e, id: id, owner: owner);
    }
  }

  /// A stable name for [error]'s type; the runtime type's name is minified
  /// under dart2js. An error of a type not listed here is `'Unknown'`.
  static String _kindOf(Object error) => switch (error) {
        AtKeyNotFoundException() => 'AtKeyNotFoundException',
        InvalidAtSignException() => 'InvalidAtSignException',
        CItemReadException() => 'CItemReadException',
        AtClientException() => 'AtClientException',
        AtException() => 'AtException',
        StateError() => 'StateError',
        ArgumentError() => 'ArgumentError',
        TimeoutException() => 'TimeoutException',
        FormatException() => 'FormatException',
        _ => 'Unknown',
      };

  static JsCollectionsError _error(Object error, {String? id, String? owner}) {
    switch (error) {
      case JsCollectionsError():
        return error;
      case CItemReadException():
        // The cause can carry record content; it stays on the Dart side.
        final (:id, :owner, code: _) = _unreadable(error);
        return JsCollectionsError(
            W8.unreadable, 'item $id owned by $owner could not be read',
            id: id, owner: owner, kind: 'CItemReadException');
      case CollectionOpException(:final failures, :final item):
        // A create without an id learns it here: the item that landed.
        return JsCollectionsError(
            W8.partialFailure, '${failures.length} key-level write(s) failed',
            id: item?.id ?? id,
            owner: item?.owner.toString() ?? owner,
            kind: 'CollectionOpException',
            failures: [
              for (final f in failures)
                {
                  'op': f.op.name,
                  'recipient': f.atKey.sharedWith ?? f.atKey.sharedBy ?? '',
                  'kind': _kindOf(f.reason),
                }
            ]);
      case AtKeyNotFoundException():
        return JsCollectionsError(W8.notFound, error.message,
            id: id, owner: owner, kind: 'AtKeyNotFoundException');
      case InvalidAtSignException():
        return JsCollectionsError(W8.invalidArgument, error.message,
            id: id, owner: owner, kind: 'InvalidAtSignException');
      case ArgumentError():
        return JsCollectionsError(W8.invalidArgument, '${error.message}',
            id: id, owner: owner, kind: 'ArgumentError');
      default:
        return JsCollectionsError(W8.failed, 'operation failed',
            id: id, owner: owner, kind: _kindOf(error));
    }
  }
}
