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

/// An event as plain values: `type`, `id`, `owner` and the fields of that
/// event type. See [JsCollectionsAdapter.watch].
typedef JsEvent = Map<String, Object?>;

/// The W8 error codes a [JsCollectionsError] carries (js-api.md §6.1).
abstract final class W8 {
  /// A malformed argument: an unknown eventSource or operator, an empty
  /// type or path segment, a value an operator cannot compare, or an
  /// invalid atSign or id.
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

  /// Some key-level writes of one operation failed.
  static const partialFailure = 'W8_PARTIAL_FAILURE';

  /// Any other failure; [JsCollectionsError.kind] names it.
  static const failed = 'W8_FAILED';
}

/// The single error shape every adapter operation rejects with.
final class JsCollectionsError implements Exception {
  JsCollectionsError(
    this.code,
    this.message, {
    this.id,
    this.owner,
    this.kind,
    this.failures = const [],
  });

  /// One of the [W8] codes.
  final String code;

  final String message;

  /// The item the failure is about, when known.
  final String? id;
  final String? owner;

  /// The Dart type of the underlying error, for [W8.failed] and each
  /// [failures] entry.
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
        () async => _item(await _collection.create(
          obj: data,
          id: id,
          sharedWith: {for (final a in sharedWith) a.toAtsign()},
        )),
        id: id,
        owner: _collection.atSign,
        stateError: id == null ? null : W8.alreadyExists,
      );

  /// The item at [address], or null when there is none.
  Future<JsItem?> get(JsItemAddress address) => _guard(() async {
        final item =
            await _collection.getOrNull(address.id, address.owner.toAtsign());
        return item == null ? null : _item(item);
      });

  /// Every item, in the order AtCollection returns them.
  Future<List<JsItem>> list() => _guard(
      () async => [for (final i in await _collection.getItems()) _item(i)]);

  /// The items matching every clause, in the order AtCollection returns
  /// them. Operators: `==`, `!=`, `<`, `<=`, `>`, `>=`, `isNull`,
  /// `isNotNull`.
  Future<List<JsItem>> query(List<JsWhereClause> clauses) => _guard(() async {
        var query = _collection.query();
        for (final clause in clauses) {
          query = query.wherePath(_predicate(clause));
        }
        final List<CItem<Map<String, dynamic>>> items;
        try {
          items = await query.get();
        } on Error catch (e) {
          // An ordering clause compared values of different types: a
          // TypeError on the VM and dart2wasm, an ArgumentError from
          // compareTo under dart2js.
          if (e is! TypeError && e is! ArgumentError) rethrow;
          throw JsCollectionsError(W8.typeMismatch,
              'a where clause compared values of different types');
        }
        return [for (final item in items) _item(item)];
      });

  /// Replaces the data of the item at [address], keeping its recipients,
  /// expiresAt and availableAt as just re-read.
  Future<JsItem> update(JsItemAddress address, Map<String, dynamic> data) =>
      _write(address, (current) async {
        final next = _collection.draft(
          obj: data,
          id: current.id,
          sharedWith: current.sharedWith,
          expiresAt: current.expiresAt,
          availableAt: current.availableAt,
        );
        await _collection.update(next, unshareWithOthers: false);
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

  static JsCollectionsError _error(Object error, {String? id, String? owner}) {
    switch (error) {
      case JsCollectionsError():
        return error;
      case CItemReadException(:final key):
        // The cause can carry record content; it stays on the Dart side.
        final keyId = key.key.split('.').first;
        return JsCollectionsError(W8.unreadable,
            'item $keyId owned by ${key.sharedBy} could not be read',
            id: keyId, owner: key.sharedBy, kind: 'CItemReadException');
      case CollectionOpException(:final failures):
        return JsCollectionsError(
            W8.partialFailure, '${failures.length} key-level write(s) failed',
            id: id,
            owner: owner,
            kind: 'CollectionOpException',
            failures: [
              for (final f in failures)
                {
                  'op': f.op.name,
                  'recipient': f.atKey.sharedWith ?? f.atKey.sharedBy ?? '',
                  'kind': f.reason.runtimeType.toString(),
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
            id: id, owner: owner, kind: error.runtimeType.toString());
    }
  }
}
